import Foundation
import AVFoundation
import CoreImage

/// Extensions on `CIImage`
public extension CIImage {
    /// Crop `CIImage`
    func crop(using options: Crop, orientation: CGImagePropertyOrientation? = nil) -> CIImage? {
        let size = self.extent.size.oriented(orientation)

        let rect = options
            .makeCroppingRectangle(in: size)
            .intersection(CGRect(origin: .zero, size: size))
            .oriented(orientation, size: self.extent.size)

        // Convert from topLeft origin to bottomLeft used by `CIImage`
        let ciRect = CGRect(
            x: rect.origin.x,
            y: self.extent.height - rect.size.height - rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )

        if size.width > rect.size.width || size.height > rect.size.height {
            return self.cropped(to: ciRect)
                .transformed(by: CGAffineTransform(translationX: -ciRect.origin.x, y: -ciRect.origin.y))
        }

        return nil
    }

    /** Apply multiple image operations and settings on `CIImage`
        - Resize using CIImage
        + Crop using CImage
        + Flip & Mirror using CImage
        + Rotate using CImage
        + Call imageProcessing(image) at the end
    */
    func edit(
        operations: Set<ImageOperation>,
        size: ImageSize,
        shouldResize: Bool,
        hasAlpha: Bool,
        preserveAlpha: Bool,
        backgroundColor: CGColor?,
        orientation: CGImagePropertyOrientation? = nil,
        index: Int = 0
    ) -> CIImage {
        var ciImage = hasAlpha ? self.unpremultiplyingAlpha() : self

        // Resize and Crop
        switch size {
        case .fit(let size):
            // Resize (without upscaling)
            if shouldResize {
                let imageSize = ciImage.extent.size

                // Orient new size to have the same directions as current image
                let size = size.oriented(orientation)

                if imageSize.width > size.width || imageSize.height > size.height {
                    // Calculate size to fit in
                    let rect = AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: CGPoint.zero, size: size))

                    // Scale down
                    let scaleX = rect.size.width / imageSize.width
                    let scaleY = rect.size.height / imageSize.height
                    ciImage = ciImage
                        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                }
            }
        case .crop(_, let options):
            // Crop
            if let cropped = ciImage.crop(using: options, orientation: orientation) {
                ciImage = cropped
            }
        default:
            break
        }

        // Apply operations in sorted order
        for operation in operations.sorted() {
            switch operation {
            case let .rotate(value, fill):
                // Warning: -angle is used for correct rotation
                let invertAngle = orientation == nil || orientation == .up || orientation == .down || orientation == .left || orientation == .right // not mirrored
                let angle = invertAngle ? -value.radians : value.radians
                let size = ciImage.extent.size

                switch fill {
                case .crop: // crop to fill
                    let cropSize = size.rotateFilling(angle: Double(angle))
                    let cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: (size.height - cropSize.height) / 2)
                    let cropRect = CGRect(origin: cropOrigin, size: cropSize)

                    ciImage = ciImage
                        .transformed(by:
                            .init(translationX: size.width / 2, y: size.height / 2)
                            .rotated(by: CGFloat(angle))
                            .translatedBy(x: -size.width / 2, y: -size.height / 2)
                        ).cropped(to: cropRect)
                case let .color(alpha: alpha, red: red, green: green, blue: blue):// colored background
                    // Rotate
                    ciImage = (hasAlpha ? ciImage.premultiplyingAlpha() : ciImage)
                        .transformed(by: CGAffineTransform(rotationAngle: CGFloat(angle)))

                    // Background color
                    let color = CIColor(red: CGFloat(red)/255, green: CGFloat(green)/255, blue: CGFloat(blue)/255, alpha: CGFloat(alpha)/255)
                    let background = CIImage(color: color).cropped(to: ciImage.extent)
                    ciImage = ciImage.composited(over: background)
                case .blur(kernel: let kernel): // blurred background
                    // Rotate original image
                    let rotated = ciImage
                        .transformed(by: CGAffineTransform(rotationAngle: CGFloat(angle)))

                    // Crop rotated to fill
                    let cropSize = size.rotateFilling(angle: Double(angle))
                    let cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: (size.height - cropSize.height) / 2)
                    let fitRect = AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: CGPoint.zero, size: cropSize))
                    let cropRect = CGRect(origin: cropOrigin, size: fitRect.size)
                    let cropped = ciImage
                        .transformed(by:
                            .init(translationX: size.width / 2, y: size.height / 2)
                            .rotated(by: CGFloat(angle))
                            .translatedBy(x: -size.width / 2, y: -size.height / 2)
                        ).cropped(to: cropRect)

                    // Blur cropped
                    let blurred = cropped.applyingGaussianBlur(sigma: Double(kernel))
                        .cropped(to: cropped.extent)

                    // Scale and translate blurred into rotated extent
                    let scaleX = rotated.extent.size.width / blurred.extent.size.width
                    let scaleY = rotated.extent.size.height / blurred.extent.size.height
                    let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
                    let translationTransform = CGAffineTransform(
                        translationX: rotated.extent.origin.x - blurred.extent.origin.x * scaleX,
                        y: rotated.extent.origin.y - blurred.extent.origin.y * scaleY
                    )
                    let transformedImage = blurred.transformed(by: scaleTransform.concatenating(translationTransform))

                    // Composite rotated image over transformed blurred background
                    let composited = rotated.composited(over: transformedImage)

                    ciImage = composited
                }
            case .flip:
                if let orientation = orientation, orientation.rawValue > UInt32(4) { // .leftMirrored, .right, rightMirrored, .left
                    // Reflect horizontally
                    ciImage = ciImage
                        .transformed(by: CGAffineTransform(scaleX: -1.0, y: 1.0))
                } else {
                    // Reflect vertically
                    ciImage = ciImage
                        .transformed(by: CGAffineTransform(scaleX: 1.0, y: -1.0))
                }
            case .mirror:
                if let orientation = orientation, orientation.rawValue > UInt32(4) { // .leftMirrored, .right, rightMirrored, .left
                    // Reflect vertically
                    ciImage = ciImage
                        .transformed(by: CGAffineTransform(scaleX: 1.0, y: -1.0))
                } else {
                    // Reflect horizontally
                    ciImage = ciImage
                        .transformed(by: CGAffineTransform(scaleX: -1.0, y: 1.0))
                }
            /*case .imageProcessing(let function):
                ciImage = function(ciImage, index)*/
            }
        }

        // Fix extent
        if ciImage.extent.minX != 0 || ciImage.extent.minY != 0 {
            ciImage = ciImage.transformed(by: .init(translationX: -ciImage.extent.minX, y: -ciImage.extent.minY))
        }

        // Alpha channel
        if !preserveAlpha && hasAlpha {
            // Stack over solid color
            let color = CIColor(cgColor: backgroundColor ?? CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)) // black
            let background = CIImage(color: color).cropped(to: ciImage.extent)
            ciImage = ciImage.premultiplyingAlpha().composited(over: background)
        }

        // Return modified image
        return ciImage
    }

    /// Bit depth
    var depth: Int {
        return self.properties[kCGImagePropertyDepth as String] as? Int ?? 8
    }

    /// Alpha presence
    var hasAlpha: Bool {
        return self.properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false
    }

    /// Detect `CIFormat` of `CIImage`
    var pixelFormat: CIFormat {
        let properties = self.properties

        let pixelFormat: CIFormat
        if let rawValue = properties[kCGImagePropertyPixelFormat as String] as? Int32 {
            pixelFormat = CIFormat(rawValue: rawValue)
        } else {
            // Parse properties
            let bitDepth = self.depth
            let hasAlpha = self.hasAlpha
            let isFloatPoint = properties[kCGImagePropertyIsFloat as String] as? Bool ?? false
            // let containsAuxiliaryData = properties[kCGImagePropertyAuxiliaryData as String] != nil

            // Construct format
            if let format = CIFormat.for(bitsPerPixel: nil, bitsPerComponent: bitDepth, hasAlpha: hasAlpha, isFloatPoint: isFloatPoint) {
                pixelFormat = format
            } else {
                pixelFormat = bitDepth > 8 ? .RGBA16 : .RGBA8
            }
        }

        return pixelFormat
    }
}
