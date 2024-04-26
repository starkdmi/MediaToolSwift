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
    public static let redundantCompression = CompressionError(description: "Compression is redundant - video and audio won't be modified during the compression")
    public static let failedToReadVideo = CompressionError(description: "Couldn't add video to reader")
    public static let failedToWriteVideo = CompressionError(description: "Couldn't add video to writer")
    public static let failedToReadAudio = CompressionError(description: "Couldn't add audio to reader")
    public static let failedToWriteAudio = CompressionError(description: "Couldn't add audio to writer")
    public static let failedToReadMetadata = CompressionError(description: "Couldn't add metadata to reader")
    public static let videoTrackNotFound = CompressionError(description: "Video track not found")
    public static let audioTrackNotFound = CompressionError(description: "Audio track not found")
    public static let invalidVideoCodec = CompressionError(description: "Specified video codec is not supported")
    public static let croppingNotAllowed = CompressionError(description: "Cropping is not allowed while the video size is set")
    public static let croppingOutOfBounds = CompressionError(description: "Cropping area is larger than source video bounds")
    public static let notSupportedOnVisionOS = CompressionError(description: "Operation is not supported on Vision Pro")

    // MARK: Image related errors

    public static let unknownImageFormat = CompressionError(description: "Failed to detect image format")
    public static let unsupportedImageFormat = CompressionError(description: "Unsupported image format")
    public static let failedToReadImage = CompressionError(description: "Failed to read image")
    public static let failedToCreateImageFile = CompressionError(description: "Failed to create destination for file.")
    public static let failedToSaveImage = CompressionError(description: "Failed to save image")
    public static let emptyImage = CompressionError(description: "Image frames are missing")
    public static let failedToGenerateThumbnails = CompressionError(description: "Failed to generate thumbnails from a video file")
    // public static let blurNotAllowed = CompressionError(description: "Blur filling is not allowed for images with alpha channel")
}
