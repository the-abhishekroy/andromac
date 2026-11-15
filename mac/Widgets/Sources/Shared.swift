import SwiftUI
import Foundation

/// State written by the app to ~/.andromac/widget-status.json.
struct AndromacStatus {
    var enabled = false, connected = false, charging = false
    var phoneName: String?, battery: Int?
    var clip = ""
    var updated: Date?

    static func load() -> AndromacStatus {
        var s = AndromacStatus()
        // The sandbox remaps NSHomeDirectory(); use the real home from the password database.
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return s }
        let url = URL(fileURLWithPath: String(cString: dir)).appendingPathComponent(".andromac/widget-status.json")
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return s }
        s.enabled = o["enabled"] as? Bool ?? false
        s.connected = o["connected"] as? Bool ?? false
        s.charging = o["charging"] as? Bool ?? false
        s.phoneName = o["phoneName"] as? String
        s.battery = o["battery"] as? Int
        s.clip = o["clip"] as? String ?? ""
        s.updated = (o["updated"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return s
    }
    var statusText: String { !enabled ? "Off" : connected ? "Connected" : "Waiting" }
}

enum Flat {
    static let bg = Color.black
    static let text = Color.white
    static let dim = Color(red: 0x8C/255, green: 0x8C/255, blue: 0x8C/255)
    static let accent = Color(red: 0x87/255, green: 0xD7/255, blue: 0x87/255)
}

/// Commands go to the running app over DistributedNotificationCenter.
func sendCommand(_ name: String) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("app.andromac.widget.command"), object: name, userInfo: nil, deliverImmediately: true)
}
