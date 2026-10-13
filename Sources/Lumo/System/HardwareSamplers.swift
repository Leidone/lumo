import Darwin
import Foundation
import IOKit
import IOKit.ps
import LumoCore

enum MemoryPressure: Int, Comparable {
    case normal = 1, warning = 2, critical = 4

    static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The kernel's own verdict — the same signal Activity Monitor's pressure graph uses.
    static func current() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }
}

/// Per-core busy fraction from `host_processor_info`.
final class CoreSampler {
    private let host = mach_host_self()
    private var previous: [CPUTicks] = []

    func sample() -> [Double] {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let stride = Int(CPU_STATE_MAX)
        let ticks = (0..<Int(coreCount)).map { core -> CPUTicks in
            let base = core * stride
            func value(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[base + Int(state)]) }
            return CPUTicks(user: value(CPU_STATE_USER), system: value(CPU_STATE_SYSTEM),
                            idle: value(CPU_STATE_IDLE), nice: value(CPU_STATE_NICE))
        }
        defer { previous = ticks }
        guard previous.count == ticks.count else { return Array(repeating: 0, count: ticks.count) }
        return zip(previous, ticks).map { CPUTicks.load(from: $0, to: $1) }
    }
}

struct NetworkSnapshot: Equatable {
    let downRate: Double
    let upRate: Double
    let sessionDown: UInt64
    let sessionUp: UInt64
    let localIP: String?

    static let empty = NetworkSnapshot(downRate: 0, upRate: 0, sessionDown: 0, sessionUp: 0, localIP: nil)
}

/// Wi-Fi/Ethernet traffic from 64-bit interface counters (NET_RT_IFLIST2).
/// VPN tunnels are skipped so traffic is not counted twice.
final class NetworkSampler {
    private static let routeInfo2: Int32 = 0x12 // RTM_IFINFO2
    private var previous: NetworkCounters?
    private var sessionDown: UInt64 = 0
    private var sessionUp: UInt64 = 0

    func sample(previousIP: String?, refreshIP: Bool) -> NetworkSnapshot {
        guard let counters = Self.readCounters() else { return .empty }
        let delta = previous.map { NetworkDelta.between($0, counters) } ?? .zero
        previous = counters
        sessionDown += delta.receivedBytes
        sessionUp += delta.sentBytes
        return NetworkSnapshot(downRate: delta.downBytesPerSecond, upRate: delta.upBytesPerSecond,
                               sessionDown: sessionDown, sessionUp: sessionUp,
                               localIP: refreshIP ? Self.localIPv4() : previousIP)
    }

    private static func readCounters() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == routeInfo2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if isPhysical(index: message.ifm_index) {
                        received += message.ifm_data.ifi_ibytes
                        sent += message.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return NetworkCounters(received: received, sent: sent, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    private static func isPhysical(index: UInt16) -> Bool {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &name) != nil else { return false }
        return String(cString: name).hasPrefix("en")
    }

    private static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name).hasPrefix("en")
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            return String(cString: host)
        }
        return nil
    }
}

/// Internal battery via IOKit power sources + the AppleSmartBattery registry entry.
enum BatterySampler {
    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            let registry = smartBatteryProperties()
            return BatteryReading(
                charge: Double(current) / Double(maximum), isCharging: charging, isPluggedIn: pluggedIn,
                minutesRemaining: minutes, cycleCount: registry["CycleCount"] as? Int,
                maxCapacity: (registry["AppleRawMaxCapacity"] ?? registry["MaxCapacity"]) as? Int,
                designCapacity: registry["DesignCapacity"] as? Int, watts: watts(from: registry))
        }
        return nil
    }

    private static func smartBatteryProperties() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return [:]
        }
        return properties?.takeRetainedValue() as? [String: Any] ?? [:]
    }

    private static func watts(from registry: [String: Any]) -> Double? {
        guard let voltage = (registry["Voltage"] as? NSNumber)?.doubleValue,
              let amperage = (registry["Amperage"] as? NSNumber)?.int64Value
        else { return nil }
        let value = abs(voltage * Double(Int32(truncatingIfNeeded: amperage))) / 1_000_000
        return value > 0.05 ? value : nil
    }
}
