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
    static let canvas = Color(red: 0, green: 0, blue: 0)
    /// Card surface
    static let surface = Color(red: 0x0D/255, green: 0x0D/255, blue: 0x0D/255)
    static let surfaceRaised = Color(red: 0x15/255, green: 0x15/255, blue: 0x15/255)
    static let border = Color(red: 0x26/255, green: 0x26/255, blue: 0x26/255)
    /// Dim text: 5.9:1 on #0D0D0D, 5.3:1 on #151515
    static let dim = Color(red: 0x8C/255, green: 0x8C/255, blue: 0x8C/255)
    /// Info blue, also the keyboard focus ring
    static let info = Color(red: 0x87/255, green: 0xAF/255, blue: 0xFF/255)
    /// Green that keeps >= 4.5:1 on its background in both appearances (used for text and icons)
    static let accent = Color(red: 0x87/255, green: 0xD7/255, blue: 0x87/255)
    static let warn = Color(red: 1, green: 0xB4/255, blue: 0x54/255)
    static let danger = Color(red: 1, green: 0x8A/255, blue: 0x80/255)
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
            Circle().fill(Brand.green).frame(width: size * 0.2, height: size * 0.2)
            ZStack {
                Ellipse().stroke(Brand.silver, lineWidth: max(2, size * 0.055))
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

private struct PopupStaticKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues { var popupStatic: Bool { get { self[PopupStaticKey.self] } set { self[PopupStaticKey.self] = newValue } } }

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
        case .off: return Brand.dim
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
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content
        }
        .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.border))
    }
}

struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduce

    func makeBody(configuration: Configuration) -> some View {
        let fg: Color = kind == .primary ? Color.black : (kind == .destructive ? Brand.danger : .primary)
        let r = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(minHeight: compact ? 32 : 38)
            .background { if kind == .primary { r.fill(Brand.green) } else { r.fill(Brand.surfaceRaised) } }
            .overlay(r.strokeBorder(kind == .primary ? Color.clear : Brand.border))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
            .animation(Motion.fast(reduce), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.45)
            .focusRing(focused, radius: 10)
            .contentShape(r)
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
                Text(detail).font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
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
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detail).font(.callout).foregroundStyle(Brand.dim).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
        }
        .toggleStyle(SpringSwitchStyle(title: title, hint: detail))
        .frame(minHeight: 44)
    }
}

/// Flat switch with a spring thumb that grows when on and squeezes while pressed. The whole row is the hit target.
struct SpringSwitchStyle: ToggleStyle {
    var title: String
    var hint: String? = nil
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(SwitchButtonStyle(isOn: configuration.isOn))
            .accessibilityRepresentation {
                Toggle(title, isOn: configuration.$isOn).accessibilityHint(hint ?? "")
            }
    }
}

private struct SwitchButtonStyle: ButtonStyle {
    let isOn: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduce

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let thumb: CGFloat = isOn ? 20 : 14
        HStack(spacing: 12) {
            configuration.label
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Brand.green : Brand.surfaceRaised)
                Capsule().strokeBorder(isOn ? Brand.green : Brand.dim, lineWidth: 1.5)
                Capsule().fill(isOn ? Color.black : Brand.dim).frame(width: thumb + (pressed ? 6 : 0), height: thumb).padding(.horizontal, 5)
            }
            .frame(width: 46, height: 28)
            .animation(reduce ? Motion.fast(true) : .spring(response: 0.35, dampingFraction: 0.8), value: isOn)
            .animation(reduce ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: pressed)
            .focusRing(focused, radius: 14)
            .accessibilityHidden(true)
        }
        .opacity(enabled ? 1 : 0.38)
        .contentShape(Rectangle())
    }
}

struct MasterSwitch: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Toggle(isOn: $m.connectionEnabled) { EmptyView() }
            .toggleStyle(SpringSwitchStyle(title: "Connection", hint: "Turns the background connection to your phone on or off. It keeps running when the window is closed."))
    }
}

// MARK: - Motion and shared polish

enum Motion {
    /// 150ms emphasized-decelerate: hover, press, colour
    static func fast(_ reduce: Bool) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: 0.15) }
    /// 200ms: fades, list insert/remove, tab content
    static func normal(_ reduce: Bool) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: 0.2) }
    /// 300ms: layout and sidebar moves (Reduce Motion falls back to a 200ms fade)
    static func slow(_ reduce: Bool) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: reduce ? 0.2 : 0.3) }
}

extension View {
    /// 2px blue keyboard focus ring, drawn only while focused.
    func focusRing(_ on: Bool, radius: CGFloat) -> some View {
        self.focusEffectDisabled()
            .overlay(RoundedRectangle(cornerRadius: radius + 2, style: .continuous).strokeBorder(Brand.info, lineWidth: 2).padding(-3).opacity(on ? 1 : 0))
    }
    /// List row insert/remove: slide plus fade (fade only with Reduce Motion).
    func listTransition(_ reduce: Bool) -> some View {
        transition(reduce ? .opacity : .asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
    }
}

/// Status dot + text chip. Pulses only while connecting; static with Reduce Motion.
struct StatusChip: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var dim = false
    @Environment(\.popupStatic) private var popupStatic
    private var busy: Bool { m.uiState == .starting || m.uiState == .waiting }
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(m.statusTintAdaptive).frame(width: 8, height: 8).opacity(busy && dim ? 0.4 : 1)
            Text(m.statusShort).font(.footnote.weight(.semibold)).foregroundStyle(m.statusTintAdaptive)
        }
        .padding(.horizontal, 10).frame(minHeight: 24)
        .background(Brand.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(Brand.border))
        .animation(popupStatic ? nil : Motion.normal(reduce), value: m.uiState)
        .onAppear { if !reduce && !popupStatic { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dim = true } } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(m.statusShort)")
    }
}

/// Flat placeholder bar used instead of spinners while content loads.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.popupStatic) private var popupStatic
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Brand.surfaceRaised)
            .frame(width: width, height: height).frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(on ? 0.55 : 1)
            .onAppear { if !reduce && !popupStatic { withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { on = true } } }
            .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(Brand.dim)
            .padding(.top, 8).accessibilityAddTraits(.isHeader)
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

/// A clipboard item's preview: a small thumbnail for images, up to two lines for text and links.
struct ClipThumb: View {
    let item: ClipItem
    var body: some View {
        if let d = item.image, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 44, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Text(item.text).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
        }
    }
}
