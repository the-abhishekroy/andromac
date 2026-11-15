import SwiftUI
import AppKit

// MARK: - Brand tokens

enum Brand {
    static let navy = Color(red: 0x0D/255, green: 0x0D/255, blue: 0x0D/255)  // near-black (name kept for call sites)
    static let navy2 = Color(red: 0x12/255, green: 0x12/255, blue: 0x12/255)
    static let green = Color(red: 0x87/255, green: 0xD7/255, blue: 0x87/255)   // same soft green as the terminal prompt
    static let silver = Color(red: 0xC8/255, green: 0xCB/255, blue: 0xD0/255)

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    /// Window background
    static let canvas = dynamic(light: rgb(0xF2F2F4), dark: rgb(0x000000))
    /// Card surface
    static let surface = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x0D0D0D))
    static let surfaceRaised = dynamic(light: rgb(0xEDEDF0), dark: rgb(0x151515))
    static let border = dynamic(light: NSColor.black.withAlphaComponent(0.09), dark: rgb(0x262626))
    /// Green that keeps >= 4.5:1 on its background in both appearances (used for text and icons)
    static let accent = dynamic(light: rgb(0x0A7A3D), dark: rgb(0x87D787))
    static let warn = dynamic(light: rgb(0x9A4A00), dark: rgb(0xFFB454))
    static let danger = dynamic(light: rgb(0xB3261E), dark: rgb(0xFF8A80))
    static let heroGradient = LinearGradient(colors: [navy, navy], startPoint: .top, endPoint: .bottom)   // flat: no gradient
}

// MARK: - Orbit logo

struct OrbitLogo: View {
    var size: CGFloat = 64
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let w = size, h = size * 0.46
        ZStack {
            if pulsing && !reduceMotion {
                Circle().stroke(Brand.green.opacity(0.5), lineWidth: 1.5)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .scaleEffect(pulse ? 2.1 : 1).opacity(pulse ? 0 : 0.7)
            }
            Circle().fill(RadialGradient(colors: [Brand.green.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: size * 0.42))
                .frame(width: size, height: size)
            Circle().fill(Brand.green).frame(width: size * 0.2, height: size * 0.2)
                .shadow(color: Brand.green.opacity(0.9), radius: size * 0.1)
            ZStack {
                Ellipse().stroke(LinearGradient(colors: [Brand.silver, Brand.green], startPoint: .leading, endPoint: .trailing), lineWidth: max(2, size * 0.055))
                    .frame(width: w, height: h)
                Circle().fill(Brand.silver).frame(width: size * 0.13, height: size * 0.13)
                    .offset(x: -w / 2 * 0.80, y: -h / 2 * 0.60)
                Circle().fill(Brand.green).frame(width: size * 0.11, height: size * 0.11)
                    .offset(x: w / 2 * 0.86, y: h / 2 * 0.52)
            }
            .rotationEffect(.degrees(-24))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard pulsing, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - App state helpers for the UI

enum ConnState {
    case off, starting, signIn, problem, waiting, connected
}

extension AppModel {
    var signedIn: Bool { tunnelState == "running" }
    var permissionsOK: Bool { hasFullDiskAccess && screenAccess && axAccess && notifAccess }
    var setupDone: Bool { signedIn && hasConnectedBefore && permissionsOK }
    var missingPermissionCount: Int { [hasFullDiskAccess, screenAccess, axAccess, notifAccess].filter { !$0 }.count }

    /// The first missing permission, for "fix it" shortcuts.
    var firstMissingPermission: PermKind? {
        if !hasFullDiskAccess { return .fullDisk }
        if !notifAccess { return .notifications }
        if !screenAccess { return .screen }
        if !axAccess { return .accessibility }
        return nil
    }

    var uiState: ConnState {
        if !connectionEnabled { return .off }
        if connected { return .connected }
        switch tunnelState {
        case "login": return .signIn
        case "error": return .problem
        case "running": return .waiting
        default: return .starting
        }
    }
    var statusTitle: String {
        switch uiState {
        case .off: return "Connection is off"
        case .starting: return "Starting secure connection"
        case .signIn: return "Sign-in needed"
        case .problem: return "Connection problem"
        case .waiting: return "Waiting for your phone"
        case .connected: return "Connected to \(phoneName ?? "your phone")"
        }
    }
    var statusDetail: String {
        switch uiState {
        case .off: return "Your phone can't reach this Mac. Turn the switch on to reconnect."
        case .starting: return "This only takes a moment."
        case .signIn: return "Sign in to the private network so your phone can find this Mac."
        case .problem: return tunnelDetail.isEmpty ? "Andromac couldn't start the private network." : tunnelDetail
        case .waiting: return "Open Andromac on your phone. It reconnects on its own."
        case .connected: return "Notifications, codes and clipboard are syncing."
        }
    }
    var statusSymbol: String {
        switch uiState {
        case .off: return "power"
        case .starting: return "arrow.triangle.2.circlepath"
        case .signIn: return "person.crop.circle.badge.exclamationmark"
        case .problem: return "exclamationmark.triangle.fill"
        case .waiting: return "hourglass"
        case .connected: return "checkmark.circle.fill"
        }
    }
    var statusShort: String {
        switch uiState {
        case .off: return "Off"; case .starting: return "Starting"; case .signIn: return "Sign-in needed"
        case .problem: return "Problem"; case .waiting: return "Waiting"; case .connected: return "Connected"
        }
    }
    /// Tint for use on the dark navy hero.
    var statusTint: Color {
        switch uiState {
        case .connected: return Brand.green
        case .off: return Brand.silver
        case .problem: return Color(red: 1, green: 0.54, blue: 0.5)
        default: return Color(red: 1, green: 0.71, blue: 0.33)
        }
    }
    /// Tint for use on normal surfaces.
    var statusTintAdaptive: Color {
        switch uiState {
        case .connected: return Brand.accent
        case .off: return .secondary
        case .problem: return Brand.danger
        default: return Brand.warn
        }
    }
}

extension ClipItem {
    var sourceName: String { fromPhone ? "Phone" : "Mac" }
    var sourceSymbol: String { fromPhone ? "iphone.gen3" : "desktopcomputer" }
}

// MARK: - Components

struct Card<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content
        }
        .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Brand.border))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }
}

struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let fg: Color = kind == .primary ? Brand.navy : (kind == .destructive ? Brand.danger : .primary)
        configuration.label
            .font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(minHeight: compact ? 32 : 38)
            .background {
                let r = RoundedRectangle(cornerRadius: 10, style: .continuous)
                if kind == .primary { r.fill(Brand.green) } else { r.fill(Brand.surfaceRaised) }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(kind == .primary ? Color.clear : Brand.border))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
    static var brandSecondary: BrandButtonStyle { BrandButtonStyle(kind: .secondary) }
    static var brandCompact: BrandButtonStyle { BrandButtonStyle(kind: .secondary, compact: true) }
    static var brandCompactPrimary: BrandButtonStyle { BrandButtonStyle(kind: .primary, compact: true) }
    static var brandDestructive: BrandButtonStyle { BrandButtonStyle(kind: .destructive) }
}

/// Icon in a soft rounded square.
struct IconBadge: View {
    let symbol: String
    var tint: Color = Brand.accent
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol).font(.body.weight(.semibold)).symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint).frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Status pill: icon + text so state is never conveyed by colour alone.
struct StatusPill: View {
    let ok: Bool
    var okText = "Allowed", badText = "Needs setup"
    var body: some View {
        Label(ok ? okText : badText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(ok ? Brand.accent : Brand.warn)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((ok ? Brand.accent : Brand.warn).opacity(0.13), in: Capsule())
    }
}

struct PermissionRow: View {
    let symbol: String, title: String, detail: String, ok: Bool
    var action: (() -> Void)? = nil
    var secondary: (String, () -> Void)? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(symbol: symbol, tint: ok ? Brand.accent : Brand.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if ok { StatusPill(ok: true) }
            else {
                if let secondary { Button(secondary.0, action: secondary.1).buttonStyle(.brandCompact) }
                if let action {
                    Button("Set up", action: action).buttonStyle(.brandCompactPrimary)
                        .accessibilityLabel("Set up \(title)").accessibilityHint("Opens a step by step guide next to System Settings")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ToggleRow: View {
    let symbol: String, title: String, detail: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Brand.green)
                .accessibilityLabel(title).accessibilityHint(detail)
        }
        .frame(minHeight: 40)
    }
}

struct SourceBadge: View {
    let item: ClipItem
    var body: some View {
        Label(item.sourceName, systemImage: item.sourceSymbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(item.fromPhone ? Brand.accent : Color.primary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((item.fromPhone ? Brand.accent : Color.primary).opacity(0.10), in: Capsule())
    }
}

struct MasterSwitch: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Toggle("Connection", isOn: $m.connectionEnabled)
            .labelsHidden().toggleStyle(.switch).tint(Brand.green).controlSize(.large)
            .accessibilityLabel("Connection")
            .accessibilityValue(m.connectionEnabled ? "On" : "Off")
            .accessibilityHint("Turns the background connection to your phone on or off. It keeps running when the window is closed.")
    }
}
