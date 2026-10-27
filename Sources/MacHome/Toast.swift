import AppKit

/// A short message at the top of the screen. It also shows over other apps, including full-screen ones.
final class Toast {
    private let panel: NSPanel
    private let background: NSView
    private let stack: NSStackView
    private let imageView: NSImageView
    private let label: NSTextField
    private let widthLimit: NSLayoutConstraint
    private var hideWork: DispatchWorkItem?

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0, alpha: 0.8).cgColor
        background.layer?.borderColor = NSColor(white: 1, alpha: 0.15).cgColor
        background.layer?.borderWidth = 1

        let imageView = NSImageView()
        imageView.contentTintColor = .white
        let label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        let widthLimit = stack.widthAnchor.constraint(lessThanOrEqualTo: background.widthAnchor, constant: -60)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            widthLimit
        ])
        panel.contentView = background

        self.panel = panel
        self.background = background
        self.stack = stack
        self.imageView = imageView
        self.label = label
        self.widthLimit = widthLimit
    }

    func show(_ text: String, symbol: String? = nil, duration: TimeInterval = 3) {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let u = max(frame.height / 1080, 0.5)

        label.font = .systemFont(ofSize: 24 * u, weight: .medium)
        label.stringValue = text
        if let symbol = symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            imageView.image = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 26 * u, weight: .semibold))
            imageView.isHidden = false
        } else {
            imageView.isHidden = true
        }
        stack.spacing = 14 * u
        widthLimit.constant = -60 * u

        let content = stack.fittingSize
        let size = NSSize(width: min(content.width + 60 * u, frame.width * 0.9), height: content.height + 36 * u)
        background.layer?.cornerRadius = size.height / 2
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - frame.height * 0.05)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
