import CoreGraphics

enum BitmapCanvas {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func make(width: Int, height: Int) throws(ImagingError) -> CGContext {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw .encodeFailed }
        context.interpolationQuality = .high
        return context
    }

    static func image(from context: CGContext) throws(ImagingError) -> CGImage {
        guard let image = context.makeImage() else { throw .encodeFailed }
        return image
    }
}
