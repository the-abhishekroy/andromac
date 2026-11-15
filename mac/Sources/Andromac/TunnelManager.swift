import Foundation

/// Runs the bundled Go sidecar (embedded Tailscale node) and reports its state.
final class TunnelManager {
    private var proc: Process?
    private var stdin: FileHandle?
    private var stopping = false
    private var backoff = 1.0
    private var port: UInt16 = 8765
    var onState: ((_ state: String, _ detail: String) -> Void)?

    static func binaryURL() -> URL? {
        if let u = Bundle.main.url(forResource: "andromac-tunnel", withExtension: nil) { return u }
        // dev fallback: repo checkout next to the mac/ folder
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tunnel/build/andromac-tunnel")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    var forwardSSH = true

    func start(port: UInt16) {
        self.port = port; stopping = false
        launch()
    }

    private func launch() {
        // never leave two helpers fighting over one identity (e.g. after a crash)
        let k = Process(); k.executableURL = URL(fileURLWithPath: "/usr/bin/pkill"); k.arguments = ["-x", "andromac-tunnel"]
        try? k.run(); k.waitUntilExit()
        guard let bin = Self.binaryURL() else { onState?("error", "tunnel helper missing"); return }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".andromac/tailscale").path
        let p = Process(), out = Pipe()
        p.executableURL = bin
        p.arguments = ["-dir", dir, "-host", "andromac-mac", "-port", String(port), "-target", "127.0.0.1:\(port)"]
        if forwardSSH { p.arguments! += ["-forward", "22=127.0.0.1:22"] }
        let inp = Pipe(); p.standardInput = inp; stdin = inp.fileHandleForWriting
        p.standardOutput = out; p.standardError = Pipe()
        var buffer = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            buffer.append(h.availableData)
            while let nl = buffer.firstIndex(of: 10) {
                let line = buffer.subdata(in: buffer.startIndex..<nl); buffer.removeSubrange(buffer.startIndex...nl)
                if let o = try? JSONSerialization.jsonObject(with: line) as? [String: String] {
                    DispatchQueue.main.async { if o["state"] == "running" { self?.backoff = 1 }; self?.onState?(o["state"] ?? "", o["detail"] ?? "") }
                }
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.stopping else { return }
                self.onState?("starting", "reconnecting")
                let delay = self.backoff; self.backoff = min(self.backoff * 2, 30)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if !self.stopping { self.launch() } }
            }
        }
        do { try p.run(); proc = p } catch { onState?("error", error.localizedDescription) }
    }

    func send(_ command: String) { stdin?.write(Data((command + "\n").utf8)) }

    func stop() { stopping = true; proc?.terminationHandler = nil; proc?.terminate(); proc = nil }
}
