import Foundation

/// Finds per-app data in ~/Library that belongs to apps which are no longer installed.
public enum LeftoverDetector {
    private static let strippedExtensions = [".plist", ".savedState", ".binarycookies", ".sfl2", ".lockfile"]

    /// "com.vendor.App.plist" → "com.vendor.App". Only reverse-DNS names (2+ dots) qualify.
    public static func bundleID(fromItemName name: String) -> String? {
        var base = name
        for suffix in strippedExtensions where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        let parts = base.split(separator: ".")
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }),
              base.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]+$", options: .regularExpression) != nil
        else { return nil }
        return base
    }

    public static func isLeftover(itemName: String, isInstalled: (String) -> Bool, running: Set<String>) -> Bool {
        guard let id = bundleID(fromItemName: itemName) else { return false }
        let lowered = id.lowercased()
        guard !lowered.hasPrefix("com.apple."), !running.contains(where: { $0.lowercased() == lowered }) else { return false }
        return !isInstalled(id)
    }
}

/// Decides which ~/Library items belong to an app that is being uninstalled.
public enum RelatedFiles {
    public static func matches(itemName: String, bundleID: String?, appName: String) -> Bool {
        let name = itemName.lowercased()
        let app = appName.lowercased()
        if name == app || name == app + ".plist" || name == app + ".log" { return true }
        guard let bundleID, !bundleID.isEmpty else { return false }
        let id = bundleID.lowercased()
        // Exact id, id + suffix ("com.x.y.plist", "com.x.y.savedState", "com.x.y.helper"),
        // or a team-prefixed group container ("ABCDE12345.com.x.y").
        return name == id || name.hasPrefix(id + ".") || name.hasSuffix("." + id)
    }
}

public struct BrewPackage: Identifiable, Equatable, Sendable {
    public let name: String
    public let isCask: Bool
    public let installedVersion: String?
    public let latestVersion: String?

    public var id: String { (isCask ? "cask:" : "formula:") + name }

    public init(name: String, isCask: Bool, installedVersion: String?, latestVersion: String?) {
        self.name = name
        self.isCask = isCask
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
    }
}

/// Parses Homebrew's machine-readable output.
public enum BrewParser {
    /// `brew outdated --json=v2`
    public static func outdated(json data: Data) -> [BrewPackage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let formulae = (root["formulae"] as? [[String: Any]] ?? []).compactMap { package($0, isCask: false) }
        let casks = (root["casks"] as? [[String: Any]] ?? []).compactMap { package($0, isCask: true) }
        return (formulae + casks).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// One name per line (`brew list -1`, `brew search`). Drops headers like "==> Formulae".
    public static func names(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") && !$0.contains(" ") }
    }

    private static func package(_ item: [String: Any], isCask: Bool) -> BrewPackage? {
        guard let name = item["name"] as? String else { return nil }
        let installed: String?
        if let versions = item["installed_versions"] as? [String] {
            installed = versions.last
        } else {
            installed = item["installed_versions"] as? String
        }
        return BrewPackage(name: name, isCask: isCask, installedVersion: installed,
                           latestVersion: item["current_version"] as? String)
    }
}

public struct StoreUpdate: Identifiable, Equatable, Sendable {
    public let appID: String
    public let name: String
    public let installedVersion: String?
    public let latestVersion: String?

    public var id: String { appID }

    public init(appID: String, name: String, installedVersion: String?, latestVersion: String?) {
        self.appID = appID
        self.name = name
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
    }
}

/// Parses `mas outdated`: "497799835  Xcode  (15.0 -> 15.1)".
public enum MasParser {
    public static func outdated(_ output: String) -> [StoreUpdate] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let space = text.firstIndex(of: " "), Int(text[..<space]) != nil else { return nil }
            let appID = String(text[..<space])
            var rest = text[space...].trimmingCharacters(in: .whitespaces)
            var installed: String?
            var latest: String?
            if let open = rest.lastIndex(of: "("), rest.hasSuffix(")") {
                let versions = rest[rest.index(after: open)..<rest.index(before: rest.endIndex)]
                    .components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespaces) }
                installed = versions.first
                latest = versions.count > 1 ? versions[1] : nil
                rest = rest[..<open].trimmingCharacters(in: .whitespaces)
            }
            return StoreUpdate(appID: appID, name: rest, installedVersion: installed, latestVersion: latest)
        }
    }
}
