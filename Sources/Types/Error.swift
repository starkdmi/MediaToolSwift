import Foundation

/// Custom compression error
public struct CompressionError: LocalizedError, Equatable {
    /// Error description
    public let description: String

    /// Public initializer
    public init(description: String = "Compression Error") {
        self.description = description
    }

    /// Localized description
    public var errorDescription: String? {
        self.description
    }

    /// Conformation to Equatable
    public static func == (lhs: CompressionError, rhs: CompressionError) -> Bool {
        lhs.description == rhs.description
    }

    // MARK: Predefined errors

    public static let sourceFileNotFound = CompressionError(description: "Source file not found")
    public static let destinationFileExists = CompressionError(description: "Destination file already exists, use `overwrite` flag to overwrite")
    public static let cannotOverWrite = CompressionError(description: "Cannot overwrite file at selected destination")
    public static let invalidFileType = CompressionError(description: "Invalid combination of file type and destination file extension")
    public static let redunantCompression = CompressionError(description: "Compression is redunant - video and audio won't be modified during the compression")
    public static let failedToReadVideo = CompressionError(description: "Couldn't add video to reader")
    public static let failedToWriteVideo = CompressionError(description: "Couldn't add video to writer")
    public static let failedToReadAudio = CompressionError(description: "Couldn't add audio to reader")
    public static let failedToWriteAudio = CompressionError(description: "Couldn't add audio to writer")
    public static let failedToReadMetadata = CompressionError(description: "Couldn't add metadata to reader")
    public static let videoTrackNotFound = CompressionError(description: "Video track not found")
    public static let invalidVideoCodec = CompressionError(description: "Specified video codec is not supported")
    public static let croppingNotAllowed = CompressionError(description: "Cropping is not allowed while the video size is set")
    public static let croppingOutOfBounds = CompressionError(description: "Cropping area is larger than source video bounds")

    // MARK: Image related errors

    public static let unknownImageFormat = CompressionError(description: "Image format should be specified to save image")
    public static let unsupportedImageFormat = CompressionError(description: "Unsupported image format")
    public static let failedToReadImage = CompressionError(description: "Failed to read image")
    public static let failedToCreateImageFile = CompressionError(description: "Failed to create destination for file.")
    public static let failedToSaveImage = CompressionError(description: "Failed to save image")
}
