import Foundation
import Testing
@testable import LumoCore

@Suite("Input extras")
struct InputExtrasTests {
    @Test("a chattering press right after release is dropped together with its release")
    func debounce() {
        var filter = PressDebouncer(threshold: 0.05)
        let results = [filter.dropDown(key: 1, at: 1.0), filter.dropUp(key: 1, at: 1.10), filter.dropDown(key: 1, at: 1.13),
                       filter.dropUp(key: 1, at: 1.15), filter.dropDown(key: 1, at: 1.40), filter.dropDown(key: 2, at: 1.41)]
        #expect(results == [false, false, true, true, false, false])
    }

    @Test("button drags become directions only past the threshold")
    func gestures() {
        #expect(MouseGesture.direction(dx: 120, dy: 10, threshold: 80) == .right)
        #expect(MouseGesture.direction(dx: -90, dy: 30, threshold: 80) == .left)
        #expect(MouseGesture.direction(dx: 5, dy: -100, threshold: 80) == .up)
        #expect(MouseGesture.direction(dx: 10, dy: 95, threshold: 80) == .down)
        #expect(MouseGesture.direction(dx: 40, dy: 40, threshold: 80) == nil)
    }

    @Test("hidutil mappings keep other remaps when Lumo adds or removes its own")
    func keyMappings() {
        let other = HIDKeyMapping(source: 0x7_0000_0035, destination: 0x7_0000_0064)
        let caps = HIDKeyMapping.capsLockToF18
        let added = HIDKeyMapping.adding(caps, to: [other])
        #expect(added == [other, caps])
        #expect(HIDKeyMapping.adding(caps, to: added) == added)
        #expect(HIDKeyMapping.removing(caps, from: added) == [other])
        #expect(HIDKeyMapping.json([caps]) == #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":30064771129,"HIDKeyboardModifierMappingDst":30064771181}]}"#)
    }

    @Test("hidutil output parses into mappings")
    func parsesHidutil() {
        let output = """
        (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        #expect(HIDKeyMapping.parse(output) == [HIDKeyMapping.capsLockToF18])
        #expect(HIDKeyMapping.parse("(null)") == [])
    }

    @Test("shortcuts render with modifier symbols in Apple's order")
    func shortcutDisplay() {
        let binding = ShortcutBinding(keyCode: 123, modifiers: [.command, .control, .option])
        #expect(binding.display == "⌃⌥⌘←")
        #expect(ShortcutBinding(keyCode: 0, modifiers: [.shift, .command]).display == "⇧⌘A")
        #expect(ShortcutBinding(keyCode: 49, modifiers: [.option]).display == "⌥Space")
    }
}
