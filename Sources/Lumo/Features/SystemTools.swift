import AppKit
import IOKit
import LumoCore

/// GPU load and whole-system power draw, both from the I/O Registry (no root needed).
enum HardwareExtras {
    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            if let value = (stats?["Device Utilization %"] as? NSNumber)?.doubleValue {
                best = max(best ?? 0, value / 100)
            }
        }
        return best.map { min(max($0, 0), 1) }
    }

    /// What the whole Mac draws right now, in watts (Apple silicon reports it in the battery's telemetry).
    static func systemPowerWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        guard let milliwatts = (telemetry?["SystemPowerIn"] as? NSNumber)?.doubleValue, milliwatts > 0 else { return nil }
        return milliwatts / 1000
    }
}

/// The apps using the most energy (macOS "Energy Impact"), sampled only while someone looks.
@MainActor
final class EnergyMonitor: ObservableObject {
    @Published private(set) var entries: [EnergyEntry] = []
    @Published private(set) var isLoading = false

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
            process.arguments = PowerTopParser.arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var parsed: [EnergyEntry] = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                parsed = PowerTopParser.parse(String(decoding: data, as: UTF8.self))
            }
            let result = Array(parsed.prefix(8))
            await MainActor.run { [weak self] in
                self?.entries = result
                self?.isLoading = false
            }
        }
    }
}

/// Apple's built-in `networkQuality` test: download, upload and responsiveness.
@MainActor
final class SpeedTester: ObservableObject {
    enum State: Equatable {
        case idle, running, done(SpeedTestResult), failed
    }

    @Published private(set) var state = State.idle
    @Published private(set) var lastRun: Date?
    private var process: Process?

    func run() {
        guard state != .running else { return cancel() }
        state = .running
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.arguments = ["-c"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        self.process = process
        Task.detached(priority: .userInitiated) {
            var result: SpeedTestResult?
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                result = SpeedTestResult.parse(data)
            }
            let outcome = result
            await MainActor.run { [weak self] in
                guard let self, self.state == .running else { return }
                self.state = outcome.map(State.done) ?? .failed
                self.lastRun = Date()
                self.process = nil
            }
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        state = .idle
    }
}

/// Manual fan speeds. Every change goes through macOS's administrator prompt and the bundled helper,
/// which validates its arguments and clamps the speed to the fan's own limits.
@MainActor
final class FanControl: ObservableObject {
    @Published private(set) var manual: [Int: Double] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy = false

    static var helperPath: String? { Bundle.main.url(forResource: "lumo-fan", withExtension: nil)?.path }
    var isAvailable: Bool { Self.helperPath != nil }

    func set(_ fan: SensorStore.Fan, rpm: Double, t: Localizer) {
        apply(["set", String(fan.index), String(Int(rpm.rounded()))], fan: fan.index, value: rpm,
              prompt: t("Lumo: задать скорость вентилятора \(fan.index + 1) — \(Int(rpm)) об/мин.",
                        "Lumo: set fan \(fan.index + 1) to \(Int(rpm)) rpm."), t: t)
    }

    func automatic(_ fan: SensorStore.Fan, t: Localizer) {
        apply(["auto", String(fan.index)], fan: fan.index, value: nil,
              prompt: t("Lumo: вернуть вентилятор \(fan.index + 1) под управление macOS.", "Lumo: hand fan \(fan.index + 1) back to macOS."), t: t)
    }

    private func apply(_ arguments: [String], fan: Int, value: Double?, prompt: String, t: Localizer) {
        guard let helper = Self.helperPath, !isBusy else { return }
        isBusy = true
        Task {
            let result = await AdminTasks.runAsAdmin([helper] + arguments, prompt: prompt, t: t)
            isBusy = false
            switch result {
            case .success:
                lastError = nil
                manual[fan] = value
            case .failure(let failure):
                lastError = failure.message
            }
        }
    }
}
