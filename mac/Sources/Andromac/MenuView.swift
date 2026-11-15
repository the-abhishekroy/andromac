import SwiftUI

struct MenuView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var copiedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            notices
            clipboardSection
            actions
            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(Brand.canvas)
        .preferredColorScheme(.dark)
        .tint(Brand.accent)
        .animation(Motion.slow(reduce), value: m.connected)
        .animation(Motion.normal(reduce), value: m.clipboardHistory.count)
        .animation(Motion.normal(reduce), value: m.uiState)
    }

    private func openMain() {
        NSApp.setActivationPolicy(.regular); openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                OrbitLogo(size: 48, pulsing: m.uiState == .connected)
                VStack(alignment: .leading, spacing: 3) {
                    Label(m.statusShort, systemImage: m.statusSymbol)
                        .font(.caption.weight(.bold)).textCase(.uppercase).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(m.statusTint)
                    Text(m.statusTitle).font(.headline).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(spacing: 4) {
                    MasterSwitch()
                    Text(m.connectionEnabled ? "On" : "Off").font(.caption.weight(.semibold)).foregroundStyle(.white)
                }
            }
            Text(m.connectionEnabled && m.connected ? "Runs in the background, even when the window is closed." : m.statusDetail)
                .font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
            if m.connectionEnabled && m.connected, let b = m.battery {
                HStack(spacing: 6) {
                    Image(systemName: m.charging ? "battery.100percent.bolt" : "battery.75percent")
                    Text("Phone battery")
                    Text("\(b)%").monospacedDigit().contentTransition(.numericText(value: Double(b)))
                    if m.charging { Text("charging") }
                }
                .font(.callout).foregroundStyle(Brand.dim)
                .animation(Motion.normal(reduce), value: b)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Phone battery \(b) percent\(m.charging ? ", charging" : "")")
            }
        }
        .padding(16)
        .environment(\.colorScheme, .dark)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.border))
        .accessibilityElement(children: .contain)
    }

    // MARK: notices

    @ViewBuilder private var notices: some View {
        if m.uiState == .signIn {
            notice(symbol: "person.crop.circle.badge.exclamationmark", tint: Brand.warn, title: "Sign in once to connect securely",
                   text: "Andromac has its own private network built in. Sign in with the same account on your phone and Mac.",
                   button: "Sign in", action: { m.openTunnelLogin() })
        } else if m.uiState == .problem {
            notice(symbol: "exclamationmark.triangle.fill", tint: Brand.danger, title: "Secure connection problem", text: m.statusDetail, button: nil, action: {})
        }
        if m.connectionEnabled && m.signedIn && !m.connected && !m.hasConnectedBefore {
            notice(symbol: "qrcode", tint: Brand.accent, title: "Connect your phone",
                   text: "Open Andromac and scan the QR code to pair.", button: "Show QR code", action: { m.showPair = true; openMain() })
        }
        if m.macSharing {
            notice(symbol: "display", tint: Brand.danger, title: "Phone is viewing and controlling this Mac", text: "Stop sharing any time.",
                   button: "Stop sharing", action: { m.stopMacShare(notify: true) })
        }
        if let kind = m.firstMissingPermission {
            Button { m.guide(kind) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warn).symbolRenderingMode(.hierarchical)
                    Text(m.missingPermissionCount == 1 ? "1 permission needs setup" : "\(m.missingPermissionCount) permissions need setup")
                        .font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text("Fix").font(.callout.weight(.semibold)).foregroundStyle(Brand.warn)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Brand.dim)
                }
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(Brand.warn.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(m.missingPermissionCount == 1 ? "1 permission needs setup" : "\(m.missingPermissionCount) permissions need setup")
            .accessibilityHint("Opens a step by step guide")
        }
    }

    private func notice(symbol: String, tint: Color, title: String, text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.callout.weight(.semibold)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
            Text(text).font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
            if let button { Button(button, action: action).buttonStyle(.brandCompactPrimary) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: clipboard

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Clipboard").font(.callout.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(m.syncClipboard ? "Syncing" : "Sync off").font(.caption.weight(.medium)).foregroundStyle(Brand.dim)
            }
            if m.clipboardHistory.isEmpty {
                Text("Copied text shows up here, on your Mac and your phone.").font(.callout).foregroundStyle(Brand.dim)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
            } else {
                ForEach(Array(m.clipboardHistory.prefix(3))) { item in
                    Button {
                        m.recopy(item); copiedID = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copiedID == item.id { copiedID = nil } }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.sourceSymbol).symbolRenderingMode(.hierarchical)
                                .foregroundStyle(item.fromPhone ? Brand.accent : Brand.dim).frame(width: 22)
                            ClipThumb(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: copiedID == item.id ? "checkmark" : "doc.on.doc").font(.callout)
                                .foregroundStyle(copiedID == item.id ? Brand.accent : Brand.dim)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 36)
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.sourceName) clipboard: \(item.displayText)")
                    .accessibilityHint("Copies this text back to your clipboard")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    // MARK: actions

    private var actions: some View {
        VStack(spacing: 8) {
            Button { m.requestPhoneScreen() } label: {
                Label("View and control phone", systemImage: "iphone.gen3").frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.brand).disabled(!m.connected)
            .accessibilityHint(m.connected ? "Opens your phone's screen in a window" : "Connect your phone first")
            if let msg = m.screenMessage { Text(msg).font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true) }
            Button { openMain() } label: {
                Label("Open Andromac", systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.brandSecondary)
        }
    }

    private var footer: some View {
        HStack {
            if m.signedIn {
                Text(m.tunnelAccount.isEmpty ? "Private network: signed in" : "Signed in as \(m.tunnelAccount)")
                    .font(.caption).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Quit and disconnect") { AppDelegate.reallyQuit = true; NSApplication.shared.terminate(nil) }
                .buttonStyle(.brandCompact).keyboardShortcut("q")
                .accessibilityHint("Fully quits Andromac. Closing the window or pressing Command Q keeps the connection running in the background")
        }
    }
}
