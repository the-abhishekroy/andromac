import Foundation
import Network

/// WebSocket server. One active phone connection at a time (newest wins).
final class Server {
    private let channel: Channel
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var current: NWConnection?
    private var lastSeq: Int = 0
    private var sendSeq: Int = 0
    private let queue = DispatchQueue(label: "andromac.server")
    var onMessage: ((String, [String: Any]) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onVideo: ((Int, Data) -> Void)?
    private var inflight = 0
    private var awaitKey = false
    /// Called (on the server queue) when delta frames had to be dropped: ask the encoder for a keyframe and lower the bitrate.
    var onCongestion: (() -> Void)?

    init(channel: Channel, port: UInt16) {
        self.channel = channel
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func disconnect() { queue.async { [self] in current?.cancel() } }

    func start() throws {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 64 * 1024 * 1024     // the clipboard history sync can carry several images; the default limit would drop the link
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true       // no Nagle delay: input and video are latency-sensitive
        let params = NWParameters(tls: nil, tcp: tcp)
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        // Only the built-in tunnel (running on this Mac) may connect; nothing is exposed on the LAN.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { state in log("listener: \(state)") }
        l.start(queue: queue)
        listener = l
    }

    /// A new connection never replaces the active one until it proves it knows the key (first valid frame).
    /// Otherwise any local program could knock the phone off just by connecting.
    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn else { return }
            switch state {
            case .ready:
                log("connection ready")
                self.receive(conn)
                self.queue.asyncAfter(deadline: .now() + 10) { if self.current !== conn, conn.state == .ready { log("unauthenticated connection timed out"); conn.cancel() } }
            case .failed(let e): log("connection failed: \(e)")
                if self.current === conn { self.current = nil; log("phone disconnected"); self.onDisconnect?() }
            case .cancelled:
                log("connection closed")
                if self.current === conn { self.current = nil; log("phone disconnected"); self.onDisconnect?() }
            default: break
            }
        }
        conn.start(queue: queue)
    }

    private func promote(_ conn: NWConnection) {
        current?.cancel()
        current = conn
        lastSeq = 0; sendSeq = 0; awaitKey = false; inflight = 0
        log("phone connected")
        send(type: "hello", data: ["device": Host.current().localizedName ?? "Mac", "version": 1, "user": NSUserName()])
        onConnect?()
    }

    private func receive(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if error != nil { conn.cancel(); return }
            if let data, let ctx = context,
               let meta = ctx.protocolMetadata(definition: NWProtocolWebSocket.definition)
                   as? NWProtocolWebSocket.Metadata, meta.opcode == .binary {
                self.handle(frame: data, on: conn)
            }
            if conn.state == .ready { self.receive(conn) }
        }
    }

    private func handle(frame: Data, on conn: NWConnection) {
        guard let plain = try? channel.open(frame) else {
            log("dropped unauthenticated frame; closing that connection")
            conn.cancel(); return                                  // only the offending connection, never the active phone
        }
        if current !== conn { promote(conn) }
        if plain.count > 2, plain[plain.startIndex] == 1 {
            onVideo?(Int(plain[plain.startIndex + 1]), plain.dropFirst(2))
            return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let seq = obj["seq"] as? Int, let type = obj["type"] as? String else { conn.cancel(); return }
        guard seq > lastSeq else { log("replayed seq \(seq) ignored"); return }
        lastSeq = seq
        onMessage?(type, obj["data"] as? [String: Any] ?? [:])
    }

    /// Binary video packet: [1][flags][H.264 access unit, Annex-B]. Drops delta frames when the link is congested.
    func sendVideo(keyframe: Bool, _ au: Data) {
        queue.async { [self] in
            guard let conn = current, conn.state == .ready else { return }
            if keyframe { awaitKey = false }
            else if awaitKey { return }                       // reference chain broken: wait for the next keyframe
            else if inflight > 4 { awaitKey = true; onCongestion?(); return }
            var plain = Data([1, keyframe ? 1 : 0]); plain.append(au)
            guard let frame = try? channel.seal(plain) else { return }
            inflight += 1
            let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
            let ctx = NWConnection.ContentContext(identifier: "video", metadata: [meta])
            conn.send(content: frame, contentContext: ctx, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.queue.async { self?.inflight -= 1 }
            })
        }
    }

    func send(type: String, data: [String: Any]) {
        queue.async { [self] in
            guard let conn = current, conn.state == .ready else { return }
            sendSeq += 1
            let env: [String: Any] = ["seq": sendSeq, "type": type,
                                      "ts": Int(Date().timeIntervalSince1970 * 1000), "data": data]
            guard let json = try? JSONSerialization.data(withJSONObject: env),
                  let frame = try? channel.seal(json) else { return }
            let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
            let ctx = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
            conn.send(content: frame, contentContext: ctx, isComplete: true, completion: .idempotent)
        }
    }
}

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
    let line = "[\(f.string(from: Date()))] \(s)"
    print(line); fflush(stdout)
    // A small rolling log (kept under ~200 KB) so problems can be diagnosed afterwards. Never contains keys or message text.
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".andromac/app.log")
    if let sz = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, sz > 200_000 { try? FileManager.default.removeItem(at: url) }
    if let d = (line + "\n").data(using: .utf8) {
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: url) }
    }
}
