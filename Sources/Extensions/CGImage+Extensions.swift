import Foundation
import AVFoundation
import CoreImage
import Accelerate.vImage

/// Public extensions on `CGImage`
public extension CGImage {
    /// Rotate `CGImage` with crop or fill options
    func rotating(by value: Rotate, using fill: RotationFill = .crop, orientation: CGImagePropertyOrientation? = nil) -> CGImage? {
        // Warning: -angle is used for correct rotation
        let invertAngle = orientation?.mirrored != true // not mirrored
        let angle = invertAngle ? -value.radians : value.radians

        switch fill {
        case .crop: // crop to fill
            if let rotated = self.rotateFill(angle: CGFloat(angle), orientation: orientation) {
                return rotated
            }
        case let .color(alpha: alpha, red: red, green: green, blue: blue): // colored background
            let color = CGColor(red: CGFloat(red)/255, green: CGFloat(green)/255, blue: CGFloat(blue)/255, alpha: CGFloat(alpha)/255)
            if let rotated = self.rotateColor(angle: CGFloat(angle), color: color, orientation: orientation) {
                return rotated
            }
        case .blur:
            // Warning: average or transparent background used for `CGImage` processing
            let color = self.averageColor(algorithm: .simple) ?? CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
            if let rotated = self.rotateColor(angle: CGFloat(angle), color: color, orientation: orientation) {
                return rotated
            }
        }
        return nil
    }

    /// Resize `CGImage` to fit, with aspect ration preserving
    func resizing(to size: CGSize) -> CGImage? {
        let size = self.size.fit(in: size)

        guard let context = CGContext.make(self, width: Int(size.width), height: Int(size.height)) else {
            return nil
        }

        context.draw(self, in: CGRect(origin: .zero, size: size))

        return context.makeImage()
    }

    /// Scale `CGImage` to fill
    func scaling(to size: CGSize) -> CGImage? {
        guard let context = CGContext.make(self, width: Int(size.width), height: Int(size.height)) else {
            return nil
        }

        context.draw(self, in: CGRect(origin: .zero, size: size))

        return context.makeImage()
    }

    /// Mirror `CGImage`
    func mirroring() -> CGImage? {
        return self.reflect(horizontally: true, vertically: false)
    }

    /// Flip `CGImage`
    func flipping() -> CGImage? {
        return self.reflect(horizontally: false, vertically: true)
    }

    /// Blend transparent `CGImage` with solid color background
    func replacingAlphaChannel(with color: CGColor) -> CGImage? {
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
}

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

    /// Convert color space of `CGImage`
    func convertColorSpace(to colorSpace: CGColorSpace) -> CGImage? {
        guard let context = CGContext.make(self, colorSpace: colorSpace) else {
            return nil
        }

        context.draw(self, in: CGRect(origin: .zero, size: self.size))

        return context.makeImage()
    }

    /// Reflect (Mirror, Flip) `CGImage`
    func reflect(horizontally: Bool, vertically: Bool) -> CGImage? {
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
                let fitSize = imageSize.fit(in: size)
                if let resized = cgImage.resizing(to: fitSize) {
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
        var imageProcessor: ImageProcessor?
        for operation in operations.sorted() {
            switch operation {
            case let .rotate(value, fill):
                if let rotated = cgImage.rotating(by: value, using: fill, orientation: orientation) {
                    cgImage = rotated
                }
            case .flip:
                if let orientation = orientation, orientation.rawValue > UInt32(4) { // .leftMirrored, .right, rightMirrored, .left
                    // Reflect horizontally
                    if let mirrored = cgImage.mirroring() {
                        cgImage = mirrored
                    }
                } else {
                    // Reflect vertically
                    if let flipped = cgImage.flipping() {
                        cgImage = flipped
                    }
                }
            case .mirror:
                if let orientation = orientation, orientation.rawValue > UInt32(4) { // .leftMirrored, .right, rightMirrored, .left
                    // Reflect vertically
                    if let flipped = cgImage.flipping() {
                        cgImage = flipped
                    }
                } else {
                    // Reflect horizontally
                    if let mirrored = cgImage.mirroring() {
                        cgImage = mirrored
                    }
                }
            case .imageProcessing(let processor):
                imageProcessor = processor
            }
        }

        // Alpha channel
        if !preserveAlpha && hasAlpha {
            // Blend with solid color
            let color = backgroundColor ?? CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) // black
            if let blended = cgImage.replacingAlphaChannel(with: color) {
                cgImage = blended
            }
        }

        // Apply custom image processor
        if let imageProcessor = imageProcessor, let image = imageProcessor(nil, cgImage, orientation, index).cgImage {
            cgImage = image
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

/// Efficient average color calculation in Core Graphics
/// https://christianselig.com/2021/04/efficient-average-color/
internal extension CGImage {
    /// There are two main ways to get the color from an image, just a simple "sum up an average" or by squaring their sums. 
    /// Each has their advantages, but the 'simple' option *seems* better for average color of entire image and closely mirrors CoreImage.
    /// Details: https://sighack.com/post/averaging-rgb-colors-the-right-way
    enum AverageColorAlgorithm {
        case simple
        case squareRoot
    }

    /// Find average color
    func averageColor(algorithm: AverageColorAlgorithm = .simple) -> CGColor? {
        // First, resize the image. We do this for two reasons:
        // 1) less pixels to deal with means faster calculation and a resized image still has the "gist" of the colors
        // 2) the image we're dealing with may come in any of a variety of color formats (CMYK, ARGB, RGBA, etc.) which complicates things, and redrawing it normalizes that into a base color format we can deal with.
        // 40x40 is a good size to resize to still preserve quite a bit of detail but not have too many pixels to deal with. Aspect ratio is irrelevant for just finding average color.
        let size = CGSize(width: 40, height: 40)

        let width = Int(size.width)
        let height = Int(size.height)
        let totalPixels = width * height

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // ARGB format
        let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        // 8 bits for each color channel, we're doing ARGB so 32 bits (4 bytes) total, and thus if the image is n pixels wide, and has 4 bytes per pixel, the total bytes per row is 4n. 
        // That gives us 2^8 = 256 color variations for each RGB channel or 256 * 256 * 256 = ~16.7M color options in total.
        // That seems like a lot, but lots of HDR movies are in 10 bit, which is (2^10)^3 = 1 billion color options!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        // Draw our resized image
        context.draw(self, in: CGRect(origin: .zero, size: size))

        guard let pixelBuffer = context.data else { return nil }

        // Bind the pixel buffer's memory location to a pointer we can use/access
        let pointer = pixelBuffer.bindMemory(to: UInt32.self, capacity: width * height)

        // Keep track of total colors (note: we don't care about alpha and will always assume alpha of 1, AKA opaque)
        var totalRed = 0
        var totalBlue = 0
        var totalGreen = 0

        // Column of pixels in image
        for hIndex in 0 ..< width {
            // Row of pixels in image
            for vIndex in 0 ..< height {
                // To get the pixel location just think of the image as a grid of pixels, but stored as one long row rather than columns and rows,
                // so for instance to map the pixel from the grid in the 15th row and 3 columns in to our "long row", we'd offset ourselves 15 times the width in pixels of the image, and then offset by the amount of columns
                let pixel = pointer[(vIndex * width) + hIndex]

                let red = red(for: pixel)
                let green = green(for: pixel)
                let blue = blue(for: pixel)

                switch algorithm {
                case .simple:
                    totalRed += Int(red)
                    totalBlue += Int(blue)
                    totalGreen += Int(green)
                case .squareRoot:
                    totalRed += Int(pow(CGFloat(red), CGFloat(2)))
                    totalGreen += Int(pow(CGFloat(green), CGFloat(2)))
                    totalBlue += Int(pow(CGFloat(blue), CGFloat(2)))
                }
            }
        }

        let averageRed: CGFloat
        let averageGreen: CGFloat
        let averageBlue: CGFloat

        switch algorithm {
        case .simple:
            averageRed = CGFloat(totalRed) / CGFloat(totalPixels)
            averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels)
            averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels)
        case .squareRoot:
            averageRed = sqrt(CGFloat(totalRed) / CGFloat(totalPixels))
            averageGreen = sqrt(CGFloat(totalGreen) / CGFloat(totalPixels))
            averageBlue = sqrt(CGFloat(totalBlue) / CGFloat(totalPixels))
        }

        // Convert from [0 ... 255] format to the [0 ... 1.0] format CGColor wants
        return CGColor(red: averageRed / 255.0, green: averageGreen / 255.0, blue: averageBlue / 255.0, alpha: 1.0)
    }

    private func red(for pixelData: UInt32) -> UInt8 {
        // For a quick primer on bit shifting and what we're doing here, in our ARGB color format image each pixel's colors are stored as a 32 bit integer, with 8 bits per color chanel (A, R, G, and B).
        //
        // So a pure red color would look like this in bits in our format, all red, no blue, no green, and 'who cares' alpha:
        //
        // 11111111 11111111 00000000 00000000
        //  ^alpha   ^red     ^blue    ^green
        //
        // We want to grab only the red channel in this case, we don't care about alpha, blue, or green.
        // So we want to shift the red bits all the way to the right in order to have them in the right position (we're storing colors as 8 bits, so we need the right most 8 bits to be the red).
        // Red is 16 points from the right, so we shift it by 16 (for the other colors, we shift less, as shown below).
        //
        // Just shifting would give us:
        //
        // 00000000 00000000 11111111 11111111
        //  ^alpha   ^red     ^blue    ^green
        //
        // The alpha got pulled over which we don't want or care about, so we need to get rid of it. 
        // We can do that with the bitwise AND operator (&) which compares bits and the only keeps a 1 if both bits being compared are 1s.
        // So we're basically using it as a gate to only let the bits we want through. 255 (below) is the value we're using as in binary it's 11111111 (or in 32 bit, it's 00000000 00000000 00000000 11111111) and the result of the bitwise operation is then:
        //
        // 00000000 00000000 11111111 11111111
        // 00000000 00000000 00000000 11111111
        // -----------------------------------
        // 00000000 00000000 00000000 11111111
        //
        // So as you can see, it only keeps the last 8 bits and 0s out the rest, which is what we want! 
        // Woohoo! (It isn't too exciting in this scenario, but if it wasn't pure red and was instead a red of value "11010010" for instance, it would also mirror that down)
        return UInt8((pixelData >> 16) & 255)
    }

    private func green(for pixelData: UInt32) -> UInt8 {
        return UInt8((pixelData >> 8) & 255)
    }

    private func blue(for pixelData: UInt32) -> UInt8 {
        return UInt8((pixelData >> 0) & 255)
    }
}
