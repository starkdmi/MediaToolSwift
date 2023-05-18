import Foundation

/// Enum represents state of compression process 
public enum CompressionState: Equatable {
    /// Indicates the preparation is finished and the compression process has started
    case started

    /// Compression process progress
    case progress(Progress)

    /// Compression finished with success, contains the destination file url
    case completed(URL)

    /// Compression failed with error
    case failed(Error)

    /// Compression was cancelled
    case cancelled

    /// Conformation to Equatable
    public static func == (lhs: CompressionState, rhs: CompressionState) -> Bool {
        switch (lhs, rhs) {
        case (.started, .started):
            return true
        case (.progress(let lhsValue), .progress(let rhsValue)):
            return lhsValue == rhsValue
        case (.completed(let lhsValue), .completed(let rhsValue)):
            return lhsValue == rhsValue
        case (.failed(let lhsValue), .failed(let rhsValue)):
            return lhsValue.localizedDescription == rhsValue.localizedDescription
        case (.cancelled, .cancelled):
            return true
        default:
            return false
        }
    }
}
