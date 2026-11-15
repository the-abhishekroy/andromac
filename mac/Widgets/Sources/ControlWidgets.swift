import WidgetKit
import SwiftUI
import AppIntents

@available(macOS 26.0, *)
struct ConnectionControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { true }
        func currentValue() async throws -> Bool { AndromacStatus.load().enabled }
    }
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.andromac.mac.widgets.connection", provider: Provider()) { on in
            ControlWidgetToggle("Andromac connection", isOn: on, action: SetConnectionIntent()) { isOn in
                Label(isOn ? "Connected" : "Off", systemImage: isOn ? "iphone.radiowaves.left.and.right" : "iphone.slash")
            }
            .tint(Flat.accent)
        }
        .displayName("Andromac connection")
        .description("Turn the Andromac connection on or off.")
    }
}

@available(macOS 26.0, *)
struct ViewPhoneControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.andromac.mac.widgets.viewphone") {
            ControlWidgetButton(action: OpenPhoneIntent()) { Label("View phone", systemImage: "iphone") }
        }
        .displayName("View phone")
        .description("Show your phone's screen on this Mac.")
    }
}
