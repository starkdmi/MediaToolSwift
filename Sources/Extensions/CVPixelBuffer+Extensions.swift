import CoreVideo
import CoreImage
import AVFoundation
import VideoToolbox

// MARK: - Pixel Buffer Creation

internal extension CVPixelBuffer {

    /// Creates a pixel buffer from a pool
    /// - Parameter pool: The pixel buffer pool to create from
    /// - Returns: A new pixel buffer, or nil if creation failed
    static func create(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pool,
            &pixelBuffer
        )
        return status == noErr ? pixelBuffer : nil
    }
}

// MARK: - Buffer Locking

internal extension CVPixelBuffer {

    /// Locks the pixel buffer for reading
    func lockForReading() {
        CVPixelBufferLockBaseAddress(self, .readOnly)
    }

    /// Unlocks the pixel buffer from reading
    func unlockFromReading() {
        CVPixelBufferUnlockBaseAddress(self, .readOnly)
    }

}

// MARK: - Color Information Tagging

internal extension CVPixelBuffer {

    /// Tags the pixel buffer with video color information
    /// - Parameter colorInfo: The color information to apply
    func tagWithColorInfo(_ colorInfo: VideoColorInformation) {
        CVBufferSetAttachments(self, [
            kCVImageBufferColorPrimariesKey: colorInfo.colorPrimaries,
            kCVImageBufferYCbCrMatrixKey: colorInfo.matrix,
            kCVImageBufferTransferFunctionKey: colorInfo.transferFunction
        ] as CFDictionary, .shouldPropagate)
    }
}

// MARK: - Image Processing

internal extension CVPixelBuffer {

    /// Processes a CIImage with the given configuration
    /// - Parameters:
    ///   - image: The source CIImage
    ///   - transform: Optional transform to apply
    ///   - cropRect: Optional crop rectangle
    ///   - videoSize: The video size mode
    ///   - targetSize: The target output size
    ///   - imageProcessor: The image processor function
    ///   - context: The CIContext for processing
    ///   - timeInSeconds: The presentation time in seconds
    /// - Returns: The processed CIImage, or nil if processing failed
    static func processImage(
        _ image: CIImage,
        transform: CGAffineTransform?,
        cropRect: CGRect?,
        videoSize: CompressionVideoSize,
        targetSize: CGSize,
        imageProcessor: (CIImage, CIContext, Double) -> CIImage?,
        context: CIContext,
        timeInSeconds: Double
    ) -> CIImage? {
        var processedImage = image

        // Invert video transformation
        if let transform = transform {
            processedImage = processedImage.transformed(by: transform.inverted())
            processedImage = processedImage.transformed(
                by: .init(translationX: -processedImage.extent.origin.x, y: -processedImage.extent.origin.y)
            )
        }

        // Crop
        if let cropRect = cropRect {
            processedImage = processedImage.cropping(to: cropRect)
        }

        // Fit (preserve aspect ratio)
        if case .fit = videoSize {
            processedImage = processedImage.resizing(to: targetSize)
        }

        // Execute image processor
        guard var outputImage = imageProcessor(processedImage, context, timeInSeconds) else {
            return nil
        }

        // Scale (also used to fix size after processing for original/fit modes)
        let size = outputImage.extent.size
        if size != targetSize {
            outputImage = outputImage.resizing(to: targetSize)
        }

        // Transform back
        if let transform = transform {
            outputImage = outputImage.transformed(by: transform)
            outputImage = outputImage.transformed(
                by: .init(translationX: -outputImage.extent.origin.x, y: -outputImage.extent.origin.y)
            )
        }

        return outputImage
    }
}

// MARK: - Sample Buffer Processing

internal extension CVPixelBuffer {

    /// Modify `CMSampleBuffer` using `VideoFrameProcessor`
    /// - Parameters:
    ///   - sampleBuffer: The source sample buffer
    ///   - presentationTimeStamp: The presentation timestamp
    ///   - processor: The video frame processor
    ///   - videoSize: The video size mode
    ///   - targetSize: The target output size
    ///   - cropRect: Optional crop rectangle
    ///   - transform: Optional transform to apply
    ///   - pixelBufferAdaptor: The pixel buffer adaptor
    ///   - colorInfo: Optional color information to tag
    ///   - context: The CIContext for processing
    /// - Returns: The processed pixel buffer, or nil if processing failed
    static func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        presentationTimeStamp: CMTime,
        processor: VideoFrameProcessor,
        videoSize: CompressionVideoSize,
        targetSize: CGSize,
        cropRect: CGRect?,
        transform: CGAffineTransform?,
        pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
        colorInfo: VideoColorInformation?,
        context: CIContext?
    ) -> CVPixelBuffer? {
        autoreleasepool {
            let timeInSeconds = presentationTimeStamp.seconds

            // Validate pixel buffer pool
            guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
                return nil
            }

            // Get source pixel buffer
            guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return nil
            }

            // Process based on processor type
            let outputPixelBuffer: CVPixelBuffer?

            sourcePixelBuffer.lockForReading()
            defer { sourcePixelBuffer.unlockFromReading() }

            switch processor {
            case .image(let imageProcessor):
                outputPixelBuffer = processWithImageProcessor(
                    sourcePixelBuffer: sourcePixelBuffer,
                    pixelBufferPool: pixelBufferPool,
                    imageProcessor: imageProcessor,
                    transform: transform,
                    cropRect: cropRect,
                    videoSize: videoSize,
                    targetSize: targetSize,
                    context: context!,
                    timeInSeconds: timeInSeconds
                )

            case .pixelBuffer(let pixelBufferProcessor):
                outputPixelBuffer = pixelBufferProcessor(
                    sourcePixelBuffer,
                    pixelBufferPool,
                    context!,
                    timeInSeconds
                )

            default:
                return nil
            }

            // Apply color info if provided
            if let output = outputPixelBuffer, let colorInfo = colorInfo {
                output.tagWithColorInfo(colorInfo)
            }

            return outputPixelBuffer
        }
    }

    /// Processes a pixel buffer using a CIImage-based processor
    private static func processWithImageProcessor(
        sourcePixelBuffer: CVPixelBuffer,
        pixelBufferPool: CVPixelBufferPool,
        imageProcessor: @escaping (CIImage, CIContext, Double) -> CIImage?,
        transform: CGAffineTransform?,
        cropRect: CGRect?,
        videoSize: CompressionVideoSize,
        targetSize: CGSize,
        context: CIContext,
        timeInSeconds: Double
    ) -> CVPixelBuffer? {
        // Create output pixel buffer
        guard let outputPixelBuffer = CVPixelBuffer.create(from: pixelBufferPool) else {
            return nil
        }

        // Create CIImage from source
        let sourceImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
        let colorSpace = sourceImage.colorSpace

        // Process the image
        guard let processedImage = CVPixelBuffer.processImage(
            sourceImage,
            transform: transform,
            cropRect: cropRect,
            videoSize: videoSize,
            targetSize: targetSize,
            imageProcessor: imageProcessor,
            context: context,
            timeInSeconds: timeInSeconds
        ) else {
            return nil
        }

        // Render to output buffer
        context.render(
            processedImage,
            to: outputPixelBuffer,
            bounds: processedImage.extent,
            colorSpace: colorSpace
        )

        return outputPixelBuffer
    }
}
