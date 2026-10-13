import CoreGraphics
import Foundation
import Testing
@testable import LumoCore

@Suite("Capture extras")
struct CaptureExtrasTests {
    @Test("scrolling frames are joined where the old bottom matches the new top")
    func stitchOverlap() {
        let previous: [UInt64] = Array(1...10)
        let next: [UInt64] = Array(6...15)
        #expect(ScrollStitcher.overlap(previous: previous, next: next, minimum: 3) == 5)
        #expect(ScrollStitcher.overlap(previous: previous, next: Array(100...110), minimum: 3) == nil)
        #expect(ScrollStitcher.overlap(previous: previous, next: previous, minimum: 3) == 10)
    }

    @Test("trim and cuts leave the kept ranges in order, and composition time maps back to the source")
    func editRanges() {
        let kept = EditRanges.kept(duration: 60, trimStart: 5, trimEnd: 50, cuts: [EditRanges.Range(start: 20, end: 30)])
        #expect(kept == [EditRanges.Range(start: 5, end: 20), EditRanges.Range(start: 30, end: 50)])
        #expect(EditRanges.sourceTime(17, in: kept) == 32)
        #expect(EditRanges.sourceTime(2, in: kept) == 7)
        #expect(EditRanges.total(kept) == 35)
    }

    @Test("auto zoom eases in at a click and back out")
    func autoZoom() {
        let clicks = [AutoZoom.Click(time: 10, point: CGPoint(x: 0.2, y: 0.3))]
        #expect(AutoZoom.state(at: 5, clicks: clicks).scale == 1)
        let peak = AutoZoom.state(at: 11, clicks: clicks)
        #expect(peak.scale == AutoZoom.maxScale)
        #expect(peak.center == CGPoint(x: 0.2, y: 0.3))
        let easing = AutoZoom.state(at: 9.85, clicks: clicks).scale
        #expect(easing > 1 && easing < AutoZoom.maxScale)
        #expect(AutoZoom.state(at: 20, clicks: clicks).scale == 1)
    }
}
