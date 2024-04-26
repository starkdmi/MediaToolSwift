import Foundation
import AVFoundation
#if os(iOS) || os(tvOS) || os(visionOS)
import MobileCoreServices
#endif

/// Custom image encoder
public protocol CustomImageFormat {
    /// Type ID, should be unique for each custom format
    var identifier: String { get }

    /// Corresponding `kUTType`,  should be unique per format
    var utType: CFString? { get }

    /// Indicator of animation supported format
    var isAnimationSupported: Bool { get }

    /// Format works in old color format and low quality
    var isLowQuality: Bool { get }

    /// Encode and write an image to the file
    func write(
        frames: [ImageFrame],
        to url: URL,
        skipMetadata: Bool,
        settings: ImageSettings,
        orientation: CGImagePropertyOrientation?,
        isHDR: Bool?,
        primaryIndex: Int,
        metadata: [CFString: Any]?
    ) throws
}

/// Image formats, only formats with encoding/writing support are included
public enum ImageFormat: Hashable, Equatable {
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

    /// Adobe PDF format
    case pdf

    /// Custom image format, should be a registered format
    case custom(String)

    /// Predefined formats
    #if os(macOS)
    internal static var allFormats: [ImageFormat] = [
        .heif, .heif10, .heic, .heics, .png, .jpeg, .jpeg2000, .gif, .tiff, .bmp, .ico, .pdf
    ]
    #else
    internal static var allFormats: [ImageFormat] = [
        .heif, .heif10, .heic, .heics, .png, .jpeg, .gif, .tiff, .bmp, .ico, .pdf
    ]
    #endif

    /// Registered custom  formats
    internal static var customFormats: [String: any CustomImageFormat] = [:]

    /// Register custom image format
    public static func registerCustomFormat(_ format: any CustomImageFormat) {
        let identifier = format.identifier
        Self.customFormats[identifier] = format
        Self.allFormats.append(.custom(identifier))
    }

    /// Equatable conformance
    public static func == (lhs: ImageFormat, rhs: ImageFormat) -> Bool {
        switch (lhs, rhs) {
        case (.heif, .heif): return true
        case (.heif10, .heif10): return true
        case (.heic, .heic): return true
        case (.heics, .heics): return true
        case (.png, .png): return true
        case (.jpeg, .jpeg): return true
        #if os(macOS)
        case (.jpeg2000, .jpeg2000): return true
        #endif
        case (.gif, .gif): return true
        case (.tiff, .tiff): return true
        case (.bmp, .bmp): return true
        case (.ico, .ico): return true
        case (.pdf, .pdf): return true
        case (.custom(let lhsFormatId), .custom(let rhsFormatId)):
            return lhsFormatId == rhsFormatId
        default: return false
        }
    }

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(utType)
    }

    /// Corresponding `kUTType`
    public var utType: CFString? {
        switch self {
        case .heif, .heif10, .heic:
            return AVFileType.heic as CFString
        case .heics:
            return "public.heics" as CFString
        case .png:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.png.identifier as CFString
            } else {
                return kUTTypePNG
            }
        case .jpeg:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.jpeg.identifier as CFString
            } else {
                return kUTTypeJPEG
            }
        #if os(macOS)
        case .jpeg2000:
            return kUTTypeJPEG2000 // public.jpeg-2000
        #endif
        case .gif:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.gif.identifier as CFString
            } else {
                return kUTTypeGIF
            }
        case .tiff:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.tiff.identifier as CFString
            } else {
                return kUTTypeTIFF
            }
        case .bmp:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.bmp.identifier as CFString
            } else {
                return kUTTypeBMP
            }
        case .ico:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.ico.identifier as CFString
            } else {
                return kUTTypeICO
            }
        case .pdf:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.pdf.identifier as CFString
            } else {
                return kUTTypePDF
            }
        case .custom(let identifier):
            return Self.customFormats[identifier]?.utType
        }
    }

    /// Init `ImageFormat` using UTType CFString
    /// Warning: `ImageFormat.heif` is returned for all the HEIF related formats
    public init?(_ cfString: CFString) {
        if let format = ImageFormat.allFormats.first(where: { format in
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
    public init?(_ fileExtension: String) {
        // Extension `.heif` isn't associated with HEIF image internally
        var filenameExtension = fileExtension
        if filenameExtension == "heif" {
            filenameExtension = "heic"
        }

        if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
            if let type = UTType(filenameExtension: filenameExtension), let format = ImageFormat(type) {
                if format == .heif, fileExtension == "heic" { // type == .heic
                    // Fix `.heic` file extension recognized as `.heif` format
                    self = .heic
                } else {
                    self = format
                }
            } else {
                return nil
            }
        } else {
            // Fallback on earlier versions
            #if os(visionOS)
            // Warning: dublicate code for visionOS
            if let type = UTType(filenameExtension: filenameExtension), let format = ImageFormat(type) {
                if format == .heif, fileExtension == "heic" { // type == .heic
                    // Fix `.heic` file extension recognized as HEIF image
                    self = .heic
                } else {
                    self = format
                }
            } else {
                return nil
            }
            #else
            let utType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, filenameExtension as CFString, nil)?.takeRetainedValue() // UTTagClass.filenameExtension
            if let utType = utType, let format = ImageFormat(utType) {
                self = format
            } else {
                return nil
            }
            #endif
        }
    }

    /// Indicator of animation supported format
    internal var isAnimationSupported: Bool {
        if case .custom(let identifier) = self, let format = Self.customFormats[identifier] {
            return format.isAnimationSupported
        }

        return self == .gif || self == .heics || self == .png || self == .pdf
    }

    /// Format works in old color format and low quality
    internal var isLowQuality: Bool {
        if case .custom(let identifier) = self, let format = Self.customFormats[identifier] {
            return format.isLowQuality
        }

        #if os(macOS)
        return self == .gif || self == .jpeg2000
        #else
        return self == .gif
        #endif
    }
}
