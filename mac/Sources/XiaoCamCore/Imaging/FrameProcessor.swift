import CoreGraphics
import Foundation

public enum FrameProcessor {
    public static func process(jpeg: Data, enhance: Bool, label: String?) throws(ImagingError) -> EncodedImage {
        guard enhance || label != nil else {
            guard let size = JPEGCodec.size(of: jpeg) else { throw .decodeFailed }
            return EncodedImage(data: jpeg, width: size.width, height: size.height)
        }
        return try JPEGCodec.encode(image(jpeg: jpeg, enhance: enhance, label: label))
    }

    public static func image(jpeg: Data, enhance: Bool, label: String?) throws(ImagingError) -> CGImage {
        var image = try JPEGCodec.decode(jpeg)
        if enhance { image = try ImageEnhancer.enhance(image) }
        if let label { image = try FrameAnnotator.annotate(image, label: label) }
        return image
    }
}
