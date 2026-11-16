import Foundation
import AppKit
import UserNotifications

/// Posts Mac notifications that carry the real app icon plus a device badge, with an inline Reply action.
/// macOS always shows the sending app's own icon on the left, so the source app's icon goes in as the attachment thumbnail.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private static let isBundle = Bundle.main.bundlePath.hasSuffix(".app")
    var onReply: ((_ key: String, _ text: String) -> Void)?
    var onOpen: ((_ key: String, _ title: String) -> Void)?
    private var iconFiles: [String: URL] = [:]

    static func setup() {
        guard isBundle else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = shared
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Reply on your phone")
        c.setNotificationCategories([
            UNNotificationCategory(identifier: "reply", actions: [reply], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "plain", actions: [], intentIdentifiers: [], options: []),
        ])
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// The app's own icon, cached as a file for the notification attachment (no badge: the subtitle already says it came from the phone).
    private func badgedIcon(bundleKey: String, png: Data?) -> URL? {
        if let u = iconFiles[bundleKey] { return u }
        guard let png, let base = NSImage(data: png) else { return nil }
        let size = NSSize(width: 256, height: 256)
        let out = NSImage(size: size)
        out.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("andromac-icon-\(abs(bundleKey.hashValue)).png")
        try? data.write(to: url)
        iconFiles[bundleKey] = url
        return url
    }

    func post(title: String, body: String, subtitle: String? = nil, key: String? = nil, iconKey: String? = nil, iconPNG: Data? = nil, canReply: Bool = false, appName: String? = nil) {
        guard Self.isBundle else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        if let subtitle { c.subtitle = subtitle }
        c.categoryIdentifier = canReply ? "reply" : "plain"
        if let key { c.userInfo = ["key": key, "title": title] }
        if let iconKey {
            if let url = badgedIcon(bundleKey: iconKey, png: iconPNG) {
                do { c.attachments = [try UNNotificationAttachment(identifier: "icon", url: url, options: [UNNotificationAttachmentOptionsThumbnailClippingRectKey: CGRect(x: 0, y: 0, width: 1, height: 1).dictionaryRepresentation])] }
                catch { log("notification icon failed: \(error.localizedDescription)") }
            } else { log("notification icon: no image for \(iconKey) (png \(iconPNG?.count ?? 0) bytes)") }
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)) { err in
            if err != nil {
                // notifications not allowed: show Andromac's own banner instead of a script-made one (those show as "Script Editor" and get mirrored back)
                DispatchQueue.main.async { BannerCenter.shared.show(BannerItem(title: title, subtitle: subtitle ?? "", body: body, icon: nil, key: key, canReply: canReply)) }
            }
        }
    }

    // banner even while Andromac is frontmost
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) { done([.banner, .sound]) }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        let info = r.notification.request.content.userInfo
        let key = info["key"] as? String ?? "", title = info["title"] as? String ?? ""
        DispatchQueue.main.async {
            if r.actionIdentifier == "reply", let t = r as? UNTextInputNotificationResponse { self.onReply?(key, t.userText) }
            else if r.actionIdentifier == UNNotificationDefaultActionIdentifier, !key.isEmpty { self.onOpen?(key, title) }
        }
        done()
    }

    // legacy: plain call used by SMS / OTP notices
    static func post(title: String, body: String) { shared.post(title: title, body: body) }

}
