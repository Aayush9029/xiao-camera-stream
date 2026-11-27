import CoreGraphics
import Foundation

public enum FrameAnnotator {
    public static func annotate(_ image: CGImage, label: String) throws(ImagingError) -> CGImage {
        let context = try BitmapCanvas.make(width: image.width, height: image.height)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)
        LabelRenderer.draw(label, in: context, rect: rect)
        return try BitmapCanvas.image(from: context)
    }

    public static func annotate(jpeg: Data, label: String) throws(ImagingError) -> EncodedImage {
        try JPEGCodec.encode(annotate(JPEGCodec.decode(jpeg), label: label))
    }
}
