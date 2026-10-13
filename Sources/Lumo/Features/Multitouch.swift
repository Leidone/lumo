import Foundation

/// Counts fingers resting on the trackpad, so a three-finger press can become a middle click.
/// Uses the private MultitouchSupport framework (the same one macOS gestures are built on).
@MainActor
final class Multitouch {
    static let shared = Multitouch()

    private typealias ContactCallback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    private typealias Control = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32

    /// Written on the multitouch thread, read when a click arrives; a 32-bit store is atomic here.
    nonisolated(unsafe) private static var currentFingers: Int32 = 0

    private var devices: [UnsafeMutableRawPointer] = []
    private var deviceList: CFArray?

    var fingers: Int { Int(Self.currentFingers) }

    func start() {
        guard devices.isEmpty,
              let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createSymbol = dlsym(handle, "MTDeviceCreateList"),
              let registerSymbol = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSymbol = dlsym(handle, "MTDeviceStart"),
              let list = unsafeBitCast(createSymbol, to: CreateList.self)()?.takeRetainedValue()
        else { return }
        let register = unsafeBitCast(registerSymbol, to: Register.self)
        let startDevice = unsafeBitCast(startSymbol, to: Control.self)
        let callback: ContactCallback = { _, _, count, _, _ in
            Multitouch.currentFingers = count
            return 0
        }
        deviceList = list
        for index in 0..<CFArrayGetCount(list) {
            guard let pointer = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: pointer)
            register(device, callback)
            _ = startDevice(device, 0)
            devices.append(device)
        }
    }

    func stop() {
        guard !devices.isEmpty,
              let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let stopSymbol = dlsym(handle, "MTDeviceStop")
        else { return }
        let stopDevice = unsafeBitCast(stopSymbol, to: Stop.self)
        devices.forEach { _ = stopDevice($0) }
        devices = []
        deviceList = nil
        Self.currentFingers = 0
    }
}
