import Foundation
import AVFoundation
import CoreImage

/// Public extensions on `CIImage`
public extension CIImage {
    /// Rotate `CIImage` with crop or fill options
    func rotating(by value: Rotate, using fill: RotationFill = .crop, orientation: CGImagePropertyOrientation? = nil) -> CIImage {
        let ciImage = self
        // Warning: -angle is used for correct rotation
        let invertAngle = orientation?.mirrored != true // not mirrored
        let angle = invertAngle ? -value.radians : value.radians
        let size = ciImage.extent.size

        switch fill {
        case .crop: // crop to fill
            let cropSize = size.rotateFilling(angle: Double(angle))
            let cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: (size.height - cropSize.height) / 2)
            let cropRect = CGRect(origin: cropOrigin, size: cropSize)

            return ciImage
                .transformed(by:
                    .init(translationX: size.width / 2, y: size.height / 2)
                    .rotated(by: CGFloat(angle))
                    .translatedBy(x: -size.width / 2, y: -size.height / 2)
                ).cropped(to: cropRect)
        case let .color(alpha: alpha, red: red, green: green, blue: blue):// colored background
            // Rotate
            let rotated = (hasAlpha ? ciImage.premultiplyingAlpha() : ciImage)
                .transformed(by: CGAffineTransform(rotationAngle: CGFloat(angle)))

            // Background color
            let color = CIColor(red: CGFloat(red)/255, green: CGFloat(green)/255, blue: CGFloat(blue)/255, alpha: CGFloat(alpha)/255)
            let background = CIImage(color: color).cropped(to: rotated.extent)
            return rotated.composited(over: background)
        case .blur(kernel: let kernel): // blurred background
            // Rotate original image
            let rotated = ciImage
                .transformed(by: CGAffineTransform(rotationAngle: CGFloat(angle)))

            // Crop rotated to fill
            let cropSize = size.rotateFilling(angle: Double(angle))
            let cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: (size.height - cropSize.height) / 2)
            let fitSize = size.fit(in: cropSize)
            let cropRect = CGRect(origin: cropOrigin, size: fitSize)
            let cropped = ciImage
                .transformed(by:
                    .init(translationX: size.width / 2, y: size.height / 2)
                    .rotated(by: CGFloat(angle))
                    .translatedBy(x: -size.width / 2, y: -size.height / 2)
                ).cropped(to: cropRect)

            // Blur cropped
            let blurred = cropped
                .clampedToExtent()
                .applyingGaussianBlur(sigma: Double(kernel))
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
            return rotated.composited(over: transformedImage)
        }
    }

    /// Crop `CIImage` with translation applying
    func cropping(to rect: CGRect) -> CIImage {
        // Origin translation
        let translation = CGAffineTransform(
            translationX: -rect.origin.x,
            y: -rect.origin.y
        )
        // Crop
        return self
            .cropped(to: rect)
            .transformed(by: translation, highQualityDownsample: true)
    }

    /// Scale `CIImage`
    func resizing(to size: CGSize) -> CIImage {
        let (scale, aspectRatio) = self.extent.size / size
        return self.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: aspectRatio
        ])
    }
}

/// Internal extensions on `CIImage`
internal extension CIImage {
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
                    let fitSize = imageSize.fit(in: size).roundEven()

                    // Scale down
                    let scaleX = fitSize.width / imageSize.width
                    let scaleY = fitSize.height / imageSize.height
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
        var imageProcessor: ImageProcessor?
        for operation in operations.sorted() {
            switch operation {
            case let .rotate(value, fill):
                ciImage = ciImage.rotating(by: value, using: fill, orientation: orientation)
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
            case .imageProcessing(let processor):
                imageProcessor = processor
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

        // Apply custom image processor
        if let imageProcessor = imageProcessor, let image = imageProcessor(ciImage, nil, orientation, index).ciImage {
            ciImage = image
        }

        // Return modified image
        return ciImage
    }

    /// Scale `CIImage` with `CIFilter` provided
    func resizing(to size: CGSize, using filter: CIFilter) -> CIImage? {
        let (scale, aspectRatio) = self.extent.size / size
        filter.setValue(self, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(aspectRatio, forKey: kCIInputAspectRatioKey)
        return filter.outputImage
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
