import Foundation
import AppKit

enum NSWorkspaceBridge {
    static func url(for bundle: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) }
}

/// Same rules as the Android side so OTPs from Mac notifications (e.g. Messages) are detected too.
enum OTP {
    static func extract(_ text: String) -> String? {
        let kw = try! NSRegularExpression(pattern: "\\b(otp|one[- ]time|verification|verify|code|passcode|pin|password|authenticate|login|security)\\b", options: .caseInsensitive)
        let r = NSRange(text.startIndex..., in: text)
        guard kw.firstMatch(in: text, range: r) != nil else { return nil }
        let d = try! NSRegularExpression(pattern: "(?<![\\d.])(\\d{4,8})(?!\\d)")
        guard let m = d.firstMatch(in: text, range: r), let rg = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[rg])
    }
}
