import Foundation
import Testing
@testable import LumoCore

@Suite("Appcast")
struct AppcastTests {
    private let feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>Version 2.3</title>
          <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/App-2.3.zip" sparkle:version="230" sparkle:shortVersionString="2.3" length="1" type="application/octet-stream"/>
        </item>
        <item>
          <title>Version 2.10 beta</title>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://example.com/App-2.10.zip" sparkle:version="300" sparkle:shortVersionString="2.10"/>
        </item>
        <item>
          <title>Version 2.4</title>
          <sparkle:version>240</sparkle:version>
          <sparkle:shortVersionString>2.4</sparkle:shortVersionString>
          <enclosure url="https://example.com/App-2.4.zip"/>
        </item>
      </channel>
    </rss>
    """

    @Test("the newest stable release wins, whether versions are attributes or elements")
    func newestStable() throws {
        let latest = try #require(AppcastParser.latest(Data(feed.utf8)))
        #expect(latest.shortVersion == "2.4")
        #expect(latest.build == "240")
        #expect(latest.downloadURL?.absoluteString == "https://example.com/App-2.4.zip")
    }

    @Test("versions compare numerically, part by part")
    func versionOrder() {
        #expect(VersionCompare.isNewer("2.10", than: "2.9"))
        #expect(VersionCompare.isNewer("1.2.1", than: "1.2"))
        #expect(!VersionCompare.isNewer("1.2.0", than: "1.2"))
        #expect(!VersionCompare.isNewer("3.0 (412)", than: "3.0"))
        #expect(VersionCompare.isNewer("31.0.1", than: "31.0"))
    }

    @Test("an update is reported only when the feed is ahead of the installed app")
    func updateNeeded() throws {
        let latest = try #require(AppcastParser.latest(Data(feed.utf8)))
        #expect(latest.isNewer(thanShort: "2.3", build: "230"))
        #expect(!latest.isNewer(thanShort: "2.4", build: "240"))
        #expect(latest.isNewer(thanShort: "2.4", build: "239"))
    }
}
