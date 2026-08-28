import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

struct ImagePreprocessor: @unchecked Sendable {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func normalizedImage(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.colorControls()
        filter.inputImage = input; filter.saturation = 0; filter.contrast = 1.12; filter.brightness = 0
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    func correctedImage(from image: CGImage, corners: [CGPoint]) -> CGImage? {
        guard corners.count == 4 else { return image }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = CIVector(cgPoint: corners[0]); filter.topRight = CIVector(cgPoint: corners[1])
        filter.bottomRight = CIVector(cgPoint: corners[2]); filter.bottomLeft = CIVector(cgPoint: corners[3])
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}