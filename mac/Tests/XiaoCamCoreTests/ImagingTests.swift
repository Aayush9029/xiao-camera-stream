import Foundation
import Testing
import XiaoCamCore

struct ImagingTests {
    @Test func gridFitsTheLongEdgeLimit() throws {
        let jpeg = try TestImage.jpeg(width: 1024, height: 768)
        let cells = try (0..<7).map { index in
            GridComposer.Cell(image: try JPEGCodec.decode(jpeg), label: "#\(index + 1)  14:03:2\(index)")
        }
        let grid = try GridComposer.compose(cells)
        #expect(max(grid.width, grid.height) <= GridComposer.defaultMaxLongEdge)
        #expect(grid.width == 3 * ((2000 - 8) / 3) + 8)
        let cellWidth = (grid.width - 8) / 3
        let cellHeight = (grid.height - 8) / 3
        #expect(abs(Double(cellWidth) / Double(cellHeight) - 4.0 / 3.0) < 0.01)
        #expect(JPEGCodec.size(of: grid.data)?.width == grid.width)
    }

    @Test func gridDoesNotUpscaleSmallFrames() throws {
        let image = try JPEGCodec.decode(try TestImage.jpeg(width: 480, height: 320))
        let grid = try GridComposer.compose([.init(image: image, label: nil), .init(image: image, label: nil)])
        #expect(grid.width == 480 * 2 + 4)
        #expect(grid.height == 320)
    }

    @Test func gridHonorsColumns() throws {
        let image = try JPEGCodec.decode(try TestImage.jpeg(width: 400, height: 300))
        let cells = Array(repeating: GridComposer.Cell(image: image, label: "x"), count: 4)
        let grid = try GridComposer.compose(cells, columns: 1)
        #expect(grid.width == 400)
        #expect(grid.height == 4 * 300 + 3 * 4)
    }

    @Test func annotationKeepsTheSizeAndChangesThePixels() throws {
        let jpeg = try TestImage.jpeg(width: 640, height: 480)
        let labeled = try FrameAnnotator.annotate(jpeg: jpeg, label: FrameLabel(date: .now).text())
        #expect(labeled.width == 640)
        #expect(labeled.height == 480)
        #expect(labeled.data != jpeg)
    }

    @Test func processingWithoutChangesKeepsTheOriginalBytes() throws {
        let jpeg = try TestImage.jpeg(width: 320, height: 240)
        let result = try FrameProcessor.process(jpeg: jpeg, enhance: false, label: nil)
        #expect(result.data == jpeg)
        #expect(result.width == 320)
    }

    @Test func enhancementKeepsTheSize() throws {
        let image = try JPEGCodec.decode(try TestImage.jpeg(width: 320, height: 240))
        let enhanced = try ImageEnhancer.enhance(image)
        #expect(enhanced.width == 320)
        #expect(enhanced.height == 240)
    }

    @Test func clipEncoderWritesAnMP4() async throws {
        let jpeg = try TestImage.jpeg(width: 321, height: 241)
        let frames = (0..<5).map { ClipEncoder.Input(jpeg: jpeg, time: Double($0) * 0.1, label: "+\($0)") }
        let clip = try await ClipEncoder.encode(frames, enhance: false)
        #expect(clip.width == 320)
        #expect(clip.height == 240)
        #expect(clip.frameCount == 5)
        #expect(String(decoding: clip.data[4..<8], as: UTF8.self) == "ftyp")
    }
}
