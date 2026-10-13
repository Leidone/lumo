import Foundation
import LumoCore

enum CacheCleaner {
    struct Result {
        let freedBytes: UInt64
        let failures: Int
    }

    /// Empties eligible folders in ~/Library/Caches (folders themselves are kept).
    /// Call off the main thread.
    static func clean(runningBundleIDs: Set<String>) -> Result {
        let fileManager = FileManager.default
        let root = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        guard let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return Result(freedBytes: 0, failures: 0)
        }

        var freed: UInt64 = 0
        var failures = 0
        let eligible = folders.filter {
            CachePolicy.isEligible(folderName: $0.lastPathComponent, runningBundleIDs: runningBundleIDs)
        }
        for folder in eligible {
            let children = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for child in children {
                let size = allocatedSize(of: child)
                do {
                    try fileManager.removeItem(at: child)
                    freed += size
                } catch {
                    failures += 1
                }
            }
        }
        return Result(freedBytes: freed, failures: failures)
    }

    private static func allocatedSize(of url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        let ownSize = UInt64((try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return ownSize
        }
        var total = ownSize
        for case let file as URL in enumerator {
            total += UInt64((try? file.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}

enum AdminTasks {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Runs `purge` and flushes the DNS cache. Without the passwordless rule macOS
    /// shows its own administrator prompt — Lumo never sees the password.
    static func purgeMemory(passwordless: Bool, t: Localizer) async -> Swift.Result<Void, Failure> {
        await Task.detached(priority: .userInitiated) {
            guard passwordless else {
                let command = SudoersRule.commands.map { $0.joined(separator: " ") }.joined(separator: "; ")
                return runWithAdminPrompt(command, prompt: t("Lumo хочет освободить оперативную память.",
                                                             "Lumo wants to free up memory."), t: t)
            }
            let failed = SudoersRule.commands.contains { run("/usr/bin/sudo", ["-n"] + $0).status != 0 }
            return failed
                ? .failure(Failure(message: t("Нет доступа без пароля — включите «Без пароля» заново",
                                              "Passwordless access is gone — turn “No password” on again")))
                : .success(())
        }.value
    }

    /// True when sudo lets this user run `purge` without asking for a password.
    static func isPasswordlessPurgeEnabled() async -> Bool {
        await Task.detached(priority: .utility) {
            run("/usr/bin/sudo", ["-n", "-l", "/usr/sbin/purge"]).status == 0
        }.value
    }

    /// Runs one command as root behind macOS's own administrator prompt — nothing is remembered,
    /// so the next change asks again. Arguments are single-quoted for the shell.
    static func runAsAdmin(_ arguments: [String], prompt: String, t: Localizer) async -> Swift.Result<Void, Failure> {
        let safe = arguments.allSatisfy { !$0.contains(where: { "'\"\\\n".contains($0) }) }
        guard safe, !arguments.isEmpty else { return .failure(Failure(message: t("Недопустимая команда", "Invalid command"))) }
        let command = arguments.map { "'\($0)'" }.joined(separator: " ")
        return await Task.detached(priority: .userInitiated) {
            runWithAdminPrompt(command, prompt: prompt, t: t)
        }.value
    }

    /// Installs or removes /etc/sudoers.d/lumo. Asks for the administrator password once.
    static func setPasswordlessPurge(_ enabled: Bool, t: Localizer) async -> Swift.Result<Void, Failure> {
        await Task.detached(priority: .userInitiated) {
            guard enabled else {
                return runWithAdminPrompt(SudoersRule.removeScript,
                                          prompt: t("Lumo: снова спрашивать пароль для очистки RAM.",
                                                    "Lumo: ask for the password to free memory again."), t: t)
            }
            guard let script = SudoersRule.installScript(for: NSUserName()) else {
                return .failure(Failure(message: t("Необычное имя пользователя — режим без пароля недоступен",
                                                   "Unusual user name — passwordless mode is unavailable")))
            }
            return runWithAdminPrompt(script, prompt: t("Lumo: разрешить очистку RAM без пароля (только purge и DNS-кэш).",
                                                        "Lumo: allow freeing memory without a password (purge and DNS cache only)."),
                                      t: t)
        }.value
    }

    private static func runWithAdminPrompt(_ command: String, prompt: String, t: Localizer) -> Swift.Result<Void, Failure> {
        // The prompt is shown by AppleScript, so quotes and backslashes can't be allowed to end the string.
        let safePrompt = prompt.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "'")
        let script = "do shell script \"\(command)\" with prompt \"\(safePrompt)\" with administrator privileges"
        let result = run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else {
            let canceled = result.errorOutput.contains("-128")
            return .failure(Failure(message: canceled
                ? t("Действие отменено", "Cancelled")
                : t("Команда администратора завершилась с ошибкой", "The administrator command failed")))
        }
        return .success(())
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, errorOutput: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let errorOutput = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, errorOutput)
    }
}
