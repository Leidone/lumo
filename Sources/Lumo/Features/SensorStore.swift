import Foundation
import IOKit

/// Temperatures (IOHID thermal sensors, no root needed) and fan speeds (SMC, read-only).
@MainActor
final class SensorStore: ObservableObject {
    struct Reading: Identifiable, Equatable {
        let name: String
        let celsius: Double
        var id: String { name }
    }

    struct Fan: Identifiable, Equatable {
        let index: Int
        let rpm: Double
        let minRPM: Double
        let maxRPM: Double
        var id: Int { index }
        var fraction: Double { maxRPM > minRPM ? min(max((rpm - minRPM) / (maxRPM - minRPM), 0), 1) : 0 }
    }

    @Published private(set) var readings: [Reading] = []
    @Published private(set) var fans: [Fan] = []
    @Published private(set) var isSupported = true

    private let thermal = ThermalSensors()
    private let smc = SMCReader()

    /// Hottest SoC die — the number people mean by "CPU temperature".
    var socTemperature: Double? { readings.filter { Self.isSoC($0.name) }.map(\.celsius).max() }
    var batteryTemperature: Double? { readings.first { $0.name.localizedCaseInsensitiveContains("battery") }?.celsius }
    var ssdTemperature: Double? { readings.filter { $0.name.contains("NAND") }.map(\.celsius).max() }

    func sample() {
        let values = thermal?.read() ?? []
        isSupported = thermal != nil
        readings = values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        fans = smc?.fans() ?? []
    }

    private static func isSoC(_ name: String) -> Bool {
        name.contains("tdie") || name.contains("SOC") || name.contains("CPU")
    }
}

/// Thin wrapper over the IOHIDEventSystem calls macOS uses for its own thermal sensors.
/// They are exported by IOKit but not declared in public headers, so they're looked up at runtime.
private final class ThermalSensors {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValue = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField = Int32(15 << 16)
    private static let validRange = 1.0...130.0

    private let client: AnyObject
    private let copyServices: CopyServices
    private let copyProperty: CopyProperty
    private let copyEvent: CopyEvent
    private let floatValue: FloatValue

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = Self.symbol(handle, "IOHIDEventSystemClientCreate", as: CreateClient.self),
              let setMatching = Self.symbol(handle, "IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = Self.symbol(handle, "IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyProperty = Self.symbol(handle, "IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let copyEvent = Self.symbol(handle, "IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let floatValue = Self.symbol(handle, "IOHIDEventGetFloatValue", as: FloatValue.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return nil }
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        setMatching(client, matching)
        self.client = client
        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.floatValue = floatValue
    }

    func read() -> [SensorStore.Reading] {
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        var seen = Set<String>()
        return services.compactMap { service in
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  seen.insert(name).inserted,
                  let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue()
            else { return nil }
            let value = floatValue(event, Self.temperatureField)
            return Self.validRange.contains(value) ? SensorStore.Reading(name: name, celsius: value) : nil
        }
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}

/// Minimal read-only AppleSMC client for fan keys.
private final class SMCReader {
    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        /// Keeps the C layout: the kernel struct is padded to 12 bytes.
        var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }

    /// Mirrors the kernel's SMCKeyData_t (80 bytes).
    private struct KeyData {
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

        var key: UInt32 = 0
        var version: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var limits: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleEvent: UInt32 = 2
    private static let readKey: UInt8 = 5
    private static let readKeyInfo: UInt8 = 9

    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(connection) }

    func fans() -> [SensorStore.Fan] {
        guard let count = read("FNum").map({ Int($0) }), count > 0 else { return [] }
        return (0..<min(count, 4)).compactMap { index in
            guard let rpm = read("F\(index)Ac") else { return nil }
            return SensorStore.Fan(index: index, rpm: rpm, minRPM: read("F\(index)Mn") ?? 0, maxRPM: read("F\(index)Mx") ?? 0)
        }
    }

    private func read(_ key: String) -> Double? {
        var input = KeyData()
        input.key = Self.fourCC(key)
        input.data8 = Self.readKeyInfo
        guard let info = call(&input) else { return nil }

        var request = KeyData()
        request.key = input.key
        request.keyInfo.dataSize = info.keyInfo.dataSize
        request.data8 = Self.readKey
        guard let output = call(&request) else { return nil }
        return Self.decode(output.bytes, type: info.keyInfo.dataType, size: Int(info.keyInfo.dataSize))
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(connection, Self.handleEvent, &input, MemoryLayout<KeyData>.stride,
                                               &output, &outputSize)
        return result == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private static func decode(_ bytes: KeyData.Bytes, type: UInt32, size: Int) -> Double? {
        let raw = withUnsafeBytes(of: bytes) { Array($0.prefix(size)) }
        switch type {
        case fourCC("flt "):
            guard raw.count >= 4 else { return nil }
            return Double(raw.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
        case fourCC("fpe2"):
            guard raw.count >= 2 else { return nil }
            return Double((UInt16(raw[0]) << 8 | UInt16(raw[1])) >> 2)
        case fourCC("ui8 "):
            return raw.first.map(Double.init)
        default:
            return nil
        }
    }

    private static func fourCC(_ code: String) -> UInt32 {
        code.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
}
