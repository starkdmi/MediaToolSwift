import Foundation
import AVFoundation
// import UniformTypeIdentifiers

/// Image formats
public enum ImageFormat: CaseIterable {
    /// HEIF image format
    case heif

    /// HEIF 10 bit image format
    case heif10

    /// HEIC sequence image format
    // case heics // UTType("public.heics")

    /// PNG image format
    case png

    /// JPEG image format
    case jpeg

    /// JPEG 2000 image format
    #if os(macOS)
    case jpeg2000
    #endif

    /// GIF image format
    case gif

    /// Tag Image File Format
    case tiff

    /// Bitmap image format
    case bmp

    /// Icon image format, squared only with 6, 32, 48, 128, or 256 pixels wide
    case ico

    /// Corresponding `kUTType`
    public var rawValue: CFString? {
        switch self {
        case .heif, .heif10:
            return nil
        case .png:
            return UTType.png.identifier as CFString // kUTTypePNG
        case .jpeg:
            return UTType.jpeg.identifier as CFString // kUTTypeJPEG
        #if os(macOS)
        case .jpeg2000:
            return kUTTypeJPEG2000 // public.jpeg-2000
        #endif
        case .gif:
            return UTType.gif.identifier as CFString // kUTTypeGIF
        case .tiff:
            return UTType.tiff.identifier as CFString // kUTTypeTIFF
        case .bmp:
            return UTType.bmp.identifier as CFString // kUTTypeBMP
        case .ico:
            return UTType.ico.identifier as CFString // kUTTypeICO
        }
    }

    /// Init `ImageFormat` using corresponding `UTType`
    public init?(_ type: UTType) {
        if let value = ImageFormat.allCases.first(where: { format in
            if let cfString = format.rawValue, cfString == (type.identifier as CFString) {
                return true
            }
            return false
        }) {
            self = value
        } else {
            return nil
        }
    }

    // MARK: Animated Images

    /// APNG and GIF built-in support (?) - https://developer.apple.com/documentation/imageio/3333271-cganimateimageaturlwithblock
    /// WebP 3-rd party encoders:
    /// https://github.com/SDWebImage/SDWebImageWebPCoder - animated supported
    /// https://github.com/ainame/Swift-WebP - no animated sequence support
    /// https://github.com/awxkee/webp.swift - animated supported
    /// https://github.com/TimOliver/WebPKit - no animated sequence support
}
