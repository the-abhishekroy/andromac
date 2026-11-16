import SwiftUI

/// The login copy: no window, no Dock icon, no menu bar icon. Just the connection (server, clipboard, notifications).
/// When the user opens Andromac it hands over to the normal app, which shows the window and the menu bar icon.
final class HeadlessDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.andromac.open"), object: nil, queue: .main) { [weak self] _ in self?.handOver() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { handOver(); return false }
    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        if AppDelegate.reallyQuit { AppDelegate.onReallyQuit(); return .terminateNow }
        return .terminateNow
    }
    /// Quit this copy and start the normal app in its place; the private network service keeps running meanwhile.
    private var handing = false
    func handOver() {
        guard !handing else { return }; handing = true
        model?.tunnelLeaveRunning()
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // unload the login job first (otherwise launchd would start the quiet copy again), then open the normal app
        p.arguments = ["-c", "unset ANDROMAC_BG; /bin/launchctl bootout gui/\(getuid())/app.andromac.app; sleep 1.5; pgrep -x Andromac >/dev/null && sleep 2; open '\(Bundle.main.bundlePath)'"]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set true only by the explicit "Quit and disconnect" button.
    static var reallyQuit = false
    /// Called when Andromac really quits ("Quit and disconnect"): stop the background service too.
    static var onReallyQuit: () -> Void = {}
    /// True while the connection switch is on (set by the model).
    static var keepRunning: () -> Bool = { true }

    /// Closing the window must not stop the connection: it keeps running from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillFinishLaunching(_ n: Notification) {
        // No window restoration: after a force-quit or crash macOS would otherwise ask "reopen windows?" on the next launch.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        // One copy only: if the quiet login copy (or any other) is running, ask it to hand over, then step aside.
        let me = Bundle.main.bundleIdentifier ?? ""
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: me).first(where: { $0 != NSRunningApplication.current }) {
            other.activate()
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("app.andromac.open"), object: nil, userInfo: nil, deliverImmediately: true)
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // When the last real window closes, drop the Dock icon so Andromac behaves like a background service.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                let visible = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && $0.styleMask.contains(.titled) }
                if !visible { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    /// ⌘Q or Dock → Quit: hide instead of stopping, as long as the connection is on. Use "Quit and disconnect" to really quit.
    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        if !Self.reallyQuit && Self.keepRunning() {
            NSApp.windows.filter { $0.styleMask.contains(.titled) }.forEach { $0.close() }
            NSApp.setActivationPolicy(.accessory)
            return .terminateCancel
        }
        if Self.reallyQuit { Self.onReallyQuit() }
        return .terminateNow
    }
}

struct AndromacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Andromac", id: "main") {
            MainWindow().environmentObject(model)
        }
        .defaultSize(width: 1000, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Quick Actions…") { NotificationCenter.default.post(name: .openPalette, object: nil) }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuView().environmentObject(model)
        } label: {
            Image(systemName: !model.connectionEnabled ? "iphone.slash" : (model.connected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3"))
                .accessibilityLabel("Andromac")
                .accessibilityValue(model.statusShort)
        }
        .menuBarExtraStyle(.window)
    }
}


@main
enum Launcher {
    static func main() {
        if ProcessInfo.processInfo.environment["ANDROMAC_BG"] == "1" {
            let app = NSApplication.shared
            let d = HeadlessDelegate()
            app.delegate = d
            app.run()
        } else {
            AndromacApp.main()
        }
    }
}
