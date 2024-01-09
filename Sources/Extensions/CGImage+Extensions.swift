import Foundation
import AVFoundation
import CoreImage
import Accelerate.vImage

/// Extensions on `CGImage`
internal extension CGImage {
    /// Alpha channel presence
    var hasAlpha: Bool {
        // let alphaInfo = CGImageAlphaInfo(rawValue: self.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue) ??  self.alphaInfo
        return alphaInfo != .none && alphaInfo != .noneSkipFirst && alphaInfo != .noneSkipLast
    }

    /// Flag for premultiplied alpha
    var premultipliedAlpha: Bool {
        return self.alphaInfo == .premultipliedFirst || self.alphaInfo == .premultipliedLast
    }

    /// High Dynamic Range
    /*var isHDR: Bool {
        // Warning: ISO HDR images return true in CGColorSpaceUsesITUR_2100TF(colorSpace)

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
    }*/

    /// `CGImage` size property
    var size: CGSize {
        return CGSize(width: self.width, height: self.height)
    }

    /// Crop `CGImage`
    func crop(using options: Crop, orientation: CGImagePropertyOrientation? = nil) -> CGImage? {
        let size = self.size.oriented(orientation)

        let rect = options
            .makeCroppingRectangle(in: size)
            .intersection(CGRect(origin: .zero, size: size))
            .oriented(orientation, size: self.size)

        if size.width > rect.size.width || size.height > rect.size.height {
            if let cropped = self.cropping(to: rect) {
                return cropped
            }
        }

        return nil
    }

    /// Resize `CGImage`
    func resize(to size: CGSize) -> CGImage? {
        let size = self.size.fit(in: size)

        guard let context = CGContext.make(self, width: Int(size.width), height: Int(size.height)) else {
            return nil
        }

        context.draw(self, in: CGRect(origin: .zero, size: size))

        return context.makeImage()
    }

    /// Convert color space of `CGImage`
    func convertColorSpace(to colorSpace: CGColorSpace) -> CGImage? {
        guard let context = CGContext.make(self) else {
            return nil
        }

        context.draw(self, in: CGRect(origin: .zero, size: self.size))

        return context.makeImage()
    }

    /// Mirror `CGImage`
    func mirror() -> CGImage? {
        return self.reflect(horizontally: true, vertically: false)
    }

    /// Flip `CGImage`
    func flip() -> CGImage? {
        return self.reflect(horizontally: false, vertically: true)
    }

    /// Reflect (Mirror, Flip) `CGImage`
    private func reflect(horizontally: Bool, vertically: Bool) -> CGImage? {
        guard let context = CGContext.make(self) else {
            return nil
        }

        if horizontally {
            context.translateBy(x: CGFloat(self.width), y: 0)
            context.scaleBy(x: -1.0, y: 1.0)
        }

        if vertically {
            context.translateBy(x: 0, y: CGFloat(self.height))
            context.scaleBy(x: 1.0, y: -1.0)
        }

        context.draw(self, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))

        return context.makeImage()
    }

    /// Blend transparent `CGImage` with solid color background
    func replaceAlphaChannel(color: CGColor) -> CGImage? {
        let imageRect = CGRect(x: 0, y: 0, width: self.width, height: self.height)

        guard let context = CGContext.make(self) else {
            return nil
        }

        // Fill background with the specified color
        context.setFillColor(color)
        context.fill(imageRect)

        // Draw an image
        context.draw(self, in: imageRect)

        return context.makeImage()
    }

    /// Rotate `CGImage` with edges extended using `CGColor`
    func rotateColor(angle: CGFloat, color: CGColor? = nil, orientation: CGImagePropertyOrientation? = nil) -> CGImage? {
        let imageSize = CGSize(width: self.width, height: self.height)

        let rect = CGRect(origin: .zero, size: imageSize)
        let enclosingRectangle = rect.rotateExtended(angle: angle)

        guard let context = CGContext.make(self, width: Int(enclosingRectangle.width), height: Int(enclosingRectangle.height)) else {
            return nil
        }

        if let color = color {
            // Fill the background with the specified color
            context.setFillColor(color)
            context.fill(
                CGRect(
                    x: enclosingRectangle.origin.x,
                    y: enclosingRectangle.origin.y,
                    width: enclosingRectangle.width - enclosingRectangle.origin.x,
                    height: enclosingRectangle.height - enclosingRectangle.origin.y
                )
            )
        }

        context.translateBy(x: enclosingRectangle.width / 2, y: enclosingRectangle.height / 2)
        context.rotate(by: angle)
        context.draw(self, in: CGRect(x: -imageSize.width / 2, y: -imageSize.height / 2, width: imageSize.width, height: imageSize.height))

        return context.makeImage()
    }

    /// Rotate `CGImage`
    func rotateFill(angle: CGFloat, orientation: CGImagePropertyOrientation? = nil) -> CGImage? {
        let imageSize = CGSize(width: self.width, height: self.height)
        let cropSize = imageSize.rotateFilling(angle: Double(angle))

        guard let context = CGContext.make(self, width: Int(cropSize.width), height: Int(cropSize.height)) else {
            return nil
        }

        context.translateBy(x: cropSize.width / 2, y: cropSize.height / 2)
        context.rotate(by: CGFloat(angle))
        context.translateBy(x: -imageSize.width / 2, y: -imageSize.height / 2)
        context.draw(self, in: CGRect(origin: .zero, size: imageSize))

        return context.makeImage()
    }

    /** Apply multiple image operations and settings on `CGImage`
        - Resize using CGImage
        + Crop using CGImage
        + Flip & Mirror using CGImage
        + Rotate using CGImage
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
    ) -> CGImage {
        var cgImage = self

        switch size {
        case .fit(let size):
            // Resize (without upscaling)
            let imageSize = cgImage.size

            // Orient new size to have the same directions as current image
            let size = size.oriented(orientation)

            if shouldResize, imageSize.width > size.width || imageSize.height > size.height {
                // Calculate size to fit in
                let rect = AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: CGPoint.zero, size: size))
                if let resized = cgImage.resize(to: rect.size) {
                    cgImage = resized
                }
            }
        case .crop(_, let options):
            // Crop
            if let cropped = cgImage.crop(using: options, orientation: orientation) {
                cgImage = cropped
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
                // let size = cgImage.size

                switch fill {
                case .crop: // crop to fill
                    if let rotated = cgImage.rotateFill(angle: CGFloat(angle), orientation: orientation) {
                        cgImage = rotated
                    }
                case let .color(alpha: alpha, red: red, green: green, blue: blue):// colored background
                    let color = CGColor(red: CGFloat(red)/255, green: CGFloat(green)/255, blue: CGFloat(blue)/255, alpha: CGFloat(alpha)/255)
                    if let rotated = cgImage.rotateColor(angle: CGFloat(angle), color: color, orientation: orientation) {
                        cgImage = rotated
                    }
                case .blur:
                    // Warning: transparent background used for `CGImage` processing
                    let color = CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
                    if let rotated = cgImage.rotateColor(angle: CGFloat(angle), color: color, orientation: orientation) {
                        cgImage = rotated
                    }
                }
            case .flip:
                if let orientation = orientation, orientation.rawValue > UInt32(4) { // .leftMirrored, .right, rightMirrored, .left
                    // Reflect horizontally
                    if let mirrored = cgImage.mirror() {
                        cgImage = mirrored
                    }
                } else {
                    // Reflect vertically
                    if let flipped = cgImage.flip() {
                        cgImage = flipped
                    }
                }
            case .mirror:
                if let orientation = orientation, orientation.rawValue > UInt32(4) { // .leftMirrored, .right, rightMirrored, .left
                    // Reflect vertically
                    if let flipped = cgImage.flip() {
                        cgImage = flipped
                    }
                } else {
                    // Reflect horizontally
                    if let mirrored = cgImage.mirror() {
                        cgImage = mirrored
                    }
                }
            /*case .imageProcessing(let function):
                cgImage = function(cgImage, index)*/
            }
        }

        // Alpha channel
        if !preserveAlpha && hasAlpha {
            // Blend with solid color
            let color = backgroundColor ?? CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) // black
            if let blended = cgImage.replaceAlphaChannel(color: color) {
                cgImage = blended
            }
        }

        // Return modified image
        return cgImage
    }

    /// Oriented image size
    func size(orientation: CGImagePropertyOrientation?) -> CGSize {
        return self.size.oriented(orientation)
    }

    /// Check image conformance with built-in Core Graphics
    /*func hasCGContextSupportedPixelFormat(colorSpace: CGColorSpace? = nil, alphaInfo: CGImageAlphaInfo? = nil) -> Bool {
        guard let colorSpace = colorSpace ?? self.colorSpace else {
            return false
        }

        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        let iOS = true
        #else
        let iOS = false
        #endif

        #if os(OSX)
        let macOS = true
        #else
        let macOS = false
        #endif

        // Full Table - https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html#//apple_ref/doc/uid/TP30001066-CH203-BCIBHHBB
        switch (colorSpace.model, self.bitsPerPixel, self.bitsPerComponent, alphaInfo ?? self.alphaInfo, self.bitmapInfo) {
        case (.unknown, 8, 8, .alphaOnly, _):
            return macOS || iOS
        case (.monochrome, 8, 8, .none, _):
            return macOS || iOS
        case (.monochrome, 8, 8, .alphaOnly, _):
            return macOS || iOS
        case (.monochrome, 16, 16, .none, _):
            return macOS
        case (.monochrome, 32, 32, .none, let bitmapInfo) where bitmapInfo.contains(.floatComponents):
            return macOS
        case (.rgb, 16, 5, .noneSkipFirst, _):
            return macOS || iOS
        case (.rgb, 32, 8, .noneSkipFirst, _):
            return macOS || iOS
        case (.rgb, 32, 8, .noneSkipLast, _):
            return macOS || iOS
        case (.rgb, 32, 8, .premultipliedFirst, _):
            return macOS || iOS
        case (.rgb, 32, 8, .premultipliedLast, _):
            return macOS || iOS
        /*case (.rgb, 32, 10, .none, _) where bitmapInfo.contains(CGImagePixelFormatInfo.RGB101010.rawValue):
            return macOS || iOS*/
        /*case (.rgb, 32, 10, .none, let bitmapInfo) where bitmapInfo.rawValue == 270336: // kCGImageAlphaNone | kCGImageByteOrder32Little | kCGImagePixelFormatRGBCIF10
             return macOS || iOS*/
        case (.rgb, 64, 16, .premultipliedLast, _):
            return macOS
        case (.rgb, 64, 16, .noneSkipLast, _):
            return macOS
        case (.rgb, 128, 32, .noneSkipLast, let bitmapInfo) where bitmapInfo.contains(.floatComponents):
            return macOS
        case (.rgb, 128, 32, .premultipliedLast, let bitmapInfo) where bitmapInfo.contains(.floatComponents):
            return macOS
        case (.cmyk, 32, 8, .none, _):
            return macOS
        case (.cmyk, 64, 16, .none, _):
            return macOS
        case (.cmyk, 128, 32, .none, let bitmapInfo) where bitmapInfo.contains(.floatComponents):
            return macOS
        default:
            return false
        }
    }*/
}
