import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

public enum ImageEnhancer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    public static func enhance(_ image: CGImage) throws(ImagingError) -> CGImage {
        let input = CIImage(cgImage: image)

        let denoise = CIFilter.noiseReduction()
        denoise.inputImage = input
        denoise.noiseLevel = 0.02
        denoise.sharpness = 0.4

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = denoise.outputImage
        sharpen.sharpness = 0.45
        sharpen.radius = 1.5

        let color = CIFilter.colorControls()
        color.inputImage = sharpen.outputImage
        color.saturation = 1.1
        color.contrast = 1.03

        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = color.outputImage
        gamma.power = 0.95

        guard let output = gamma.outputImage?.cropped(to: input.extent),
              let result = context.createCGImage(output, from: input.extent, format: .BGRA8, colorSpace: BitmapCanvas.colorSpace)
        else { throw .encodeFailed }
        return result
    }
}
