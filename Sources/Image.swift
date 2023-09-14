import AVFoundation
import Foundation
import CoreImage
import ImageIO
import Accelerate.vImage
import SDWebImageWebPCoder

/// Image related singletone interface
public struct ImageTool {

    /// Convert image file
    /// - Parameters:
    ///   - source: Input image URL
    ///   - destination: Output image URL
    ///   - settings: Image format options
    ///   - skipMetadata: Whether copy or not source image metadata to destination image file
    ///   - overwrite: Replace destination file if exists, for `false` error will be raised when file already exists
    ///   - deleteSourceFile: Delete source file on success
    //   - queue: Image processing queue, `global()` used by default
    //   - completion: The completion callback containing saved image info or an error
    public static func convert(
        source: URL,
        destination: URL,
        settings: ImageSettings = ImageSettings(),
        skipMetadata: Bool = false,
        overwrite: Bool = false,
        deleteSourceFile: Bool = false
    ) throws -> ImageInfo {
        // Check the source file exists
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CompressionError.sourceFileNotFound
        }

        // Check the destination location
        if FileManager.default.fileExists(atPath: destination.path) {
            if overwrite {
                do {
                    try FileManager.default.removeItem(atPath: destination.path)
                } catch {
                    throw CompressionError.cannotOverWrite
                }
            } else {
                throw CompressionError.destinationFileExists
            }
        }

        // Init image source
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            // debugPrint(CGImageSourceCopyTypeIdentifiers()) // list of supported formats
            throw CompressionError.failedToReadImage // unsupportedImageFormat
        }

        // Source format
        var sourceFormat: ImageFormat?
        let sourceType = CGImageSourceGetType(imageSource) as? String
        let isWebPSource = sourceType == "org.webmproject.webp"
        if let sourcePathFormat = ImageFormat(source.pathExtension) {
            // Format using source path extension
            sourceFormat = sourcePathFormat
        } else if #available(macOS 11, iOS 14, tvOS 14, *), let type = sourceType, let utType = UTType(type), let imageFormat = ImageFormat(utType) {
            // Format by getting image source type
            sourceFormat = imageFormat
        }

        // Destination format
        var format = settings.format
        if format == nil {
            if let destinationPathFormat = ImageFormat(destination.pathExtension) {
                // Use destination file path extension
                format = destinationPathFormat
            } else if let sourceFormat = sourceFormat {
                // Use Source image format
                format = sourceFormat
            }
        }

        // Load image properties
        let totalFrames = CGImageSourceGetCount(imageSource)
        var primaryIndex = CGImageSourceGetPrimaryImageIndex(imageSource) // equals 0 for non-HEIF images
        let primaryProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, primaryIndex, nil) as? [CFString: Any]

        // Size options
        var fitSize: CGSize?
        if case .fit(let size) = settings.size {
            // Get original frame resolution
            let width = primaryProperties?[kCGImagePropertyPixelWidth] as? CGFloat
            let height = primaryProperties?[kCGImagePropertyPixelHeight] as? CGFloat

            if let width = width, let height = height {
                // If requested size is smaller than original
                if size.width < width || size.height < height {
                    // Should resize
                    fitSize = size
                }
            } else {
                // Original size in unknown
                fitSize = size
            }
        }

        // Other settings
        var settings = settings
        var framework = settings.preferredFramework
        let isRotationByCustomAngle = settings.edit.containsRotationByCustomAngle

        // HDR
        let depth = primaryProperties?[kCGImagePropertyDepth] as? Int ?? 8
        var isHDR = depth > 8

        // Alpha channel
        var hasAlpha = primaryProperties?[kCGImagePropertyHasAlpha] as? Bool ?? false

        // Orientation
        var orientation: CGImagePropertyOrientation?
        if let orientationProperty = primaryProperties?[kCGImagePropertyOrientation] as? UInt32 {
            orientation = CGImagePropertyOrientation(rawValue: orientationProperty)
        }

        // Animation
        var isAnimated: Bool = !settings.skipAnimation && totalFrames > 1
        if isAnimated, format?.isAnimationSupported == false {
            isAnimated = false
        }
        if isAnimated, framework == .ciImage {
            // `CIImage` has no support for animated sequences
            framework = ImageFramework.animatedFramework(
                isHDR: isHDR,
                hasAlpha: hasAlpha,
                preserveAlphaChannel: settings.preserveAlphaChannel,
                isRotationByCustomAngle: isRotationByCustomAngle,
                preferredFramework: framework
            )
        }

        var loadingMethod = ImageLoadingMethod.select(
            preferredFramework: framework,
            isHDR: isHDR,
            isWebP: isWebPSource,
            isLowQuality: format?.isLowQuality ?? false,
            isAnimated: isAnimated,
            hasAlpha: hasAlpha,
            preserveAlphaChannel: settings.preserveAlphaChannel,
            isRotationByCustomAngle: isRotationByCustomAngle,
            fitSize: fitSize
        )

        // Load primary frame
        var primaryFrame = try ImageFrame.load(
            url: source,
            imageSource: imageSource,
            index: primaryIndex,
            method: loadingMethod,
            isAnimated: isAnimated
        )

        // Update local variables based on loaded image in addition to loaded properties
        if let cgImage = primaryFrame.cgImage {
            var changed = false

            // Alpha channel presence
            if !hasAlpha, cgImage.hasAlpha == true {
                hasAlpha = true
                changed = true
            }

            // HDR
            if !isHDR, cgImage.bitsPerComponent > 8 {
                isHDR = true
                changed = true
            }

            if changed {
                // Get new method and compare with used one
                let method = ImageLoadingMethod.select(
                    preferredFramework: framework,
                    isHDR: isHDR,
                    isWebP: isWebPSource,
                    isLowQuality: format?.isLowQuality ?? false,
                    isAnimated: isAnimated,
                    hasAlpha: hasAlpha,
                    preserveAlphaChannel: settings.preserveAlphaChannel,
                    isRotationByCustomAngle: isRotationByCustomAngle,
                    fitSize: fitSize
                )

                if loadingMethod != method {
                    // Reload frame
                    loadingMethod = method
                    primaryFrame = try ImageFrame.load(
                        url: source,
                        imageSource: imageSource,
                        index: primaryIndex,
                        method: loadingMethod,
                        isAnimated: isAnimated
                    )
                }
            }
        }

        if format == nil {
            // When destination format is `nil` use the `CGImage` image format
            if let cgImage = primaryFrame.cgImage, let utType = cgImage.utType, let cgImageFormat = ImageFormat(utType) {
                format = cgImageFormat
            } else {
                throw CompressionError.unsupportedImageFormat
            }

            // Confirm animation is supported
            if isAnimated, format?.isAnimationSupported == false {
                isAnimated = false
            }
        }

        // Fix HEIF format based on bit depth
        if isHDR, format == .heif {
            format = .heif10
        }
        if !isHDR, format == .heif10 {
            format = .heif
        }

        // Animation specific variables
        var images: [ImageFrame] = []
        images.reserveCapacity(isAnimated ? totalFrames : 1)

        if isAnimated {
            // Load all the frames
            for index in 0 ..< totalFrames {
                // Insert the primary image frame
                if index == primaryIndex {
                    images.append(primaryFrame)
                    continue
                }

                // Load an image
                let frame = try ImageFrame.load(
                    url: source,
                    imageSource: imageSource,
                    index: index,
                    method: loadingMethod,
                    isAnimated: isAnimated
                )
                images.append(frame)
            }
            // guard images.count == totalFrames else { Some frames skipped }

            // Confirm image is still animated (has more than one frame)
            if images.count <= 1 {
                isAnimated = false
            }

            primaryIndex = primaryIndex < images.count ? primaryIndex : 0
        } else {
            // Use only the primary frame
            images.append(primaryFrame)
        }

        // Adjust animated image sequence frame rate
        var frameRate: Int?
        let duration = images.duration // image sequence duration
        if isAnimated, let animationFrameRate = settings.frameRate, let duration = duration {
            let (updatedFrames, updatedFrameRate) = images.withAdjustedFrameRate(frameRate: animationFrameRate, duration: duration)
            if let updatedFrames = updatedFrames {
                images = updatedFrames
            }
            frameRate = updatedFrameRate
        }

        // Fix HEIC format based on animation presence
        if !isHDR, isAnimated, format == .heic {
            format = .heics
        }
        if !isAnimated, format == .heics {
            format = .heic
        }

        // Image processing algorithm
        let processingMethod = ImageFramework.processingFramework(
            isHDR: isHDR,
            hasAlpha: hasAlpha,
            preserveAlphaChannel: settings.preserveAlphaChannel,
            isLowQuality: format?.isLowQuality ?? false,
            isAnimated: isAnimated,
            isRotationByCustomAngle: isRotationByCustomAngle,
            preferredFramework: framework
        )

        // Edit
        var size: CGSize = primaryFrame.canvasSize ?? primaryFrame.size.oriented(orientation)
        if !settings.edit.isEmpty || settings.size != .original || (!settings.preserveAlphaChannel && hasAlpha) {
            switch processingMethod {
            case .vImage:
                guard let primary = primaryFrame.cgImage ?? images[primaryIndex].cgImage ?? images.first?.cgImage else { break }
                let format = vImage_CGImageFormat(primary)

                // Warning: Converters may be used in parallel, but temp buffer can't (use nil then)
                var tempBuffer: TemporaryBuffer? = TemporaryBuffer()
                let converterIn = vImageConverter.create(from: format)
                let converterOut = vImageConverter.create(to: format)

                for index in 0 ..< images.count {
                    let frame = images[index]
                    guard let cgImage = frame.cgImage else { continue }

                    let edited = try? vImage.edit(
                        image: cgImage,
                        operations: settings.edit,
                        size: settings.size,
                        shouldResize: frame.shouldResize,
                        hasAlpha: hasAlpha,
                        preserveAlpha: settings.preserveAlphaChannel,
                        backgroundColor: settings.backgroundColor,
                        orientation: orientation,
                        index: index,
                        format: format,
                        converterIn: converterIn,
                        converterOut: converterOut,
                        tempBuffer: &tempBuffer
                    )
                    guard let edited = edited else { continue } // continue if wasn't changed

                    // Update image size
                    if index == primaryIndex {
                        size = edited.size(orientation: orientation)
                    }
                    // Set image
                    images[index].cgImage = edited
                }
                tempBuffer?.free()
            case .cgImage:
                for index in 0 ..< images.count {
                    let frame = images[index]
                    guard let cgImage = frame.cgImage else { continue }

                    // Apply edits
                    let edited = cgImage.edit(
                        operations: settings.edit,
                        size: settings.size,
                        shouldResize: frame.shouldResize,
                        hasAlpha: hasAlpha,
                        preserveAlpha: settings.preserveAlphaChannel,
                        backgroundColor: settings.backgroundColor,
                        orientation: orientation,
                        index: index
                    )
                    // Set image
                    images[index].cgImage = edited

                    // Update size
                    if index == primaryIndex {
                        size = edited.size
                    }
                }
            case .ciImage:
                for index in 0 ..< images.count { // more likely a static image
                    let frame = images[index]
                    var ciImage = frame.ciImage
                    if ciImage == nil, let cgImage = frame.cgImage {
                        ciImage = CIImage(cgImage: cgImage, options: [.applyOrientationProperty: false])
                    }
                    guard var ciImage = ciImage else { continue }

                    // Apply edits
                    ciImage = ciImage.edit(
                        operations: settings.edit,
                        size: settings.size,
                        shouldResize: frame.shouldResize, // `CIImage` always loaded full size and should be resized
                        hasAlpha: hasAlpha,
                        preserveAlpha: settings.preserveAlphaChannel && format != .jpeg,
                        backgroundColor: settings.backgroundColor,
                        orientation: orientation,
                        index: index
                    )
                    // Set image
                    images[index].ciImage = ciImage

                    // Update size
                    if index == primaryIndex {
                        size = ciImage.extent.size
                    }
                }
            }
        }

        // Update the format
        settings.format = format

        // Save
        try saveImage(images,
            at: destination,
            overwrite: overwrite,
            settings: settings,
            orientation: orientation,
            isHDR: isHDR,
            primaryIndex: primaryIndex,
            metadata: primaryProperties
        )

        // Info
        let info = ImageInfo(
            format: settings.format!,
            size: size,
            hasAlpha: hasAlpha && settings.preserveAlphaChannel,
            isHDR: isHDR,
            orientation: orientation,
            framesCount: images.count,
            frameRate: frameRate,
            duration: duration
        )

        // Delete original
        if deleteSourceFile {
            try? FileManager.default.removeItem(atPath: source.path)
        }

        return info
    }

    /// Save `CGImage` to file in `ImageFormat` with `ImageSettings` applying
    internal static func saveImage(
        _ frames: [ImageFrame],
        at url: URL,
        overwrite: Bool = false,
        settings: ImageSettings,
        orientation: CGImagePropertyOrientation? = nil,
        isHDR: Bool? = nil,
        primaryIndex: Int = 0,
        metadata: [CFString: Any]? = nil
    ) throws {
        guard let format = settings.format else {
            throw CompressionError.unknownImageFormat
        }

        guard !frames.isEmpty else {
            throw CompressionError.emptyImage
        }

        let embedThumbnail = settings.embedThumbnail ? kCFBooleanTrue! : kCFBooleanFalse!
        let optimizeColors = settings.optimizeColorForSharing ? kCFBooleanTrue! : kCFBooleanFalse!

        let primaryFrame = frames[primaryIndex]
        let primaryCGImage: CGImage? = primaryFrame.cgImage
        let primaryCIImage: CIImage? = primaryFrame.ciImage

        var imageFormat: ImageFormat? = format
        // PNG, TIFF and JPEG with 10+ bit depth should be saved using `CIContext` for HDR data preserving
        if format == .png || format == .tiff || format == .jpeg, (frames.count == 1 && isHDR == true) || primaryCIImage != nil {
            imageFormat = nil
        }

        switch imageFormat {
        case .heif, .heif10, nil:
            let ciContext = CIContext()

            // Get image
            let ciImage: CIImage
            if var image = primaryCIImage {
                // Metadata
                if let metadata = metadata {
                    image = image.settingProperties(metadata)
                }

                ciImage = image
            } else if let image = primaryCGImage {
                // Base options
                var options: [CIImageOption: Any] = [
                    .applyOrientationProperty: true
                ]

                // Metadata
                if let metadata = metadata {
                    options[.properties] = metadata
                }

                ciImage = CIImage(cgImage: image, options: options)
            } else {
                throw CompressionError.emptyImage
            }

            var optionsDict: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationEmbedThumbnail as String): embedThumbnail
            ]
            if settings.optimizeColorForSharing {
                optionsDict[CIImageRepresentationOption(rawValue: kCGImageDestinationOptimizeColorForSharing as String)] = optimizeColors
            }
            if let quality = settings.quality {
                optionsDict[CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)] = quality
            }

            do {
                func getColorSpace() -> CGColorSpace {
                    return ciImage.colorSpace ?? CGColorSpace(name: ciImage.hasAlpha ? CGColorSpace.sRGB : CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
                }

                switch format {
                case .heif:
                    let pixelFormat = CIFormat.RGBA8
                    let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

                    try ciContext.writeHEIFRepresentation(of: ciImage, to: url, format: pixelFormat, colorSpace: colorSpace, options: optionsDict)
                case .heif10:
                    if #available(macOS 12, iOS 15, tvOS 15, *) {
                        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
                        try ciContext.writeHEIF10Representation(of: ciImage, to: url, colorSpace: colorSpace, options: optionsDict)
                    } else {
                        let pixelFormat = CIFormat.RGBA16
                        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
                        try ciContext.writeHEIFRepresentation(of: ciImage, to: url, format: pixelFormat, colorSpace: colorSpace, options: optionsDict)
                    }
                case .png:
                    // Warning: PNG will store up to 16 bit per component, no OpenEXR support
                    let colorSpace = CGColorSpace(name: CGColorSpace.genericRGBLinear)! // ciImage.depth <= 8 ? getColorSpace() :
                    try ciContext.writePNGRepresentation(of: ciImage, to: url, format: ciImage.pixelFormat, colorSpace: colorSpace, options: optionsDict)
                case .tiff:
                    let colorSpace = ciImage.depth <= 8 ? getColorSpace() : CGColorSpace(name: CGColorSpace.displayP3_HLG)! // itur_2100_HLG/displayP3_PQ
                    try ciContext.writeTIFFRepresentation(of: ciImage, to: url, format: ciImage.pixelFormat, colorSpace: colorSpace, options: optionsDict)
                case .jpeg:
                    let colorSpace = ciImage.depth <= 8 ? getColorSpace() : CGColorSpace(name: CGColorSpace.displayP3_HLG)! // itur_2100_HLG/displayP3_PQ
                    try ciContext.writeJPEGRepresentation(of: ciImage, to: url, colorSpace: colorSpace, options: optionsDict)
                default:
                    break
                }
            } catch {
                throw CompressionError.failedToSaveImage
            }
        #if os(macOS)
        case .jpeg2000:
            fallthrough
        #endif
        case .jpeg, .gif, .bmp, .ico, .png, .tiff, .heic, .heics:
            guard let utType = format.utType, let destination = CGImageDestinationCreateWithURL(url as CFURL, utType, frames.count, nil) else {
                // debugPrint(CGImageSourceCopyTypeIdentifiers()) // supported output image formats when using `CGImageDestination` methods
                throw CompressionError.failedToCreateImageFile
            }

            var imageOptions: [CFString: Any] = [
                kCGImageDestinationEmbedThumbnail: embedThumbnail
            ]

            // Adjust colors for sharing
            if settings.optimizeColorForSharing {
                imageOptions[kCGImageDestinationOptimizeColorForSharing] = optimizeColors
            }

            // Compression quality
            if let quality = settings.quality {
                imageOptions[kCGImageDestinationLossyCompressionQuality] = quality
            }

            // Background color
            if let color = settings.backgroundColor { // !settings.preserveAlphaChannel
                imageOptions[kCGImageDestinationBackgroundColor] = color
            }
            /*if let color = settings.backgroundColor, let components = color.components {
                let red = components[0]
                let green = components[1]
                let blue = components[2]

                // Convert color to BGRA format
                let colorSpace = primaryCGImage?.colorSpace ?? CGColorSpaceCreateDeviceRGB()
                let bgraColor = CGColor(colorSpace: colorSpace, components: [blue, green, red, 1.0])
                imageOptions[kCGImageDestinationBackgroundColor] = bgraColor
            }*/

            // Metadata
            if let metadata = metadata {
                // GPS
                if let gps = metadata[kCGImagePropertyGPSDictionary] {
                    imageOptions[kCGImagePropertyGPSDictionary] = gps
                }

                // Exif
                if let exif = metadata[kCGImagePropertyExifDictionary] {
                    imageOptions[kCGImagePropertyExifDictionary] = exif
                }

                // TIFF
                if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    tiff[kCGImagePropertyTIFFOrientation] = orientation?.rawValue // override orientation
                    imageOptions[kCGImagePropertyTIFFDictionary] = tiff
                }

                // MakerApple
                if let apple = metadata[kCGImagePropertyMakerAppleDictionary] {
                    imageOptions[kCGImagePropertyMakerAppleDictionary] = apple
                }

                // IPTC
                if let apple = metadata[kCGImagePropertyIPTCDictionary] {
                    imageOptions[kCGImagePropertyIPTCDictionary] = apple
                }
            }

            // Orientation
            if let orientation = orientation {
                imageOptions[kCGImagePropertyOrientation] = orientation.rawValue
            }

            // Set all frame properties
            CGImageDestinationSetProperties(destination, imageOptions as CFDictionary)

            // Insert all the frames
            lazy var context = CIContext() // options: [.highQualityDownsample: true]
            for index in 0 ..< frames.count {
                var properties: [CFString: Any]?
                let frame = frames[index]

                switch format {
                case .gif:
                    var gifProperties: [CFString: Any] = [:]
                    if let delayTime = frame.delayTime {
                        gifProperties[kCGImagePropertyGIFDelayTime] = delayTime
                    }
                    if let unclampedDelayTime = frame.unclampedDelayTime {
                        gifProperties[kCGImagePropertyGIFUnclampedDelayTime] = unclampedDelayTime
                    }
                    if let loopCount = frame.loopCount {
                        gifProperties[kCGImagePropertyGIFLoopCount] = loopCount
                    }
                    if let frameInfoArray = frame.frameInfoArray {
                        gifProperties[kCGImagePropertyGIFFrameInfoArray] = frameInfoArray
                    }
                    if let canvasWidth = frame.canvasWidth {
                        gifProperties[kCGImagePropertyGIFCanvasPixelWidth] = canvasWidth
                    }
                    if let canvasHeight = frame.canvasHeight {
                        gifProperties[kCGImagePropertyGIFCanvasPixelHeight] = canvasHeight
                    }
                    if !gifProperties.isEmpty {
                        properties = [kCGImagePropertyGIFDictionary: gifProperties]
                    }
                case .heics:
                    var heicsProperties: [CFString: Any] = [:]
                    if let delayTime = frame.delayTime {
                        heicsProperties[kCGImagePropertyHEICSDelayTime] = delayTime
                    }
                    if let unclampedDelayTime = frame.unclampedDelayTime {
                        heicsProperties[kCGImagePropertyHEICSUnclampedDelayTime] = unclampedDelayTime
                    }
                    if let loopCount = frame.loopCount {
                        heicsProperties[kCGImagePropertyHEICSLoopCount] = loopCount
                    }
                    if let frameInfoArray = frame.frameInfoArray {
                        heicsProperties[kCGImagePropertyHEICSFrameInfoArray] = frameInfoArray
                    }
                    if let canvasWidth = frame.canvasWidth {
                        heicsProperties[kCGImagePropertyHEICSCanvasPixelWidth] = canvasWidth
                    }
                    if let canvasHeight = frame.canvasHeight {
                        heicsProperties[kCGImagePropertyHEICSCanvasPixelHeight] = canvasHeight
                    }
                    if !heicsProperties.isEmpty {
                        properties = [kCGImagePropertyHEICSDictionary: heicsProperties]
                    }
                case .png:
                    var pngProperties: [CFString: Any] = [:]
                    if let delayTime = frame.delayTime {
                        pngProperties[kCGImagePropertyAPNGDelayTime] = delayTime
                    }
                    if let unclampedDelayTime = frame.unclampedDelayTime {
                        pngProperties[kCGImagePropertyAPNGUnclampedDelayTime] = unclampedDelayTime
                    }
                    if let loopCount = frame.loopCount {
                        pngProperties[kCGImagePropertyAPNGLoopCount] = loopCount
                    }
                    if let frameInfoArray = frame.frameInfoArray {
                        pngProperties[kCGImagePropertyAPNGFrameInfoArray] = frameInfoArray
                    }
                    if let canvasWidth = frame.canvasWidth {
                        pngProperties[kCGImagePropertyAPNGCanvasPixelWidth] = canvasWidth
                    }
                    if let canvasHeight = frame.canvasHeight {
                        pngProperties[kCGImagePropertyAPNGCanvasPixelHeight] = canvasHeight
                    }
                    if !pngProperties.isEmpty {
                        properties = [kCGImagePropertyPNGDictionary: pngProperties]
                    }
                default:
                    break
                }

                if format != .heics, index == 0 || index == primaryIndex {
                    // First and primary frame should be storing the image metadata
                    if properties != nil {
                        properties!.merge(imageOptions, uniquingKeysWith: { (current, _) in return current})
                    } else {
                        properties = imageOptions
                    }
                }

                // If image was proceed using `CIImage` convert it to `CGImage` instead of using cached `CGImage` at `frame.image`
                let image: CGImage
                if let ciImage = frame.ciImage {
                    // image = context.createCGImage(ciImage, from: ciImage.extent, format: <#T##CIFormat#>, colorSpace: <#T##CGColorSpace?#>)
                    image = context.createCGImage(ciImage, from: ciImage.extent) ?? frame.cgImage!
                } else {
                    image = frame.cgImage!
                }

                CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
            }

            // Write
            if CGImageDestinationFinalize(destination) == false {
                throw CompressionError.failedToSaveImage
            }
        case .webp:
            // Collect all the frames
            var sdFrames: [SDImageFrame] = []
            lazy var context = CIContext()
            for index in 0 ..< frames.count {
                let frame = frames[index]

                let cgImage: CGImage
                if let ciImage = frame.ciImage {
                    cgImage = context.createCGImage(ciImage, from: ciImage.extent) ?? frame.cgImage!
                } else {
                    cgImage = frame.cgImage!
                }

                #if os(OSX)
                let image = NSImage(
                    cgImage: cgImage,
                    scale: 1.0,
                    orientation: orientation ?? .up
                )
                #else
                let image = UIImage(
                    cgImage: cgImage,
                    scale: 1.0,
                    orientation: UIImage.Orientation(rawValue: Int((orientation ?? .up).rawValue)) ?? .up
                )
                #endif

                sdFrames.append(SDImageFrame(image: image, duration: frame.unclampedDelayTime ?? frame.delayTime ?? 0.1))
            }

            // WebP Settings
            var options: [SDImageCoderOption: Any] = [:]
            if let quality = settings.quality {
                options[.encodeCompressionQuality] = quality
            }
            /*if settings.preserveAlphaChannel, primaryCGImage?.hasAlpha == true {
                options[.encodeWebPAlphaQuality] = 0...100 // default is 100
                options[.encodeWebPAlphaCompression] = 0 || 1 // default is 1
            }*/
            if settings.embedThumbnail {
                options[.encodeEmbedThumbnail] = true
            }
            if let backgroundColor = settings.backgroundColor {
                options[.encodeBackgroundColor] = backgroundColor
            }

            // Encode WebP
            let webpData = SDImageWebPCoder.shared.encodedData(
                with: sdFrames,
                loopCount: UInt(primaryFrame.loopCount ?? 0),
                format: .webP,
                options: options
            )
            guard let webpData = webpData else {
                throw CompressionError.failedToCreateImageFile
            }

            // Write to file
            do {
                try webpData.write(to: url)
            } catch {
                throw CompressionError.failedToSaveImage
            }
        }
    }
}
