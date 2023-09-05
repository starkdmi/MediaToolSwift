import CoreImage
import CoreGraphics

/// Extensions on`CIFormat`
internal extension CIFormat {
    /// Detect `CIFormat` of image
    static func from(
        bitsPerPixel: Int,
        bitsPerComponent: Int,
        pixelFormat: ImagePixelFormat,
        hasAlpha: Bool,
        isFloatPoint: Bool,
        containsAuxiliary: Bool // auxiliary information
    ) -> CIFormat? {
        switch (bitsPerPixel, bitsPerComponent, pixelFormat, hasAlpha, isFloatPoint, containsAuxiliary) {
        case (32, 8, .abgr, _, false, false):
            // A 32-bit-per-pixel, fixed-point pixel format (kCVPixelFormatType_32ABGR)
            return .ABGR8
        case (32, 8, .argb, _, false, false):
            // A 32-bit-per-pixel, fixed-point pixel format (kCVPixelFormatType_32ARGB)
            return .ARGB8
        case (32, 8, .bgra, _, false, false):
            // A 32-bit-per-pixel, fixed-point pixel format (kCVPixelFormatType_32BGRA)
            return .BGRA8
        case (32, 8, .rgba, _, false, false):
            // A 32-bit-per-pixel, fixed-point pixel format (kCVPixelFormatType_32RGBA)
            return .RGBA8
        case (64, 16, .rgba, _, false, false):
            // A 64-bit-per-pixel, fixed-point pixel format
            return .RGBA16
        case (64, 16, .rgba, _, true, false):
            // A 64-bit-per-pixel, floating-point pixel format
            return .RGBAh
        case (128, 32, .rgba, _, true, false):
            // A 128-bit-per-pixel, floating-point pixel format
            return .RGBAf
        default:
            break
        }

        /*if #available(macOS 11, iOS 14.2, tvOS 14.2, *) {
            switch (bitsPerPixel, bitsPerComponent, pixelFormat, hasAlpha, isFloatPoint, containsAuxiliary) {
            case (64, 16, _, false, false, true):
                // A 64-bit-per-pixel, fixed-point pixel format
                return .RGBX16
            default:
                break
            }
        }*/

        /*if #available(macOS 14, iOS 17, tvOS 17, *) {
            switch (bitsPerPixel, bitsPerComponent, pixelFormat, hasAlpha, isFloatPoint, containsAuxiliary) {
            case (32, 10, _, false, false, false):
                // A 32-bit-per-pixel, 10 bit-per-component, fixed-point pixel format
                return .RGB10
            case (64, 16, _, false, true, true):
                // A 64-bit-per-pixel, floating-point pixel format, contains auxiliary information
                return .rgbXh
            case (128, 32, _, false, true, true):
                // A 128-bit-per-pixel, floating-point pixel format, contains auxiliary information
                return .rgbXf
            default:
                break
            }
        }*/

        return nil
    }

    /// Find `CIFormat` for output in hard-coded channel order
    static func `for`(bitsPerPixel: Int?, bitsPerComponent: Int, hasAlpha: Bool, isFloatPoint: Bool) -> CIFormat? {
        var bitsPerPixel = bitsPerPixel
        if bitsPerPixel == nil {
            if bitsPerComponent <= 8 {
                bitsPerPixel = 32
            } /*lse if bitsPerComponent <= 10 {
                bitsPerPixel = 32 // 64
            }*/ else if bitsPerComponent <= 16 {
                bitsPerPixel = 64
            } else {
                bitsPerPixel = 128
            }
        }

        switch (bitsPerPixel, bitsPerComponent, hasAlpha, isFloatPoint) {
        case (32, let depth, _, false) where depth <= 8:
            // A 32-bit-per-pixel, fixed-point pixel format
            return .RGBA8
        /*case (32, 10, false, false):
            // A 32-bit-per-pixel, 10 bit-per-component, fixed-point pixel format
            return CIFormat(rawValue: Int32(CGImagePixelFormatInfo.RGBCIF10.rawValue))
        case (32, 10, true, false):
            // A 32-bit-per-pixel, 10 bit-per-component, fixed-point pixel format, alpha != none
            return CIFormat(rawValue: Int32(CGImagePixelFormatInfo.RGB101010.rawValue))*/
        case (64, let depth, _, false) where depth <= 16:
            // A 64-bit-per-pixel, fixed-point pixel format
            return .RGBA16
        case (64, let depth, _, true) where depth <= 16:
            // A 64-bit-per-pixel, floating-point pixel format
            return .RGBAh
        case (128, _, _, true):
            // A 128-bit-per-pixel, floating-point pixel format
            return .RGBAf
        default:
            return nil
        }
    }
}
