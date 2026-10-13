import Foundation

/// Compares dotted version strings numerically ("2.10" > "2.9"); trailing text like " (412)" is ignored.
public enum VersionCompare {
    public static func components(_ version: String) -> [Int] {
        let prefix = version.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber || $0 == "." }
        return prefix.split(separator: ".").compactMap { Int($0) }
    }

    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let left = components(candidate), right = components(installed)
        guard !left.isEmpty else { return false }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

/// One release from a Sparkle appcast feed.
public struct AppcastItem: Equatable, Sendable {
    public let shortVersion: String
    public let build: String
    public let downloadURL: URL?

    public init(shortVersion: String, build: String, downloadURL: URL?) {
        self.shortVersion = shortVersion
        self.build = build
        self.downloadURL = downloadURL
    }

    /// Sparkle compares the build number (CFBundleVersion); the display version is the fallback.
    public func isNewer(thanShort installedShort: String, build installedBuild: String) -> Bool {
        if !VersionCompare.components(build).isEmpty, !VersionCompare.components(installedBuild).isEmpty {
            return VersionCompare.isNewer(build, than: installedBuild)
        }
        return VersionCompare.isNewer(shortVersion.isEmpty ? build : shortVersion, than: installedShort)
    }
}

/// Reads Sparkle appcasts (RSS with the sparkle namespace) and returns the newest stable release.
public enum AppcastParser {
    public static func latest(_ data: Data) -> AppcastItem? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !delegate.items.isEmpty else { return nil }
        return delegate.items.max { lhs, rhs in
            rhs.isNewer(thanShort: lhs.shortVersion, build: lhs.build)
        }
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [AppcastItem] = []
        private var inItem = false
        private var text = ""
        private var short = ""
        private var build = ""
        private var url: URL?
        private var isBeta = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "item":
                inItem = true
                short = ""
                build = ""
                url = nil
                isBeta = false
            case "enclosure" where inItem:
                if let value = attributes["sparkle:shortVersionString"] { short = value }
                if let value = attributes["sparkle:version"] { build = value }
                url = attributes["url"].flatMap(URL.init(string:))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard inItem else { return }
            switch name {
            case "sparkle:shortVersionString": short = value
            case "sparkle:version": build = value
            case "sparkle:channel": isBeta = !value.isEmpty
            case "item":
                inItem = false
                if !isBeta, !(short.isEmpty && build.isEmpty) { items.append(AppcastItem(shortVersion: short, build: build, downloadURL: url)) }
            default: break
            }
        }
    }
}
