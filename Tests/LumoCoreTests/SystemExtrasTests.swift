import Foundation
import Testing
@testable import LumoCore

@Suite("System extras")
struct SystemExtrasTests {
    @Test("energy impact is read from the last top sample, keeping spaces in names")
    func parsesPowerTop() {
        let output = """
        Processes: 500 total
        PID    COMMAND          POWER
        10     WindowServer     1.0

        Processes: 501 total
        Load Avg: 1.2
        PID    COMMAND          POWER
        812    Google Chrome He 24.5
        77     WindowServer     8.1
        5      kernel_task      0.0
        """
        let entries = PowerTopParser.parse(output)
        #expect(entries == [EnergyEntry(pid: 812, name: "Google Chrome He", impact: 24.5),
                            EnergyEntry(pid: 77, name: "WindowServer", impact: 8.1)])
    }

    @Test("networkQuality JSON becomes megabits per second")
    func parsesSpeedTest() throws {
        let json = #"{"dl_throughput": 245000000, "ul_throughput": 31500000, "responsiveness": 1200.5, "base_rtt": 18.2}"#
        let result = try #require(SpeedTestResult.parse(Data(json.utf8)))
        #expect(result.downloadMbps == 245)
        #expect(result.uploadMbps == 31.5)
        #expect(result.responsiveness == 1200.5)
        #expect(SpeedTestResult.parse(Data("{}".utf8)) == nil)
    }

    @Test("fan curve interpolates between points and clamps to the fan's range")
    func fanCurve() {
        let curve = FanCurve(points: [FanCurve.Point(celsius: 50, fraction: 0), FanCurve.Point(celsius: 90, fraction: 1)])
        #expect(curve.rpm(at: 40, min: 1200, max: 6000) == 1200)
        #expect(curve.rpm(at: 70, min: 1200, max: 6000) == 3600)
        #expect(curve.rpm(at: 120, min: 1200, max: 6000) == 6000)
    }

    @Test("sampling slows down in the background, more on battery and in Low Power Mode")
    func sampleCadence() {
        #expect(SampleCadence.interval(foreground: true, liveReadouts: false, onBattery: true, lowPowerMode: true) == 2)
        #expect(SampleCadence.interval(foreground: false, liveReadouts: true, onBattery: false, lowPowerMode: false) == 2)
        #expect(SampleCadence.interval(foreground: false, liveReadouts: true, onBattery: true, lowPowerMode: false) == 3)
        #expect(SampleCadence.interval(foreground: false, liveReadouts: false, onBattery: false, lowPowerMode: false) == 3)
        #expect(SampleCadence.interval(foreground: false, liveReadouts: false, onBattery: true, lowPowerMode: false) == 6)
        #expect(SampleCadence.interval(foreground: false, liveReadouts: false, onBattery: false, lowPowerMode: true) == 10)
    }
}
