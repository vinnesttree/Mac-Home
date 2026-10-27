import AppKit

/// A borderless window covering the whole screen that can still take keyboard focus.
final class FullScreenWindow: NSWindow {
    convenience init(frame: NSRect) {
        self.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        backgroundColor = .black
        acceptsMouseMovedEvents = true
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
