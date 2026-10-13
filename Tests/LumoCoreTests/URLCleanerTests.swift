import Foundation
import Testing
@testable import LumoCore

@Suite("URL cleaner")
struct URLCleanerTests {
    @Test("tracking parameters are removed and the rest is kept in order")
    func removesTrackers() {
        let dirty = "https://shop.example.com/item?id=42&utm_source=news&utm_medium=email&color=red&fbclid=abc#reviews"
        #expect(URLCleaner.clean(dirty) == "https://shop.example.com/item?id=42&color=red#reviews")
    }

    @Test("a URL with only trackers loses its question mark")
    func dropsEmptyQuery() {
        #expect(URLCleaner.clean("https://youtu.be/xyz?si=AbCdEf") == "https://youtu.be/xyz")
        #expect(URLCleaner.clean("https://open.spotify.com/track/1?si=q1&utm_campaign=x") == "https://open.spotify.com/track/1")
    }

    @Test("clean links and non-links are returned unchanged")
    func untouched() {
        #expect(URLCleaner.clean("https://example.com/search?q=lumo") == nil)
        #expect(URLCleaner.clean("just some words") == nil)
        #expect(URLCleaner.clean("ftp://example.com/?utm_source=x") == nil)
    }

    @Test("a link surrounded by spaces is cleaned")
    func trims() {
        #expect(URLCleaner.clean("  https://example.com/?gclid=1&a=b \n") == "https://example.com/?a=b")
    }
}
