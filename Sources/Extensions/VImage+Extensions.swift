import Foundation
import AVFoundation
import Accelerate.vImage
import CoreGraphics
import CoreImage

/// vImage editing implementation
internal extension vImage {
    /** Apply multiple image operations and settings on `CGImage`
        - Resize using vImage or CGImage
        + Crop using vImage
        + Flip & Mirror using vImage
        + Rotate using vImage
        + Call imageProcessing(image) at the end
    */
    static func edit(
        image: CGImage,
        operations: Set<ImageOperation>,
        size: ImageSize,
        shouldResize: Bool,
        // forceCGImageResize: Bool = false,
        hasAlpha: Bool,
        preserveAlpha: Bool,
        backgroundColor: CGColor?,
        orientation: CGImagePropertyOrientation? = nil,
        index: Int = 0,
        format: vImage_CGImageFormat? = nil,
        converterIn: vImageConverter? = nil,
        converterOut: vImageConverter? = nil,
        tempBuffer: inout TemporaryBuffer?
    ) throws -> CGImage? {
        let replaceAlpha = hasAlpha && !preserveAlpha
        let cropOrResize = size != .original
        guard !operations.isEmpty || cropOrResize || replaceAlpha else { return nil }

        var image = image
        let imageSize = image.size(orientation: orientation) // image.size

        // When only cropping or resizing is requested
        if cropOrResize && operations.isEmpty && !replaceAlpha {
            if case .crop(_, let crop) = size {
                // Crop using `CGImage` to prevent conversion to `vImage` just for cropping
                if let cropped = image.crop(using: crop, orientation: orientation) {
                    return cropped
                }
            } else {
                // Return if resizing is skipped
                guard !shouldResize else { return nil }
            }
        }

        // Resize (without upscaling) using `CGImage`
        // Applied when `forceCGImageResize` is enabled or only resize operation was passed to this image processing block
        /*if shouldResize, forceCGImageResize || (operations.isEmpty && !replaceAlpha), case .fit(let size) = settings.size {
            // Orient new size to have the same directions as current image
            let size = size.oriented(orientation)

            let imageSize = image.size
            if shouldResize, imageSize.width > size.width || imageSize.height > size.height {
                // Calculate size to fit in
                let fitSize = imageSize.fit(in: size)

                if let resized = image.resize(to: fitSize) {
                    image = resized
                }
            }

            // Finish image processing
            if settings.edit.isEmpty && !replaceAlpha {
                return image
            }
        }*/

        let format = format ?? vImage_CGImageFormat(image)

        // Convert CGImage to vImage_Buffer
        var imageBuffer = try vImage_Buffer(cgImage: image, format: format, flags: [.noFlags])
        defer { imageBuffer.free() }

        // Convert
        if let converter = converterIn ?? vImageConverter.create(from: format) {
            vImageConvert_AnyToAny(converter, &imageBuffer, &imageBuffer, nil, vImage_Flags(kvImageNoFlags))
        }

        let premultipliedAlpha = image.premultipliedAlpha
        if premultipliedAlpha {
            // Unpremultiply the image data
            // https://developer.apple.com/documentation/accelerate/building_a_basic_image-processing_workflow#2941461
            try imageBuffer.unpremultiply()
        }

        switch size {
        case .fit(let size):
            // Resize (without upscaling)
            if shouldResize { // && !forceCGImageResize
                // Orient new size to have the same directions as current image
                let size = size.oriented(orientation)
                let imageSize = image.size

                if imageSize.width > size.width || imageSize.height > size.height {
                    // Calculate size to fit in
                    let fitSize = imageSize.fit(in: size)

                    let scaledBuffer = try imageBuffer.scale(
                        width: Int(fitSize.width),
                        height: Int(fitSize.height),
                        bitsPerPixel: UInt32(image.bitsPerPixel)
                        // temporaryBuffer: &scaleTempBuffer
                    )
                    imageBuffer.free()
                    imageBuffer = scaledBuffer
                }
            }
        case .crop(_, let options):
            // Crop
            let rect = options
                .makeCroppingRectangle(in: imageSize)
                .intersection(CGRect(origin: .zero, size: imageSize))
                .oriented(orientation, size: image.size)

            if imageSize.width > rect.size.width || imageSize.height > rect.size.height,
               let croppedBuffer = try imageBuffer.crop(rect, bitsPerPixel: image.bitsPerPixel) {
                imageBuffer.free()
                imageBuffer = croppedBuffer
            }
        default:
            break
        }

        // Replace alpha channel with solid color
        if !preserveAlpha && hasAlpha {
            var color: [UInt8] = [255, 0, 0, 0] // black
            if let backgroundColor = backgroundColor {
                if let rgba = backgroundColor.components?.map({ UInt8($0 * CGFloat(255)) }), rgba.count >= 3 {
                    color = [rgba.count > 3 ? rgba[3] : 255, rgba[0], rgba[1], rgba[2]]
                }
            }
            // Blend
            let blended = try imageBuffer.replaceAlphaChannel(color: color, bitsPerPixel: UInt32(image.bitsPerPixel))
            imageBuffer.free()
            imageBuffer = blended
        }

        // Apply operations in sorted order
        let operations = operations.sorted()
        for operation in operations {
            switch operation {
            case .flip:
                let flipped: vImage_Buffer
                if let orientation = orientation, orientation.rawValue > UInt32(4) { // .leftMirrored, .right, rightMirrored, .left
                    // Reflect horizontally
                    flipped = try imageBuffer.mirror(bitsPerPixel: UInt32(image.bitsPerPixel))
                } else {
                    // Reflect vertically
                    flipped = try imageBuffer.flip(bitsPerPixel: UInt32(image.bitsPerPixel))
                }
                imageBuffer.free()
                imageBuffer = flipped
            case .mirror:
                let mirrored: vImage_Buffer
                if let orientation = orientation, orientation.rawValue > UInt32(4) { // .leftMirrored, .right, rightMirrored, .left
                    // Reflect vertically
                    mirrored = try imageBuffer.flip(bitsPerPixel: UInt32(image.bitsPerPixel))
                } else {
                    // Reflect horizontally
                    mirrored = try imageBuffer.mirror(bitsPerPixel: UInt32(image.bitsPerPixel))
                }
                imageBuffer.free()
                imageBuffer = mirrored
            case let .rotate(rotation, fill):
                // Rotation
                // Reduce the angle by 360 multiplies
                let angle = rotation.radians.truncatingRemainder(dividingBy: .pi*2)
                if angle != .zero {
                    // Apply blur effect only to solid images
                    /*if hasAlpha, case .blur(_) = fill {
                        throw CompressionError.blurNotAllowed
                   }*/

                    // Warning: -angle is used for correct rotation
                    let invertAngle = orientation == nil || orientation == .up || orientation == .down || orientation == .left || orientation == .right // not mirrored
                    let angle = invertAngle ? Float(-angle) : Float(angle)

                    let rotated = try imageBuffer.rotate(
                        angle: angle,
                        fill: fill,
                        bitsPerPixel: UInt32(image.bitsPerPixel),
                        temporaryBuffer: &tempBuffer
                    )
                    imageBuffer.free()
                    imageBuffer = rotated

                    // Adjust the settings if alpha channel was added
                    /*if !premultipliedAlpha, case .color(let alpha, _, _, _) = fill, alpha != 255 {
                        hasAlpha = true
                        premultipliedAlpha = true
                    }*/
                }
            /*case .imageProcessing(let function):
                // Custom image processing callback, executed after all the other image operations
                break
            */
            }
        }

        if premultipliedAlpha {
            // Premultiply image data back
            try imageBuffer.premultiply()
        }

        if let converter = converterOut ?? vImageConverter.create(to: format) {
            vImageConvert_AnyToAny(converter, &imageBuffer, &imageBuffer, nil, vImage_Flags(kvImageNoFlags))
        }

        // Convert vImage_Buffer to CGImage
        image = try imageBuffer.createCGImage(format: format, flags: [.highQualityResampling])
        // buffer.createCGImage is iOS 13+, but flags uses vImage.Options which is iOS 14+
        /*var error = vImage_Error()
        let cgImagePointer = vImageCreateCGImageFromBuffer(&imageBuffer, &format, nil, nil, vImage_Flags(kvImageHighQualityResampling), &error)
        if let cgImage = cgImagePointer?.takeRetainedValue() {
            image = cgImage
        }
        try error.check()*/

        return image
    }
}

/// vImage related extensions
internal extension vImage_Buffer {
    /// Unpremultiply alpha channel
    mutating func unpremultiply() throws {
        let error = vImageUnpremultiplyData_ARGB8888(&self, &self, vImage_Flags(kvImageNoFlags))
        try error.check()
    }

    /// Premultiply alpha channel
    mutating func premultiply() throws {
        let error = vImagePremultiplyData_ARGB8888(&self, &self, vImage_Flags(kvImageNoFlags))
        try error.check()
    }

    /// Scale pixel buffer
    mutating func scale(
        width: Int,
        height: Int,
        bitsPerPixel: UInt32 = 32
        // temporaryBuffer: inout TemporaryBuffer?
    ) throws -> vImage_Buffer {
        // Create image buffer using smaller rect
        var destinationBuffer = try vImage_Buffer(width: width, height: height, bitsPerPixel: bitsPerPixel)

        // Scale
        let error = vImageScale_ARGB8888(&self, &destinationBuffer, nil, vImage_Flags(kvImageHighQualityResampling)) // &temporaryBuffer
        try error.check()

        return destinationBuffer
    }

    /// Crop image buffer
    func crop(_ rect: CGRect, bitsPerPixel: Int) throws -> vImage_Buffer? {
        guard rect.origin.x >= 0, rect.origin.y >= 0, rect.size.width <= CGFloat(self.width), rect.size.height <= CGFloat(self.height) else {
            return nil
        }

        let data = self.data.assumingMemoryBound(to: UInt8.self)
            .advanced(by: Int(rect.origin.y) * self.rowBytes + Int(rect.origin.x) * (bitsPerPixel / 8))

        // Create image buffer using smaller rect
        var croppedBuffer = vImage_Buffer(
            data: data,
            height: vImagePixelCount(rect.size.height),
            width: vImagePixelCount(rect.size.width),
            rowBytes: self.rowBytes
        )

        // Copy pixels into new image buffer
        var copyBuffer = try vImage_Buffer(
            width: Int(rect.size.width),
            height: Int(rect.size.height),
            bitsPerPixel: UInt32(bitsPerPixel)
        )
        let error = vImageCopyBuffer(&croppedBuffer, &copyBuffer, bitsPerPixel / 8, vImage_Flags(kvImageNoFlags))
        try error.check()

        return copyBuffer
    }

    /// Reflect horizontally
    mutating func mirror(bitsPerPixel: UInt32 = 32) throws -> vImage_Buffer {
        return try reflect(horizontal: true, bitsPerPixel: bitsPerPixel)
    }

    /// Reflect vetically
    mutating func flip(bitsPerPixel: UInt32 = 32) throws -> vImage_Buffer {
        return try reflect(horizontal: false, bitsPerPixel: bitsPerPixel)
    }

    /// Reflect pixel buffer
    private mutating func reflect(horizontal: Bool, bitsPerPixel: UInt32 = 32) throws -> vImage_Buffer {
        var destinationBuffer = try vImage_Buffer(width: Int(self.width), height: Int(self.height), bitsPerPixel: bitsPerPixel)
        let flags = vImage_Flags(kvImageNoFlags)

        var error = vImage_Error()
        if horizontal {
            error = vImageHorizontalReflect_ARGB8888(&self, &destinationBuffer, flags)
        } else {
            error = vImageVerticalReflect_ARGB8888(&self, &destinationBuffer, flags)
        }

        try error.check()

        return destinationBuffer
    }

    /// Rotate pixel buffer
    /// - angle: rotation angle in radians
    /// - fill: edges filling options
    /// - bitsPerPixel: image bits per pixel amount
    /// - temporaryBuffer: reused temporary buffer, initialized internally, don't forget to free the buffer when not needed anymore
    mutating func rotate(
        angle: Float,
        fill: RotationFill = .crop,
        bitsPerPixel: UInt32 = 32,
        temporaryBuffer: inout TemporaryBuffer?
    ) throws -> vImage_Buffer {
        let width = Int(self.width)
        let height = Int(self.height)
        let size = CGSize(width: width, height: height)

        // Initialize pixel buffer
        var destinationBuffer: vImage_Buffer
        switch fill {
        case .crop:
            // Calculate image size after resizing
            let cropSize = size.rotateFilling(angle: Double(angle))

            // Create new buffer
            destinationBuffer = try vImage_Buffer(
                width: Int(cropSize.width),
                height: Int(cropSize.height),
                bitsPerPixel: bitsPerPixel
            )
        default:
            let rect = CGRect(origin: .zero, size: size)
            let enclosingRectangle = rect.rotateExtended(angle: CGFloat(angle))

            // Create new buffer
            destinationBuffer = try vImage_Buffer(
                width: Int(enclosingRectangle.width),
                height: Int(enclosingRectangle.height),
                bitsPerPixel: bitsPerPixel
            )
        }

        // Properties
        var backColor: [UInt8] = [0, 0, 0, 0]
        let flags = vImage_Flags(kvImageHighQualityResampling) // kvImageBackgroundColorFill
        var error = vImage_Error()

        // Rotation
        switch angle {
        case .pi, -.pi: // clockwise 180 or counter clockwise 180
            error = vImageRotate90_ARGB8888(&self, &destinationBuffer, UInt8(kRotate180DegreesClockwise), &backColor, flags)
        case .pi/2, -.pi * 1.5: // 90 or -270-degree rotation, Warning: Inverted Angle -> Counter Clockwise
            error = vImageRotate90_ARGB8888(&self, &destinationBuffer, UInt8(kRotate90DegreesCounterClockwise), &backColor, flags)
        case -.pi/2, .pi * 1.5: // -90 or 270-degree rotation, Warning: Inverted Angle -> Clockwise
            error = vImageRotate90_ARGB8888(&self, &destinationBuffer, UInt8(kRotate90DegreesClockwise), &backColor, flags)
        default: // custom angle
            // Warning: rotation to a custom angle may cause some artifacts, more likely visible on semi-transparent images

            // Rotation buffer
            let tempBuffer: UnsafeMutableRawPointer!
            if temporaryBuffer != nil {
                // Reuse additional buffer required for rotation between multiple runs (animated images, videos)
                if temporaryBuffer!.isInitialized {
                    tempBuffer = temporaryBuffer!.buffer
                } else {
                    // Get temp buffer size
                    let bufferSize: Int
                    switch fill {
                    case .crop:
                        bufferSize = vImageRotate_ARGB8888(&self, &destinationBuffer, nil, angle, &backColor, vImage_Flags(kvImageHighQualityResampling | kvImageGetTempBufferSize))
                    case .color(_, _, _, _):
                        bufferSize = vImageRotate_ARGB8888(&self, &destinationBuffer, nil, angle, &backColor, vImage_Flags(kvImageHighQualityResampling | kvImageBackgroundColorFill | kvImageGetTempBufferSize))
                    case .blur(_):
                        bufferSize = vImageRotate_ARGB8888(&self, &destinationBuffer, nil, angle, &backColor, vImage_Flags(kvImageHighQualityResampling | kvImageEdgeExtend | kvImageGetTempBufferSize))
                    }

                    // Initialize temporary buffer
                    if bufferSize >= 0 {
                        temporaryBuffer!.buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 64)
                        tempBuffer = temporaryBuffer!.buffer
                    } else {
                        tempBuffer = nil
                    }
                }
            } else {
                tempBuffer = nil
            }

            switch fill {
            case .crop: // Rotation with zoom to fill effect
                error = vImageRotate_ARGB8888(&self, &destinationBuffer, tempBuffer, angle, &backColor, vImage_Flags(kvImageHighQualityResampling))
            case let .color(alpha, red, green, blue): // Rotation with solid color fill
                backColor = [alpha, red, green, blue]
                error = vImageRotate_ARGB8888(&self, &destinationBuffer, tempBuffer, angle, &backColor, vImage_Flags(kvImageHighQualityResampling | kvImageBackgroundColorFill))
            case let .blur(kernel): // Rotation with blurred edges generated
                var rotatedBuffer = try vImage_Buffer(
                    width: Int(destinationBuffer.width),
                    height: Int(destinationBuffer.height),
                    bitsPerPixel: bitsPerPixel
                )
                defer { rotatedBuffer.free() }

                // Rotate an image with edges extended (filled) using nearest pixels
                error = vImageRotate_ARGB8888(&self, &rotatedBuffer, tempBuffer, angle, &backColor, vImage_Flags(kvImageHighQualityResampling | kvImageEdgeExtend))
                try error.check()

                // Blur rotated image
                var blurredBuffer = try vImage_Buffer(
                    width: Int(rotatedBuffer.width), // if srcOffsetToROI_X is used adjust the buffer width
                    height: Int(rotatedBuffer.height), // if srcOffsetToROI_Y is used adjust the buffer height
                    bitsPerPixel: bitsPerPixel
                )
                defer { blurredBuffer.free() }

                error = vImageTentConvolve_ARGB8888(&rotatedBuffer, &blurredBuffer, nil, 0, 0, kernel, kernel, &backColor, vImage_Flags(kvImageHighQualityResampling | kvImageEdgeExtend))
                try error.check()

                // Average image color (for border filling, small amount of pixel, due to rotation)
                var transparentColor = self.averageColor_ARGB8888()
                // Set alpha to transparent, but still will be visible at the border of image due to processing
                transparentColor[0] = 0

                var overlayBuffer = try vImage_Buffer(
                    width: Int(rotatedBuffer.width),
                    height: Int(rotatedBuffer.height),
                    bitsPerPixel: bitsPerPixel
                )
                defer { overlayBuffer.free() }

                // Source image rotated again with transparent color filling the background at the edges
                error = vImageRotate_ARGB8888(&self, &overlayBuffer, nil, angle, &transparentColor, vImage_Flags(kvImageHighQualityResampling | kvImageBackgroundColorFill))
                try error.check()

                // Blend image with transparent edges over the blurred one, so the main (not extended) area is not blurred
                error = vImageAlphaBlend_ARGB8888(&overlayBuffer, &blurredBuffer, &destinationBuffer, vImage_Flags(kvImageHighQualityResampling)) // vImagePremultipliedAlphaBlend_ARGB8888
            }
        }
        try error.check()

        return destinationBuffer
    }

    /// Fill alpha channel with solid coror
    mutating func replaceAlphaChannel(color: [UInt8] = [255, 0, 0, 0], bitsPerPixel: UInt32 = 32) throws -> vImage_Buffer {
        var destinationBuffer = try vImage_Buffer(
            width: Int(self.width),
            height: Int(self.height),
            bitsPerPixel: bitsPerPixel
        )

        var backgroundBuffer = try vImage_Buffer(
            width: Int(destinationBuffer.width),
            height: Int(destinationBuffer.height),
            bitsPerPixel: bitsPerPixel
        )
        defer { backgroundBuffer.free() }

        // Fill background buffer with solid color
        var error = vImageBufferFill_ARGB8888(&backgroundBuffer, color, vImage_Flags(kvImageNoFlags))
        try error.check()

        // Blend image with alpha channel over background
        error = vImageAlphaBlend_ARGB8888(&self, &backgroundBuffer, &destinationBuffer, vImage_Flags(kvImageHighQualityResampling | kvImageBackgroundColorFill))
        try error.check()

        return destinationBuffer
    }

    /// Get average color
    /// https://stackoverflow.com/questions/55093326/averaging-the-color-of-pixels-with-accelerate
    private func averageColor_ARGB8888() -> [UInt8] {
        let pixelCount: Int = Int(self.width) * Int(self.height)
        let channelsPerPixel: Int = 4

        let rows: Int32 = Int32(channelsPerPixel)
        let columns: Int32 = Int32(pixelCount)

        var vectorA = [Float](repeating: 0, count: pixelCount * channelsPerPixel)

        // Convert pixels to float point
        vDSP_vfltu8(self.data, vDSP_Stride(1), &vectorA, vDSP_Stride(1), vDSP_Length(pixelCount * channelsPerPixel))

        var vectorX = [Float](repeating: 1 / Float(pixelCount), count: pixelCount)

        var vectorY = [Float](repeating: 0, count: channelsPerPixel)

        // Calculate average
        cblas_sgemv(CblasColMajor, CblasNoTrans, rows, columns, 1, &vectorA, rows, &vectorX, 1, 1, &vectorY, 1)

        // Construct the color
        /*let alpha = y[0].rounded()
        let red = y[1].rounded()
        let green = y[2].rounded()
        let blue = y[3].rounded()*/
        // Normalize red, green and blue channels based on alpha value
        let alphaCoefficient = 255.0 / vectorY[0]
        let alpha: Float = 255.0
        let red = min((vectorY[1] * alphaCoefficient).rounded(), 255)
        let green = min((vectorY[2] * alphaCoefficient).rounded(), 255)
        let blue = min((vectorY[3] * alphaCoefficient).rounded(), 255)

        guard alpha >= 0, alpha <= 255, red >= 0, red <= 255, green >= 0, green <= 255, blue >= 0, blue <= 255 else {
            return [0, 0, 0, 0]
        }

        return [UInt8(alpha), UInt8(red), UInt8(green), UInt8(blue)]
    }
}

/// vImage format extension
internal extension vImage_CGImageFormat {
    /// Custom `vImage_CGImageFormat` initializer
    init(
        _ image: CGImage,
        bitsPerComponent: Int? = nil,
        bitsPerPixel: Int? = nil,
        colorSpace: CGColorSpace? = nil,
        bitmapInfo: CGBitmapInfo? = nil,
        renderingIntent: CGColorRenderingIntent? = nil
    ) {
        if bitsPerComponent == nil, bitsPerComponent == nil, colorSpace == nil, bitmapInfo == nil, renderingIntent == nil, let format = vImage_CGImageFormat(cgImage: image) {
            self = format
        } else {
            let cgColorSpace: Unmanaged<CGColorSpace>!
            if let colorSpace = colorSpace {
                cgColorSpace = Unmanaged.passUnretained(colorSpace)
            } else {
                if let sourceColorSpace = image.colorSpace {
                    cgColorSpace = Unmanaged.passUnretained(sourceColorSpace)
                } else {
                    cgColorSpace = nil
                }
            }

            self = vImage_CGImageFormat(
                bitsPerComponent: UInt32(bitsPerComponent ?? image.bitsPerComponent),
                bitsPerPixel: UInt32(bitsPerPixel ?? image.bitsPerPixel),
                colorSpace: cgColorSpace,
                bitmapInfo: bitmapInfo ?? CGBitmapInfo(rawValue: image.bitmapInfo.rawValue | image.alphaInfo.rawValue),
                version: 0,
                decode: image.decode,
                renderingIntent: renderingIntent ?? image.renderingIntent
            )
        }
    }
}

/// vImage error extension
internal extension vImage_Error {
    /// Throws when containing an error
    func check() throws {
        guard self == kvImageNoError else {
            throw vImage.Error(vImageError: self)
        }
    }
}

/// Converter extension for standard `vImage` <-> `CGImage` conversions
internal extension vImageConverter {
    /// Make `vImage` <-> `CGImage` converter using base format in combination with one of source or destination
    static func create(from sourceFormat: vImage_CGImageFormat? = nil, to destinationFormat: vImage_CGImageFormat? = nil) -> vImageConverter? {
        // Hardcoded working format
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrderDefault.rawValue)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) // CGColorSpaceCreateDeviceRGB()
        guard let colorSpace = colorSpace, var baseFormat = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }

        // Converter
        var error = vImage_Error()
        let flags = vImage_Flags(kvImageNoFlags)
        let converter: Unmanaged<vImageConverter>!
        if var sourceFormat = sourceFormat, var destinationFormat = destinationFormat {
            converter = vImageConverter_CreateWithCGImageFormat(&sourceFormat, &destinationFormat, nil, flags, &error)
        } else if var sourceFormat = sourceFormat {
            converter = vImageConverter_CreateWithCGImageFormat(&sourceFormat, &baseFormat, nil, flags, &error)
        } else if var destinationFormat = destinationFormat {
            converter = vImageConverter_CreateWithCGImageFormat(&baseFormat, &destinationFormat, nil, flags, &error)
        } else {
            return nil
        }

        guard error == kvImageNoError, let converter = converter?.takeRetainedValue() else {
            return nil
        }

        return converter
    }
}

/// Wrapping `UnsafeMutableRawPointer` for optional usage
internal struct TemporaryBuffer {
    var buffer: UnsafeMutableRawPointer! = nil

    var isInitialized: Bool {
        return buffer != nil
    }

    func free() {
        if isInitialized {
            buffer.deallocate()
        }
    }
}
