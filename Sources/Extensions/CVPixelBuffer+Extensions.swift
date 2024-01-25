import CoreVideo
import CoreImage
import AVFoundation
import VideoToolbox

/// Public extensions on `CVPixelBuffer`
/*public extension CVPixelBuffer {
    /// Initialize an empty pixel buffer with specified size and pixel format
    static func create(with size: CGSize, pixelFormat: OSType?) -> CVPixelBuffer? {
        var cvPixelBuffer: CVPixelBuffer?

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            pixelFormat ?? kCVPixelFormatType_32BGRA,
            nil,
            &cvPixelBuffer
        )

        return status == kCVReturnSuccess ? cvPixelBuffer : nil
    }

    /// Initialize an empty pixel buffer using existing pixel buffer pool
    static func create(pixelBufferPool: CVPixelBufferPool) -> CVPixelBuffer? {
        var cvPixelBuffer: CVPixelBuffer?

        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pixelBufferPool,
            &cvPixelBuffer
        )

        return status == kCVReturnSuccess ? cvPixelBuffer : nil
    }
}*/

/// Private extensions on `CVPixelBuffer`
internal extension CVPixelBuffer {
    /// Modify `CMSampleBuffer` using `VideoFrameProcessor`
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
        autoreleasepool { // () throws -> Optional<CVBuffer> in
            let timeInSeconds = presentationTimeStamp.seconds

            // Confirm pixel buffer pool is ready
            guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else { return nil }

            // Convert `CMSampleBuffer` to `CVPixelBuffer`
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
            // let width = CVPixelBufferGetWidth(pixelBuffer)
            // let height = CVPixelBufferGetHeight(pixelBuffer)

            // Lock & unlock source buffer
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
            }

            var outputPixelBuffer: CVPixelBuffer?
            switch processor {
            case .image: // .cgImage, .vImage
                // Initialize an empty pixel buffer using existing pixel buffer pool
                let status = CVPixelBufferPoolCreatePixelBuffer(
                    kCFAllocatorDefault,
                    pixelBufferPool,
                    &outputPixelBuffer
                )
                guard status == noErr, outputPixelBuffer != nil else { return nil }

                // Lock & unlock output buffer
                CVPixelBufferLockBaseAddress(outputPixelBuffer!, CVPixelBufferLockFlags.readOnly)
                defer {
                    CVPixelBufferUnlockBaseAddress(outputPixelBuffer!, CVPixelBufferLockFlags.readOnly)
                }

                switch processor {
                case .image(let imageProcessor):
                    // Init `CIImage`
                    var image = CIImage(cvPixelBuffer: pixelBuffer)
                    let colorSpace = image.colorSpace

                    // Invert video transformation
                    if let transform = transform {
                        image = image.transformed(by: transform.inverted())
                        image = image.transformed(by: .init(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
                    }

                    // Crop
                    if let cropRect = cropRect {
                        image = image.cropping(to: cropRect)
                    }

                    // Fit (preserve aspect ratio)
                    if case .fit = videoSize {
                        image = image.resizing(to: targetSize)
                    }

                    // Execute image processor
                    let outputImage = imageProcessor(image, context!, timeInSeconds)
                    guard var outputImage = outputImage else { return nil }

                    // Scale (also used to fix size after processing for original/fit modes)
                    let size = outputImage.extent.size
                    if size != targetSize {
                        outputImage = outputImage.resizing(to: targetSize)
                    }

                    // Transform back
                    if let transform = transform {
                        outputImage = outputImage.transformed(by: transform)
                        outputImage = outputImage
                            .transformed(by: .init(translationX: -outputImage.extent.origin.x, y: -outputImage.extent.origin.y))
                    }

                    // Render image to the new pixel buffer
                    context!.render(outputImage, to: outputPixelBuffer!, bounds: outputImage.extent, colorSpace: colorSpace)
                // MARK: CGImage Processor
                // case .cgImage(let cgImageProcessor):
                    // Warning: No HDR and partial Alpha Channel support

                    // Load CGImage from CVPixelBuffer
                    // Consider setting kCVPixelBufferCGImageCompatibilityKey and kCVPixelBufferCGBitmapContextCompatibilityKey in sourcePixelBufferAttributes
                    /*var cgImage: CGImage?
                    let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
                    guard status == noErr, var cgImage = cgImage else { return nil }*/

                    // Init image context
                    /*guard let context = CGContext(
                        data: CVPixelBufferGetBaseAddress(outputPixelBuffer!),
                        width: targetSize.width,
                        height: targetSize.height,
                        bitsPerComponent: cgImage.bitsPerComponent,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(outputPixelBuffer!),
                        space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: cgImage.bitmapInfo.rawValue
                    ) else {
                        return nil
                    }
                    context.interpolationQuality = .high*/

                    // Transform (rotate, if needed)
                    // Crop
                    // Fit
                    // Run custom CGImage processor
                    // Scale
                    // Transform back (if needed)

                    // Write CGImage to outputPixelBuffer:
                    // context.draw(cgImage, in: CGRect(origin: .zero, size: cgImage.size))
                // MARK: vImage Processor
                // case .vImage(let vImageProcessor):
                    // https://developer.apple.com/documentation/accelerate/applying_vimage_operations_to_video_sample_buffers
                    // https://developer.apple.com/documentation/accelerate/core_video_interoperability
                    // https://developer.apple.com/documentation/accelerate/core_video_interoperability
                    // https://developer.apple.com/documentation/accelerate/using_vimage_pixel_buffers_to_generate_video_effects#4225030
                    // https://developer.apple.com/documentation/accelerate/integrating_vimage_pixel_buffers_into_a_core_image_workflow
                    // Init vImage_Buffer from pixelBuffer (vImageBuffer_InitWithCVPixelBuffer)
                    // Transform (if required) using transform(CGAffineTransform, backgroundColor: Pixel_8?, destination: vImage.PixelBuffer<Format>)
                    // Crop vImage_Buffer using ImageTool helpers
                    // Fit (when videoSize == .fit) - vImage+Extensions & https://nshipster.com/image-resizing/#technique-5-image-scaling-with-vimage
                    // Run custom vImageProcessor
                    // Scale
                    // Copy buffer to outputPixelBuffer (vImageBuffer_CopyToCVPixelBuffer)
                default:
                    return nil
                }
            case .pixelBuffer(let pixelBufferProcessor):
                // Execute custom pixel buffer processor
                outputPixelBuffer = pixelBufferProcessor(pixelBuffer, pixelBufferPool, context!, timeInSeconds)
            default:
                return nil
            }
            guard let outputPixelBuffer = outputPixelBuffer else { return nil }

            // Tag pixel buffer with video color information
            // https://developer.apple.com/documentation/avfoundation/media_reading_and_writing/tagging_media_with_video_color_information
            if let colorInfo = colorInfo {
                CVBufferSetAttachments(outputPixelBuffer, [
                    kCVImageBufferColorPrimariesKey: colorInfo.colorPrimaries,
                    kCVImageBufferYCbCrMatrixKey: colorInfo.matrix,
                    kCVImageBufferTransferFunctionKey: colorInfo.transferFunction
                ] as CFDictionary, .shouldPropagate)
            }

            // Convert `CVPixelBuffer` to `CMSampleBuffer`
            /*var formatDescription: CMFormatDescription!
            let createFormatDescriptionStatus = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: outputPixelBuffer!,
                formatDescriptionOut: &formatDescription
            )
            guard createFormatDescriptionStatus == noErr else { return nil }

            // Recreate timing info
            var timingInfo = CMSampleTimingInfo()
            timingInfo.duration = CMSampleBufferGetDuration(sampleBuffer)
            timingInfo.presentationTimeStamp = presentationTimeStamp
            timingInfo.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)

            // Create `CMSampleBuffer`
            var sampleBuffer: CMSampleBuffer!
            let createSampleBufferStatus = CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: outputPixelBuffer!,
                formatDescription: formatDescription,
                sampleTiming: &timingInfo,
                sampleBufferOut: &sampleBuffer
            )

            return createSampleBufferStatus == noErr ? sampleBuffer : nil*/

            return outputPixelBuffer
        }
    }
}
