import AVFoundation
import CoreImage
import ImageIO
import Accelerate.vImage

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
    /*public static func convert(
        source: URL,
        destination: URL,
        settings: ImageSettings = ImageSettings(),
        skipMetadata: Bool = false,
        overwrite: Bool = false,
        deleteSourceFile: Bool = false
    ) throws -> ImageInfo {
        // Check the source file exists
        guard FileManager.default.fileExists(atPath: source.path) else {
            // Also caused by insufficient permissions
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
        /*#if !os(macOS)
        // Custom encoder require conversion to a platform specific image class, which fails on iOS when CIImage image loader is used
        if framework == .ciImage, case .custom = format {
            framework = .cgImage
        }
        #endif*/
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

        // Fix HEIC format based on animation presence
        if !isHDR, isAnimated, format == .heic {
            format = .heics
        }
        if !isAnimated, format == .heics {
            format = .heic
        }

        // Fix HEIF animated images (only when format wasn't passed)
        if !isHDR, isAnimated, settings.format == nil, format == .heif || format == .heif10 {
            format = .heics
        }

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

        // Fix HEIC format based on animation presence (duplicate, properties may have changed)
        if !isHDR, isAnimated, format == .heic {
            format = .heics
        }
        if !isAnimated, format == .heics {
            format = .heic
        }
        // Final format
        settings.format = format

        // Edit
        var size: CGSize = primaryFrame.canvasSize ?? primaryFrame.size.oriented(orientation)
        if !settings.edit.isEmpty || settings.size != .original || (!settings.preserveAlphaChannel && hasAlpha) {
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

        // Save
        try encode(images,
            at: destination,
            overwrite: overwrite,
            skipGPSMetadata: skipMetadata,
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
            bitDepth: depth,
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
    }*/

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
            // Also caused by insufficient permissions
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

        // Decode image frames
        let image = try decode(
            source: source,
            destination: destination,
            settings: settings,
            skipMetadata: skipMetadata
        )

        // Update settings based on decoded info
        var settings = settings
        settings.format = image.format

        // Edit frames
        let (frames, size) = edit(
            image.frames,
            settings: settings,
            processingMethod: image.processingMethod,
            hasAlpha: image.hasAlpha,
            orientation: image.info.orientation,
            primaryIndex: image.primaryIndex
        )

        // Encode image frames
        try encode(frames,
            at: destination,
            skipGPSMetadata: skipMetadata,
            settings: settings,
            orientation: image.info.orientation,
            isHDR: image.info.isHDR,
            primaryIndex: image.primaryIndex,
            metadata: image.primaryProperties
        )

        // Info
        let info = ImageInfo(
            format: settings.format!,
            size: size,
            hasAlpha: image.hasAlpha && settings.preserveAlphaChannel,
            isHDR: image.info.isHDR,
            bitDepth: image.info.bitDepth,
            orientation: image.info.orientation,
            framesCount: frames.count,
            frameRate: image.info.frameRate,
            duration: image.info.duration
        )

        // Delete original
        if deleteSourceFile {
            try? FileManager.default.removeItem(atPath: source.path)
        }

        return info
    }

    /// Convert image to multiple output formats
    /// - Parameters:
    ///   - source: Source image URL
    ///   - destinations: Destination URLs and format related settings, only encoding related parameters are used - decoding options and edits are ignored
    ///   - settings: Settings applied to source image, providing format is unnecessery,  set edits/resizing here
    ///   - skipMetadata: Whether copy or not source image metadata to destination image file
    ///   - overwrite: Replace destination file if exists, for `false` error will be raised when file already exists
    ///   - deleteSourceFile: Delete source file on every output success
    /// - Returns: Dictionary containing info or error for each of specified destination
    /// Source image is decoded and edited just once, all encodings proceed sequentially without multithreading
    /*public static func convertToMany(
        source: URL,
        destinations: [URL: ImageSettings],
        settings: ImageSettings,
        skipMetadata: Bool = false,
        overwrite: Bool = false,
        deleteSourceFile: Bool = false
    ) throws -> [URL: Result<ImageInfo, Error>] {
        // Check the source file exists
        guard FileManager.default.fileExists(atPath: source.path) else {
            // Also caused by insufficient permissions
            throw CompressionError.sourceFileNotFound
        }

        // Load image frames
        var sourceSettings = settings
        if sourceSettings.format != nil {
            // Pass empty format to preserve HDR, animations, alpha based on detected source and not the provided one
            sourceSettings.format = nil
        }
        let image = try decode(
            source: source,
            settings: sourceSettings,
            skipMetadata: skipMetadata
        )
        sourceSettings.format = image.format
        let sourceInfo = image.info
        let isHDR = sourceInfo.isHDR
        let isAnimated = sourceInfo.isAnimated

        // Edit frames
        let (frames, size) = edit(
            image.frames,
            settings: sourceSettings,
            processingMethod: image.processingMethod,
            hasAlpha: image.hasAlpha,
            orientation: image.info.orientation,
            primaryIndex: image.primaryIndex
        )

        var images: [URL: Result<ImageInfo, Error>] = [:]
        var hasErrors = false
        for (destination, settings) in destinations {
            do {
                guard !FileManager.default.fileExists(atPath: destination.path) || !overwrite else {
                    throw CompressionError.destinationFileExists
                }

                var settings = settings
                // Correct image format based on source format and info
                if settings.format == nil {
                    if let destinationPathFormat = ImageFormat(destination.pathExtension) {
                        // Use destination file path extension
                        settings.format = destinationPathFormat
                    } else if let sourceFormat = sourceSettings.format {
                        // Use Source image format
                        settings.format = sourceFormat
                    }

                    if !isHDR, isAnimated, settings.format == .heif || settings.format == .heif10 {
                        settings.format = .heics
                    }
                }
                if !isHDR, isAnimated, settings.format == .heic {
                    settings.format = .heics
                }
                if !isAnimated, settings.format == .heics {
                    settings.format = .heic
                }

                // Encode image frames
                let frames = isAnimated && frames.count > 1 && settings.format?.isAnimationSupported == false ? [frames[image.primaryIndex]] : frames
                try encode(frames,
                    at: destination,
                    skipGPSMetadata: skipMetadata,
                    settings: settings,
                    orientation: sourceInfo.orientation,
                    isHDR: sourceInfo.isHDR,
                    primaryIndex: image.primaryIndex,
                    metadata: image.primaryProperties
                )

                // Info
                let info = ImageInfo(
                    format: settings.format!,
                    size: size,
                    hasAlpha: image.hasAlpha && sourceSettings.preserveAlphaChannel,
                    isHDR: sourceInfo.isHDR,
                    bitDepth: sourceInfo.bitDepth,
                    orientation: sourceInfo.orientation,
                    framesCount: frames.count,
                    frameRate: frames.count > 1 ? sourceInfo.frameRate : nil,
                    duration: frames.count > 1 ? sourceInfo.duration : nil
                )

                images[destination] = .success(info)
            } catch {
                images[destination] = .failure(error)
                hasErrors = true
            }
        }

        // Delete original
        if hasErrors == false, deleteSourceFile {
            try? FileManager.default.removeItem(atPath: source.path)
        }

        return images
    }*/

    /// Decode image frames
    /// - Parameters:
    ///   - source: Input image URL
    ///   - destination: Output image URL, used to detect image format when other methods fails
    ///   - settings: Image format options
    ///   - skipMetadata: Whether copy or not source image metadata to destination image file
    /// - Returns: Image object containing frames and required for future processing image info
    public static func decode(
        source: URL,
        settings: ImageSettings = ImageSettings(),
        skipMetadata: Bool = false
    ) throws -> Image {
        return try decode(
            source: source,
            destination: source.deletingPathExtension().appendingPathExtension("png"), // PNG supports all the features
            settings: settings,
            skipMetadata: skipMetadata
        )
    }

    /// Decode image frames
    /// - Parameters:
    ///   - source: Input image URL
    ///   - destination: Output image URL, used to detect image format when other methods fails
    ///   - settings: Image format options
    ///   - skipMetadata: Whether copy or not source image metadata to destination image file
    /// - Returns: Image object containing frames and required for future processing image info
    public static func decode(
        source: URL,
        destination: URL,
        settings: ImageSettings = ImageSettings(),
        skipMetadata: Bool = false
    ) throws -> Image {
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
        /*#if !os(macOS)
        // Custom encoder require conversion to a platform specific image class, which fails on iOS when CIImage image loader is used
        if framework == .ciImage, case .custom = format {
            framework = .cgImage
        }
        #endif*/
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

        // Fix HEIC format based on animation presence
        if !isHDR, isAnimated, format == .heic {
            format = .heics
        }
        if !isAnimated, format == .heics {
            format = .heic
        }

        // Fix HEIF animated images (only when format wasn't passed)
        if !isHDR, isAnimated, settings.format == nil, format == .heif || format == .heif10 {
            format = .heics
        }

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

        // Fix HEIC format based on animation presence (duplicate, properties may have changed)
        if !isHDR, isAnimated, format == .heic {
            format = .heics
        }
        if !isAnimated, format == .heics {
            format = .heic
        }
        // Final format
        settings.format = format

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

        // Loaded image size
        let size = primaryFrame.canvasSize ?? primaryFrame.size.oriented(orientation)

        // Info
        let info = ImageInfo(
            format: settings.format!,
            size: size,
            hasAlpha: hasAlpha && settings.preserveAlphaChannel,
            isHDR: isHDR,
            bitDepth: depth,
            orientation: orientation,
            framesCount: images.count,
            frameRate: frameRate,
            duration: duration
        )

        return Image(
            frames: images,
            info: info,
            format: format,
            // sourceFormat: sourceFormat,
            size: size,
            primaryProperties: primaryProperties,
            primaryIndex: primaryIndex,
            hasAlpha: hasAlpha,
            processingMethod: processingMethod
        )
    }

    /// Edit image frames
    /// - Parameters:
    ///   - image: Input image
    ///   - settings: Image settings
    /// - Returns: Edited image frames and updated resolution
    public static func edit(_ image: Image, settings: ImageSettings) -> (frames: [ImageFrame], size: CGSize) {
       return edit(image.frames,
            settings: settings,
            processingMethod: image.processingMethod,
            hasAlpha: image.hasAlpha,
            orientation: image.info.orientation,
            primaryIndex: image.primaryIndex
        )
    }

    /// Edit image frames
    /// - Parameters:
    ///   - frames: Image frames
    ///   - settings: Image settings
    ///   - processingMethod: Image framework, pass `processingMethod` property of `Image` returned by `decode()` method
    ///   - hasAlpha: Alpha channel presence, pass `hasAlpha` property of `Image` returned by `decode()` method
    ///   - orientation: Image orientation, pass `info.orientation` from `Image` object returned by `decode()` method
    ///   - primaryIndex: Alpha channel presence, pass `hasAlpha` property of `Image` returned by `decode()` method
    /// - Returns: Edited image frames and updated resolution
    public static func edit(
        _ frames: [ImageFrame],
        settings: ImageSettings,
        processingMethod: ImageFramework,
        hasAlpha: Bool,
        orientation: CGImagePropertyOrientation? = nil,
        primaryIndex: Int = 0
    ) -> (frames: [ImageFrame], size: CGSize) {
        var images = frames
        let primaryFrame = frames[primaryIndex]

        var size = primaryFrame.canvasSize ?? primaryFrame.size.oriented(orientation)
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
                        preserveAlpha: settings.preserveAlphaChannel && settings.format != .jpeg,
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

        return (images, size)
    }

    /// Write image to the file using `ImageFormat` and `ImageSettings`
    /// - Parameters:
    ///   - image: Input image
    ///   - url: Destination URL
    ///   - skipGPSMetadata: Skip GPS metadata
    ///   - settings: Image format options
    public static func encode(
        _ image: Image,
        at url: URL,
        skipGPSMetadata: Bool = false,
        settings: ImageSettings
    ) throws {
        return try encode(
            image.frames,
            at: url,
            skipGPSMetadata: skipGPSMetadata,
            settings: settings,
            orientation: image.info.orientation,
            isHDR: image.info.isHDR,
            primaryIndex: image.primaryIndex,
            metadata: image.primaryProperties
        )
    }

    /// Write image frames to the file using `ImageFormat` and `ImageSettings`
    /// - Parameters:
    ///   - frames: Image frames
    ///   - url: Destination URL
    ///   - skipGPSMetadata: Skip GPS metadata
    ///   - settings: Image format options
    ///   - orientation: Image orientation
    ///   - isHDR: HDR presence
    ///   - primaryIndex: Primary index
    ///   - metadata: Image metadata properties
    public static func encode(
        _ frames: [ImageFrame],
        at url: URL,
        skipGPSMetadata: Bool = false,
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
        // PNG and TIFF with 10+ bit depth should be saved using `CIContext` for HDR data preserving
        if format == .png || format == .tiff, (frames.count == 1 && isHDR == true) || primaryCIImage != nil {
            imageFormat = nil
        }

        switch imageFormat {
        case .heif, .heif10, nil:
            let ciContext = CIContext()
            var metadata = metadata
            if skipGPSMetadata {
                metadata?[kCGImagePropertyGPSDictionary] = nil
            }

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
            if skipGPSMetadata {
                optionsDict[CIImageRepresentationOption(rawValue: kCGImageMetadataShouldExcludeGPS as String)] = kCFBooleanTrue!
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
                    // Warning: PNG will store up to 16 bit per component
                    let colorSpace = ciImage.depth <= 8 ? getColorSpace() : CGColorSpace(name: CGColorSpace.genericRGBLinear)!
                    try ciContext.writePNGRepresentation(of: ciImage, to: url, format: ciImage.pixelFormat, colorSpace: colorSpace, options: optionsDict)
                case .tiff:
                    let colorSpace = ciImage.depth <= 8 ? getColorSpace() : CGColorSpace(name: CGColorSpace.displayP3_HLG)! // itur_2100_HLG/displayP3_PQ
                    try ciContext.writeTIFFRepresentation(of: ciImage, to: url, format: ciImage.pixelFormat, colorSpace: colorSpace, options: optionsDict)
                /*case .jpeg:
                    let colorSpace = ciImage.depth <= 8 ? getColorSpace() : CGColorSpace(name: CGColorSpace.displayP3_HLG)! // itur_2100_HLG/displayP3_PQ
                    try ciContext.writeJPEGRepresentation(of: ciImage, to: url, colorSpace: colorSpace, options: optionsDict)*/
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
        case .jpeg, .gif, .bmp, .ico, .png, .tiff, .heic, .heics, .exr, .pdf:
            guard let utType = format.utType, let destination = CGImageDestinationCreateWithURL(url as CFURL, utType, frames.count, nil) else {
                // debugPrint(CGImageDestinationCopyTypeIdentifiers()) // supported output image formats when using `CGImageDestination` methods
                throw CompressionError.failedToCreateImageFile
            }

            var imageOptions: [CFString: Any] = [
                kCGImageDestinationEmbedThumbnail: embedThumbnail
            ]

            // Exclude GPS
            if skipGPSMetadata {
                imageOptions[kCGImageMetadataShouldExcludeGPS] = kCFBooleanTrue!
            }

            // Adjust colors for sharing, GIF and BMP provide incorrect image orientation
            if settings.optimizeColorForSharing && format != .gif && format != .bmp {
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

            // Apply orientation and remove EXIF/TIFF orientation related keys from metadata
            #if os(macOS)
            let orientInPlace = format == .jpeg2000
            #else
            let orientInPlace = false
            #endif

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
                    tiff[kCGImagePropertyTIFFOrientation] = orientInPlace ? nil : orientation?.rawValue // override orientation
                    imageOptions[kCGImagePropertyTIFFDictionary] = tiff
                }

                // MakerApple
                if let apple = metadata[kCGImagePropertyMakerAppleDictionary] {
                    imageOptions[kCGImagePropertyMakerAppleDictionary] = apple
                }

                // IPTC
                if let iptc = metadata[kCGImagePropertyIPTCDictionary] {
                    imageOptions[kCGImagePropertyIPTCDictionary] = iptc
                }

                // OpenEXR
                if let exr = metadata[kCGImagePropertyOpenEXRDictionary] {
                    imageOptions[kCGImagePropertyOpenEXRDictionary] = exr
                }
            }

            // Orientation
            if let orientation = orientation {
                imageOptions[kCGImagePropertyOrientation] = orientInPlace ? nil : orientation.rawValue
            }

            // Set all frame properties
            CGImageDestinationSetProperties(destination, imageOptions as CFDictionary)

            // Insert all the frames
            lazy var context = CIContext(options: [.highQualityDownsample: true])
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
                var image: CGImage
                if let ciImage = frame.ciImage {
                    // image = context.createCGImage(ciImage, from: ciImage.extent, format: <#T##CIFormat#>, colorSpace: <#T##CGColorSpace?#>)
                    image = context.createCGImage(ciImage, from: ciImage.extent) ?? frame.cgImage!
                } else {
                    image = frame.cgImage!
                }

                #if os(macOS)
                // Color space fallback for JP2
                let colorSpace = format == .jpeg2000 ? CGColorSpace(name: CGColorSpace.sRGB) : image.colorSpace
                #else
                let colorSpace = image.colorSpace
                #endif
                // Orient
                if orientInPlace, let oriented = image.orient(orientation, colorSpace: colorSpace) {
                    image = oriented
                }

                CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
            }

            // Write
            if CGImageDestinationFinalize(destination) == false {
                throw CompressionError.failedToSaveImage
            }
        case .custom(let identifier):
            do {
                // Custom encoder
                try ImageFormat.customFormats[identifier]!.write(
                    frames: frames,
                    to: url,
                    skipMetadata: skipGPSMetadata,
                    settings: settings,
                    orientation: orientation,
                    isHDR: isHDR,
                    primaryIndex: primaryIndex,
                    metadata: metadata
                )
            } catch {
                throw CompressionError.failedToSaveImage
            }
        }
    }

    /// Retvieve image information
    /// - Parameters:
    ///   - source: Input image URL
    /// - Returns: `ImageInfo` object with collected info
    public static func getInfo(source: URL) throws -> ImageInfo {
        // Check source file existence
        if !FileManager.default.fileExists(atPath: source.path) {
            // Also caused by insufficient permissions
            throw CompressionError.sourceFileNotFound
        }

        // Init image source
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw CompressionError.failedToReadImage // unsupportedImageFormat
        }

        // Image format
        var format: ImageFormat?
        let sourceType = CGImageSourceGetType(imageSource) as? String
        if #available(macOS 11, iOS 14, tvOS 14, *), let type = sourceType, let utType = UTType(type), let imageFormat = ImageFormat(utType) {
            // Format by getting image source type
            format = imageFormat
        } else if let sourcePathFormat = ImageFormat(source.pathExtension) {
            // Format using source path extension
            format = sourcePathFormat
        }
        /*guard let format = format else {
            throw CompressionError.unknownImageFormat
        }*/

        // Base properties
        let framesCount = CGImageSourceGetCount(imageSource)
        let primaryIndex = CGImageSourceGetPrimaryImageIndex(imageSource)

        // Variables
        var duration: Double = .zero
        var width: CGFloat?
        var height: CGFloat?
        var hasAlpha: Bool = false
        var isHDR: Bool = false
        var bitDepth = 8
        var orientation: CGImagePropertyOrientation?
        // Loop over all the frames
        for index in 0 ..< framesCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] else { continue }

            // Primary frame properties
            if index == primaryIndex {
                // Resolution
                width = properties[kCGImagePropertyPixelWidth] as? CGFloat
                height = properties[kCGImagePropertyPixelHeight] as? CGFloat

                // Alpha channel
                hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false

                // HDR
                if let depth = properties[kCGImagePropertyDepth] as? Int {
                    bitDepth = depth
                }
                isHDR = bitDepth > 8

                // Orientation
                if let orientationProperty = properties[kCGImagePropertyOrientation] as? UInt32 {
                    orientation = CGImagePropertyOrientation(rawValue: orientationProperty)
                }
            }

            // Frame duration
            var delay: Double?
            if let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                delay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
            } else if let heicsProperties = properties[kCGImagePropertyHEICSDictionary] as? [CFString: Any] {
                delay = heicsProperties[kCGImagePropertyHEICSDelayTime] as? Double
            } else if #available(macOS 11, iOS 14, tvOS 14, *), let webPProperties = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
                delay = webPProperties[kCGImagePropertyWebPDelayTime] as? Double
            } else if let pngProperties = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
                delay = pngProperties[kCGImagePropertyAPNGDelayTime] as? Double
            }
            duration += delay ?? .zero
        }

        // Frame rate
        var frameRate: Int?
        if duration != .zero {
            let nominalFrameRate = Double(framesCount) / duration
            frameRate = Int(nominalFrameRate.rounded())
        }

        return ImageInfo(
            format: format,
            size: CGSize(width: width ?? .zero, height: height ?? .zero),
            hasAlpha: hasAlpha,
            isHDR: isHDR,
            bitDepth: bitDepth,
            orientation: orientation,
            framesCount: framesCount,
            frameRate: frameRate,
            duration: duration != .zero ? duration : nil
        )
    }
}
