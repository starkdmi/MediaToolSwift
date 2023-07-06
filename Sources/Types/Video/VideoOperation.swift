import Foundation
import CoreMedia
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Image processing function type
public typealias ImageProcessor = (_ image: CIImage, _ size: CGSize, _ atTime: Double) -> CIImage

/// Video operations
public enum VideoOperation: Equatable, Hashable {
    /// Cutting
    case cut(from: Double = 0.0, to: Double = .infinity)

    /// Cropping
    /// Not allowed when `size` of `CompressionVideoSettings` is set
    /// May not reduce the video size, it adjusts the rendering area without decoding/encoding each frame as image and modifying it
    /// May be used to increase video size - scale down video to square/rectangle with black background
    case crop(Crop)

    /// Rotation
    case rotate(Rotate)

    /// Flip upside down
    case flip

    /// Right to left mirror effect
    case mirror

    /// Image processing
    /// Warning: `CIImage` size should not be modified
    case imageProcessing(ImageProcessor)

    /// Transform value
    var transform: CGAffineTransform? {
        switch self {
        case .rotate(let value):
            return CGAffineTransform(rotationAngle: value.radians)
        case .flip:
            return CGAffineTransform(scaleX: 1.0, y: -1.0)
        case .mirror:
            return CGAffineTransform(scaleX: -1.0, y: 1.0)
        default:
            return nil
        }
    }

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .cut(from: from, to: to):
            hasher.combine("cut")
            hasher.combine(from)
            hasher.combine(to)
        case .crop(let value):
            hasher.combine(value)
        case .rotate(let value):
            hasher.combine(value)
        case .flip:
            hasher.combine("flip")
        case .mirror:
            hasher.combine("mirror")
        case .imageProcessing:
            hasher.combine("processor")
        }
    }

    /// Equatable conformance
    public static func == (lhs: VideoOperation, rhs: VideoOperation) -> Bool {
        switch (lhs, rhs) {
        case (let .cut(lhsFrom, lhsTo), let .cut(rhsFrom, rhsTo)):
            return lhsFrom == rhsFrom && lhsTo == rhsTo
        case (.crop(let lhsCrop), .crop(let rhsCrop)):
            return lhsCrop == rhsCrop
        case (.rotate(let lhsRotation), .rotate(let rhsRotation)):
            return lhsRotation == rhsRotation
        case (.flip, .flip):
            return true
        case (.mirror, .mirror):
            return true
        default:
            return false
        }
    }
}
