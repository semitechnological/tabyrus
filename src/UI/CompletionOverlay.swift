import Cocoa

final class CompletionOverlay {
    private var window: NSWindow?
    private var textField: NSTextField?

    func show(suggestion: String, at caretRect: CGRect, in elementFrame: CGRect) {
        hide()
        buildWindowIfNeeded()

        guard let window, let textField else { return }

        textField.stringValue = suggestion

        let origin = NSPoint(
            x: caretRect.maxX + 4,
            y: caretRect.minY
        )

        window.setFrame(
            NSRect(origin: origin, size: window.frame.size),
            display: true
        )

        window.orderFront(nil)
        window.level = .floating
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func buildWindowIfNeeded() {
        guard window == nil else { return }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 24),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
        w.level = .floating

        let tf = NSTextField(frame: w.contentView!.bounds)
        tf.isEditable = false
        tf.isBordered = false
        tf.backgroundColor = .clear
        tf.textColor = NSColor.systemGray.withAlphaComponent(0.65)
        tf.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tf.alignment = .left
        tf.maximumNumberOfLines = 1
        tf.lineBreakMode = .byTruncatingTail

        w.contentView?.addSubview(tf)
        tf.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 2),
            tf.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -2),
            tf.centerYAnchor.constraint(equalTo: w.contentView!.centerYAnchor)
        ])

        self.window = w
        self.textField = tf
    }
}
