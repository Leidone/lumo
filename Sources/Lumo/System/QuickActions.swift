import AppKit
import LumoCore

/// Control Center–style one-tap actions. Every one is user-initiated.
@MainActor
enum QuickActions {
    static var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Needs a one-time Automation permission for System Events.
    static func setDarkMode(_ enabled: Bool) -> Bool {
        runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to \(enabled)")
    }

    static var desktopIconsHidden: Bool {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let value = CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString)
        return (value as? Bool) == false
    }

    /// Relaunches Finder so the change applies, exactly like the well-known `defaults` trick.
    static func setDesktopIcons(hidden: Bool) -> Bool {
        let wrote = run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"])
        guard wrote else { return false }
        return run("/usr/bin/killall", ["Finder"])
    }

    static func lockScreen() {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockScreen = @convention(c) () -> Int32
            _ = unsafeBitCast(symbol, to: LockScreen.self)()
            return
        }
        _ = run("/usr/bin/pmset", ["displaysleepnow"])
    }

    /// Needs a one-time Automation permission for Finder.
    static func emptyTrash() -> Bool {
        runAppleScript("tell application \"Finder\" to empty trash")
    }

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    private static func run(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum PortScanner {
    /// Ports opened by this user's processes (lsof shows only those without root). Call off the main thread.
    static func listening() -> [ListeningPort] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = LsofParser.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // lsof exits with 1 when nothing is listening; the output is still valid.
        return LsofParser.parse(String(decoding: data, as: UTF8.self))
    }
}
