import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

struct ImagePreprocessor: Sendable {
    func normalizedImage(from image: CGImage) -> CGImage? {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let input = CIImage(cgImage: image)
        let filter = CIFilter.colorControls()
        filter.inputImage = input; filter.saturation = 0; filter.contrast = 1.12; filter.brightness = 0
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    func correctedImage(from image: CGImage, corners: [CGPoint]) -> CGImage? {
        guard corners.count == 4 else { return image }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = corners[0]
        filter.topRight = corners[1]
        filter.bottomRight = corners[2]
        filter.bottomLeft = corners[3]
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}