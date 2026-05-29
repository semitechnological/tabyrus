import Cocoa
import SwiftUI

final class CompletionOverlay {
    private var window: NSWindow?
    private var hostingView: NSHostingView<CompletionOverlaySuggestionView>?

    func show(suggestion: String, at caretRect: CGRect, in elementFrame: CGRect) {
        hide()
        buildWindowIfNeeded()

        guard let window, let hostingView else { return }

        hostingView.rootView = CompletionOverlaySuggestionView(suggestion: suggestion)

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

        let hostingView = NSHostingView(rootView: CompletionOverlaySuggestionView(suggestion: ""))

        w.contentView?.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: w.contentView!.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor)
        ])

        self.window = w
        self.hostingView = hostingView
    }
}

private struct CompletionOverlaySuggestionView: View {
    let suggestion: String

    var body: some View {
        Text(suggestion)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.secondary.opacity(0.75))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .glassEffect()
    }
}
