import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window must not stop the connection: it keeps running from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
