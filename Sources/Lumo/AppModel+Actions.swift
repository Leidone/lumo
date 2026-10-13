import AppKit
import LumoCore
import ServiceManagement

// MARK: - Optimization

extension AppModel {
    func optimize(automatic: Bool = false) {
        guard !isOptimizing else { return }
        isOptimizing = true
        errorMessage = nil
        let context = makeContext()
        let policy = policy
        let closeApps = closeApps
        let options = OptimizationOptions(
            policy: policy, cleanCaches: cleanCaches, purgeMemory: purgeMemory && (!automatic || passwordlessPurge),
            passwordlessPurge: passwordlessPurge, isAutomatic: automatic, t: t)

        Task {
            let records = await Self.scan()
            let groups = OptimizationPlanner.groups(from: (try? records.get()) ?? [], context: context)
            let plan = OptimizationPlanner.plan(groups, policy: policy, closeApps: closeApps)
            let report = await optimizer.run(plan: plan, options: options) { [monitor] in monitor.memory() }
            finish(with: report)
        }
    }

    /// Explicit per-row action: the user asked for this exact app/process.
    func stopNow(_ group: UsageGroup) {
        guard !isOptimizing, !group.isFrontmost else { return }
        isOptimizing = true
        let item = PlanItem(group: group, action: group.isApp ? .quitApp : .terminate)
        let options = OptimizationOptions(policy: policy, cleanCaches: false, purgeMemory: false,
                                          passwordlessPurge: passwordlessPurge, isAutomatic: false, t: t)
        Task {
            let report = await optimizer.run(plan: [item], options: options) { [monitor] in monitor.memory() }
            finish(with: report)
        }
    }

    func toggleException(_ key: String) {
        exceptions = exceptions.contains(key) ? exceptions.filter { $0 != key } : exceptions + [key]
        refreshProcesses()
    }

    /// Installs/removes the sudoers rule; macOS asks for the admin password once.
    func setPasswordlessPurge(_ enabled: Bool) {
        guard !isConfiguringPurge, enabled != passwordlessPurge else { return }
        isConfiguringPurge = true
        Task {
            let result = await AdminTasks.setPasswordlessPurge(enabled, t: t)
            passwordlessPurge = await AdminTasks.isPasswordlessPurgeEnabled()
            isConfiguringPurge = false
            switch result {
            case .success:
                errorMessage = nil
                if passwordlessPurge { purgeMemory = true }
            case .failure(let failure):
                errorMessage = failure.message
            }
        }
    }

    func refreshPasswordlessStatus() {
        Task { passwordlessPurge = await AdminTasks.isPasswordlessPurgeEnabled() }
    }

    func dismissReport() {
        lastReport = nil
    }

    private func finish(with report: OptimizationReport) {
        lastReport = report
        isOptimizing = false
        completedRuns += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        refreshProcesses()
        refreshPorts()
    }
}

// MARK: - Processes & ports

extension AppModel {
    func refreshProcesses() {
        guard !isScanning else { return }
        isScanning = true
        let context = makeContext()
        Task {
            let result = await Self.scan()
            isScanning = false
            switch result {
            case .success(let records):
                lastRecords = records
                groups = OptimizationPlanner.groups(from: records, context: context)
            case .failure:
                errorMessage = t("Не удалось получить список процессов", "Couldn't read the process list")
            }
        }
    }

    func refreshPorts() {
        Task {
            ports = await Task.detached(priority: .utility) { PortScanner.listening() }.value
        }
    }

    /// Ports may be stopped when their process is the user's own and not part of macOS.
    /// Terminal-started servers are allowed here: freeing a stuck dev port is the whole point.
    func canStop(_ port: ListeningPort) -> Bool {
        guard let record = lastRecords.first(where: { $0.pid == port.pid }) else { return false }
        switch ProcessClassifier.classify(record, in: makeContext()) {
        case .excluded(.terminalSession), .app, .helper, .background: return true
        case .excluded: return false
        }
    }

    func executablePath(for pid: Int32) -> String? {
        lastRecords.first { $0.pid == pid }?.path
    }

    func stop(_ port: ListeningPort) {
        guard canStop(port) else { return }
        kill(port.pid, SIGTERM)
        ports = ports.filter { $0.pid != port.pid }
        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshPorts()
            refreshProcesses()
        }
    }

    func makeContext() -> ClassificationContext {
        ClassificationContext(
            currentUID: getuid(), ownPID: getpid(),
            apps: ProcessScanner.runningApps(frontmostPID: lastUserFrontmostPID),
            exceptions: Set(exceptions))
    }

    static func scan() async -> Result<[ProcessRecord], Error> {
        await Task.detached(priority: .utility) {
            Result { try ProcessScanner.snapshot() }
        }.value
    }
}

// MARK: - Tools

extension AppModel {
    func startKeepAwake(minutes: Int?) {
        keepAwakeTimer?.invalidate()
        guard keepAwakeService.activate(keepDisplayOn: keepDisplayAwake, reason: "Lumo") else {
            errorMessage = t("Не удалось запретить сон", "Couldn't prevent sleep")
            return
        }
        let until = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        keepAwake = .on(until: until)
        guard let until else { return }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopKeepAwake() }
        }
        RunLoop.main.add(timer, forMode: .common)
        keepAwakeTimer = timer
    }

    func stopKeepAwake() {
        keepAwakeTimer?.invalidate()
        keepAwakeTimer = nil
        keepAwakeService.deactivate()
        keepAwake = .off
    }

    func refreshQuickToggles() {
        darkMode = QuickActions.isDarkMode
        desktopIconsHidden = QuickActions.desktopIconsHidden
    }

    func toggleDarkMode() {
        let target = !darkMode
        guard QuickActions.setDarkMode(target) else {
            errorMessage = t("Разрешите Lumo управлять «System Events»: Настройки → Конфиденциальность → Автоматизация",
                             "Allow Lumo to control System Events: Settings → Privacy → Automation")
            return
        }
        darkMode = target
    }

    func toggleDesktopIcons() {
        let target = !desktopIconsHidden
        guard QuickActions.setDesktopIcons(hidden: target) else {
            errorMessage = t("Не удалось изменить иконки рабочего стола", "Couldn't change desktop icons")
            return
        }
        desktopIconsHidden = target
    }

    func lockScreen() {
        QuickActions.lockScreen()
    }

    func emptyTrash() {
        guard QuickActions.emptyTrash() else {
            errorMessage = t("Разрешите Lumo управлять Finder: Настройки → Конфиденциальность → Автоматизация",
                             "Allow Lumo to control Finder: Settings → Privacy → Automation")
            return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func setAlert(_ kind: AlertKind, enabled: Bool) {
        guard enabled else {
            enabledAlerts = enabledAlerts.subtracting([kind])
            return
        }
        Task {
            guard await AlertService.requestAuthorization() else {
                errorMessage = t("Разрешите уведомления для Lumo: Настройки → Уведомления",
                                 "Allow notifications for Lumo: Settings → Notifications")
                return
            }
            enabledAlerts = enabledAlerts.union([kind])
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = t("Автозапуск недоступен: \(error.localizedDescription). Переместите Lumo в «Программы».",
                             "Launch at login failed: \(error.localizedDescription). Move Lumo to Applications.")
        }
        objectWillChange.send()
    }
}
