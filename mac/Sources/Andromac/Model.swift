import Foundation
import AppKit
import ServiceManagement
import ApplicationServices
import CoreGraphics
import UserNotifications
import IOKit.pwr_mgt

struct ActivityEvent: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let date = Date()
}

struct ClipItem: Identifiable {
    let id = UUID()
    let text: String
    let fromPhone: Bool
    var date = Date()
    var image: Data? = nil          // copied images (JPEG or PNG bytes)
    var mime: String? = nil
    var key: String { image.map { "img:" + ImageCodec.sha($0) } ?? text }
    var displayText: String { image != nil ? "Image" : text }
}

final class AppModel: ObservableObject {
    @Published var clipboardHistory: [ClipItem] = []
    /// Don't mirror a phone notification if the same app (WhatsApp, Telegram, Slack…) is running on this Mac and already notifies there.
    @Published var skipRunningApps: Bool { didSet { UserDefaults.standard.set(skipRunningApps, forKey: "skipRunning") } }
    private var recentlyShown: [String: Date] = [:]
    /// True if an equivalent notification was shown in the last few seconds (SMS arrives as both a text message and a notification).
    private func isDuplicateNotification(_ app: String, _ title: String, _ body: String) -> Bool {
        let norm: (String) -> String = { String($0.lowercased().filter { !$0.isWhitespace }.prefix(80)) }
        let now = Date()
        recentlyShown = recentlyShown.filter { now.timeIntervalSince($0.value) < 12 }
        let k = norm(body)
        if k.count >= 3, recentlyShown[k] != nil { return true }
        if k.count >= 3 { recentlyShown[k] = now }
        return false
    }
    /// The Mac app that already notifies for this phone app, if it is running (matched by name or well-known bundle id).
    private func runningMacApp(for phoneApp: String, pkg: String) -> String? {
        let ids: [String: String] = ["com.whatsapp": "net.whatsapp.WhatsApp", "org.telegram.messenger": "ru.keepcoder.Telegram",
            "com.Slack": "com.tinyspeck.slackmacgap", "com.slack": "com.tinyspeck.slackmacgap", "com.microsoft.teams": "com.microsoft.teams2",
            "com.discord": "com.hnc.Discord", "org.thoughtcrime.securesms": "org.whispersystems.signal-desktop",
            "com.facebook.orca": "com.facebook.archon", "com.linkedin.android": "com.linkedin.LinkedIn"]
        let name = phoneApp.lowercased()
        return NSWorkspace.shared.runningApplications.first { r in
            guard r.activationPolicy != .prohibited else { return false }
            if let id = ids[pkg], r.bundleIdentifier == id { return true }
            return (r.localizedName ?? "").lowercased() == name
        }?.localizedName
    }
    /// Off (default): Andromac draws its own banners with the real app icon on the left. On: macOS notification banners.
    @Published var nativeBanners: Bool { didSet { UserDefaults.standard.set(nativeBanners, forKey: "nativeBanners") } }
    /// Stops the Mac from going to sleep on idle, so the phone (and `ssh m5`) can always reach it. The display can still sleep.
    @Published var keepAwake: Bool { didSet { UserDefaults.standard.set(keepAwake, forKey: "keepAwake"); applyKeepAwake() } }
    private var assertionID: IOPMAssertionID = 0
    private func applyKeepAwake() {
        if keepAwake, assertionID == 0 {
            IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Andromac: keep this Mac reachable" as CFString, &assertionID)
        } else if !keepAwake, assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
    }
    /// Lets the phone's terminal reach this Mac's SSH server through Andromac's private network (only your own devices).
    @Published var terminalAccess: Bool { didSet { UserDefaults.standard.set(terminalAccess, forKey: "termOn"); tunnel.forwardSSH = terminalAccess; if connectionEnabled { tunnel.stop(); tunnel.start(port: port) } } }
    @Published var syncClipboard: Bool { didSet { UserDefaults.standard.set(syncClipboard, forKey: "syncClip") } }
    /// Master switch: when off the private network helper is stopped and nothing connects.
    @Published var connectionEnabled: Bool { didSet { UserDefaults.standard.set(connectionEnabled, forKey: "connOn"); applyConnection() } }

    // connection
    @Published var connected = false
    @Published var phoneName: String?
    @Published var battery: Int?
    @Published var charging = false
    @Published var events: [ActivityEvent] = []
    @Published var hasFullDiskAccess = true
    @Published var justCopiedLink = false
    @Published var showPair = false
    @Published var notifAccess = true
    @Published var screenAccess = true
    @Published var axAccess = true
    // embedded Tailscale
    @Published var tunnelState = "starting"      // starting | login | running | error
    @Published var tunnelLoginURL: URL?
    @Published var tunnelIP: String?
    @Published var tunnelDetail = ""
    @Published var tunnelAccount = ""
    @Published var tunnelHost = ""
    // screen sharing
    @Published var macSharing = false
    @Published var screenMessage: String?
    private var phoneWindow: PhoneScreenWindow?
    private var share: MacScreenShare?
    private let tunnel = TunnelManager()
    private var iconPNG: [String: Data] = [:]
    // phone files (WebDAV through the private network, mounted in Finder as "Phone")
    @Published var phoneFilesEnabled = false
    @Published var phoneFilesWritable = false
    @Published var phoneFilesNeedsPermission = false
    @Published var phoneFilesMounted = false
    @Published var phoneFilesMessage: String?
    private var nameProc: Process?
    private var phoneTailIP: String?
    private var cursorTimer: Timer?
    private var lastCursor = CGPoint(x: -1, y: -1)
    /// Mac-side bridge: 127.0.0.1:2223 → the phone's Termux SSH (port 8022) through the private network.
    func updatePhoneSSH() { if terminalAccess, let ip = phoneTailIP { tunnel.send("proxy 2223 \(ip):8022") } }
    private var pendingOpen: (key: String, title: String)?

    // settings
    @Published var mirrorMacNotifications: Bool { didSet { UserDefaults.standard.set(mirrorMacNotifications, forKey: "mirrorMac") } }
    @Published var autoCopyOTP: Bool { didSet { UserDefaults.standard.set(autoCopyOTP, forKey: "autoOTP") } }
    @Published var launchAtLogin: Bool {
        didSet {
            do { launchAtLogin ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { log("login item: \(error.localizedDescription)") }
        }
    }
    @Published var hasConnectedBefore: Bool { didSet { UserDefaults.standard.set(hasConnectedBefore, forKey: "paired") } }

    let port: UInt16 = 8765
    let secret = loadOrCreateSecret()
    let server: Server
    private var macNotifs: MacNotifications!
    private var widgetBridge: WidgetBridge?
    private var lastClip = NSPasteboard.general.changeCount
    @Published private(set) var pairingURL = ""

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["skipRunning": true, "nativeBanners": true, "mirrorMac": true, "autoOTP": true, "syncClip": true, "termOn": true, "connOn": true, "firstRun": true])
        let first = d.bool(forKey: "firstRun")
        syncClipboard = d.bool(forKey: "syncClip")
        terminalAccess = d.bool(forKey: "termOn")
        keepAwake = d.bool(forKey: "keepAwake")
        nativeBanners = d.bool(forKey: "nativeBanners")
        skipRunningApps = d.bool(forKey: "skipRunning")
        connectionEnabled = d.bool(forKey: "connOn")
        mirrorMacNotifications = d.bool(forKey: "mirrorMac")
        autoCopyOTP = d.bool(forKey: "autoOTP")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasConnectedBefore = d.bool(forKey: "paired")
        server = Server(channel: Channel(secret: secret), port: port)

        server.onVideo = { [weak self] _, au in
            guard let self, let w = self.phoneWindow else { return }
            if !w.decoder.decode(au) { self.server.send(type: "keyframe", data: [:]) }
        }
        server.onMessage = { [weak self] t, data in DispatchQueue.main.async { self?.handle(t, data) } }
        server.onConnect = { [weak self] in DispatchQueue.main.async { self?.connected = true; self?.hasConnectedBefore = true; if self?.syncClipboard == true { self?.sendClipSync() } } }
        server.onDisconnect = { [weak self] in DispatchQueue.main.async { self?.connected = false; self?.battery = nil } }
        do { try server.start() } catch { log("server failed: \(error)") }
        tunnel.onState = { [weak self] state, detail in self?.tunnelEvent(state, detail) }
        tunnel.forwardSSH = terminalAccess
        applyKeepAwake()
        loadClips()
        if let cur = NSPasteboard.general.string(forType: .string), !cur.isEmpty, !clipboardHistory.contains(where: { $0.text == cur }) { addClip(cur, fromPhone: false) }   // what is on the clipboard right now counts too
        AppDelegate.keepRunning = { [weak self] in self?.connectionEnabled ?? false }
        AppDelegate.onReallyQuit = { [weak self] in self?.tunnel.stop() }
        installLoginLauncher()
        BannerCenter.shared.onReply = { [weak self] key, text in
            self?.server.send(type: "notification_reply", data: ["key": key, "text": text])
            self?.record("arrowshape.turn.up.left.fill", "Replied from Mac", text)
        }
        BannerCenter.shared.onOpen = { [weak self] key, title in self?.openOnPhone(key: key, title: title) }
        if connectionEnabled { tunnel.start(port: port) } else { tunnelState = "off" }
        if first { d.set(false, forKey: "firstRun"); if Bundle.main.bundlePath.hasSuffix(".app") { launchAtLogin = true } }

        macNotifs = MacNotifications(server: server)
        widgetBridge = WidgetBridge(model: self)
        macNotifs.enabled = { [weak self] in self?.mirrorMacNotifications ?? true }
        macNotifs.onAccess = { [weak self] ok in self?.hasFullDiskAccess = ok }
        macNotifs.start()

        Notifier.shared.onReply = { [weak self] key, text in
            self?.server.send(type: "notification_reply", data: ["key": key, "text": text])
            self?.record("arrowshape.turn.up.left.fill", "Replied from Mac", text)
        }
        Notifier.shared.onOpen = { [weak self] key, title in self?.openOnPhone(key: key, title: title) }
        Notifier.setup()
        refreshPermissions()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshPermissions() }
        Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.watchClipboard() }
    }

    // MARK: messages from phone
    private func handle(_ type: String, _ data: [String: Any]) {
        switch type {
        case "hello":
            phoneName = data["device"] as? String
            if let ip = data["tip"] as? String, !ip.isEmpty { phoneTailIP = ip; updatePhoneSSH() }
            if let f = data["files"] as? [String: Any] { applyFilesState(f) }
        case "files_state":
            applyFilesState(data)
        case "battery":
            battery = data["level"] as? Int
            charging = (data["charging"] as? Bool) ?? ((data["charging"] as? Int) == 1)
        case "notification":
            let app = data["app"] as? String ?? "Phone"
            let title = data["title"] as? String ?? ""
            let text = data["text"] as? String ?? ""
            let pkg = data["pkg"] as? String ?? app
            if let b64 = data["icon"] as? String, let png = Data(base64Encoded: b64) { iconPNG[pkg] = png }
            if let macApp = skipRunningApps ? runningMacApp(for: app, pkg: pkg) : nil {
                // WhatsApp (etc.) is open on this Mac and shows its own notification with its own logo: don't show a second one.
                record("bell.fill", "\(app)\(title.isEmpty ? "" : " · \(title)")", "Shown by \(macApp) on this Mac")
                if let otp = data["otp"] as? String { gotOTP(otp, from: app) }
                return
            }
            if isDuplicateNotification(app, title, text) { return }
            if nativeBanners {
                Notifier.shared.post(title: title.isEmpty ? app : title, body: text, subtitle: "\(app) · Phone",
                                     key: data["key"] as? String, iconKey: pkg, iconPNG: iconPNG[pkg], canReply: (data["canReply"] as? Bool) ?? false, appName: app)
            } else {
                BannerCenter.shared.show(BannerItem(title: title.isEmpty ? app : title, subtitle: "\(app) · Phone", body: text,
                                                    icon: iconPNG[pkg].flatMap { NSImage(data: $0) }, key: data["key"] as? String,
                                                    canReply: (data["canReply"] as? Bool) ?? false))
            }
            record("bell.fill", "\(app)\(title.isEmpty ? "" : " · \(title)")", text)
            if let otp = data["otp"] as? String { gotOTP(otp, from: app) }
        case "sms":
            let from = data["from"] as? String ?? "SMS"
            let body = data["body"] as? String ?? ""
            if !isDuplicateNotification("SMS", from, body) { Notifier.post(title: "SMS · \(from)", body: body) }
            record("message.fill", "SMS · \(from)", body)
            if let otp = data["otp"] as? String { gotOTP(otp, from: from) }
        case "clip_sync":
            if syncClipboard, let items = data["items"] as? [[String: Any]] { mergeClips(items) }
        case "clipboard":
            if syncClipboard {
                if let b64 = data["image"] as? String, let img = Data(base64Encoded: b64) {
                    setClipboardImage(img); addImageClip(img, mime: data["mime"] as? String ?? "image/jpeg", fromPhone: true)
                } else if let text = data["text"] as? String, !text.isEmpty {
                    setClipboard(text); addClip(text, fromPhone: true)
                }
            }
        case "screen_started":
            if phoneWindow == nil {
                phoneWindow = PhoneScreenWindow(send: { [weak self] d in self?.server.send(type: "input", data: d) },
                                                onClipboard: { [weak self] in self?.sendClipboardNow() },
                                                onStop: { [weak self] in self?.stopPhoneScreen() },
                                                onClose: { [weak self] in self?.closePhoneScreen(notify: true) })
                NotificationCenter.default.addObserver(forName: .phonePaste, object: nil, queue: .main) { [weak self] _ in
                    self?.sendClipboardNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.server.send(type: "input", data: ["k": "paste"]) }
                }
            }
            phoneWindow?.setSize(data["w"] as? Int ?? 0, data["h"] as? Int ?? 0)
            phoneWindow?.show()
            server.send(type: "keyframe", data: [:])
            if let p = pendingOpen { pendingOpen = nil; server.send(type: "notification_open", data: ["key": p.key, "title": p.title]) }
            record("rectangle.on.rectangle", "Viewing phone screen", "")
        case "screen_stopped":
            closePhoneScreen(notify: false)
            if (data["reason"] as? String) == "denied" { screenMessage = "Phone declined screen sharing" }
        case "control_off":
            screenMessage = "Control is off. On the phone: Settings → Accessibility → Andromac → On."
            phoneWindow?.showControlOff()
        case "mac_open_app":
            if let id = data["bundle"] as? String, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            }
        case "mac_screen_request": askToShareMac()
        case "mac_screen_stop": stopMacShare(notify: false)
        case "mac_keyframe": share?.requestKeyframe()
        case "input":
            if (data["target"] as? String) == "mac", macSharing { InputInjector.handle(data) }
        case "ping": server.send(type: "pong", data: [:])
        default: break
        }
    }

    private func gotOTP(_ otp: String, from: String) {
        guard autoCopyOTP else { return }
        setClipboard(otp)
        Notifier.post(title: "Code copied: \(otp)", body: "From \(from)")
        record("key.fill", "Code copied: \(otp)", "From \(from)")
    }

    private func record(_ icon: String, _ title: String, _ detail: String) {
        events.insert(ActivityEvent(icon: icon, title: title, detail: detail), at: 0)
        if events.count > 40 { events.removeLast(events.count - 40) }
    }

    // MARK: clipboard
    private func setClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(text, forType: .string)
        lastClip = pb.changeCount
    }

    private func watchClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastClip else { return }
        lastClip = pb.changeCount
        let types = Set((pb.types ?? []).map { $0.rawValue })
        // password managers mark secrets as concealed/transient: never record or sync those
        if !types.isDisjoint(with: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"]) { return }
        if let t = pb.string(forType: .string), !t.isEmpty {        // text and links
            guard t.utf8.count < 100_000, !(clipboardHistory.first.map { $0.image == nil && $0.text == t } ?? false) else { return }
            addClip(t, fromPhone: false)
            if connected && syncClipboard { sendClip(t) }
            return
        }
        // images (screenshots, "Copy Image", …)
        guard let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff), let (img, mime) = ImageCodec.prepare(raw) else { return }
        if clipboardHistory.first?.key == "img:" + ImageCodec.sha(img) { return }
        addImageClip(img, mime: mime, fromPhone: false)
        if connected && syncClipboard { sendImage(img, mime) }
    }

    private func sendImage(_ d: Data, _ mime: String) {
        server.send(type: "clipboard", data: ["image": d.base64EncodedString(), "mime": mime, "ts": Int(Date().timeIntervalSince1970 * 1000)])
    }

    private func sendClip(_ t: String) {
        server.send(type: "clipboard", data: ["text": t, "ts": Int(Date().timeIntervalSince1970 * 1000)])
    }

    private func addClip(_ text: String, fromPhone: Bool, date: Date = Date()) {
        clipboardHistory.removeAll { $0.image == nil && $0.text == text }
        clipboardHistory.insert(ClipItem(text: text, fromPhone: fromPhone, date: date), at: 0)
        trimClips()
        if !fromPhone { lastLocalClip = date }
        saveClips()
    }

    private func addImageClip(_ data: Data, mime: String, fromPhone: Bool, date: Date = Date()) {
        let k = "img:" + ImageCodec.sha(data)
        clipboardHistory.removeAll { $0.key == k }
        clipboardHistory.insert(ClipItem(text: "", fromPhone: fromPhone, date: date, image: data, mime: mime), at: 0)
        trimClips()
        if !fromPhone { lastLocalClip = date }
        saveClips()
    }

    private func trimClips() {
        if clipboardHistory.count > 100 { clipboardHistory.removeLast(clipboardHistory.count - 100) }
        var images = 0
        clipboardHistory.removeAll { if $0.image != nil { images += 1; return images > 30 }; return false }   // keep the 30 newest images
    }

    private func setClipboardImage(_ data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let img = NSImage(data: data) { pb.writeObjects([img]) }
        lastClip = pb.changeCount
    }

    // MARK: clipboard history: saved on this Mac and exchanged with the phone every time they connect
    private var lastLocalClip = Date.distantPast
    private var saveWork: DispatchWorkItem?
    private var clipFile: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Andromac", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return d.appendingPathComponent("clipboard.json")
    }
    private var clipDir: URL {
        let d = clipFile.deletingLastPathComponent().appendingPathComponent("clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return d
    }
    private func saveClips() {
        saveWork?.cancel()
        let snapshot = clipboardHistory
        let w = DispatchWorkItem { [clipFile, clipDir] in
            var keep = Set<String>(); var rows: [[String: Any]] = []
            for it in snapshot {
                if let img = it.image {
                    let name = ImageCodec.sha(img) + ((it.mime == "image/png") ? ".png" : ".jpg"); keep.insert(name)
                    let f = clipDir.appendingPathComponent(name)
                    if !FileManager.default.fileExists(atPath: f.path) { try? img.write(to: f) }
                    rows.append(["f": name, "mt": it.mime ?? "image/jpeg", "p": it.fromPhone, "d": it.date.timeIntervalSince1970])
                } else { rows.append(["t": it.text, "p": it.fromPhone, "d": it.date.timeIntervalSince1970]) }
            }
            for f in (try? FileManager.default.contentsOfDirectory(atPath: clipDir.path)) ?? [] where !keep.contains(f) { try? FileManager.default.removeItem(at: clipDir.appendingPathComponent(f)) }
            if let data = try? JSONSerialization.data(withJSONObject: rows) {
                try? data.write(to: clipFile, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: clipFile.path)
            }
        }
        saveWork = w; DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: w)
    }
    private func loadClips() {
        guard let data = try? Data(contentsOf: clipFile), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        clipboardHistory = arr.compactMap { o in
            guard let d = o["d"] as? Double else { return nil }
            if let f = o["f"] as? String {
                guard let img = try? Data(contentsOf: clipDir.appendingPathComponent(f)) else { return nil }
                return ClipItem(text: "", fromPhone: (o["p"] as? Bool) ?? false, date: Date(timeIntervalSince1970: d), image: img, mime: o["mt"] as? String ?? "image/jpeg")
            }
            guard let t = o["t"] as? String else { return nil }
            return ClipItem(text: t, fromPhone: (o["p"] as? Bool) ?? false, date: Date(timeIntervalSince1970: d))
        }.sorted { $0.date > $1.date }
        lastLocalClip = clipboardHistory.first(where: { !$0.fromPhone })?.date ?? .distantPast
    }
    /// Everything we have, for the phone (newest first; huge items skipped).
    private func sendClipSync() {
        var images = 0
        var items: [[String: Any]] = []
        for it in clipboardHistory.prefix(100) {
            var o: [String: Any] = ["s": it.fromPhone ? "phone" : "mac", "ts": Int(it.date.timeIntervalSince1970 * 1000)]
            if let img = it.image { images += 1; if images > 10 { continue }; o["img"] = img.base64EncodedString(); o["mime"] = it.mime ?? "image/jpeg" }
            else if it.text.utf8.count < 20_000 { o["t"] = it.text } else { continue }
            items.append(o)
        }
        server.send(type: "clip_sync", data: ["items": items])
    }
    /// Merge the phone's history into ours. If the phone's newest item is newer than anything copied here, make it current.
    private func mergeClips(_ items: [[String: Any]]) {
        for o in items {
            guard let ms = o["ts"] as? Double ?? (o["ts"] as? Int).map(Double.init) else { continue }
            let fromPhone = (o["s"] as? String) != "mac", date = Date(timeIntervalSince1970: ms / 1000)
            if let b64 = o["img"] as? String, let img = Data(base64Encoded: b64) {
                let k = "img:" + ImageCodec.sha(img)
                if clipboardHistory.contains(where: { $0.key == k }) { continue }
                clipboardHistory.append(ClipItem(text: "", fromPhone: fromPhone, date: date, image: img, mime: o["mime"] as? String ?? "image/jpeg"))
            } else if let t = o["t"] as? String, !t.isEmpty {
                if clipboardHistory.contains(where: { $0.image == nil && $0.text == t }) { continue }
                clipboardHistory.append(ClipItem(text: t, fromPhone: fromPhone, date: date))
            }
        }
        clipboardHistory.sort { $0.date > $1.date }
        trimClips(); saveClips()
        if syncClipboard, let newest = clipboardHistory.first, newest.fromPhone, newest.date > lastLocalClip {
            if let img = newest.image { setClipboardImage(img) } else { setClipboard(newest.text) }
        }
    }

    /// Put a history item back on this Mac's clipboard and on the phone's.
    func recopy(_ item: ClipItem) {
        if let img = item.image {
            setClipboardImage(img); addImageClip(img, mime: item.mime ?? "image/jpeg", fromPhone: item.fromPhone)
            if connected && syncClipboard { sendImage(img, item.mime ?? "image/jpeg") }
        } else {
            setClipboard(item.text)
            addClip(item.text, fromPhone: item.fromPhone)
            if connected && syncClipboard { sendClip(item.text) }
        }
    }

    func clearClipboardHistory() { clipboardHistory.removeAll(); saveClips() }

    /// Fully drop the connection (private network helper and phone session), then bring it up again.
    func reconnect() {
        if !connectionEnabled { connectionEnabled = true; return }
        tunnel.stop(); server.disconnect()
        tunnelState = "starting"; tunnelIP = nil; connected = false; battery = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.connectionEnabled else { return }
            self.tunnel.start(port: self.port)
        }
    }

    private func applyConnection() {
        if connectionEnabled {
            if tunnelState == "off" || tunnelState == "error" { tunnelState = "starting"; tunnel.start(port: port) }
        } else {
            tunnel.stop(); server.disconnect()
            tunnelState = "off"; tunnelIP = nil; pairingURL = ""; connected = false; battery = nil
        }
    }

    func sendClipboardNow() {
        guard let t = NSPasteboard.general.string(forType: .string) else { return }
        sendClip(t)
    }

    // MARK: tunnel
    private func makePairingURL(_ host: String) -> String { "andromac://\(host):\(port)/\(secret.base64URL())" }

    private func tunnelEvent(_ state: String, _ detail: String) {
        switch state {
        case "account":
            let p = detail.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            tunnelAccount = p.first ?? ""; tunnelHost = p.count > 1 ? p[1] : ""
        case "login": tunnelState = "login"; tunnelLoginURL = URL(string: detail); tunnelAccount = ""
        case "running": tunnelState = "running"; tunnelLoginURL = nil; tunnelIP = detail; pairingURL = makePairingURL(detail); updatePhoneSSH()
            if tunnelIP != nil { refreshPermissions() }
        case "error": tunnelState = "error"; tunnelDetail = detail
        default: if tunnelState != "login" && tunnelState != "running" { tunnelState = "starting" }
        }
    }

    private func applyFilesState(_ f: [String: Any]) {
        phoneFilesEnabled = (f["enabled"] as? Bool) ?? false
        phoneFilesWritable = (f["write"] as? Bool) ?? false
        phoneFilesNeedsPermission = (f["needsPermission"] as? Bool) ?? false
        if !phoneFilesEnabled { phoneFilesMounted = false }
    }

    /// Open the phone's storage in Finder as the drive "Phone".
    func mountPhoneFiles() {
        guard let ip = phoneTailIP else { phoneFilesMessage = "Connect your phone first."; return }
        guard phoneFilesEnabled else {
            phoneFilesMessage = phoneFilesNeedsPermission ? "On the phone: Settings, Files on your Mac, Allow all files access."
                                                          : "On the phone: Settings, Files on your Mac, turn on Share this phone's files."
            return
        }
        tunnel.send("proxy 8790 \(ip):8790")              // Mac 127.0.0.1:8790 -> phone file server, through the private network
        phoneFilesMessage = "Mounting…"
        let pw = davPassword(secret: secret)
        // Finder labels a network drive with the host name it connected to. Register "phone.local" (pointing at this Mac's own
        // tunnel doorway) with Bonjour so the drive is called "Phone" in the sidebar, and keep that registration alive while mounted.
        if nameProc?.isRunning != true {
            let n = Process(); n.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
            n.arguments = ["-P", "Phone", "_http._tcp", "local", "8790", "Phone.local", "127.0.0.1"]
            n.standardOutput = Pipe(); n.standardError = Pipe(); try? n.run(); nameProc = n
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let script = "mount volume \"http://Phone.local:8790/Phone/\" as user name \"andromac\" with password \"\(pw)\""
            let p = Process(), err = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
            p.standardError = err; p.standardOutput = Pipe()
            try? p.run(); p.waitUntilExit()
            let ok = p.terminationStatus == 0
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.phoneFilesMounted = ok
                self?.phoneFilesMessage = ok ? nil : "Could not mount: \(msg.prefix(120))"
                if ok { NSWorkspace.shared.open(URL(fileURLWithPath: "/Volumes/Phone")) }
            }
        }
    }

    func unmountPhoneFiles() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil"); p.arguments = ["unmount", "/Volumes/Phone"]
        try? p.run(); p.waitUntilExit(); phoneFilesMounted = false; nameProc?.terminate(); nameProc = nil
    }

    func tunnelSignOut() { tunnelIP = nil; tunnel.send("logout") }

    func openTunnelLogin() { if let u = tunnelLoginURL { NSWorkspace.shared.open(u) } }

    // MARK: screen sharing
    func requestPhoneScreen() { server.send(type: "screen_request", data: [:]); screenMessage = "Approve on the phone…" }

    /// Clicked a phone notification on the Mac: show the phone and open that conversation there.
    func openOnPhone(key: String, title: String) {
        if phoneWindow != nil { phoneWindow?.show(); server.send(type: "notification_open", data: ["key": key, "title": title]) }
        else { pendingOpen = (key, title); requestPhoneScreen() }
    }

    func stopPhoneScreen() { server.send(type: "screen_stop", data: [:]); closePhoneScreen(notify: true) }

    private func closePhoneScreen(notify: Bool) {
        phoneWindow?.close(); phoneWindow = nil; screenMessage = nil
    }

    private func askToShareMac() {
        // Without the macOS Screen Recording permission nothing can be shared, so say so instead of asking a question we can't honour.
        guard CGPreflightScreenCaptureAccess() else {
            screenMessage = "Allow Screen Recording for Andromac first."
            server.send(type: "mac_screen_denied", data: ["reason": "permission"])
            Notifier.post(title: "Andromac needs Screen Recording", body: "Your phone asked to see this Mac. Open Andromac → Set up → Screen Recording.")
            NSApp.activate(ignoringOtherApps: true)
            PermissionGuide.show(.screen, model: self)
            return
        }
        let a = NSAlert()
        a.messageText = "Let your phone view and control this Mac?"
        a.informativeText = "Your phone will see your screen and can move the mouse and type until you stop it. Only allow this if you just asked for it on your phone."
        a.addButton(withTitle: "Allow"); a.addButton(withTitle: "Deny")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { server.send(type: "mac_screen_denied", data: [:]); return }
        _ = InputInjector.trusted(prompt: true)       // asks for Accessibility if missing
        let s = MacScreenShare(); share = s
        server.onCongestion = { [weak s] in s?.congestion() }
        s.onPacket = { [weak self] key, data in self?.server.sendVideo(keyframe: key, data) }
        s.onStopped = { [weak self] in DispatchQueue.main.async { self?.stopMacShare(notify: true) } }
        Task { @MainActor in
            do {
                try await s.start()
                macSharing = true
                cursorTimer?.invalidate()
                cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
                    guard let self, self.macSharing, let scr = NSScreen.main else { return }
                    let p = NSEvent.mouseLocation, f = scr.frame
                    let q = CGPoint(x: (p.x - f.minX) / f.width, y: 1 - (p.y - f.minY) / f.height)
                    if abs(q.x - self.lastCursor.x) > 0.002 || abs(q.y - self.lastCursor.y) > 0.002 {
                        self.lastCursor = q; self.server.send(type: "cursor", data: ["x": Double(q.x), "y": Double(q.y)])
                    }
                }
                server.send(type: "mac_screen_started", data: ["w": Int(s.size.width), "h": Int(s.size.height)])
                record("display", "Phone is viewing this Mac", "")
            } catch {
                share = nil
                screenMessage = "Could not start screen sharing: \(error.localizedDescription)"
                server.send(type: "mac_screen_denied", data: ["reason": "permission"])
                PermissionGuide.show(.screen, model: self)
            }
        }
    }

    func stopMacShare(notify: Bool) {
        share?.stop(); share = nil; macSharing = false; cursorTimer?.invalidate(); cursorTimer = nil
        if notify { server.send(type: "mac_screen_stopped", data: [:]) }
    }

    // MARK: actions
    func copyPairingLink() {
        setClipboard(pairingURL)
        justCopiedLink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.justCopiedLink = false }
    }

    func refreshPermissions() {
        screenAccess = CGPreflightScreenCaptureAccess()
        axAccess = AXIsProcessTrusted()
        if Bundle.main.bundlePath.hasSuffix(".app") {
            UNUserNotificationCenter.current().getNotificationSettings { st in
                let ok = st.authorizationStatus == .authorized || st.authorizationStatus == .provisional
                DispatchQueue.main.async { self.notifAccess = ok }
            }
        }
    }

    func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// Shows Andromac.app in Finder so it can be dragged into (or picked with +) the Full Disk Access list.
    func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }

    func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }

    /// Start Andromac (hidden, no window) every time you log in, so notifications, clipboard and the phone link are live
    /// right after a restart. The connection service itself is a separate launchd job (see TunnelManager).
    private func installLoginLauncher() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/app.andromac.app.plist")
        let plist: [String: Any] = [
            "Label": "app.andromac.app",
            "ProgramArguments": [Bundle.main.bundlePath + "/Contents/MacOS/Andromac"],
            "EnvironmentVariables": ["ANDROMAC_BG": "1"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],          // a crash or force-quit brings it back; "Quit and disconnect" stays quit
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        guard (try? Data(contentsOf: url)) != data else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data?.write(to: url)
        // loaded from the next login on (loading it now would start a second copy of the running app)
    }

    func restartApp() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open '\(Bundle.main.bundlePath)'"]
        try? p.run(); tunnel.leaveRunning(); NSApp.terminate(nil)
    }

    func guide(_ kind: PermKind) { PermissionGuide.show(kind, model: self) }

    func openFullDiskAccess() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    static func tailscaleIP() -> String {
        for path in ["/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale",
                     "/Applications/Tailscale.app/Contents/MacOS/Tailscale"] where FileManager.default.isExecutableFile(atPath: path) {
            let p = Process(), out = Pipe()
            p.executableURL = URL(fileURLWithPath: path); p.arguments = ["ip", "-4"]
            p.standardOutput = out; p.standardError = Pipe()
            if (try? p.run()) != nil {
                p.waitUntilExit()
                let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if let ip = s.split(separator: "\n").first { return String(ip) }
            }
        }
        return "100.x.x.x"
    }
}
