import Foundation
import AVFoundation
#if os(iOS) || os(tvOS)
import MobileCoreServices
#endif

/// Image formats, only formats with encoding/writing support are included
public enum ImageFormat: String, CaseIterable {
    /// HEIC (HEIF with HEVC compression) image format
    case heif

    /// HEIF 10 bit image format
    case heif10

    /// HEIC format with the QuickTime 'nclc' profile
    case heic

    /// HEIFS (HEIC sequence) image format
    /// Warning: Displayed darker in macOS Preview app
    case heics

    /// PNG image format, with support of animated images (APNG)
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

    /// Decoding of static and animated images is supported by Apple
    /// The encoding implemented in separate `plus` branch - https://github.com/starkdmi/MediaToolSwift/tree/plus
    // case webp // UTType.webP

    /// Corresponding `kUTType`
    public var utType: CFString? {
        switch self {
        case .heif, .heif10, .heic:
            return AVFileType.heic as CFString
        case .heics:
            return "public.heics" as CFString
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

    /// Init `ImageFormat` using UTType CFString
    /// Warning: `ImageFormat.heif` is returned for all the HEIF related formats
    public init?(_ cfString: CFString) {
        if let format = ImageFormat.allCases.first(where: { format in
            if let utType = format.utType, utType == cfString {
                return true
            }
            return false
        }) {
            self = format
        } else {
            return nil
        }
    }

    /// Init `ImageFormat` using corresponding `UTType`
    @available(macOS 11, iOS 14, tvOS 14, *)
    public init?(_ type: UTType) {
        if let format = Self(type.identifier as CFString) {
            self = format
        } else {
            return nil
        }
    }

    /// Init `ImageFormat` using file extension
    public init?(_ filenameExtension: String) {
        // Extension `.heif` isn't associated with HEIF image internally
        var filenameExtension = filenameExtension
        if filenameExtension == "heif" {
            filenameExtension = "heic"
        }

        if #available(macOS 11, iOS 14, tvOS 14, *) {
            if let type = UTType(filenameExtension: filenameExtension), let format = ImageFormat(type) {
                self = format
            } else {
                return nil
            }
        } else {
            // Fallback on earlier versions
            let utType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, filenameExtension as CFString, nil)?.takeRetainedValue()
            if let utType = utType, let format = ImageFormat(utType) {
                self = format
            } else {
                return nil
            }
        }
    }

    /// Indicator of animation supported format
    internal var isAnimationSupported: Bool {
        return self == .gif || self == .heics || self == .png
    }

    /// Format works in old color format and low quality
    internal var isLowQuality: Bool {
        #if os(macOS)
        return self == .gif || self == .jpeg2000
        #else
        return self == .gif
        #endif
    }
}
