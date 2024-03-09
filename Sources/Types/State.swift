import Foundation

/// Enum represents state of compression process 
public enum CompressionState: Equatable {
    /// Indicates the preparation is finished and the compression process has started
    case started

    /// Compression process progress
    ///
    /// Warning: writing (saving) progress is based on estimated final file size, so is:
    /// - used only for videos
    /// - skipped for small output files (under 25MB)
    /// - likely precise for `.source`, `.filesize(:)`
    /// - maybe be inaccurate for `.encoder`, `.auto` or small bitrate passed to `.value(:)`
    /// - not include audio track in file size calculation
    case progress(encoding: Progress, writing: Progress?)

    /// Compression finished with success, contains the destination file url
    case completed(MediaInfo)

    /// Compression failed with error
    case failed(Error)

    /// Compression was cancelled
    case cancelled

    /// Conformation to Equatable
    public static func == (lhs: CompressionState, rhs: CompressionState) -> Bool {
        switch (lhs, rhs) {
        case (.started, .started):
            return true
        case (let .progress(lhsEncoding, lhsWriting), let .progress(rhsEncoding, rhsWriting)):
            return lhsEncoding == rhsEncoding && lhsWriting == rhsWriting
        case (.completed(let lhsValue), .completed(let rhsValue)):
            return lhsValue.url == rhsValue.url
        case (.failed(let lhsValue), .failed(let rhsValue)):
            return lhsValue.localizedDescription == rhsValue.localizedDescription
        case (.cancelled, .cancelled):
            return true
        default:
            return false
        }
    }
}
