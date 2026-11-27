import Clocks
import CoreGraphics
import Foundation
import Testing
import XiaoCamKit

@MainActor
func eventually(
    timeout: Duration = .seconds(5),
    _ condition: @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("The condition did not become true in \(timeout).", sourceLocation: sourceLocation)
}

@MainActor
@discardableResult
func advance(
    _ clock: TestClock<Duration>,
    until condition: @MainActor () -> Bool,
    step: Duration = .milliseconds(100),
    limit: Duration = .seconds(120),
    sourceLocation: SourceLocation = #_sourceLocation
) async -> Duration {
    var advanced = Duration.zero
    while !condition() {
        guard advanced < limit else {
            Issue.record("The condition did not become true after \(limit) of test clock time.", sourceLocation: sourceLocation)
            return advanced
        }
        await clock.advance(by: step)
        advanced += step
        try? await Task.sleep(for: .milliseconds(2))
    }
    return advanced
}

enum Fixtures {
    static func jpeg(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try JPEGCodec.encode(try #require(context.makeImage())).data
    }

    static func frame(jpeg: Data, sequence: UInt32, micros: UInt64, receivedAt: Date) -> Frame {
        Frame(
            header: FrameHeader(
                sequence: sequence, deviceMicroseconds: micros, width: 320, height: 240,
                modeValue: 0, quality: 14, temperatureTenths: 500, payloadLength: UInt32(jpeg.count)
            ),
            jpeg: jpeg,
            receivedAt: receivedAt
        )
    }

    static func status(mode: CameraMode, brightness: Int = 0) -> DeviceStatus {
        var status = DeviceStatus.preview
        status.mode = mode.rawValue
        status.brightness = brightness
        return status
    }

    static func source(
        host: String = "10.0.0.5",
        frames: @escaping @Sendable () -> AsyncStream<Frame> = { AsyncStream { $0.finish() } },
        defaults: CaptureDefaults = CaptureDefaults(enhance: false, timestamp: true),
        status: DeviceStatus? = .preview
    ) -> CaptureSource {
        CaptureSource(
            liveHost: { host },
            frames: { frames() },
            defaults: { defaults },
            status: { status },
            statusChanged: { _ in }
        )
    }
}
