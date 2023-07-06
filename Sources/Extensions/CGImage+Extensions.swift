import Foundation
import CoreImage

extension CGImage {
    /// Apply multiple image operations on image
    func applyingOperations(_ operations: Set<ImageOperation>) -> CGImage {
        var image = self
        let operations = operations.sorted()

        var ciImage: CIImage?
        var ciContext: CIContext?
        func getCIImage() -> CIImage {
            if ciContext == nil {
                ciContext = CIContext()
            }
            return ciImage ?? CIImage(cgImage: image)
        }
        
        for operation in operations {
            switch operation {
            case .crop(let options):
                if let cropped = image.cropping(to: options.makeCroppingRectangle(in: CGSize(width: image.width, height: image.height))) {
                    image = cropped
                }
            case .rotate(let value):
                ciImage = getCIImage().transformed(by: CGAffineTransform(rotationAngle: value.radians))
            }
        }

        if let ciImage = ciImage, let modified = ciContext!.createCGImage(ciImage, from: ciImage.extent) {
            image = modified
        }

        return image
    }
}
