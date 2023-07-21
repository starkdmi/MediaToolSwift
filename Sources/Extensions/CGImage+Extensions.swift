import Foundation
import CoreImage

public extension CGImage {
    /// Alpha channel presence
    /// Warning: Premultiplied alpha is skipped here
    var hasAlpha: Bool {
        return alphaInfo == CGImageAlphaInfo.first || alphaInfo == CGImageAlphaInfo.last
    }

    /// HDR data presence
    var isHDR: Bool {
        var hdrColorSpace = true
        if let colorSpace = self.colorSpace {
            if #available(macOS 11, iOS 14, tvOS 14, *) {
                if CGColorSpaceUsesExtendedRange(colorSpace) || CGColorSpaceUsesITUR_2100TF(colorSpace) {
                    hdrColorSpace = true
                } else {
                    hdrColorSpace = false
                }
            } else if CGColorSpaceUsesExtendedRange(colorSpace) {
                hdrColorSpace = true
            } else {
                hdrColorSpace = false
            }
        }

        return bitsPerComponent > 8 && hdrColorSpace
    }

    /// Apply multiple image operations on image
    func applyingOperations(_ operations: Set<ImageOperation>, resize: CGSize? = nil) -> CGImage {
        let image = self
        let size = CGSize(width: self.width, height: self.height)

        // Convert to CIImage
        let context = CIContext()
        var ciImage = CIImage(cgImage: image, options: [.applyOrientationProperty: true])

        // Resize
        if let resize = resize {
            let scaleX = resize.width / size.width
            let scaleY = resize.height / size.height
            let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            ciImage = ciImage.transformed(by: scaleTransform)
        }

        // Apply operations in sorted order
        for operation in operations.sorted() {
            switch operation {
            case .crop(let options):
                let rect = options.makeCroppingRectangle(in: size)
                ciImage = ciImage.cropped(to: rect)
                    .transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
            case .rotate(let value):
                ciImage = ciImage
                    .transformed(by: CGAffineTransform(rotationAngle: value.radians))
            case .imageProcessing(let function):
                ciImage = function(ciImage)
            }
        }

        // Create a CGImage
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }

        return cgImage
    }
}
