import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set true only by the explicit "Quit and disconnect" button.
    static var reallyQuit = false
    /// True while the connection switch is on (set by the model).
    static var keepRunning: () -> Bool = { true }

    /// Closing the window must not stop the connection: it keeps running from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
        return .terminateNow
    }
}

@main
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
