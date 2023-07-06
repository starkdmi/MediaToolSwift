import Foundation
import AVFoundation
#if os(iOS) || os(tvOS)
import MobileCoreServices
#endif

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
            if #available(macOS 11, iOS 14, tvOS 14, *) {
                return UTType.png.identifier as CFString
            } else {
                return kUTTypePNG
            }
        case .jpeg:
            if #available(macOS 11, iOS 14, tvOS 14, *) {
                return UTType.jpeg.identifier as CFString
            } else {
                return kUTTypeJPEG
            }
        #if os(macOS)
        case .jpeg2000:
            return kUTTypeJPEG2000 // public.jpeg-2000
        #endif
        case .gif:
            if #available(macOS 11, iOS 14, tvOS 14, *) {
                return UTType.gif.identifier as CFString
            } else {
                return kUTTypeGIF
            }
        case .tiff:
            if #available(macOS 11, iOS 14, tvOS 14, *) {
                return UTType.tiff.identifier as CFString
            } else {
                return kUTTypeTIFF
            }
        case .bmp:
            if #available(macOS 11, iOS 14, tvOS 14, *) {
                return UTType.bmp.identifier as CFString
            } else {
                return kUTTypeBMP
            }
        case .ico:
            if #available(macOS 11, iOS 14, tvOS 14, *) {
                return UTType.ico.identifier as CFString
            } else {
                return kUTTypeICO
            }
        }
    }

    /// Init `ImageFormat` using corresponding `UTType`
    @available(macOS 11, iOS 14, tvOS 14, *)
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

    /// Init `ImageFormat` using file extension
    public init?(_ filenameExtension: String) {
        if #available(macOS 11, iOS 14, tvOS 14, *) {
            if let type = UTType(filenameExtension: filenameExtension), let format = ImageFormat(type) {
                self = format
            } else {
                return nil
            }
        } else {
            // Fallback on earlier versions
            if let identifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, filenameExtension as CFString, nil)?.takeRetainedValue(),
                let value = ImageFormat.allCases.first(where: { format in
                if let cfString = format.rawValue, cfString == identifier {
                    return true
                }
                return false
            }) {
                self = value
            } else {
                return nil
            }
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
