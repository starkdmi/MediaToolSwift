import CoreMedia

/// Extensions on `CMSampleBuffer`
internal extension CMSampleBuffer {
    /// Modify `CMSampleBuffer` by executing `PixelBufferProcessor` handler on`CVPixelBuffer`
    func editingPixelBuffer(_ handler: PixelBufferProcessor) -> CMSampleBuffer {
        // Convert `CMSampleBuffer` to `CVPixelBuffer`
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(self) else {
            return self
        }

        CVPixelBufferLockBaseAddress(
            pixelBuffer,
            CVPixelBufferLockFlags.readOnly)

        // Run custom pixel buffer modifier
        let processedPixelBuffer = handler(pixelBuffer)

        CVPixelBufferUnlockBaseAddress(
            pixelBuffer,
            CVPixelBufferLockFlags.readOnly)

        // Convert `CVPixelBuffer` to `CMSampleBuffer`
        var formatDescription: CMFormatDescription!
        let createFormatDescriptionStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: processedPixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard createFormatDescriptionStatus == noErr else { return self }

        // Recreate timing info
        var timingInfo = CMSampleTimingInfo()
        timingInfo.duration = CMSampleBufferGetDuration(self)
        timingInfo.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(self)
        timingInfo.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(self)

        // Create `CMSampleBuffer`
        var sampleBuffer: CMSampleBuffer!
        let createSampleBufferStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: processedPixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        return createSampleBufferStatus == noErr ? sampleBuffer : self
    }
}
