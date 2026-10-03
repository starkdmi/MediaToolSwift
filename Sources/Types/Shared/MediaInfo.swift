import Foundation

/// Media info protocol type
public protocol MediaInfo: Sendable {
    /// Media file path
    var url: URL { get }

    /// Extended media information
    var extendedInfo: ExtendedFileInfo? { get }
}
