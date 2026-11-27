import Testing
import XiaoCamCore

struct CapturePlanTests {
    @Test func includesBothEnds() {
        #expect(CapturePlan(every: 5, for: 30).offsets == [0, 5, 10, 15, 20, 25, 30])
        #expect(CapturePlan(every: 2, for: 8).offsets == [0, 2, 4, 6, 8])
    }

    @Test func dropsAPartialLastStep() {
        #expect(CapturePlan(every: 3, for: 10).offsets == [0, 3, 6, 9])
    }

    @Test func zeroDurationTakesOnePhoto() {
        #expect(CapturePlan(every: 5, for: 0).offsets == [0])
    }

    @Test func clampsTheIntervalToTheMinimum() {
        let plan = CapturePlan(every: 0.1, for: 2)
        #expect(plan.interval == CapturePlan.minimumInterval)
        #expect(plan.offsets == [0, 0.5, 1, 1.5, 2])
    }

    @Test func spreadsALongRunOverTheFrameLimit() {
        let plan = CapturePlan(every: 1, for: 60)
        #expect(plan.frameCount == CapturePlan.maximumFrames)
        #expect(plan.offsets.first == 0)
        #expect(abs((plan.offsets.last ?? 0) - 60) < 0.001)
    }

    @Test func clampsTheDuration() {
        let plan = CapturePlan(every: 600, for: 99_999)
        #expect(plan.duration == CapturePlan.maximumDuration)
        #expect(plan.offsets.count == 7)
    }

    @Test func ignoresValuesThatAreNotFinite() {
        let plan = CapturePlan(every: .nan, for: .infinity)
        #expect(plan.offsets == [0])
    }
}
