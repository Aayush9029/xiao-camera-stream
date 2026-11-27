import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

public final class ClipWriter {
    public static let readinessTimeout: Duration = .seconds(10)

    private let enhance: Bool
    private let bitRate: Int
    private let url = FileManager.default.temporaryDirectory.appending(path: "xiaocam-\(UUID().uuidString).mp4")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var width = 0
    private var height = 0
    private var lastTime = CMTime.negativeInfinity
    public private(set) var frameCount = 0

    public init(enhance: Bool, bitRate: Int = 4_000_000) {
        self.enhance = enhance
        self.bitRate = bitRate
    }

    deinit {
        if writer?.status == .writing { writer?.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }

    public func append(jpeg: Data, time: Double, label: String?) async throws {
        try Task.checkCancellation()
        if writer == nil { try setUp(from: jpeg) }
        guard let writer, let input, let adaptor else { throw ImagingError.videoWriterFailed("the writer did not start") }

        var presentation = CMTime(seconds: max(0, time), preferredTimescale: 600)
        if presentation <= lastTime { presentation = lastTime + CMTime(value: 1, timescale: 600) }
        let image = try FrameProcessor.image(jpeg: jpeg, enhance: enhance, label: label)

        var waited = Duration.zero
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed || writer.status == .cancelled {
                throw ImagingError.videoWriterFailed(writer.error?.localizedDescription ?? "the writer stopped")
            }
            guard waited < Self.readinessTimeout else {
                throw ImagingError.videoWriterFailed("the writer did not take frames for \(Self.readinessTimeout)")
            }
            try await Task.sleep(for: .milliseconds(5))
            waited += .milliseconds(5)
        }
        guard let pool = adaptor.pixelBufferPool else {
            throw ImagingError.videoWriterFailed(writer.error?.localizedDescription ?? "no pixel buffer pool")
        }
        let buffer = try Self.render(image, pool: pool, width: width, height: height)
        guard adaptor.append(buffer, withPresentationTime: presentation) else {
            throw ImagingError.videoWriterFailed(writer.error?.localizedDescription ?? "a frame was rejected")
        }
        lastTime = presentation
        frameCount += 1
    }

    public func finish() async throws -> ClipEncoder.Output {
        guard let writer, let input, frameCount > 0 else { throw ImagingError.noFrames }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ImagingError.videoWriterFailed(writer.error?.localizedDescription ?? "the writer did not finish")
        }
        return ClipEncoder.Output(data: try Data(contentsOf: url), width: width, height: height, frameCount: frameCount)
    }

    private func setUp(from jpeg: Data) throws {
        guard let size = JPEGCodec.size(of: jpeg) else { throw ImagingError.decodeFailed }
        width = size.width & ~1
        height = size.height & ~1
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw ImagingError.videoWriterFailed("the H.264 input is not supported") }
        writer.add(input)
        guard writer.startWriting() else {
            throw ImagingError.videoWriterFailed(writer.error?.localizedDescription ?? "the writer did not start")
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }

    private static func render(_ image: CGImage, pool: CVPixelBufferPool, width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw ImagingError.videoWriterFailed("no pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: BitmapCanvas.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw ImagingError.videoWriterFailed("no drawing context") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
