import Foundation
import UIKit

enum ImageRenderer {
    static func jpegData(from image: CGImage, quality: CGFloat = 0.88) -> Data? { UIImage(cgImage: image).jpegData(compressionQuality: quality) }
}