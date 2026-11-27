import Foundation
import Testing
import XiaoCamCore

struct FrameLabelTests {
    let utc = TimeZone(identifier: "UTC")!
    let date = Date(timeIntervalSince1970: 1_795_000_000)

    @Test func formatsTheDateAndTime() {
        #expect(FrameLabel(date: date).text(timeZone: utc) == "2026-11-18 11:06:40")
    }

    @Test func addsTheIndexAndTheElapsedTime() {
        #expect(FrameLabel(date: date, index: 3, elapsed: 10, style: .time).text(timeZone: utc) == "#3  11:06:40  +10s")
        #expect(FrameLabel(date: date, elapsed: 2.46, style: .time).text(timeZone: utc) == "11:06:40  +2.5s")
    }
}
