import AppKit
import Combine

struct FocusSnapshot {
    let bundleIdentifier: String?
    let appName: String?
    let textValue: String?
    let caretRect: CGRect
    let inputFrameRect: CGRect
    let isEditable: Bool
    let element: AXUIElement?

    enum Capability {
        case unsupported
        case supported
    }

    var capability: Capability {
        guard isEditable, textValue != nil else { return .unsupported }
        return .supported
    }

    var context: FocusedContext? {
        guard capability == .supported,
              let textValue, let appName, let element else { return nil }
        return FocusedContext(
            textValue: textValue,
            appName: appName,
            caretRect: caretRect,
            inputFrameRect: inputFrameRect,
            element: element
        )
    }
}

struct FocusedContext {
    let textValue: String
    let appName: String
    let caretRect: CGRect
    let inputFrameRect: CGRect
    let element: AXUIElement
}

@MainActor
final class FocusTracker: ObservableObject {
    @Published var snapshot = FocusSnapshot(
        bundleIdentifier: nil, appName: nil, textValue: nil,
        caretRect: .zero, inputFrameRect: .zero, isEditable: false, element: nil
    )

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 0.08

    func start() {
        stop()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshNow() {
        poll()
    }

    private func poll() {
        guard AXIsProcessTrusted() else { return }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        guard result == .success,
              let focusedRef,
              let element = (focusedRef as! AXUIElement?) else { return }

        let bundleId = bundleIdentifier(for: element)
        let appName = applicationName(for: element)

        guard bundleId != Bundle.main.bundleIdentifier else { return }

        let isEditable = checkEditable(element)
        let textValue = textContent(from: element)
        let caretRect = caretGeometry(from: element)
        let inputFrameRect = elementFrame(from: element)

        let newSnapshot = FocusSnapshot(
            bundleIdentifier: bundleId,
            appName: appName,
            textValue: textValue,
            caretRect: caretRect,
            inputFrameRect: inputFrameRect,
            isEditable: isEditable,
            element: element
        )

        snapshot = newSnapshot
    }

    private func bundleIdentifier(for element: AXUIElement) -> String? {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private func applicationName(for element: AXUIElement) -> String? {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    private func checkEditable(_ element: AXUIElement) -> Bool {
        var isEditable: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXIsEditableAttribute as CFString, &isEditable)
        if result == .success, let value = isEditable as? Bool {
            return value
        }
        return AXTextGeometryResolver.canBeTextInput(element)
    }

    private func textContent(from element: AXUIElement) -> String? {
        var textValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        if result == .success, let text = textValue as? String {
            return text
        }
        return nil
    }

    private func caretGeometry(from element: AXUIElement) -> CGRect {
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        if rangeResult == .success {
            var bounds: CFTypeRef?
            let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString,
                selectedRange!, &bounds
            )
            if boundsResult == .success {
                if let rectValue = bounds {
                    var rect = CGRect.zero
                    if AXValueGetValue(rectValue as! AXValue, .cgRect, &rect) {
                        return rect
                    }
                }
            }
        }

        var position: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        if posResult == .success {
            var point = CGPoint.zero
            if AXValueGetValue(position as! AXValue, .cgPoint, &point) {
                var sizeRef: CFTypeRef?
                let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
                var size = CGSize(width: 2, height: 16)
                if sizeResult == .success {
                    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
                }
                return CGRect(x: point.x, y: point.y, width: size.width, height: size.height)
            }
        }

        return .zero
    }

    private func elementFrame(from element: AXUIElement) -> CGRect {
        var position: CFTypeRef?
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)

        var point = CGPoint.zero
        var cgSize = CGSize.zero
        if let p = position { AXValueGetValue(p as! AXValue, .cgPoint, &point) }
        if let s = size { AXValueGetValue(s as! AXValue, .cgSize, &cgSize) }

        return CGRect(origin: point, size: cgSize)
    }
}

enum AXTextGeometryResolver {
    static func canBeTextInput(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let roleStr = role as? String else { return false }
        return roleStr == kAXTextAreaRole || roleStr == kAXTextFieldRole
    }
}
