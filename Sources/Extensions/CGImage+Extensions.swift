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
        return bitsPerPixel >= 32 && bitsPerComponent >= 8
    }

    /// Detect Image Pixel Format based on bits information
    func getPixelFormat() -> CIFormat {
        switch (bitsPerPixel, bitsPerComponent) {
        case (32, 32), (32, 64), (32, 128):
            return .RGBAf
        case (16, 32), (16, 64), (32, 32):
            return .RGBAh
        case (32, 16), (16, 16):
            return .RGBA16
        case (32, 8):
            return .RGBA8
        case (16, 8):
            return .RG8
        case (8, 8):
            return .R8
        default:
            return .BGRA8
        }
    }

    /// Color space
    func getColorSpace(extendedColorSpace: Bool) -> CGColorSpace {
        var colorSpace = self.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        // Replace color space with the HDR supported one when required
        if #available(macOS 11, iOS 14, tvOS 14, *) {
            if CGColorSpaceUsesExtendedRange(colorSpace) || CGColorSpaceUsesITUR_2100TF(colorSpace) {
                colorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)! // CGColorSpaceCreateExtended(colorSpace)!
            }
        } else if CGColorSpaceUsesExtendedRange(colorSpace) {
            colorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)! // CGColorSpaceCreateExtended(colorSpace)!
        }

        return colorSpace
    }

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
            return ciImage ?? CIImage(cgImage: image, options: [.applyOrientationProperty: true])
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

        if let ciImage = ciImage {
            let pixelFormat = image.getPixelFormat()
            let colorSpace = image.getColorSpace(extendedColorSpace: !image.hasAlpha && image.isHDR)
            if let modified = ciContext!.createCGImage(ciImage, from: ciImage.extent, format: pixelFormat, colorSpace: colorSpace) {
                image = modified
            }
        }

        return image
    }
}
