import AppKit

final class InputMonitor {
    var tabPressedHandler: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        stop()
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, info in
                guard type == .keyDown,
                      let info else { return Unmanaged.passUnretained(event) }

                let monitor = Unmanaged<InputMonitor>.fromOpaque(info).takeUnretainedValue()
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                if keyCode == 48 && flags.isEmpty {
                    if monitor.tabPressedHandler?() == true {
                        return nil
                    }
                }

                monitor.keyDownHandler?(keyCode, flags)
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func refresh() {
    }

    var keyDownHandler: ((Int64, CGEventFlags) -> Void)?
}
