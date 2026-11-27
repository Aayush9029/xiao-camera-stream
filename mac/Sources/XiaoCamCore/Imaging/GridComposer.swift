import CoreGraphics
import Foundation

public enum GridComposer {
    public struct Cell: Sendable {
        public var image: CGImage
        public var label: String?

        public init(image: CGImage, label: String?) {
            self.image = image
            self.label = label
        }
    }

    public static let defaultMaxLongEdge = 2000
    static let gap = 4

    public static func compose(
        _ cells: [Cell],
        columns: Int? = nil,
        maxLongEdge: Int = defaultMaxLongEdge
    ) throws(ImagingError) -> EncodedImage {
        guard let first = cells.first else { throw .noFrames }
        let layout = GridLayout(count: cells.count, columns: columns)
        let size = canvasSize(layout: layout, cellWidth: first.image.width, cellHeight: first.image.height, maxLongEdge: maxLongEdge)
        let context = try BitmapCanvas.make(width: size.width, height: size.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        for (index, cell) in cells.enumerated() {
            let (row, column) = layout.position(of: index)
            let rect = CGRect(
                x: column * (size.cellWidth + gap),
                y: size.height - (row + 1) * size.cellHeight - row * gap,
                width: size.cellWidth,
                height: size.cellHeight
            )
            context.draw(cell.image, in: aspectFit(cell.image, in: rect))
            if let label = cell.label {
                LabelRenderer.draw(label, in: context, rect: rect)
            }
        }
        return try JPEGCodec.encode(BitmapCanvas.image(from: context), quality: 0.8)
    }

    public static func canvasSize(
        layout: GridLayout,
        cellWidth: Int,
        cellHeight: Int,
        maxLongEdge: Int = defaultMaxLongEdge
    ) -> (width: Int, height: Int, cellWidth: Int, cellHeight: Int) {
        let fullWidth = layout.columns * cellWidth + (layout.columns - 1) * gap
        let fullHeight = layout.rows * cellHeight + (layout.rows - 1) * gap
        let scale = min(1, Double(maxLongEdge) / Double(max(fullWidth, fullHeight)))
        let scaledCellWidth = max(1, Int((Double(cellWidth) * scale).rounded(.down)))
        let scaledCellHeight = max(1, Int((Double(cellHeight) * scale).rounded(.down)))
        return (
            layout.columns * scaledCellWidth + (layout.columns - 1) * gap,
            layout.rows * scaledCellHeight + (layout.rows - 1) * gap,
            scaledCellWidth,
            scaledCellHeight
        )
    }

    private static func aspectFit(_ image: CGImage, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
}
