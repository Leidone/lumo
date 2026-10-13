import AppKit
import LumoCore

struct OptimizationOptions {
    let policy: OptimizationPolicy
    let cleanCaches: Bool
    let purgeMemory: Bool
    let passwordlessPurge: Bool
    let isAutomatic: Bool
    let t: Localizer
}

struct OptimizationReport: Equatable {
    let stopped: [String]
    let failed: [String]
    let freedMemoryBytes: UInt64
    let cacheBytes: UInt64
    let purged: Bool
    let notes: [String]
    let isAutomatic: Bool
    let date: Date

    var didAnything: Bool { !stopped.isEmpty || cacheBytes > 0 || purged }
}

/// Executes a plan: quits apps gracefully, SIGTERMs background hogs, then optional maintenance.
@MainActor
final class Optimizer {
    private static let terminationGrace: Duration = .milliseconds(1500)
    private static let settleDelay: Duration = .milliseconds(800)

    func run(plan: [PlanItem], options: OptimizationOptions, readMemory: () -> MemoryUsage) async -> OptimizationReport {
        let before = readMemory().usedBytes
        let outcomes = plan.map { (name: $0.group.displayName, ok: stop($0)) }

        if !plan.isEmpty { try? await Task.sleep(for: Self.terminationGrace) }
        if options.policy.forceKillStubborn { forceKillSurvivors(of: plan) }

        var notes: [String] = []
        var cacheBytes: UInt64 = 0
        if options.cleanCaches {
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let result = await Task.detached(priority: .utility) { CacheCleaner.clean(runningBundleIDs: running) }.value
            cacheBytes = result.freedBytes
            if result.failures > 0 { notes.append(options.t("Пропущено файлов кэша: \(result.failures)",
                                                          "Cache files skipped: \(result.failures)")) }
        }

        var purged = false
        if options.purgeMemory {
            switch await AdminTasks.purgeMemory(passwordless: options.passwordlessPurge, t: options.t) {
            case .success: purged = true
            case .failure(let failure): notes.append(failure.message)
            }
        }

        try? await Task.sleep(for: Self.settleDelay)
        let after = readMemory().usedBytes
        return OptimizationReport(
            stopped: outcomes.filter(\.ok).map(\.name),
            failed: outcomes.filter { !$0.ok }.map(\.name),
            freedMemoryBytes: before > after ? before - after : 0,
            cacheBytes: cacheBytes, purged: purged, notes: notes,
            isAutomatic: options.isAutomatic, date: Date())
    }

    private func stop(_ item: PlanItem) -> Bool {
        switch item.action {
        case .quitApp:
            guard case .app(let app) = item.group.kind,
                  let running = NSRunningApplication(processIdentifier: app.pid)
            else { return false }
            return running.terminate()
        case .terminate:
            let results = item.group.pids.map { kill($0, SIGTERM) == 0 }
            return results.contains(true)
        }
    }

    /// Background processes that ignored SIGTERM. Apps are never force-killed:
    /// they may be showing a "save changes?" dialog.
    private func forceKillSurvivors(of plan: [PlanItem]) {
        for item in plan where item.action == .terminate {
            for pid in item.group.pids where kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }
}
