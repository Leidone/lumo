import Foundation
import Testing
@testable import LumoCore

@Suite("Island")
struct IslandTests {
    @Test("synced lyrics parse with multiple stamps, an offset and sorting")
    func parsesLyrics() {
        let lyrics = LyricsParser.parse("""
        [ar:Someone]
        [offset:500]
        [00:12.50]Second line
        [00:05.00][00:30.00]Chorus
        not a lyric line
        [01:02]Last
        """)
        #expect(lyrics.map(\.text) == ["Chorus", "Second line", "Chorus", "Last"])
        #expect(lyrics.map(\.time) == [4.5, 12.0, 29.5, 61.5])
    }

    @Test("current lyric is the last line that already started")
    func currentLyric() {
        let lyrics = [LyricLine(time: 1, text: "a"), LyricLine(time: 5, text: "b"), LyricLine(time: 9, text: "c")]
        #expect(LyricsParser.index(at: 0.5, in: lyrics) == nil)
        #expect(LyricsParser.index(at: 5, in: lyrics) == 1)
        #expect(LyricsParser.index(at: 100, in: lyrics) == 2)
    }

    @Test("elapsed time advances with the playback rate and stays within the track")
    func elapsedTime() {
        let start = Date(timeIntervalSince1970: 1000)
        let playing = NowPlayingState(title: "T", artist: "A", album: "", duration: 200, elapsed: 50, timestamp: start, rate: 1)
        #expect(playing.elapsed(at: start.addingTimeInterval(10)) == 60)
        #expect(playing.elapsed(at: start.addingTimeInterval(1000)) == 200)
        let paused = NowPlayingState(title: "T", artist: "A", album: "", duration: 200, elapsed: 50, timestamp: start, rate: 0)
        #expect(paused.elapsed(at: start.addingTimeInterval(10)) == 50)
        #expect(!paused.isPlaying)
        #expect(playing.progress(at: start.addingTimeInterval(50)) == 0.5)
    }

    @Test("the most urgent activity wins the collapsed island")
    func activityPriority() {
        #expect(IslandActivity.primary(of: [.awake, .media, .timer]) == .timer)
        #expect(IslandActivity.primary(of: [.media, .recording]) == .recording)
        #expect(IslandActivity.primary(of: []) == nil)
    }

    @Test("partial downloads are recognised and mapped to their final name")
    func partialDownloads() {
        #expect(DownloadNames.finalName(of: "movie.mp4.crdownload") == "movie.mp4")
        #expect(DownloadNames.finalName(of: "Report.pdf.download") == "Report.pdf")
        #expect(DownloadNames.finalName(of: "song.mp3.part") == "song.mp3")
        #expect(DownloadNames.finalName(of: "notes.txt") == nil)
        #expect(DownloadNames.finalName(of: ".crdownload") == nil)
    }

    @Test("notification payloads decode title, subtitle and body")
    func notificationPayload() {
        let payload: [String: Any] = ["app": "com.apple.mail", "req": ["titl": "Anna", "subt": "Lunch", "body": "See you at 1?"]]
        let decoded = NotificationPayload(plist: payload)
        #expect(decoded == NotificationPayload(title: "Anna", subtitle: "Lunch", body: "See you at 1?"))
        #expect(NotificationPayload(plist: ["req": [:] as [String: Any]]) == nil)
    }
}
