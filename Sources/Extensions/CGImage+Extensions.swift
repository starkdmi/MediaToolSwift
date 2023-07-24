import Foundation
import AVFoundation
import CoreImage

public extension CGImage {
    /// Alpha channel presence
    /// Warning: Premultiplied alpha is skipped here
    var hasAlpha: Bool {
        return alphaInfo == CGImageAlphaInfo.first || alphaInfo == CGImageAlphaInfo.last
    }

    /// High Dynamic Range
    var isHDR: Bool {
        return bitsPerComponent > 8

        /*var hdrColorSpace = true
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

        return bitsPerComponent > 8 && hdrColorSpace*/
    }

    /// Apply multiple image operations and settings on `CGImage`
    func edit(settings: ImageSettings, index: Int = 0) -> CGImage {
        var size = CGSize(width: self.width, height: self.height)

        let shouldResize: Bool
        if let resize = settings.size, size.width > resize.width || size.height > resize.height {
            shouldResize = true
        } else {
            shouldResize = false
        }

        let shouldReplaceAlpha = !settings.preserveAlphaChannel && self.hasAlpha

        // Skip if nothing is changed
        guard !settings.edit.isEmpty || shouldResize || shouldReplaceAlpha else {
            return self
        }

        // Convert to CIImage
        let context = CIContext()
        var ciImage = CIImage(cgImage: self, options: [.applyOrientationProperty: true])

        // Resize (without upscaling)
        if shouldResize, var resize = settings.size {
            // Calculate size to fit in
            let rect = AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: CGPoint.zero, size: resize))
            resize = rect.size

            // Scale down
            let scaleX = resize.width / size.width
            let scaleY = resize.height / size.height
            ciImage = ciImage
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            size = resize
        }

        // Apply operations in sorted order
        for operation in settings.edit.sorted() {
            switch operation {
            case .crop(let options):
                let rect = options.makeCroppingRectangle(in: size)
                ciImage = ciImage.cropped(to: rect)
                    .transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
            case .rotate(let value):
                ciImage = ciImage
                    .transformed(by: CGAffineTransform(rotationAngle: value.radians))
            case .flip:
                ciImage = ciImage
                    .transformed(by: CGAffineTransform(scaleX: 1.0, y: -1.0))
            case .mirror:
                ciImage = ciImage
                    .transformed(by: CGAffineTransform(scaleX: -1.0, y: 1.0))
            case .imageProcessing(let function):
                ciImage = function(ciImage, index)
            }
        }

        // Alpha channel
        if shouldReplaceAlpha {
            // Stack over solid color
            let color = CIColor(cgColor: settings.backgroundColor ?? CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)) // black
            let background = CIImage(color: color).cropped(to: ciImage.extent)
            ciImage = ciImage.composited(over: background)
        }

        // Create a CGImage
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return self
        }

        return cgImage
    }
}
