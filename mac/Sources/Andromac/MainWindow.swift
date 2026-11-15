import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home = "Home", clipboard = "Clipboard", screen = "Screen", activity = "Activity", network = "Network", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house.fill"; case .clipboard: return "doc.on.clipboard.fill"; case .screen: return "display"
        case .activity: return "bell.badge.fill"; case .network: return "network"; case .settings: return "gearshape.fill"
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("selectedTab") private var tabRaw = Tab.home.rawValue
    private var tab: Tab { Tab(rawValue: tabRaw) ?? .home }
    private var selection: Binding<Tab?> {
        Binding(get: { tab }, set: { if let t = $0 { tabRaw = t.rawValue } })
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    ForEach(Tab.allCases) { t in
                        let sel = t == tab
                        Button { tabRaw = t.rawValue } label: {
                            Label(t.rawValue, systemImage: t.icon)
                                .symbolRenderingMode(.hierarchical)
                                .font(.body.weight(sel ? .semibold : .regular))
                                .foregroundStyle(sel ? Brand.accent : Color.primary)
                                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .background(sel ? Brand.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t.rawValue)
                        .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 4)
                Spacer(minLength: 0)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    OrbitLogo(size: 34)
                    Text("Andromac").font(.title3.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                .accessibilityElement(children: .combine)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.statusShort).font(.callout.weight(.semibold))
                        Text(m.connected ? (m.phoneName ?? "Phone") : "Background connection")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: m.statusSymbol).symbolRenderingMode(.hierarchical).foregroundStyle(m.statusTintAdaptive)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Brand.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Connection status: \(m.statusShort)")
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case .home: HomePage(go: { tabRaw = $0.rawValue })
                    case .clipboard: ClipboardPage()
                    case .screen: ScreenPage()
                    case .activity: ActivityPage()
                    case .network: NetworkPage()
                    case .settings: SettingsPage()
                    }
                }
                .padding(28).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(Brand.canvas)
            .navigationTitle(tab.rawValue)
        }
        .frame(minWidth: 900, minHeight: 640)
        .tint(Brand.accent)
    }
}

// MARK: shared bits

struct EmptyState: View {
    let symbol: String, title: String, message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).symbolRenderingMode(.hierarchical).foregroundStyle(Brand.accent)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .accessibilityElement(children: .combine)
    }
}

struct ActionTile: View {
    let icon: String, title: String, subtitle: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(symbol: icon, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Brand.border))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: Hero

struct ConnectionHero: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 20) {
                OrbitLogo(size: 84, pulsing: m.uiState == .connected)
                VStack(alignment: .leading, spacing: 6) {
                    Label(m.statusShort, systemImage: m.statusSymbol)
                        .font(.caption.weight(.bold)).textCase(.uppercase)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(m.statusTint)
                    Text(m.statusTitle).font(.title.weight(.semibold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(m.statusDetail).font(.callout).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(spacing: 6) {
                    MasterSwitch()
                    Text(m.connectionEnabled ? "On" : "Off").font(.callout.weight(.semibold)).foregroundStyle(.white)
                }
                .accessibilityElement(children: .contain)
            }
            Divider().overlay(.white.opacity(0.15))
            HStack(spacing: 14) {
                Label("Runs in the background, even when this window is closed", systemImage: "moon.stars.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.callout).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if m.connected, let b = m.battery {
                    Label("\(b)%\(m.charging ? " charging" : "")", systemImage: m.charging ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.9))
                        .accessibilityLabel("Phone battery \(b) percent\(m.charging ? ", charging" : "")")
                }
            }
        }
        .padding(24)
        .environment(\.colorScheme, .dark)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Brand.heroGradient)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Brand.green.opacity(0.0)).frame(width: 1, height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: Brand.navy.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}

// MARK: Home

struct HomePage: View {
    @EnvironmentObject var m: AppModel
    let go: (Tab) -> Void

    var body: some View {
        ConnectionHero()
        if !m.setupDone { SetupChecklist() } else { Dashboard(go: go) }
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
                Text("\(doneCount) of 3 done").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                step(1, "Sign in to the private network", "Gives your phone a safe path to this Mac, from any network.", done: s1) {
                    switch m.uiState {
                    case .signIn:
                        Text("Andromac has its own private network built in, so you don't need the Tailscale app. Sign in with the same account on your Mac and your phone.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { m.openTunnelLogin() } label: { Label("Sign in", systemImage: "person.crop.circle.badge.checkmark") }.buttonStyle(.brand)
                    case .off:
                        Text("The connection is switched off. Turn it on above to continue.").font(.callout).foregroundStyle(.secondary)
                    case .problem:
                        Text(m.statusDetail).font(.callout).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
                    default:
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Starting secure connection…").font(.callout).foregroundStyle(.secondary) }
                    }
                }
                step(2, "Connect your phone", "Scan a QR code with your phone's camera.", done: s2) {
                    if m.signedIn { PairCard(embedded: true) }
                    else { Text("Available once you've signed in.").font(.callout).foregroundStyle(.secondary) }
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
                    else { Text("\(n)").font(.callout.weight(.bold)).foregroundStyle(isActive ? Brand.accent : Color.secondary) }
                }
                if !last { Rectangle().fill(Brand.border).frame(width: 2).frame(maxHeight: .infinity).padding(.vertical, 4) }
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.body.weight(.semibold))
                        if done { Text("Done").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent) }
                    }
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
    let go: (Tab) -> Void

    var body: some View {
        if let msg = m.screenMessage {
            Label(msg, systemImage: "info.circle.fill").font(.callout).fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                ActionTile(icon: "iphone.gen3", title: "View and control phone",
                           subtitle: m.connected ? "Open your phone's screen in a window" : "Connect your phone first",
                           enabled: m.connected) { m.requestPhoneScreen() }
                ActionTile(icon: "display", title: "Phone controls this Mac",
                           subtitle: m.macSharing ? "Active. Click to stop sharing" : "Start it from the phone, you approve here") {
                    if m.macSharing { m.stopMacShare(notify: true) } else { go(.screen) }
                }
            }
        }
        Card(title: "Clipboard", subtitle: "Copied text moves between your Mac and phone automatically.") {
            if m.clipboardHistory.isEmpty {
                Text("Nothing copied yet. Copy something on either device and it shows up here.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(m.clipboardHistory.prefix(3))) { item in
                        ClipRow(item: item, compact: true)
                        if item.id != m.clipboardHistory.prefix(3).last?.id { Divider() }
                    }
                }
            }
            Button("See all clipboard history") { go(.clipboard) }.buttonStyle(.brandCompact)
        }
        if !m.events.isEmpty {
            Card(title: "Recent activity") {
                VStack(spacing: 12) {
                    ForEach(m.events.prefix(3)) { e in EventRow(e: e) }
                }
                Button("See all activity") { go(.activity) }.buttonStyle(.brandCompact)
            }
        }
        if !m.connected { PairAnotherCard() }
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
                    VStack(spacing: 8) { ProgressView(); Text("Preparing secure link…").font(.callout).foregroundStyle(.secondary) }
                        .frame(width: 190, height: 190)
                } else if let img = QR.image(m.pairingURL, size: 190) {
                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 190, height: 190)
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
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
                        Text(item.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.text).font(.callout).foregroundStyle(.primary)
                        .lineLimit(compact ? 2 : 3).truncationMode(.tail)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.callout.weight(.semibold)).foregroundStyle(copied ? Brand.accent : .secondary)
                    .frame(minHeight: 32)
            }
            .padding(.vertical, 10).padding(.horizontal, 8)
            .background(hover ? Brand.surfaceRaised : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.sourceName) clipboard, \(item.date.formatted(.relative(presentation: .named))): \(item.text)")
        .accessibilityHint("Copies this text back to your clipboard, and your phone's")
        .accessibilityAddTraits(.isButton)
    }
}

struct ClipboardPage: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    @State private var confirmClear = false

    private var items: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return m.clipboardHistory }
        return m.clipboardHistory.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.sourceName.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Card {
            ToggleRow(symbol: "arrow.left.arrow.right", title: "Sync clipboard",
                      detail: "Copy on your Mac, paste on your phone, and the other way around. It happens automatically in real time.",
                      isOn: $m.syncClipboard)
            Label("Items also appear in your phone's clipboard history. Passwords copied from password managers are never recorded.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search clipboard history", text: $query).textFieldStyle(.plain)
                    .accessibilityLabel("Search clipboard history")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 28, height: 28) }
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
                        ClipRow(item: item)
                        if item.id != items.last?.id { Divider().padding(.horizontal, 8) }
                    }
                }
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
                if !m.connected { Text("Connect your phone first").font(.callout).foregroundStyle(.secondary) }
            }
            if let msg = m.screenMessage { Label(msg, systemImage: "info.circle.fill").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Text("The phone asks you to approve every time, and needs Andromac turned on in Accessibility to accept taps.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Card(title: "Control this Mac from your phone") {
            if m.macSharing {
                Label("Your phone is viewing and controlling this Mac", systemImage: "dot.radiowaves.left.and.right")
                    .font(.body.weight(.semibold)).foregroundStyle(Brand.danger)
                Button("Stop sharing") { m.stopMacShare(notify: true) }.buttonStyle(.brandDestructive)
            } else {
                Text("On your phone open Andromac, then Screen, then View and control Mac. A prompt appears here and nothing is shared until you click Allow.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
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
                if !e.detail.isEmpty { Text(e.detail).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
            }
            Spacer(minLength: 8)
            Text(e.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ActivityPage: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        if m.events.isEmpty {
            Card { EmptyState(symbol: "bell.slash", title: "Nothing yet", message: "Phone notifications, codes and screen sessions show up here.") }
        } else {
            Card {
                VStack(spacing: 14) {
                    ForEach(m.events) { e in
                        EventRow(e: e)
                        if e.id != m.events.last?.id { Divider() }
                    }
                }
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
        switch m.tunnelState { case "running": return Brand.accent; case "error": return Brand.danger; case "off": return .secondary; default: return Brand.warn }
    }

    var body: some View {
        Card(title: "Private network") {
            Label(stateText, systemImage: symbol).font(.title3.weight(.semibold)).foregroundStyle(tint).symbolRenderingMode(.hierarchical)
            if m.tunnelState == "running" {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow { Text("Account").foregroundStyle(.secondary); Text(m.tunnelAccount.isEmpty ? "Signed in" : m.tunnelAccount).textSelection(.enabled) }
                    GridRow { Text("This Mac").foregroundStyle(.secondary); Text(m.tunnelHost.isEmpty ? "andromac-mac" : m.tunnelHost).textSelection(.enabled) }
                    GridRow { Text("Address").foregroundStyle(.secondary); Text(m.tunnelIP ?? "-").font(.body.monospaced()).textSelection(.enabled) }
                }
                Button { m.tunnelSignOut() } label: { Label("Sign out or switch account", systemImage: "rectangle.portrait.and.arrow.right") }.buttonStyle(.brandSecondary)
            } else if m.tunnelState == "login" {
                Text("Sign in with the same account you use on your phone.").font(.callout).foregroundStyle(.secondary)
                Button("Sign in") { m.openTunnelLogin() }.buttonStyle(.brand)
            } else if m.tunnelState == "error" {
                Text(m.tunnelDetail).font(.callout).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
            } else if m.tunnelState == "off" {
                Text("The connection is switched off. Turn it on from Home to bring the private network back.").font(.callout).foregroundStyle(.secondary)
            }
        }
        Card(title: "How it works") {
            Label("Andromac includes its own private network. Your phone and Mac reach each other from any network, with no cable, no shared Wi-Fi and no separate Tailscale app.", systemImage: "network")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Everything is also encrypted by Andromac itself. Your existing Tailscale app, if you have one, is not affected.", systemImage: "lock.fill")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            Divider()
            ToggleRow(symbol: "bell.badge.fill", title: "Show Mac notifications on my phone", detail: "Needs Full Disk Access.", isOn: $m.mirrorMacNotifications)
            Divider()
            ToggleRow(symbol: "key.fill", title: "Copy one-time codes automatically", detail: "Codes from texts and notifications are copied for you.", isOn: $m.autoCopyOTP)
            Divider()
            ToggleRow(symbol: "sunrise.fill", title: "Open Andromac at login", detail: "Starts quietly in the menu bar.", isOn: $m.launchAtLogin)
        }
        Card(title: "Notifications") {
            ToggleRow(symbol: "bell.badge", title: "Use macOS notification banners",
                      detail: "Off (recommended): Andromac shows its own banners with the real app's icon on the left, a phone badge, Reply and click to open. On: standard macOS banners, which always show Andromac's own icon.",
                      isOn: $m.nativeBanners)
        }
        Card(title: "Availability") {
            ToggleRow(symbol: "moon.zzz.fill", title: "Keep this Mac reachable",
                      detail: "Stops the Mac from sleeping when idle so your phone, and ssh from Termux, can always reach it. The screen can still turn off.",
                      isOn: $m.keepAwake)
        }
        Card(title: "Terminal") {
            ToggleRow(symbol: "terminal.fill", title: "Let my phone's terminal reach this Mac",
                      detail: "Termux on your phone can run  ssh -p 2222 \(NSUserName())@127.0.0.1  through Andromac, even when the Tailscale app is off. Needs Remote Login in System Settings › General › Sharing. Only your own devices can reach it.",
                      isOn: $m.terminalAccess)
        }
        Card(title: "Permissions") { PermissionList() }
        Card {
            HStack(spacing: 14) {
                OrbitLogo(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Andromac 0.3").font(.body.weight(.semibold))
                    Text("Mac and Android, one ecosystem.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
