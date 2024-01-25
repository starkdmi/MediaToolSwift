import CoreGraphics

/// Extensions on `CGContext`
internal extension CGContext {
    /// Create `CGContext` from `CGImage`
    static func make(
        _ image: CGImage,
        width: Int? = nil,
        height: Int? = nil,
        colorSpace: CGColorSpace? = nil,
        bitmapInfo: CGBitmapInfo? = nil
    ) -> CGContext? {
        let colorSpace = colorSpace ?? image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = bitmapInfo ?? image.bitmapInfo // CGBitmapInfo(rawValue: self.bitmapInfo.rawValue | self.alphaInfo.rawValue)
        /*var alphaInfo: CGImageAlphaInfo?

        // Fix 10 bit HDR image
        if image.bitsPerComponent == 10, let sRGB = CGColorSpace(name: CGColorSpace.extendedSRGB) {
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGImagePixelFormatInfo.RGBCIF10.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            colorSpace = sRGB
        }

        // Fix alpha (only 4 pixel formats supported for 8 bit per component)
        if image.bitsPerComponent == 8 {
            if image.alphaInfo == .first {
                alphaInfo = .premultipliedFirst
                bitmapInfo.remove(.alphaInfoMask)
                bitmapInfo.insert(CGBitmapInfo(rawValue: alphaInfo!.rawValue))
            } else if image.alphaInfo == .last {
                alphaInfo = .premultipliedLast
                bitmapInfo.remove(.alphaInfoMask)
                bitmapInfo.insert(CGBitmapInfo(rawValue: alphaInfo!.rawValue))
            } else if image.alphaInfo == .none {
                alphaInfo = .noneSkipLast
                bitmapInfo.remove(.alphaInfoMask)
                bitmapInfo.insert(CGBitmapInfo(rawValue: alphaInfo!.rawValue))
            }
        }*/

        // Check if image supported by Core Graphics
        // guard image.hasCGContextSupportedPixelFormat(colorSpace: colorSpace, alphaInfo: alphaInfo) else { return nil }

        let context = CGContext(
            data: nil,
            width: width ?? image.width,
            height: height ?? image.height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0, // self.bytesPerRow, 0 equals to auto
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
        context?.interpolationQuality = .high

        return context
    }
}
