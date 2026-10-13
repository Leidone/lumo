import Foundation
import LumoCore

/// Everything Lumo knows about the Mac at one moment. A new value is built on every sample.
struct MonitorSnapshot {
    static let historyLength = 60

    let cpuLoad: Double
    let coreLoads: [Double]
    let memory: MemoryUsage
    let pressure: MemoryPressure
    let swapBytes: UInt64
    let disk: DiskUsage
    let thermal: ProcessInfo.ThermalState
    let network: NetworkSnapshot
    let battery: BatteryReading?
    let selfUsage: SelfUsage
    let cpuHistory: MetricHistory
    let memoryHistory: MetricHistory
    let downHistory: MetricHistory
    let upHistory: MetricHistory

    /// Raw "how full is it" — drives auto-optimize, which the user configures in these terms.
    var systemLoad: Double { max(cpuLoad, memory.fraction) }

    /// "How is the Mac feeling" — drives colors and status text. macOS keeps memory ~70% full
    /// on purpose, so memory only counts as strain when the kernel reports pressure.
    var healthLoad: Double {
        let memoryStrain: Double
        switch pressure {
        case .normal: memoryStrain = min(memory.fraction * 0.7, 0.59)
        case .warning: memoryStrain = 0.75
        case .critical: memoryStrain = 0.95
        }
        return max(cpuLoad, memoryStrain)
    }

    static let empty = MonitorSnapshot(
        cpuLoad: 0, coreLoads: [], memory: MemoryUsage(), pressure: .normal, swapBytes: 0, disk: DiskUsage(),
        thermal: .nominal, network: .empty, battery: nil, selfUsage: SelfUsage(),
        cpuHistory: MetricHistory(capacity: historyLength), memoryHistory: MetricHistory(capacity: historyLength),
        downHistory: MetricHistory(capacity: historyLength), upHistory: MetricHistory(capacity: historyLength))
}

/// Combines all samplers. Fast readings every tick, slow ones (disk, battery, IP) every 10 s.
@MainActor
final class MonitorService {
    private static let slowInterval: TimeInterval = 10

    private let system = SystemSampler()
    private let cores = CoreSampler()
    private let network = NetworkSampler()
    private var lastSlowSample = Date.distantPast

    func prime() {
        _ = system.cpuLoad()
        _ = cores.sample()
        _ = network.sample(previousIP: nil, refreshIP: false)
    }

    func memory() -> MemoryUsage { system.memory() }

    func sample(after previous: MonitorSnapshot, now: Date) -> MonitorSnapshot {
        let refreshSlow = now.timeIntervalSince(lastSlowSample) >= Self.slowInterval
        if refreshSlow { lastSlowSample = now }

        let cpu = system.cpuLoad() ?? previous.cpuLoad
        let memory = system.memory()
        let traffic = network.sample(previousIP: previous.network.localIP, refreshIP: refreshSlow)
        return MonitorSnapshot(
            cpuLoad: cpu, coreLoads: cores.sample(), memory: memory, pressure: .current(),
            swapBytes: system.swapUsedBytes(), disk: refreshSlow ? system.disk() : previous.disk,
            thermal: ProcessInfo.processInfo.thermalState, network: traffic,
            battery: refreshSlow ? BatterySampler.read() : previous.battery, selfUsage: system.selfUsage(),
            cpuHistory: previous.cpuHistory.appending(cpu),
            memoryHistory: previous.memoryHistory.appending(memory.fraction),
            downHistory: previous.downHistory.appending(traffic.downRate),
            upHistory: previous.upHistory.appending(traffic.upRate))
    }
}
