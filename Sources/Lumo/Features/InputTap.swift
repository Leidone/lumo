import AppKit
import CoreGraphics

/// One shared Quartz event tap for every input tool. Handlers return the event to pass it on,
/// or nil to swallow it. The tap only exists while at least one tool needs it.
@MainActor
final class InputTap {
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    /// Marks events Lumo posts itself, so the tap lets them through untouched.
    nonisolated static let syntheticMarker: Int64 = 0x4C554D4F // "LUMO"

    private var handlers: [(mask: CGEventMask, handle: Handler)] = []
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { port != nil }

    func configure(_ handlers: [(mask: CGEventMask, handle: Handler)]) {
        stop()
        self.handlers = handlers
        let mask = handlers.reduce(CGEventMask(0)) { $0 | $1.mask }
        guard mask != 0, AXIsProcessTrusted() else { return }

        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<InputTap>.fromOpaque(info).takeUnretainedValue()
            return MainActor.assumeIsolated { tap.dispatch(type, event) }
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        port = nil
        source = nil
    }

    static func mask(_ types: CGEventType...) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }

    private func dispatch(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        let bit = CGEventMask(1) << CGEventMask(type.rawValue)
        var current = event
        for handler in handlers where handler.mask & bit != 0 {
            guard let next = handler.handle(type, current) else { return nil }
            current = next
        }
        return Unmanaged.passUnretained(current)
    }
}
