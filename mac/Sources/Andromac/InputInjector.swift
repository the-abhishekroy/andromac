import Foundation
import AppKit
import ApplicationServices

/// Turns touch/keyboard messages from the phone into real Mac mouse and keyboard events.
/// Requires the Accessibility permission, and only runs while the user has approved a session.
enum InputInjector {
    private static var dragging = false
    private static var lastDown = Date.distantPast
    private static var lastPoint = CGPoint.zero

    static func trusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
    }

    private static func point(_ d: [String: Any]) -> CGPoint {
        let b = CGDisplayBounds(CGMainDisplayID())
        let x = (d["x"] as? Double) ?? 0, y = (d["y"] as? Double) ?? 0
        return CGPoint(x: b.minX + b.width * x, y: b.minY + b.height * y)
    }

    private static func post(_ type: CGEventType, _ p: CGPoint, button: CGMouseButton = .left, clicks: Int64 = 1) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: clicks)
        e.post(tap: .cghidEventTap)
    }

    static func handle(_ d: [String: Any]) {
        guard trusted(prompt: false) else { return }
        switch d["k"] as? String {
        case "down":
            let p = point(d)
            let dbl = Date().timeIntervalSince(lastDown) < 0.4 && hypot(p.x - lastPoint.x, p.y - lastPoint.y) < 12
            lastDown = Date(); lastPoint = p; dragging = true
            post(.mouseMoved, p); post(.leftMouseDown, p, clicks: dbl ? 2 : 1)
        case "move":
            let p = point(d); post(dragging ? .leftMouseDragged : .mouseMoved, p)
        case "up":
            let p = point(d)
            if dragging { post(.leftMouseUp, p, clicks: Date().timeIntervalSince(lastDown) < 0.4 ? 1 : 1) }
            dragging = false
        case "hover":                                   // trackpad mode: move the cursor without pressing
            post(.mouseMoved, point(d))
        case "mac":                                     // system actions that plain key combos can't trigger reliably
            switch d["a"] as? String {
            case "mission": run("/usr/bin/open", ["-a", "Mission Control"])
            case "desktop": tap(103, fn: true)           // F11 = Show Desktop
            default: break
            }
        case "rclick":
            let p = point(d)
            if dragging { post(.leftMouseUp, p); dragging = false }
            post(.rightMouseDown, p, button: .right); post(.rightMouseUp, p, button: .right)
        case "scroll":
            let dy = (d["dy"] as? Double) ?? 0
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(dy * 1800), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        case "text":
            for ch in (d["t"] as? String ?? "") { typeUnicode(String(ch)) }
        case "key":
            if let name = d["c"] as? String, let code = keyCodes[name] { tap(code) }
        case "combo":
            guard let name = d["c"] as? String, let code = keyCodes[name] else { return }
            var flags: CGEventFlags = []
            for m in (d["m"] as? [String]) ?? [] {
                switch m { case "cmd": flags.insert(.maskCommand); case "ctrl": flags.insert(.maskControl)
                           case "alt": flags.insert(.maskAlternate); case "shift": flags.insert(.maskShift); default: break }
            }
            if [123, 124, 125, 126, 160, 103, 99].contains(code) { flags.insert(.maskSecondaryFn) }   // arrows / F-keys carry the Fn flag on a real keyboard; without it Ctrl+arrow shortcuts are ignored
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
                e?.flags = flags; e?.post(tap: .cghidEventTap)
            }
        default: break
        }
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "backspace": 51, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "f3": 160,
    ]

    private static func tap(_ code: CGKeyCode, fn: Bool = false) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            if fn { e?.flags = .maskSecondaryFn }
            e?.post(tap: .cghidEventTap)
        }
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        try? p.run()
    }

    private static func typeUnicode(_ s: String) {
        let u = Array(s.utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            e?.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u)
            e?.post(tap: .cghidEventTap)
        }
    }
}
