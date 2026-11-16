import Foundation
import SQLite3
import AppKit

/// Mirrors Mac notifications to the phone by polling the Notification Center database.
/// macOS has no public API for reading other apps' notifications, so this needs
/// Full Disk Access for whatever launches the daemon (Terminal now, the app later).
final class MacNotifications {
    private let server: Server
    private var lastId: Int64 = -1
    private var accessOK: Bool?
    var enabled: () -> Bool = { true }
    /// Apps the user excluded from sharing.
    var isMuted: (String) -> Bool = { _ in false }
    /// Every app that has posted a notification on this Mac, for the "Choose apps" list.
    var onApps: (([String]) -> Void)?
    var onAccess: ((Bool) -> Void)?
    private let src = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2")
    private let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("andromac-nc")
    /// Our own osascript notifications show up as Script Editor; skip them or we'd echo forever.
    /// (Compared in lower case: macOS stores Script Editor as "com.apple.scripteditor2", which used to slip through and echo back to the phone.)
    private let ignored: Set<String> = ["com.apple.scripteditor2", "com.apple.scripteditor.id.osascript", "app.andromac.mac"]
    /// Same app, title and text within a few seconds: send once (Calendar and others post each alert twice).
    private var recentlySent: [String: Date] = [:]

    init(server: Server) { self.server = server }

    func start() {
        poll()
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let fm = FileManager.default
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        for name in ["db", "db-wal", "db-shm"] {
            let from = src.appendingPathComponent(name), to = tmp.appendingPathComponent(name)
            try? fm.removeItem(at: to)
            do { try fm.copyItem(at: from, to: to) }
            catch {
                if name == "db" { setAccess(false); return }
            }
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.appendingPathComponent("db").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        setAccess(true)
        var ap: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT identifier FROM app", -1, &ap, nil) == SQLITE_OK {
            var ids: [String] = []
            while sqlite3_step(ap) == SQLITE_ROW { if let c = sqlite3_column_text(ap, 0) { let s = String(cString: c); if !ignored.contains(s), !s.hasPrefix("_") { ids.append(s) } } }
            sqlite3_finalize(ap)
            let sorted = ids.sorted()
            DispatchQueue.main.async { self.onApps?(sorted) }
        }

        if lastId < 0 {   // first run: start from "now", don't replay history
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id),0) FROM record", -1, &st, nil) == SQLITE_OK,
               sqlite3_step(st) == SQLITE_ROW { lastId = sqlite3_column_int64(st, 0) }
            sqlite3_finalize(st); return
        }
        var st: OpaquePointer?
        let sql = "SELECT r.rec_id, a.identifier, r.data FROM record r JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > ? ORDER BY r.rec_id"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, lastId)
        while sqlite3_step(st) == SQLITE_ROW {
            lastId = max(lastId, sqlite3_column_int64(st, 0))
            let bundle = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
            if ignored.contains(bundle.lowercased()) || bundle.lowercased().contains("scripteditor") || !enabled() || isMuted(bundle) { continue }
            guard let bytes = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(st, 2)))
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let req = plist["req"] as? [String: Any] else { continue }
            let title = req["titl"] as? String ?? "", sub = req["subt"] as? String ?? "", body = req["body"] as? String ?? ""
            if title.isEmpty && body.isEmpty { continue }
            if sub.hasSuffix("· Phone") { continue }              // a phone notification Andromac itself showed here: never send it back
            let sig = "\(bundle)|\(title)|\(body)"
            let now = Date()
            recentlySent = recentlySent.filter { now.timeIntervalSince($0.value) < 20 }
            if recentlySent[sig] != nil { continue }
            recentlySent[sig] = now
            let app = Self.appName(bundle)
            var msg: [String: Any] = ["pkg": bundle, "app": app, "title": title, "text": body, "sub": sub,
                                      "ts": Int(Date().timeIntervalSince1970 * 1000), "source": "mac"]
            if let otp = OTP.extract("\(title) \(body)") { msg["otp"] = otp }
            if let png = Self.iconPNG(bundle) { msg["icon"] = png.base64EncodedString() }
            server.send(type: "notification", data: msg)
            log("mac→phone: \(app) · \(title)")
        }
    }

    private func setAccess(_ ok: Bool) {
        guard accessOK != ok else { return }
        accessOK = ok
        DispatchQueue.main.async { self.onAccess?(ok) }
    }

    private static var iconCache: [String: Data] = [:]
    /// The app's real icon as a 96px PNG so the phone can show it on the notification.
    static func iconPNG(_ bundle: String) -> Data? {
        if let d = iconCache[bundle] { return d }
        guard let url = NSWorkspaceBridge.url(for: bundle) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        let size = NSSize(width: 96, height: 96)
        let out = NSImage(size: size); out.lockFocus(); img.draw(in: NSRect(origin: .zero, size: size)); out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return nil }
        iconCache[bundle] = png
        return png
    }

    private static func appName(_ bundle: String) -> String {
        if let url = NSWorkspaceBridge.url(for: bundle), let b = Bundle(url: url),
           let n = (b.infoDictionary?["CFBundleDisplayName"] ?? b.infoDictionary?["CFBundleName"]) as? String { return n }
        return bundle.split(separator: ".").last.map(String.init) ?? bundle
    }
}
