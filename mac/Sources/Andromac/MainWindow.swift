import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home = "Home", clipboard = "Clipboard", screen = "Screen", activity = "Activity", network = "Network", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"; case .clipboard: return "doc.on.clipboard"; case .screen: return "display"
        case .activity: return "bell.badge"; case .network: return "network"; case .settings: return "gearshape"
        }
    }
    var iconSelected: String { icon + ".fill" }
    var shortcutKey: KeyEquivalent { KeyEquivalent(Character("\((Tab.allCases.firstIndex(of: self) ?? 0) + 1)")) }
}

extension Notification.Name {
    static let openPalette = Notification.Name("andromac.openPalette")
}

struct MainWindow: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("selectedTab") private var tabRaw = Tab.home.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Namespace private var selectionNS
    @State private var showPalette = false
    @State private var scrollTarget: String?
    private var tab: Tab { Tab(rawValue: tabRaw) ?? .home }

    private func select(_ t: Tab, anchor: String? = nil) {
        withAnimation(Motion.slow(reduce)) { tabRaw = t.rawValue }
        scrollTarget = anchor
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 232)
            Rectangle().fill(Brand.border).frame(width: 1)
            detail
        }
        .background(Brand.canvas.ignoresSafeArea())
        .frame(minWidth: 900, minHeight: 640)
        .tint(Brand.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPalette) {
            CommandPalette(commands: paletteCommands, close: { showPalette = false })
                .environmentObject(m)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPalette)) { _ in showPalette = true }
        .onChange(of: m.connected) { _, now in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: now ? "Phone connected" : "Phone disconnected",
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private var paletteCommands: [PaletteCommand] {
        [
            PaletteCommand(title: m.connectionEnabled ? "Turn connection off" : "Turn connection on", symbol: "power", hint: "Stay connected in the background") {
                m.connectionEnabled.toggle() },
            PaletteCommand(title: "View and control phone", symbol: "iphone.gen3", hint: m.connected ? "Open the phone screen" : "Connect your phone first", enabled: m.connected) {
                m.requestPhoneScreen() },
            PaletteCommand(title: "Clipboard history", symbol: "doc.on.clipboard", hint: "Go to Clipboard") { select(.clipboard) },
            PaletteCommand(title: "Terminal help", symbol: "terminal", hint: "ssh m5 and ssh f14 shortcuts") { select(.settings, anchor: "terminal") },
            PaletteCommand(title: "Settings", symbol: "gearshape", hint: "Go to Settings") { select(.settings) },
            PaletteCommand(title: "Quit and disconnect", symbol: "xmark.circle", hint: "Fully quit Andromac", destructive: true) {
                AppDelegate.reallyQuit = true; NSApplication.shared.terminate(nil) },
        ]
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeviceHeader()
                .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 12)
            VStack(spacing: 2) {
                ForEach(Tab.allCases) { t in sidebarRow(t) }
            }
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                OrbitLogo(size: 24)
                Text("Andromac").font(.footnote.weight(.semibold)).foregroundStyle(Brand.dim)
                Spacer()
                Text("\u{2318}K").font(.footnote.weight(.medium)).foregroundStyle(Brand.dim)
                    .padding(.horizontal, 6).frame(minHeight: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Brand.border))
                    .accessibilityHidden(true)
            }
            .padding(16)
        }
        .background(Brand.canvas)
    }

    private func sidebarRow(_ t: Tab) -> some View {
        SidebarRow(tab: t, selected: t == tab, ns: selectionNS) { select(t) }
    }

    // MARK: detail

    private var detail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tab.rawValue).font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 4)
                    Group {
                        switch tab {
                        case .home: HomePage(go: { select($0, anchor: $1) })
                        case .clipboard: ClipboardPage()
                        case .screen: ScreenPage()
                        case .activity: ActivityPage()
                        case .network: NetworkPage()
                        case .settings: SettingsPage()
                        }
                    }
                }
                .id(tab)
                .transition(.opacity)
                .padding(32).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
            }
            .onChange(of: scrollTarget) { _, id in
                guard let id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(Motion.slow(reduce)) { proxy.scrollTo(id, anchor: .top) }
                    scrollTarget = nil
                }
            }
        }
        .animation(Motion.normal(reduce), value: tabRaw)
        .background(Brand.canvas)
    }
}

struct SidebarRow: View {
    let tab: Tab, selected: Bool, ns: Namespace.ID
    let action: () -> Void
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? tab.iconSelected : tab.icon).font(.body).frame(width: 22)
                    .foregroundStyle(selected ? Brand.accent : Color.primary)
                Text(tab.rawValue).font(.body.weight(selected ? .semibold : .regular)).foregroundStyle(.primary)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background {
                ZStack {
                    if hover && !selected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.surface) }
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.surfaceRaised)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Brand.accent).frame(width: 3, height: 18).padding(.leading, 4)
                            }
                            .matchedGeometryEffect(id: "sel", in: ns)
                    }
                }
            }
            .focusRing(focused, radius: 10)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tab.shortcutKey, modifiers: .command)
        .onHover { h in withAnimation(Motion.fast(reduce)) { hover = h } }
        .accessibilityLabel(tab.rawValue)
        .accessibilityHint("Command \(tab.shortcutKey.character)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Phone name, battery and status dot at the top of the sidebar.
struct DeviceHeader: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: m.connected ? "iphone.gen3" : "iphone.gen3.slash").font(.title3)
                .foregroundStyle(m.connected ? Brand.accent : Brand.dim).frame(width: 40, height: 40)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(m.connected ? (m.phoneName ?? "Your phone") : "No phone").font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(m.statusTintAdaptive).frame(width: 8, height: 8)
                    Text(m.statusShort).font(.footnote).foregroundStyle(Brand.dim).lineLimit(1)
                    if m.connected, let b = m.battery {
                        Text("\u{00B7}").foregroundStyle(Brand.dim)
                        Image(systemName: m.charging ? "bolt.fill" : "battery.75percent").font(.footnote).foregroundStyle(Brand.dim)
                        Text("\(b)%").font(.footnote.monospacedDigit()).foregroundStyle(Brand.dim)
                            .contentTransition(.numericText(value: Double(b)))
                    }
                }
                .animation(Motion.normal(reduce), value: m.battery)
                .animation(Motion.normal(reduce), value: m.connected)
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.connected ? (m.phoneName ?? "Your phone") : "No phone connected")
        .accessibilityValue("\(m.statusShort)\(m.connected && m.battery != nil ? ", battery \(m.battery!) percent\(m.charging ? ", charging" : "")" : "")")
    }
}

// MARK: shared bits

struct EmptyState: View {
    let symbol: String, title: String, message: String
    var action: (String, () -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title).symbolRenderingMode(.hierarchical).foregroundStyle(Brand.accent)
                .frame(width: 64, height: 64).background(Brand.surfaceRaised, in: Circle())
                .scaleEffect(shown || reduce ? 1 : 0.6).opacity(shown || reduce ? 1 : 0)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(Brand.dim).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420)
            if let action { Button(action.0, action: action.1).buttonStyle(.brandCompact).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .accessibilityElement(children: .combine)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { shown = true } }
    }
}

/// Pressable surface card used for Home tiles.
struct TileButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        let r = RoundedRectangle(cornerRadius: 16, style: .continuous)
        configuration.label
            .background(configuration.isPressed ? Brand.surfaceRaised : Brand.surface, in: r)
            .overlay(r.strokeBorder(Brand.border))
            .animation(Motion.fast(reduce), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.5)
            .focusRing(focused, radius: 16)
            .contentShape(r)
    }
}

struct ActionTile: View {
    let icon: String, title: String, subtitle: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                IconBadge(symbol: icon, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text(subtitle).font(.callout).foregroundStyle(Brand.dim).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        }
        .buttonStyle(TileButtonStyle()).disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: Device card

struct DeviceCard: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    let go: (Tab, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    StatusChip()
                    Text(m.statusTitle).font(.title.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(m.statusDetail).font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(spacing: 6) {
                    MasterSwitch()
                    Text(m.connectionEnabled ? "On" : "Off").font(.callout.weight(.semibold))
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .contain)
            }
            HStack(spacing: 10) {
                Button { m.reconnect() } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                    .buttonStyle(.brandCompact).accessibilityHint("Drops the connection completely and connects again")
                if m.connectionEnabled {
                    Button { m.connectionEnabled = false } label: { Label("Stop service", systemImage: "stop.circle") }
                        .buttonStyle(.brandCompact).accessibilityHint("Stops the background connection service completely. It stays stopped, even after a restart, until you press Start service")
                } else {
                    Button { m.connectionEnabled = true } label: { Label("Start service", systemImage: "play.circle") }
                        .buttonStyle(.brandCompact)
                }
                Spacer()
            }
            if m.uiState == .problem {
                HStack(spacing: 10) {
                    Label("Check the private network", systemImage: "exclamationmark.triangle.fill").font(.callout.weight(.semibold)).foregroundStyle(Brand.danger)
                    Spacer()
                    Button("Open Network") { go(.network, nil) }.buttonStyle(.brandCompact)
                }
                .padding(12).background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity)
            }
            Rectangle().fill(Brand.border).frame(height: 1)
            HStack(spacing: 24) {
                stat("Battery", m.connected && m.battery != nil ? AnyView(batteryText) : AnyView(Text("\u{2013}").foregroundStyle(Brand.dim)))
                stat("Network", AnyView(Text(m.signedIn ? "Private network" : "Not connected").foregroundStyle(m.signedIn ? Color.primary : Brand.dim)))
                stat("Background", AnyView(Text("Keeps running").foregroundStyle(.primary)))
                Spacer(minLength: 0)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.border))
        .animation(Motion.normal(reduce), value: m.uiState)
        .accessibilityElement(children: .contain)
    }

    private var batteryText: some View {
        let b = m.battery ?? 0
        return HStack(spacing: 4) {
            Image(systemName: m.charging ? "battery.100percent.bolt" : "battery.75percent").foregroundStyle(Brand.accent)
            Text("\(b)%").monospacedDigit().contentTransition(.numericText(value: Double(b)))
                .animation(Motion.normal(reduce), value: b)
            if m.charging { Text("charging").foregroundStyle(Brand.dim) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Phone battery \(b) percent\(m.charging ? ", charging" : "")")
    }

    private func stat(_ label: String, _ value: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.footnote).foregroundStyle(Brand.dim)
            value.font(.callout.weight(.medium))
        }
    }
}

// MARK: Home

struct HomePage: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    let go: (Tab, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DeviceCard(go: go)
            if m.macSharing {
                Label("Your phone is viewing and controlling this Mac", systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout.weight(.semibold)).foregroundStyle(Brand.danger)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.border))
                    .transition(.opacity)
            }
            if m.setupDone {
                Label { Text("All set").font(.callout.weight(.semibold)) + Text("  Sign-in, pairing and permissions are done.").font(.callout).foregroundColor(Brand.dim) }
                    icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.accent) }
                    .padding(.horizontal, 4).transition(.opacity)
                    .accessibilityElement(children: .combine)
            } else {
                SetupChecklist().transition(.opacity)
            }
            Dashboard(go: go)
        }
        .animation(Motion.slow(reduce), value: m.setupDone)
        .animation(Motion.normal(reduce), value: m.macSharing)
    }
}

struct SetupChecklist: View {
    @EnvironmentObject var m: AppModel

    private var s1: Bool { m.signedIn }
    private var s2: Bool { m.hasConnectedBefore || m.connected }
    private var s3: Bool { m.permissionsOK }
    private var doneCount: Int { [s1, s2, s3].filter { $0 }.count }
    private var active: Int { !s1 ? 1 : (!s2 ? 2 : 3) }

    var body: some View {
        Card(title: "Finish setting up", subtitle: "Three quick steps and Andromac is ready.") {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(doneCount), total: 3).tint(Brand.green)
                    .accessibilityLabel("Setup progress").accessibilityValue("\(doneCount) of 3 steps done")
                Text("\(doneCount) of 3 done").font(.caption.weight(.medium)).foregroundStyle(Brand.dim)
            }
            VStack(alignment: .leading, spacing: 4) {
                step(1, "Sign in to the private network", "Gives your phone a safe path to this Mac, from any network.", done: s1) {
                    switch m.uiState {
                    case .signIn:
                        Text("Andromac has its own private network built in, so you don't need the Tailscale app. Sign in with the same account on your Mac and your phone.")
                            .font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
                        Button { m.openTunnelLogin() } label: { Label("Sign in", systemImage: "person.crop.circle.badge.checkmark") }.buttonStyle(.brand)
                    case .off:
                        Text("The connection is switched off. Turn it on above to continue.").font(.callout).foregroundStyle(Brand.dim)
                    case .problem:
                        Text(m.statusDetail).font(.callout).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
                    default:
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Starting secure connection…").font(.callout).foregroundStyle(Brand.dim) }
                    }
                }
                step(2, "Connect your phone", "Scan a QR code with your phone's camera.", done: s2) {
                    if m.signedIn { PairCard(embedded: true) }
                    else { Text("Available once you've signed in.").font(.callout).foregroundStyle(Brand.dim) }
                }
                step(3, "Allow permissions", "So notifications, clipboard and screen features work.", done: s3, last: true) {
                    PermissionList(onlyMissing: true)
                }
            }
        }
    }

    @ViewBuilder
    private func step<C: View>(_ n: Int, _ title: String, _ detail: String, done: Bool, last: Bool = false, @ViewBuilder content: () -> C) -> some View {
        let isActive = active == n
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(done ? Brand.green : (isActive ? Brand.accent.opacity(0.18) : Brand.surfaceRaised)).frame(width: 32, height: 32)
                    if done { Image(systemName: "checkmark").font(.callout.weight(.bold)).foregroundStyle(Brand.navy) }
                    else { Text("\(n)").font(.callout.weight(.bold)).foregroundStyle(isActive ? Brand.accent : Brand.dim) }
                }
                if !last { Rectangle().fill(Brand.border).frame(width: 2).frame(maxHeight: .infinity).padding(.vertical, 4) }
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.body.weight(.semibold))
                        if done { Text("Done").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent) }
                    }
                    Text(detail).font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 32, alignment: .leading)
                if isActive { content().padding(.bottom, 8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, last ? 0 : 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(n): \(title), \(done ? "done" : (isActive ? "current" : "not started"))")
    }
}

struct PermissionList: View {
    @EnvironmentObject var m: AppModel
    var onlyMissing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !onlyMissing || !m.hasFullDiskAccess {
                PermissionRow(symbol: "internaldrive.fill", title: "Full Disk Access",
                              detail: "Lets Mac notifications reach your phone. Click +, then choose Andromac. It never adds itself.",
                              ok: m.hasFullDiskAccess, action: { m.guide(.fullDisk) }, secondary: ("Show Andromac", m.revealApp))
            }
            if !onlyMissing || !m.notifAccess {
                PermissionRow(symbol: "bell.badge.fill", title: "Notifications", detail: "Shows your phone's notifications on this Mac.",
                              ok: m.notifAccess, action: { m.guide(.notifications) })
            }
            if !onlyMissing || !m.screenAccess {
                PermissionRow(symbol: "record.circle", title: "Screen Recording", detail: "Lets your phone see this Mac.",
                              ok: m.screenAccess, action: { m.guide(.screen) })
            }
            if !onlyMissing || !m.axAccess {
                PermissionRow(symbol: "hand.tap.fill", title: "Accessibility", detail: "Lets your phone click and type on this Mac.",
                              ok: m.axAccess, action: { m.guide(.accessibility) })
            }
        }
    }
}

struct Dashboard: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    let go: (Tab, String?) -> Void

    var body: some View {
        if let msg = m.screenMessage {
            Label(msg, systemImage: "info.circle.fill").font(.callout).foregroundStyle(Brand.info).fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity)
        }
        SectionHeader("Quick actions")
        HStack(spacing: 12) {
            ActionTile(icon: "iphone.gen3", title: "View and control phone",
                       subtitle: m.connected ? "Open your phone's screen in a window" : "Connect your phone first",
                       enabled: m.connected) { m.requestPhoneScreen() }
            ActionTile(icon: "doc.on.clipboard", title: "Clipboard history",
                       subtitle: m.clipboardHistory.isEmpty ? "Nothing copied yet" : "\(m.clipboardHistory.count) saved items") { go(.clipboard, nil) }
            ActionTile(icon: "externaldrive.connected.to.line.below", title: "Phone files",
                       subtitle: m.phoneFilesMounted ? "Mounted in Finder as Phone"
                                 : (m.phoneFilesMessage ?? (m.phoneFilesEnabled ? "Open your phone's storage in Finder" : "Turn on sharing in the phone's Settings")),
                       enabled: m.connected) { m.phoneFilesMounted ? m.unmountPhoneFiles() : m.mountPhoneFiles() }
            ActionTile(icon: "terminal", title: "Terminal help",
                       subtitle: "Two shortcuts: ssh m5 and ssh f14") { go(.settings, "terminal") }
        }
        SectionHeader("Recent")
        recent
        if !m.connected { PairAnotherCard() }
    }

    private var recent: some View {
        HStack(alignment: .top, spacing: 12) {
            Card(title: "Last copied", padding: 16) {
                if let item = m.clipboardHistory.first {
                    ClipRow(item: item, compact: true).id(item.id).transition(.opacity)
                } else if m.uiState == .starting {
                    VStack(alignment: .leading, spacing: 8) { SkeletonBar(); SkeletonBar(width: 120) }.padding(.vertical, 6)
                } else {
                    Text("Copy something on either device and it shows up here.").font(.callout).foregroundStyle(Brand.dim)
                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                }
                Button("See all") { go(.clipboard, nil) }.buttonStyle(.brandCompact)
            }
            Card(title: "Recent activity", padding: 16) {
                if m.events.isEmpty {
                    if m.uiState == .starting {
                        VStack(alignment: .leading, spacing: 8) { SkeletonBar(); SkeletonBar(width: 160); SkeletonBar(width: 100) }.padding(.vertical, 6)
                    } else {
                        Text("Phone notifications, codes and screen sessions show up here.").font(.callout).foregroundStyle(Brand.dim)
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(m.events.prefix(3)) { e in EventRow(e: e).listTransition(reduce) }
                    }
                }
                Button("See all") { go(.activity, nil) }.buttonStyle(.brandCompact)
            }
        }
        .animation(Motion.normal(reduce), value: m.events.count)
        .animation(Motion.normal(reduce), value: m.clipboardHistory.first?.id)
    }
}

struct PairAnotherCard: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        if m.signedIn {
            Card {
                DisclosureGroup(isExpanded: $m.showPair) {
                    PairCard(embedded: true).padding(.top, 12)
                } label: {
                    Label("Pair another phone", systemImage: "qrcode").font(.body.weight(.semibold))
                }
            }
        }
    }
}

struct PairCard: View {
    @EnvironmentObject var m: AppModel
    var embedded = false
    var body: some View {
        let content = HStack(alignment: .center, spacing: 24) {
            Group {
                if m.pairingURL.isEmpty {
                    VStack(spacing: 8) { ProgressView(); Text("Preparing secure link…").font(.callout).foregroundStyle(Brand.dim) }
                        .frame(width: 190, height: 190)
                } else if let img = QR.image(m.pairingURL, size: 190) {
                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 190, height: 190)
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Pairing QR code").accessibilityHint("Scan with your phone's camera. Or use the Copy link button.")
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                pairStep("1", "Install and open Andromac on your phone")
                pairStep("2", "Point the phone's camera at this code")
                pairStep("3", "Tap the link that appears")
                Button { m.copyPairingLink() } label: {
                    Label(m.justCopiedLink ? "Copied" : "Copy link instead", systemImage: m.justCopiedLink ? "checkmark" : "link")
                }
                .buttonStyle(.brandCompact).disabled(m.pairingURL.isEmpty)
            }
        }
        if embedded { content } else { Card(title: "Connect your phone") { content } }
    }
    private func pairStep(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.caption.weight(.bold)).foregroundStyle(Brand.accent)
                .frame(width: 22, height: 22).background(Brand.accent.opacity(0.15), in: Circle())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Clipboard

struct ClipRow: View {
    @EnvironmentObject var m: AppModel
    let item: ClipItem
    var compact = false
    @State private var copied = false
    @State private var hover = false
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Button {
            m.recopy(item)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        SourceBadge(item: item)
                        Text(item.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(Brand.dim)
                    }
                    if let d = item.image, let img = NSImage(data: d) {
                        Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 150, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text(item.text).font(.callout).foregroundStyle(.primary)
                        .lineLimit(compact ? 2 : 3).truncationMode(.tail)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.callout.weight(.semibold)).foregroundStyle(copied ? Brand.accent : Brand.dim)
                    .frame(minHeight: 32)
            }
            .padding(.vertical, 10).padding(.horizontal, 8)
            .background(hover ? Brand.surfaceRaised : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .focusRing(focused, radius: 10)
            .animation(Motion.fast(reduce), value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.sourceName) clipboard, \(item.date.formatted(.relative(presentation: .named))): \(item.displayText)")
        .accessibilityHint("Copies this text back to your clipboard, and your phone's")
        .accessibilityAddTraits(.isButton)
    }
}

struct ClipboardPage: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    @State private var confirmClear = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var items: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return m.clipboardHistory }
        return m.clipboardHistory.filter { $0.displayText.localizedCaseInsensitiveContains(q) || $0.sourceName.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Card {
            ToggleRow(symbol: "arrow.left.arrow.right", title: "Sync clipboard",
                      detail: "Copy on your Mac, paste on your phone, and the other way around. It happens automatically in real time.",
                      isOn: $m.syncClipboard)
            Label("Items also appear in your phone's clipboard history. Passwords copied from password managers are never recorded.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.dim).accessibilityHidden(true)
                TextField("Search clipboard history", text: $query).textFieldStyle(.plain)
                    .accessibilityLabel("Search clipboard history")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.dim).frame(width: 28, height: 28) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 38)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.border))
            Button(role: .destructive) { confirmClear = true } label: { Label("Clear history", systemImage: "trash") }
                .buttonStyle(.brandDestructive).disabled(m.clipboardHistory.isEmpty)
                .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
                    Button("Clear history", role: .destructive) { m.clearClipboardHistory() }
                } message: { Text("This only clears the list in Andromac. It doesn't change what's on your clipboard.") }
        }
        if m.clipboardHistory.isEmpty {
            Card { EmptyState(symbol: "doc.on.clipboard", title: "Nothing copied yet",
                              message: "Copy text on your Mac or your phone and it appears here, ready to paste on the other device.") }
        } else if items.isEmpty {
            Card { EmptyState(symbol: "magnifyingglass", title: "No matches", message: "Nothing in your clipboard history matches \"\(query)\".") }
        } else {
            Card(padding: 12) {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        VStack(spacing: 0) {
                            ClipRow(item: item)
                            if item.id != items.last?.id { Divider().overlay(Brand.border).padding(.horizontal, 8) }
                        }
                        .listTransition(reduce)
                    }
                }
                .animation(Motion.normal(reduce), value: items.map(\.id))
            }
        }
    }
}

// MARK: Screen

struct ScreenPage: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Card(title: "View and control your phone", subtitle: "Your phone appears in a window shaped like its screen.") {
            VStack(alignment: .leading, spacing: 8) {
                tip("cursorarrow.click", "Click to tap, drag to swipe, scroll with the trackpad")
                tip("keyboard", "Type with your Mac keyboard")
                tip("slider.horizontal.3", "Toolbar: Back, Home, Recents, notifications, lock, volume, screenshot, rotate and full screen")
            }
            HStack(spacing: 12) {
                Button { m.requestPhoneScreen() } label: { Label("View and control phone", systemImage: "iphone.gen3") }
                    .buttonStyle(.brand).disabled(!m.connected)
                if !m.connected { Text("Connect your phone first").font(.callout).foregroundStyle(Brand.dim) }
            }
            if let msg = m.screenMessage { Label(msg, systemImage: "info.circle.fill").font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true) }
            Text("The phone asks you to approve every time, and needs Andromac turned on in Accessibility to accept taps.")
                .font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
        }
        Card(title: "Control this Mac from your phone") {
            if m.macSharing {
                Label("Your phone is viewing and controlling this Mac", systemImage: "dot.radiowaves.left.and.right")
                    .font(.body.weight(.semibold)).foregroundStyle(Brand.danger)
                Button("Stop sharing") { m.stopMacShare(notify: true) }.buttonStyle(.brandDestructive)
            } else {
                Text("On your phone open Andromac, then Screen, then View and control Mac. A prompt appears here and nothing is shared until you click Allow.")
                    .font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Brand.border)
            PermissionRow(symbol: "record.circle", title: "Screen Recording", detail: "Lets your phone see this Mac", ok: m.screenAccess, action: { m.guide(.screen) })
            PermissionRow(symbol: "hand.tap.fill", title: "Accessibility", detail: "Lets your phone click and type", ok: m.axAccess, action: { m.guide(.accessibility) })
        }
    }
    private func tip(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).font(.callout).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol).symbolRenderingMode(.hierarchical).foregroundStyle(Brand.accent).frame(width: 22)
        }
    }
}

// MARK: Activity

struct EventRow: View {
    let e: ActivityEvent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: e.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.body.weight(.medium)).lineLimit(2)
                if !e.detail.isEmpty { Text(e.detail).font(.callout).foregroundStyle(Brand.dim).lineLimit(3) }
            }
            Spacer(minLength: 8)
            Text(e.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(Brand.dim)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ActivityPage: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        if m.events.isEmpty {
            Card { EmptyState(symbol: "bell.slash", title: "Nothing yet", message: "Phone notifications, codes and screen sessions show up here.") }
        } else {
            Card {
                VStack(spacing: 14) {
                    ForEach(m.events) { e in
                        VStack(spacing: 14) {
                            EventRow(e: e)
                            if e.id != m.events.last?.id { Divider().overlay(Brand.border) }
                        }
                        .listTransition(reduce)
                    }
                }
                .animation(Motion.normal(reduce), value: m.events.map(\.id))
            }
        }
    }
}

// MARK: Network

struct NetworkPage: View {
    @EnvironmentObject var m: AppModel
    private var stateText: String {
        switch m.tunnelState {
        case "running": return "Connected"; case "login": return "Sign-in needed"; case "error": return "Problem"
        case "off": return "Off"; default: return "Starting"
        }
    }
    private var symbol: String {
        switch m.tunnelState {
        case "running": return "checkmark.circle.fill"; case "login": return "person.crop.circle.badge.exclamationmark"
        case "error": return "exclamationmark.triangle.fill"; case "off": return "power"; default: return "arrow.triangle.2.circlepath"
        }
    }
    private var tint: Color {
        switch m.tunnelState { case "running": return Brand.accent; case "error": return Brand.danger; case "off": return Brand.dim; default: return Brand.warn }
    }

    var body: some View {
        Card(title: "Private network") {
            Label(stateText, systemImage: symbol).font(.title3.weight(.semibold)).foregroundStyle(tint).symbolRenderingMode(.hierarchical)
            if m.tunnelState == "running" {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow { Text("Account").foregroundStyle(Brand.dim); Text(m.tunnelAccount.isEmpty ? "Signed in" : m.tunnelAccount).textSelection(.enabled) }
                    GridRow { Text("This Mac").foregroundStyle(Brand.dim); Text(m.tunnelHost.isEmpty ? "andromac-mac" : m.tunnelHost).textSelection(.enabled) }
                    GridRow { Text("Address").foregroundStyle(Brand.dim); Text(m.tunnelIP ?? "-").font(.body.monospaced()).textSelection(.enabled) }
                }
                Button { m.tunnelSignOut() } label: { Label("Sign out or switch account", systemImage: "rectangle.portrait.and.arrow.right") }.buttonStyle(.brandSecondary)
            } else if m.tunnelState == "login" {
                Text("Sign in with the same account you use on your phone.").font(.callout).foregroundStyle(Brand.dim)
                Button("Sign in") { m.openTunnelLogin() }.buttonStyle(.brand)
            } else if m.tunnelState == "error" {
                Text(m.tunnelDetail).font(.callout).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
            } else if m.tunnelState == "off" {
                Text("The connection is switched off. Turn it on from Home to bring the private network back.").font(.callout).foregroundStyle(Brand.dim)
            }
        }
        Card(title: "How it works") {
            Label("Andromac includes its own private network. Your phone and Mac reach each other from any network, with no cable, no shared Wi-Fi and no separate Tailscale app.", systemImage: "network")
                .font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
            Label("Everything is also encrypted by Andromac itself. Your existing Tailscale app, if you have one, is not affected.", systemImage: "lock.fill")
                .font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Settings

struct SettingsPage: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Card(title: "Connection") {
            ToggleRow(symbol: "power", title: "Stay connected",
                      detail: "Runs in the background, even when this window is closed. Turn off to stop the private network completely.",
                      isOn: $m.connectionEnabled)
        }
        Card(title: "Sync") {
            ToggleRow(symbol: "doc.on.clipboard.fill", title: "Sync clipboard", detail: "Copy on one device, paste on the other, in real time.", isOn: $m.syncClipboard)
            Divider().overlay(Brand.border)
            ToggleRow(symbol: "bell.badge.fill", title: "Show Mac notifications on my phone", detail: "Needs Full Disk Access.", isOn: $m.mirrorMacNotifications)
            Divider().overlay(Brand.border)
            ToggleRow(symbol: "key.fill", title: "Copy one-time codes automatically", detail: "Codes from texts and notifications are copied for you.", isOn: $m.autoCopyOTP)
            Divider().overlay(Brand.border)
            ToggleRow(symbol: "sunrise.fill", title: "Connect at login", detail: "Only the background connection starts. No window, no menu bar icon until you open Andromac.", isOn: $m.launchAtLogin)
        }
        Card(title: "Notifications") {
            ToggleRow(symbol: "bell.badge", title: "Use macOS notifications (Notification Center)",
                      detail: "On (default): real macOS notifications that stay in Notification Center, with the app's icon as a thumbnail, Reply, and click to open on your phone. macOS always shows Andromac's own icon on the left of these. Off: Andromac draws its own banners with the real app icon on the left, which are not kept in Notification Center.",
                      isOn: $m.nativeBanners)
        }
        AppsCard()
        Card(title: "Duplicates") {
            ToggleRow(symbol: "bell.slash", title: "Skip apps already open on this Mac",
                      detail: "If WhatsApp, Telegram or Slack is running on this Mac it already notifies you with its own logo, so Andromac won't show a second copy of the phone's notification.",
                      isOn: $m.skipRunningApps)
        }
        Card(title: "Availability") {
            ToggleRow(symbol: "moon.zzz.fill", title: "Keep this Mac reachable",
                      detail: "Stops the Mac from sleeping when idle so your phone, and ssh from Termux, can always reach it. The screen can still turn off.",
                      isOn: $m.keepAwake)
        }
        TerminalCard().id("terminal")
        Card(title: "Permissions") { PermissionList() }
        Card {
            HStack(spacing: 14) {
                OrbitLogo(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Andromac \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(.body.weight(.semibold))
                    Text("Mac and Android, one ecosystem.").font(.callout).foregroundStyle(Brand.dim)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}


// MARK: Choose which apps are shared

/// Per-app switches: which of this Mac's apps send notifications to the phone.
struct AppsCard: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    private func macName(_ b: String) -> String {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b), let bu = Bundle(url: u),
           let n = (bu.infoDictionary?["CFBundleDisplayName"] ?? bu.infoDictionary?["CFBundleName"]) as? String { return n }
        return b.split(separator: ".").last.map(String.init) ?? b
    }
    private func macIcon(_ b: String) -> NSImage {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) { return NSWorkspace.shared.icon(forFile: u.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
    private func row(_ icon: NSImage?, _ name: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Group {
                    if let icon { Image(nsImage: icon).resizable() } else { Image(systemName: "app.fill").resizable().foregroundStyle(Brand.dim) }
                }.frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 6))
                Text(name).font(.body)
                Spacer(minLength: 8)
            }
        }
        .toggleStyle(SpringSwitchStyle(title: name))
        .frame(minHeight: 40)
    }
    var body: some View {
        Card(title: "Choose apps") {
            Text("Turn off an app to stop its notifications on this Mac from going to your phone. Which phone apps send notifications is chosen in the Andromac app on your phone.")
                .font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
            TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
            let q = query.lowercased()
            let apps = m.macAppChoices.map { ($0, macName($0)) }.sorted { $0.1.lowercased() < $1.1.lowercased() }.filter { q.isEmpty || $0.1.lowercased().contains(q) }
            if apps.isEmpty { Text(m.hasFullDiskAccess ? "No Mac apps have sent notifications yet." : "Allow Full Disk Access to list your Mac's apps.").font(.callout).foregroundStyle(Brand.dim) }
            ForEach(apps, id: \.0) { bundle, name in
                row(macIcon(bundle), name, isOn: Binding(get: { !m.mutedMacApps.contains(bundle) },
                    set: { on in if on { m.mutedMacApps.remove(bundle) } else { m.mutedMacApps.insert(bundle) } }))
            }
        }
    }
}
