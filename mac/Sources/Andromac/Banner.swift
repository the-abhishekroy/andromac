import SwiftUI
import AppKit

/// Andromac's own notification banners: the REAL app icon on the left (LinkedIn, WhatsApp, …) with a small phone badge,
/// inline Reply, click to open on the phone. macOS native banners always show the sending app's icon (Andromac) on the left
/// and cannot be changed, so phone notifications are drawn here instead (switchable in Settings).
struct BannerItem: Identifiable {
    let id = UUID()
    let title: String, subtitle: String, body: String
    let icon: NSImage?
    let key: String?
    let canReply: Bool
}

private final class BannerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class BannerCenter {
    static let shared = BannerCenter()
    var onReply: ((_ key: String, _ text: String) -> Void)?
    var onOpen: ((_ key: String, _ title: String) -> Void)?
    private var panels: [(id: UUID, panel: NSPanel, height: CGFloat)] = []
    private let width: CGFloat = 372

    func show(_ item: BannerItem) {
        DispatchQueue.main.async { [self] in
            let h: CGFloat = item.canReply ? 136 : 92
            let view = BannerView(item: item,
                dismiss: { [weak self] in self?.dismiss(item.id) },
                open: { [weak self] in if let k = item.key { self?.onOpen?(k, item.title) }; self?.dismiss(item.id) },
                reply: { [weak self] text in if let k = item.key { self?.onReply?(k, text) }; self?.dismiss(item.id) })
            let p = BannerPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: h),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .statusBar; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.hidesOnDeactivate = false; p.isMovableByWindowBackground = false
            p.contentView = NSHostingView(rootView: view)
            panels.insert((item.id, p, h), at: 0)
            if panels.count > 4, let old = panels.last { dismiss(old.id) }
            layout(animated: false); p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; p.animator().alphaValue = 1 }
            NSSound(named: "Pop")?.play()
        }
    }

    func dismiss(_ id: UUID) {
        guard let i = panels.firstIndex(where: { $0.id == id }) else { return }
        let p = panels.remove(at: i).panel
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
        layout(animated: true)
    }

    /// Stack the banners under the menu bar, newest on top.
    private func layout(animated: Bool) {
        guard let vis = NSScreen.main?.visibleFrame else { return }
        var y = vis.maxY - 12
        for e in panels {
            y -= e.height
            let f = NSRect(x: vis.maxX - width - 14, y: y, width: width, height: e.height)
            if animated { NSAnimationContext.runAnimationGroup { $0.duration = 0.2; e.panel.animator().setFrame(f, display: true) } }
            else { e.panel.setFrame(f, display: true) }
            y -= 10
        }
    }
}

private struct BannerView: View {
    let item: BannerItem
    let dismiss: () -> Void, open: () -> Void, reply: (String) -> Void
    @State private var hover = false
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let icon = item.icon { Image(nsImage: icon).resizable().interpolation(.high) }
                        else { Image(systemName: "bell.fill").resizable().scaledToFit().padding(10).foregroundStyle(.white) }
                    }
                    .frame(width: 46, height: 46).background(Color.white.opacity(item.icon == nil ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.subtitle).font(.caption).foregroundStyle(Color(white: 0.55)).lineLimit(1)
                    Text(item.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(item.body).font(.system(size: 12.5)).foregroundStyle(Color(white: 0.82)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if item.canReply {
                HStack(spacing: 6) {
                    TextField("Reply on your phone", text: $text).textFieldStyle(.plain).focused($focused)
                        .font(.system(size: 12.5)).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onSubmit { send() }
                        .accessibilityLabel("Reply")
                    Button("Send", action: send).buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.53, green: 0.84, blue: 0.53)).disabled(text.isEmpty)
                }
            }
        }
        .padding(14).frame(width: 372, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 0.05, green: 0.05, blue: 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
        .overlay(alignment: .topTrailing) {
            if hover { Button(action: dismiss) { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Color(white: 0.6)) }
                .buttonStyle(.plain).padding(8).accessibilityLabel("Dismiss") }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { if !focused { open() } }
        .onHover { hover = $0; hover ? timer?.invalidate() : startTimer() }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
        .accessibilityElement(children: .contain)
    }

    private func send() { let t = text.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { reply(t) } }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in if !hover && !focused && text.isEmpty { dismiss() } else { startTimer() } }
    }
}
