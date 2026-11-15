import Foundation
import Darwin

/// The connection runs as a launchd background service (`app.andromac.tunnel`, started at login, restarted if it dies)
/// so it keeps working when the Andromac window or app is closed. This class installs that service and attaches to it
/// over a unix socket to read its state and send commands (sign in, SSH to the phone, mount phone files…).
final class TunnelManager {
    var onState: ((_ state: String, _ detail: String) -> Void)?
    var forwardSSH = true
    private var port: UInt16 = 8765
    private var fd: Int32 = -1
    private var reader: DispatchSourceRead?
    private var buffer = Data()
    private var stopping = false
    private var retry = 1.0

    private let label = "app.andromac.tunnel"
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var socketPath: String { home.appendingPathComponent(".andromac/tunnel.sock").path }
    private var plistURL: URL { home.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    private var uid: String { String(getuid()) }

    static func binaryURL() -> URL? {
        if let u = Bundle.main.url(forResource: "andromac-tunnel", withExtension: nil) { return u }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tunnel/build/andromac-tunnel")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    // MARK: service

    private func args() -> [String] {
        var a = ["-standalone", "-socket", socketPath, "-dir", home.appendingPathComponent(".andromac/tailscale").path,
                 "-host", "andromac-mac", "-port", String(port), "-target", "127.0.0.1:\(port)"]
        if forwardSSH { a += ["-forward", "22=127.0.0.1:22"] }
        return a
    }

    private func sh(_ path: String, _ a: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = a
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }

    /// Write (or refresh) the launchd job and make sure it is loaded.
    private func installService() -> Bool {
        guard let bin = Self.binaryURL() else { return false }
        // run the binary from a stable place so moving or updating the app never leaves the service pointing nowhere
        let support = home.appendingPathComponent(".andromac/bin"); try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let stable = support.appendingPathComponent("andromac-tunnel")
        let needCopy = (try? Data(contentsOf: stable)) != (try? Data(contentsOf: bin))
        if needCopy { try? FileManager.default.removeItem(at: stable); try? FileManager.default.copyItem(at: bin, to: stable) }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [stable.path] + args(),
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],          // restart if it crashes; a deliberate "shutdown" stays stopped
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null",
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let changed = (try? Data(contentsOf: plistURL)) != data
        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if changed || needCopy { try? data?.write(to: plistURL); _ = sh("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"]) }
        _ = sh("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistURL.path])      // no-op if already loaded
        _ = sh("/bin/launchctl", ["kickstart", "gui/\(uid)/\(label)"])
        return true
    }

    // MARK: connection to the service

    func start(port: UInt16) {
        self.port = port; stopping = false
        guard installService() else { onState?("error", "tunnel helper missing"); return }
        attach()
    }

    private func attach() {
        guard !stopping else { return }
        detach()
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        _ = socketPath.withCString { src in withUnsafeMutablePointer(to: &addr.sun_path) { dst in
            dst.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, src, 103) } } }
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } } == 0
        guard ok else {
            close(s)
            let d = retry; retry = min(retry * 2, 5)         // the service may still be starting
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.attach() }
            return
        }
        retry = 1; fd = s
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: .global())
        src.setEventHandler { [weak self] in self?.readable() }
        src.setCancelHandler { close(s) }
        src.resume(); reader = src
    }

    private func readable() {
        var tmp = [UInt8](repeating: 0, count: 8192)
        let n = read(fd, &tmp, tmp.count)
        if n <= 0 {                                            // service went away: reattach
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopping else { return }
                self.onState?("starting", "reconnecting")
                self.detach()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.attach() }
            }
            return
        }
        buffer.append(contentsOf: tmp[0..<n])
        while let nl = buffer.firstIndex(of: 10) {
            let line = buffer.subdata(in: buffer.startIndex..<nl); buffer.removeSubrange(buffer.startIndex...nl)
            if let o = try? JSONSerialization.jsonObject(with: line) as? [String: String] {
                DispatchQueue.main.async { [weak self] in self?.onState?(o["state"] ?? "", o["detail"] ?? "") }
            }
        }
    }

    private func detach() { reader?.cancel(); reader = nil; fd = -1; buffer.removeAll() }

    func send(_ command: String) {
        guard fd >= 0 else { return }
        let d = Array((command + "\n").utf8); _ = write(fd, d, d.count)
    }

    /// Leave the service running (the window or app is closing) but stop listening to it.
    func leaveRunning() { stopping = true; detach() }

    /// Really turn the connection off: stop the service and keep it stopped until it is turned on again.
    func stop() {
        send("shutdown")
        stopping = true; detach()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in _ = sh("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"]) }
    }
}
