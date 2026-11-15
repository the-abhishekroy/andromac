import SwiftUI
import AppKit

enum PermKind: String { case fullDisk, screen, accessibility, notifications }

/// A small floating window next to System Settings that says exactly which app and which switch.
enum PermissionGuide {
    private static var panel: NSPanel?

    static func show(_ kind: PermKind, model: AppModel) {
        // Registers Andromac in the right list where macOS allows it (Screen Recording, Accessibility).
        switch kind {
        case .screen: _ = CGRequestScreenCaptureAccess()
        case .accessibility: _ = InputInjector.trusted(prompt: true)
        default: break
        }
        let pane: String
        switch kind {
        case .fullDisk: pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .screen: pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility: pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .notifications: pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        }
        NSWorkspace.shared.open(URL(string: pane)!)

        panel?.close()
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
                        styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Set up Andromac"
        p.isFloatingPanel = true; p.level = .floating; p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: GuideView(kind: kind, close: { p.close() }).environmentObject(model))
        if let vis = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: vis.minX + 24, y: vis.minY + 40)) }
        p.makeKeyAndOrderFront(nil)
        panel = p
    }
}

private struct GuideView: View {
    @EnvironmentObject var m: AppModel
    let kind: PermKind
    let close: () -> Void

    private var granted: Bool {
        switch kind {
        case .fullDisk: return m.hasFullDiskAccess
        case .screen: return m.screenAccess
        case .accessibility: return m.axAccess
        case .notifications: return m.notifAccess
        }
    }
    private var title: String {
        switch kind {
        case .fullDisk: return "Full Disk Access"; case .screen: return "Screen Recording"
        case .accessibility: return "Accessibility"; case .notifications: return "Notifications"
        }
    }
    private var steps: [String] {
        switch kind {
        case .fullDisk: return [
            "System Settings is open on Full Disk Access.",
            "Drag the Andromac icon below into that list. (Or click + under the list and choose Andromac from Applications.)",
            "Switch Andromac on. If macOS asks, click Quit & Reopen, or use the button below."]
        case .screen: return [
            "Find Andromac in the list in System Settings.",
            "Switch it on. If macOS asks, click Quit & Reopen, or use the button below."]
        case .accessibility: return [
            "Find Andromac in the list in System Settings.",
            "Switch it on. (If it is not listed, click + and choose Andromac.)"]
        case .notifications: return ["Find Andromac in the list.", "Turn on Allow Notifications."]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconBadge(symbol: granted ? "checkmark.seal.fill" : "lock.shield.fill", tint: granted ? Brand.accent : Brand.warn, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Andromac").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text("Privacy & Security \u{203A} \(title)").font(.callout).foregroundStyle(Brand.dim)
                }
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(Brand.accent)
                        .frame(width: 24, height: 24).background(Circle().fill(Brand.accent.opacity(0.15)))
                    Text(t).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(i + 1): \(t)")
            }
            if kind == .fullDisk {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 72, height: 72)
                            .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                            .accessibilityLabel("Andromac app icon").accessibilityHint("Drag into the Full Disk Access list, or use Show Andromac in Finder")
                        Text("Andromac").font(.callout.weight(.medium))
                        Text("Drag me into the list").font(.caption).foregroundStyle(Brand.dim)
                    }
                    .padding(14).background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(Brand.dim))
                    Spacer()
                }
                Button("Show Andromac in Finder") { m.revealApp() }.buttonStyle(.brandCompact)
            }
            Divider()
            HStack {
                if granted { Label("Done. Andromac is allowed.", systemImage: "checkmark.circle.fill").font(.callout.weight(.semibold)).foregroundStyle(Brand.accent) }
                else { Label("Waiting for you\u{2026}", systemImage: "hourglass").font(.callout).foregroundStyle(Brand.dim) }
                Spacer()
                if kind == .fullDisk || kind == .screen { Button("Restart Andromac") { m.restartApp() }.buttonStyle(.brandCompact) }
                Button(granted ? "Close" : "Later", action: close).buttonStyle(.brandCompactPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 400).background(Brand.canvas).preferredColorScheme(.dark).tint(Brand.accent)
        .animation(Motion.normal(false), value: granted)
    }
}
