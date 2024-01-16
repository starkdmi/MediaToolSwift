import CoreVideo
import CoreImage
import AVFoundation

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
        cropRect: CGRect?,
        transform: CGAffineTransform?,
        pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
        colorInfo: VideoColorInformation?,
        context: CIContext?
    ) -> CVPixelBuffer? {
        autoreleasepool {
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
            case .image, .cgImage, .vImage:
                // Initialize an empty pixel buffer using existing pixel buffer pool
                let status = CVPixelBufferPoolCreatePixelBuffer(
                    kCFAllocatorDefault,
                    pixelBufferPool,
                    &outputPixelBuffer
                )
                guard status == noErr else { return nil }

                switch processor {
                case .image(let imageProcessor):
                    // Init `CIImage`
                    var image = CIImage(cvPixelBuffer: pixelBuffer)

                    // Invert video transformation
                    if let transform = transform {
                        image = image.transformed(by: transform.inverted())
                        image = image.transformed(by: .init(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
                    }

                    // Apply cropping
                    if let cropRect = cropRect {
                        image = image
                            .cropped(to: cropRect)
                            .transformed(by: .init(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
                    }

                    // Execute image processor
                    let outputImage = imageProcessor(image, context!, timeInSeconds)
                    guard var outputImage = outputImage else { return nil }

                    // Transform back
                    if let transform = transform {
                        outputImage = outputImage.transformed(by: transform)
                        outputImage = outputImage
                            .transformed(by: .init(translationX: -outputImage.extent.origin.x, y: -outputImage.extent.origin.y))
                    }

                    // Rendrer image to the new pixel buffer
                    context!.render(outputImage, to: outputPixelBuffer!, bounds: outputImage.extent, colorSpace: image.colorSpace)
                case .cgImage(let cgImageProcessor):
                    // TODO: CGImage processor
                    // Create CGImage using VTCreateCGImageFromCVPixelBuffer(pixelBuffer, NULL, &cgImage)
                    // Transform (if required) CGImage
                    if let cropRect = cropRect {
                        // Crop CGImage
                    }
                    // Run custom cgImageProcessor
                    // Write CGImage to outputPixelBuffer
                    fatalError("CGImage processor is not implemented yet")
                case .vImage(let vImageProcessor):
                    // TODO: vImage processor
                    // https://developer.apple.com/documentation/accelerate/applying_vimage_operations_to_video_sample_buffers
                    // https://developer.apple.com/documentation/accelerate/core_video_interoperability
                    // https://developer.apple.com/documentation/accelerate/core_video_interoperability
                    // https://developer.apple.com/documentation/accelerate/using_vimage_pixel_buffers_to_generate_video_effects#4225030
                    // https://developer.apple.com/documentation/accelerate/integrating_vimage_pixel_buffers_into_a_core_image_workflow
                    // Init vImage_Buffer from pixelBuffer (vImageBuffer_InitWithCVPixelBuffer)
                    // Transform (if required) using transform(CGAffineTransform, backgroundColor: Pixel_8?, destination: vImage.PixelBuffer<Format>)
                    if let cropRect = cropRect {
                        // Crop vImage_Buffer using ImageTool helpers
                    }
                    // Run custom vImageProcessor
                    // Copy buffer to outputPixelBuffer (vImageBuffer_CopyToCVPixelBuffer)
                    fatalError("vImage processor is not implemented yet")
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
