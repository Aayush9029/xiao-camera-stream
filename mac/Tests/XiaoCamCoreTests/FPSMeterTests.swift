import Testing
import XiaoCamCore

struct FPSMeterTests {
    @Test func measuresTheRateInTheWindow() {
        var meter = FPSMeter(window: 2)
        for frame in 0...20 { meter.record(Double(frame) * 0.1) }
        #expect(abs(meter.framesPerSecond - 10) < 0.001)
    }

    @Test func forgetsFramesOutsideTheWindow() {
        var meter = FPSMeter(window: 1)
        for frame in 0...10 { meter.record(Double(frame) * 0.02) }
        for frame in 0...10 { meter.record(10 + Double(frame) * 0.1) }
        #expect(abs(meter.framesPerSecond - 10) < 0.001)
    }

    @Test func needsTwoFrames() {
        var meter = FPSMeter()
        #expect(meter.framesPerSecond == 0)
        meter.record(1)
        #expect(meter.framesPerSecond == 0)
    }
}
