import Foundation
/*#if os(macOS)
import AppKit
#else
import UIKit
#endif*/

/// Image operations
public enum ImageOperation: Equatable, Hashable, Comparable {
    /// Cropping
    case crop(Crop)

    /// Rotation
    case rotate(Rotate)

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .crop(let value):
            hasher.combine(value)
        case .rotate(let value):
            hasher.combine(value)
        }
    }

    /// Equatable conformance
    public static func == (lhs: ImageOperation, rhs: ImageOperation) -> Bool {
        switch (lhs, rhs) {
        case (.crop(let lhsCrop), .crop(let rhsCrop)):
            return lhsCrop == rhsCrop
        case (.rotate(let lhsRotation), .rotate(let rhsRotation)):
            return lhsRotation == rhsRotation
        default:
            return false
        }
    }

    /// Operation priority
    private var priority: Int {
        switch self {
        case .crop(_):
            return 1
        case .rotate(_):
            return 2
        }
    }

    /// Comparable conformance
    public static func < (lhs: ImageOperation, rhs: ImageOperation) -> Bool {
        return lhs.priority < rhs.priority
    }
}
