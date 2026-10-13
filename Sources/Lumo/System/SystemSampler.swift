import Darwin
import Foundation
import LumoCore

struct MemoryUsage: Equatable {
    var usedBytes: UInt64 = 0
    var totalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    var fraction: Double { totalBytes == 0 ? 0 : min(Double(usedBytes) / Double(totalBytes), 1) }
}

struct DiskUsage: Equatable {
    var availableBytes: UInt64 = 0
    var totalBytes: UInt64 = 0

    var fraction: Double { totalBytes == 0 ? 0 : 1 - Double(availableBytes) / Double(totalBytes) }
}

struct SelfUsage: Equatable {
    var cpuPercent: Double = 0
    var footprintBytes: UInt64 = 0
}

/// Cheap kernel-level readings (no subprocesses): CPU ticks, VM stats, swap, disk.
final class SystemSampler {
    private let host = mach_host_self()
    private let pageSize = UInt64(getpagesize())
    private var previousTicks: CPUTicks?
    private var previousSelfCPU: (cpu: Double, wall: Double)?

    /// Busy fraction since the previous call; `nil` on the very first call.
    func cpuLoad() -> Double? {
        guard let ticks = readTicks() else { return nil }
        defer { previousTicks = ticks }
        guard let previousTicks else { return nil }
        return CPUTicks.load(from: previousTicks, to: ticks)
    }

    /// "Memory Used" as Activity Monitor defines it: app + wired + compressed.
    func memory() -> MemoryUsage {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return MemoryUsage(usedBytes: 0, totalBytes: total) }

        let internalPages = UInt64(stats.internal_page_count)
        let appPages = internalPages - min(UInt64(stats.purgeable_count), internalPages)
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        return MemoryUsage(usedBytes: min(used, total), totalBytes: total)
    }

    func swapUsedBytes() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    func disk() -> DiskUsage {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return DiskUsage() }
        return DiskUsage(availableBytes: UInt64(max(available, 0)), totalBytes: UInt64(max(total, 0)))
    }

    /// Lumo's own footprint, so the user can see the optimizer is not a hog itself.
    func selfUsage() -> SelfUsage {
        var spec = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &spec)
        let cpu = Double(spec.tv_sec) + Double(spec.tv_nsec) / 1_000_000_000
        let wall = ProcessInfo.processInfo.systemUptime
        defer { previousSelfCPU = (cpu, wall) }

        var percent = 0.0
        if let previous = previousSelfCPU, wall > previous.wall {
            percent = (cpu - previous.cpu) / (wall - previous.wall) * 100
        }
        return SelfUsage(cpuPercent: max(percent, 0), footprintBytes: footprint())
    }

    private func readTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
