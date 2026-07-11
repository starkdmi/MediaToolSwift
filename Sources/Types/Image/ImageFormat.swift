import Foundation
import AVFoundation
#if (os(iOS) && !targetEnvironment(macCatalyst)) || os(tvOS) || os(visionOS)
import MobileCoreServices
#endif

#if targetEnvironment(macCatalyst)
private enum CatalystLegacyImageUTType {
    static let png = "public.png" as CFString
    static let jpeg = "public.jpeg" as CFString
    static let gif = "com.compuserve.gif" as CFString
    static let tiff = "public.tiff" as CFString
    static let bmp = "com.microsoft.bmp" as CFString
    static let ico = "com.microsoft.ico" as CFString
    static let pdf = "com.adobe.pdf" as CFString
}
#endif

private final class ImageFormatRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var formats: [String: any CustomImageFormat] = [:]
    private var identifiers: [String] = []

    func register(_ format: any CustomImageFormat) {
        lock.lock()
        defer { lock.unlock() }

        let identifier = format.identifier
        if formats[identifier] == nil {
            identifiers.append(identifier)
        }
        formats[identifier] = format
    }

    func formatsSnapshot() -> [String: any CustomImageFormat] {
        lock.lock()
        defer { lock.unlock() }
        return formats
    }

    func identifiersSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return identifiers
    }

    func format(for identifier: String) -> (any CustomImageFormat)? {
        lock.lock()
        defer { lock.unlock() }
        return formats[identifier]
    }
}

/// Custom image encoder
public protocol CustomImageFormat {
    /// Type ID, should be unique for each custom format
    var identifier: String { get }

    /// Corresponding `kUTType`,  should be unique per format
    var utType: CFString? { get }

    // File extensions associated with format, should not conflict with built-in format extensions, empty array allowed
    // var fileExtensions: [String] { get }

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
public enum ImageFormat: Hashable, Equatable, Sendable {
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

    /// OpenEXR image format
    case exr

    /// Icon image format, squared only with 6, 32, 48, 128, or 256 pixels wide
    case ico

    /// Adobe PDF format
    case pdf

    /// Custom image format, should be a registered format
    case custom(String)

    /// Immutable formats built into ImageIO on supported platforms.
    #if os(macOS)
    private static let builtInFormats: [ImageFormat] = [
        .heif, .heif10, .heic, .heics, .png, .jpeg, .jpeg2000, .gif, .tiff, .bmp, .exr, .ico, .pdf
    ]
    #else
    private static let builtInFormats: [ImageFormat] = [
        .heif, .heif10, .heic, .heics, .png, .jpeg, .gif, .tiff, .bmp, .exr, .ico, .pdf
    ]
    #endif

    private static let registry = ImageFormatRegistry()

    internal static var allFormats: [ImageFormat] {
        builtInFormats + registry.identifiersSnapshot().map { .custom($0) }
    }

    /// Available output image formats
    public static var allCases: [ImageFormat] {
        allFormats
    }

    /// Registered custom formats. The dictionary is a snapshot so callers cannot
    /// mutate the registry without synchronization.
    internal static var customFormats: [String: any CustomImageFormat] {
        registry.formatsSnapshot()
    }

    /// Registered custom  formats
    public static var registeredFormats: [String: any CustomImageFormat] {
        registry.formatsSnapshot()
    }

    /// Register custom image format
    public static func registerCustomFormat(_ format: any CustomImageFormat) {
        registry.register(format)
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
        case (.exr, .exr): return true
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
                #if targetEnvironment(macCatalyst)
                return CatalystLegacyImageUTType.png
                #else
                return kUTTypePNG
                #endif
            }
        case .jpeg:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.jpeg.identifier as CFString
            } else {
                #if targetEnvironment(macCatalyst)
                return CatalystLegacyImageUTType.jpeg
                #else
                return kUTTypeJPEG
                #endif
            }
        #if os(macOS)
        case .jpeg2000:
            return kUTTypeJPEG2000 // public.jpeg-2000
        #endif
        case .gif:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.gif.identifier as CFString
            } else {
                #if targetEnvironment(macCatalyst)
                return CatalystLegacyImageUTType.gif
                #else
                return kUTTypeGIF
                #endif
            }
        case .tiff:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.tiff.identifier as CFString
            } else {
                #if targetEnvironment(macCatalyst)
                return CatalystLegacyImageUTType.tiff
                #else
                return kUTTypeTIFF
                #endif
            }
        case .bmp:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.bmp.identifier as CFString
            } else {
                #if targetEnvironment(macCatalyst)
                return CatalystLegacyImageUTType.bmp
                #else
                return kUTTypeBMP
                #endif
            }
        case .exr:
            return "com.ilm.openexr-image" as CFString
        case .ico:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.ico.identifier as CFString
            } else {
                #if targetEnvironment(macCatalyst)
                return CatalystLegacyImageUTType.ico
                #else
                return kUTTypeICO
                #endif
            }
        case .pdf:
            if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *) {
                return UTType.pdf.identifier as CFString
            } else {
                #if targetEnvironment(macCatalyst)
                return CatalystLegacyImageUTType.pdf
                #else
                return kUTTypePDF
                #endif
            }
        case .custom(let identifier):
            return Self.registry.format(for: identifier)?.utType
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
        // Try initialize custom formats using file extension
        /*for (identifier, format) in Self.customFormats {
            if format.fileExtensions.contains(fileExtension) {
                self = .custom(identifier)
                return
            }
        }*/

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
        if case .custom(let identifier) = self, let format = Self.registry.format(for: identifier) {
            return format.isAnimationSupported
        }

        return self == .gif || self == .heics || self == .png || self == .pdf
    }

    /// Format works in old color format and low quality
    internal var isLowQuality: Bool {
        if case .custom(let identifier) = self, let format = Self.registry.format(for: identifier) {
            return format.isLowQuality
        }

        #if os(macOS)
        return self == .gif || self == .jpeg2000
        #else
        return self == .gif
        #endif
    }
}
