import AppKit
import AVFoundation

/// A resizable window showing the phone's screen. Trackpad and mouse gestures are translated to touch:
/// click/drag = tap/drag (hold then drag = select), two-finger scroll = live scroll, three-finger drag = drag,
/// pinch = pinch zoom, right-click = Back.
final class PhoneScreenWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let view: PhoneView
    let decoder = VideoDecoder()
    private let send: ([String: Any]) -> Void
    private let onClose: () -> Void
    private let onClipboard: () -> Void
    private let onStop: () -> Void
    private var videoW = 0, videoH = 0
    private var stretchButton: NSButton?, pinButton: NSButton?, helpButton: NSButton?

    init(send: @escaping ([String: Any]) -> Void, onClipboard: @escaping () -> Void, onStop: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.send = send; self.onClose = onClose; self.onClipboard = onClipboard; self.onStop = onStop
        view = PhoneView(decoder: decoder)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Phone"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = view
        window.backgroundColor = .black
        window.minSize = NSSize(width: 240, height: 320)
        view.send = send

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .bottom
        let bar = NSStackView()
        bar.orientation = .horizontal; bar.spacing = 2; bar.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 4, right: 8)
        @discardableResult func add(_ symbol: String, _ tip: String, _ sel: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: self, action: sel)
            b.bezelStyle = .texturedRounded; b.toolTip = tip; b.imagePosition = .imageOnly
            bar.addArrangedSubview(b); return b
        }
        func sep() { let v = NSBox(); v.boxType = .separator; v.widthAnchor.constraint(equalToConstant: 1).isActive = true; v.heightAnchor.constraint(equalToConstant: 16).isActive = true; bar.addArrangedSubview(v) }
        // navigation
        add("chevron.backward", "Back", #selector(back)); add("circle", "Home", #selector(home)); add("square.on.square", "Recent apps", #selector(recents)); sep()
        // phone system
        add("bell", "Notifications", #selector(notifs)); add("switch.2", "Quick settings", #selector(quick)); add("lock", "Lock phone", #selector(lock))
        add("camera.viewfinder", "Take screenshot on phone", #selector(shot)); sep()
        // sound + clipboard
        add("speaker.minus", "Volume down", #selector(volDown)); add("speaker.plus", "Volume up", #selector(volUp))
        add("doc.on.clipboard", "Send Mac clipboard to phone and paste", #selector(pasteClip)); sep()
        bar.addArrangedSubview(NSView())   // flexible spacer pushes view controls right
        // view
        stretchButton = add("arrow.left.and.right.square", "Stretch to fill window (off = keep shape)", #selector(toggleStretch))
        add("rotate.right", "Rotate view", #selector(rotate))
        pinButton = add("pin", "Keep window on top", #selector(togglePin))
        add("arrow.up.left.and.arrow.down.right", "Full screen", #selector(fullscreen)); sep()
        helpButton = add("questionmark.circle", "Gestures", #selector(showHelp))
        add("xmark.circle", "Stop viewing", #selector(stop))
        accessory.view = bar
        window.addTitlebarAccessoryViewController(accessory)
        window.center()
    }

    @objc private func back() { nav("back") }
    @objc private func home() { nav("home") }
    @objc private func recents() { nav("recents") }
    @objc private func notifs() { nav("notifications") }
    @objc private func quick() { nav("quicksettings") }
    @objc private func lock() { nav("lock") }
    @objc private func volDown() { nav("voldown") }
    @objc private func volUp() { nav("volup") }
    @objc private func shot() { nav("screenshot") }
    private func nav(_ a: String) { send(["k": "nav", "a": a]) }
    @objc private func pasteClip() { onClipboard(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.send(["k": "paste"]) } }
    @objc private func rotate() { view.rotation = (view.rotation + 1) % 4; if !window.styleMask.contains(.fullScreen) { let f = window.frame; window.setContentSize(NSSize(width: window.contentLayoutRect.height, height: window.contentLayoutRect.width)); _ = f } }
    @objc private func fullscreen() { window.toggleFullScreen(nil) }
    @objc private func stop() { onStop() }
    @objc private func showHelp() {
        let text = """
        One finger click / drag     tap, swipe, drag (hold, then drag, to select text)
        Double click                double tap
        Two-finger scroll           smooth scroll with fling
        Three-finger drag           drag (turn on in Accessibility › Pointer Control › Trackpad)
        Pinch                       zoom in / out
        Rotate (two fingers)        rotate gesture
        Option + drag               pinch with a mouse
        Three-finger swipe          right: Back · left: Recents · up: Home · down: Notifications
        Right-click / two-finger click    Back
        ⌘V                          paste the Mac clipboard into the phone's field
        ⌘A                          select all in the phone's field
        """
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.frame = NSRect(x: 14, y: 12, width: 520, height: 190)
        let vc = NSViewController(); let v = NSView(frame: NSRect(x: 0, y: 0, width: 548, height: 214)); v.addSubview(label); vc.view = v
        let pop = NSPopover(); pop.contentViewController = vc; pop.behavior = .transient
        if let b = helpButton { pop.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }
    @objc private func toggleStretch() {
        view.stretch.toggle()
        stretchButton?.state = view.stretch ? .on : .off
        stretchButton?.contentTintColor = view.stretch ? .controlAccentColor : nil
    }
    @objc private func togglePin() {
        let on = window.level != .floating
        window.level = on ? .floating : .normal
        pinButton?.contentTintColor = on ? .controlAccentColor : nil
    }

    func showControlOff() { view.showBanner("View only. On the phone, turn on Andromac in Settings → Accessibility to control it.") }

    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.makeFirstResponder(view) }
    func close() { window.delegate = nil; window.close() }
    func windowWillClose(_ n: Notification) { onClose() }

    /// The phone reports its screen size (and again when it rotates). The window is freely resizable;
    /// we only pick a sensible starting size the first time and when the orientation flips.
    func setSize(_ w: Int, _ h: Int) {
        guard w > 0, h > 0 else { return }
        let flipped = videoW > 0 && (w > h) != (videoW > videoH)
        let first = videoW == 0
        videoW = w; videoH = h
        view.videoAspect = CGFloat(w) / CGFloat(h)
        window.title = "Phone — \(w > h ? "landscape" : "portrait")"
        guard (first || flipped), !window.styleMask.contains(.fullScreen) else { return }
        let vis = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let swapped = view.rotation % 2 == 1
        let aw = CGFloat(swapped ? h : w), ah = CGFloat(swapped ? w : h)
        let scale = min(0.6, (vis.height - 140) / ah, (vis.width - 80) / aw)
        window.setContentSize(NSSize(width: aw * scale, height: ah * scale))
    }
}

final class PhoneView: NSView {
    let decoder: VideoDecoder
    var send: (([String: Any]) -> Void)?
    var videoAspect: CGFloat = 9.0 / 19.5 { didSet { needsLayout = true } }
    var rotation = 0 { didSet { needsLayout = true } }       // view rotation, clockwise quarter turns
    var stretch = false { didSet { decoder.layer.videoGravity = stretch ? .resize : .resizeAspect; needsLayout = true } }
    private var lastMove = Date.distantPast
    private var scrollPoint = CGPoint.zero, scrolling = false
    private var magnifyTotal: CGFloat = 0
    private var rotateTotal: CGFloat = 0
    private var pinchAnchor: CGPoint?        // Option + drag = pinch (for mouse users)
    private var pinchScale: CGFloat = 1

    init(decoder: VideoDecoder) {
        self.decoder = decoder
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(decoder.layer)
        allowedTouchTypes = [.indirect]
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }

    private let banner = NSTextField(labelWithString: "")
    func showBanner(_ text: String) {
        banner.stringValue = "  " + text + "  "
        banner.textColor = .black; banner.backgroundColor = NSColor.systemYellow; banner.drawsBackground = true
        banner.font = .systemFont(ofSize: 12, weight: .medium); banner.lineBreakMode = .byWordWrapping; banner.maximumNumberOfLines = 3
        banner.preferredMaxLayoutWidth = max(bounds.width - 20, 100)
        if banner.superview == nil { addSubview(banner) }
        banner.isHidden = false
        needsLayout = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.banner.isHidden = true }
    }

    override func layout() {
        banner.frame = NSRect(x: 10, y: bounds.height - 56, width: max(bounds.width - 20, 100), height: 46)
        super.layout()
        let b = bounds, swapped = rotation % 2 == 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        decoder.layer.bounds = CGRect(x: 0, y: 0, width: swapped ? b.height : b.width, height: swapped ? b.width : b.height)
        decoder.layer.position = CGPoint(x: b.midX, y: b.midY)
        decoder.layer.setAffineTransform(CGAffineTransform(rotationAngle: -CGFloat(rotation) * .pi / 2))
        CATransaction.commit()
    }

    /// Rectangle (view coordinates) the video occupies: the whole view when stretched, else aspect-fit.
    private var videoRect: NSRect {
        let b = bounds; guard b.width > 0, b.height > 0 else { return b }
        if stretch { return b }
        let a = rotation % 2 == 1 ? 1 / videoAspect : videoAspect
        let w = min(b.width, b.height * a), h = w / a
        return NSRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
    }

    /// View point → normalized coordinates in the phone's own (unrotated) screen.
    private func norm(_ p: CGPoint, clamp: Bool = false) -> (CGFloat, CGFloat)? {
        let r = videoRect
        guard r.width > 0, clamp || r.contains(p) else { return nil }
        let u = min(max((p.x - r.minX) / r.width, 0), 1), v = min(max(1 - (p.y - r.minY) / r.height, 0), 1)
        switch rotation {
        case 1: return (v, 1 - u)
        case 2: return (1 - u, 1 - v)
        case 3: return (1 - v, u)
        default: return (u, v)
        }
    }
    private func norm(_ e: NSEvent, clamp: Bool = false) -> (CGFloat, CGFloat)? { norm(convert(e.locationInWindow, from: nil), clamp: clamp) }

    // click / drag (also what a three-finger drag produces): live touch stream
    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        if e.modifierFlags.contains(.option) { pinchAnchor = convert(e.locationInWindow, from: nil); pinchScale = 1; return }
        if let (x, y) = norm(e) { send?(["k": "down", "x": x, "y": y]) }
    }
    override func mouseDragged(with e: NSEvent) {
        if let a = pinchAnchor {   // drag away from the anchor = zoom in, towards = zoom out
            let p = convert(e.locationInWindow, from: nil)
            pinchScale = max(0.3, min(3.5, 1 + (hypot(p.x - a.x, p.y - a.y) * (p.y >= a.y ? 1 : -1)) / 160))
            return
        }
        guard Date().timeIntervalSince(lastMove) > 0.008, let (x, y) = norm(e, clamp: true) else { return }
        lastMove = Date(); send?(["k": "move", "x": x, "y": y])
    }
    override func mouseUp(with e: NSEvent) {
        if let a = pinchAnchor {
            pinchAnchor = nil
            if let (x, y) = norm(a, clamp: true), abs(pinchScale - 1) > 0.05 { send?(["k": "pinch", "x": x, "y": y, "s": pinchScale]) }
            return
        }
        if let (x, y) = norm(e, clamp: true) { send?(["k": "up", "x": x, "y": y]) }
    }
    override func rightMouseDown(with e: NSEvent) { send?(["k": "nav", "a": "back"]) }      // two-finger click / right-click = Back

    // two-finger scroll: becomes a real finger drag so scrolling is smooth and flings like on the phone
    override func scrollWheel(with e: NSEvent) {
        let trackpad = e.phase != [] || e.momentumPhase != []
        guard trackpad else {   // classic mouse wheel: one short swipe per notch
            if let (x, y) = norm(e) { send?(["k": "scroll", "x": x, "y": y, "dy": -e.scrollingDeltaY / max(videoRect.height, 1) * 8]) }
            return
        }
        if e.momentumPhase != [] { return }       // the phone applies its own fling
        let r = videoRect
        switch e.phase {
        case .began, .mayBegin:
            let p = convert(e.locationInWindow, from: nil)
            scrollPoint = r.contains(p) ? p : CGPoint(x: r.midX, y: r.midY)
            scrolling = true
            if let (x, y) = norm(scrollPoint, clamp: true) { send?(["k": "down", "x": x, "y": y]) }
        case .changed:
            if !scrolling { return }
            // natural scrolling: fingers moving down ⇒ content moves down ⇒ finger point moves down (view y decreases)
            scrollPoint.x = min(max(scrollPoint.x + e.scrollingDeltaX, r.minX + 2), r.maxX - 2)
            scrollPoint.y = min(max(scrollPoint.y - e.scrollingDeltaY, r.minY + 2), r.maxY - 2)
            guard Date().timeIntervalSince(lastMove) > 0.016, let (x, y) = norm(scrollPoint, clamp: true) else { return }
            lastMove = Date(); send?(["k": "move", "x": x, "y": y])
        case .ended, .cancelled:
            if scrolling, let (x, y) = norm(scrollPoint, clamp: true) { send?(["k": "up", "x": x, "y": y]) }
            scrolling = false
        default: break
        }
    }

    // pinch to zoom
    override func magnify(with e: NSEvent) {
        switch e.phase {
        case .began: magnifyTotal = 0
        case .changed: magnifyTotal += e.magnification
        case .ended:
            magnifyTotal += e.magnification
            if let (x, y) = norm(e, clamp: true), abs(magnifyTotal) > 0.05 { send?(["k": "pinch", "x": x, "y": y, "s": max(0.25, 1 + magnifyTotal)]) }
        default: break
        }
    }

    // two-finger rotate
    override func rotate(with e: NSEvent) {
        switch e.phase {
        case .began: rotateTotal = 0
        case .changed: rotateTotal += CGFloat(e.rotation)
        case .ended:
            rotateTotal += CGFloat(e.rotation)
            if let (x, y) = norm(e, clamp: true), abs(rotateTotal) > 8 { send?(["k": "rotate", "x": x, "y": y, "deg": -rotateTotal]) }  // AppKit: counter-clockwise positive
        default: break
        }
    }

    // three-finger swipe (when macOS "swipe between pages" is on): right = Back, left = Recents, up = Home, down = Notifications
    override func swipe(with e: NSEvent) {
        if e.deltaX < 0 { send?(["k": "nav", "a": "back"]) }
        else if e.deltaX > 0 { send?(["k": "nav", "a": "recents"]) }
        else if e.deltaY > 0 { send?(["k": "nav", "a": "home"]) }
        else if e.deltaY < 0 { send?(["k": "nav", "a": "notifications"]) }
    }

    override func keyDown(with e: NSEvent) {
        if e.modifierFlags.contains(.command), let c = e.charactersIgnoringModifiers {
            switch c {
            case "v": NotificationCenter.default.post(name: .phonePaste, object: nil); return
            case "a": send?(["k": "selectall"]); return
            default: break
            }
        }
        switch e.keyCode {
        case 51: send?(["k": "key", "c": "backspace"])
        case 36, 76: send?(["k": "key", "c": "enter"])
        case 53: send?(["k": "nav", "a": "back"])
        default: if let t = e.characters, !t.isEmpty, !e.modifierFlags.contains(.command) { send?(["k": "text", "t": t]) }
        }
    }
}

extension Notification.Name { static let phonePaste = Notification.Name("andromac.phonePaste") }
