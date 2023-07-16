import Foundation
import CoreImage

/// Image operations
public enum ImageOperation: Equatable, Hashable, Comparable {
    /// Cropping
    case crop(Crop)

    /// Rotation
    case rotate(Rotate)

    /// Custom image processing function, appplied after all the other image operations
    case imageProcessing((_ image: CIImage) -> CIImage)

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .crop(let value):
            hasher.combine(value)
        case .rotate(let value):
            hasher.combine(value)
        case .imageProcessing(_):
            hasher.combine("ImageProcessing")
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
        case .imageProcessing(_):
            // Should be executed after all the operations
            return 100
        }
    }

    /// Comparable conformance
    public static func < (lhs: ImageOperation, rhs: ImageOperation) -> Bool {
        return lhs.priority < rhs.priority
    }
}
