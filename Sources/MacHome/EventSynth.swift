import AppKit
import ApplicationServices

/// Keys the gamepad can press.
enum SynthKey {
    case up, down, left, right, enter, escape, space
    /// Control-Command-F: the standard macOS "Enter/Exit Full Screen" shortcut.
    case fullScreen
    /// Command-[ and Command-]: back and forward in browsers.
    case back, forward

    var keyCode: CGKeyCode {
        switch self {
        case .up: return 126
        case .down: return 125
        case .left: return 123
        case .right: return 124
        case .enter: return 36
        case .escape: return 53
        case .space: return 49
        case .fullScreen: return 3
        case .back: return 33
        case .forward: return 30
        }
    }

    var systemFlags: CGEventFlags {
        switch self {
        case .fullScreen: return [.maskCommand, .maskControl]
        case .back, .forward: return .maskCommand
        default: return []
        }
    }

    /// Characters for key events posted inside MacHome. Only the plain keys the web player uses have them.
    var characters: String? {
        switch self {
        case .up: return SynthKey.functionKey(NSUpArrowFunctionKey)
        case .down: return SynthKey.functionKey(NSDownArrowFunctionKey)
        case .left: return SynthKey.functionKey(NSLeftArrowFunctionKey)
        case .right: return SynthKey.functionKey(NSRightArrowFunctionKey)
        case .enter: return "\r"
        case .escape: return "\u{1B}"
        case .space: return " "
        default: return nil
        }
    }

    /// Real arrow-key events carry these flags, so posted ones do too.
    var localFlags: NSEvent.ModifierFlags {
        switch self {
        case .up, .down, .left, .right: return [.numericPad, .function]
        default: return []
        }
    }

    private static func functionKey(_ code: Int) -> String {
        UnicodeScalar(code).map { String(Character($0)) } ?? ""
    }
}

/// Posts keyboard and mouse events to whichever app is in front.
/// macOS drops these unless MacHome is allowed under Security & Privacy › Accessibility.
final class EventSynth {
    private let source = CGEventSource(stateID: .hidSystemState)
    private(set) var leftDown = false
    private(set) var rightDown = false
    private var clickCount = 0
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero

    var hasSystemAccess: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system dialog that leads to the Accessibility settings.
    func requestSystemAccess() {
        // The value of kAXTrustedCheckOptionPrompt, written out because its Swift type differs between SDKs.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func tap(_ key: SynthKey) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: isDown) else { continue }
            let flags = key.systemFlags
            if !flags.isEmpty { event.flags = flags }
            event.post(tap: .cghidEventTap)
        }
    }

    var pointerLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    func movePointer(by delta: CGVector) {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        var point = pointerLocation
        point.x = min(max(point.x + delta.dx, bounds.minX), bounds.maxX - 1)
        point.y = min(max(point.y + delta.dy, bounds.minY), bounds.maxY - 1)
        let type: CGEventType
        let button: CGMouseButton
        if leftDown {
            type = .leftMouseDragged
            button = .left
        } else if rightDown {
            type = .rightMouseDragged
            button = .right
        } else {
            type = .mouseMoved
            button = .left
        }
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }

    func setButton(_ button: CGMouseButton, down: Bool) {
        let point = pointerLocation
        let type: CGEventType
        if button == .right {
            type = down ? .rightMouseDown : .rightMouseUp
            rightDown = down
        } else {
            type = down ? .leftMouseDown : .leftMouseUp
            leftDown = down
            if down { countClick(at: point) }
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
        // Apps read double-clicks from this field, so quick repeat presses of A double-click.
        event.setIntegerValueField(.mouseEventClickState, value: Int64(button == .right ? 1 : clickCount))
        event.post(tap: .cghidEventTap)
    }

    func scroll(dx: Int32, dy: Int32) {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private func countClick(at point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let near = hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < 8
        clickCount = (now - lastClickTime < NSEvent.doubleClickInterval && near) ? clickCount + 1 : 1
        lastClickTime = now
        lastClickPoint = point
    }
}
