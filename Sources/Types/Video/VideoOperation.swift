import Foundation

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
            hasher.combine("crop")
            hasher.combine(value.cropSize.width)
            hasher.combine(value.cropSize.height)
        case .rotate(let value):
            hasher.combine("rotate")
            hasher.combine(value.radians)
        case .flip:
            hasher.combine("flip")
        case .mirror:
            hasher.combine("mirror")
        }
    }

    /// Equatable conformance
    public static func == (lhs: VideoOperation, rhs: VideoOperation) -> Bool {
        switch (lhs, rhs) {
        case (let .cut(lhsFrom, lhsTo), let .cut(rhsFrom, rhsTo)):
            return lhsFrom == rhsFrom && lhsTo == rhsTo
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

/// Rotation enumeration
public enum Rotate: Equatable {
    /// Rotate in a rightward direction
    case clockwise

    /// Rotate in a leftward direction
    case counterclockwise

    /// Custom rotation angle in radians, most likely will be displayed as nearest 90' value
    case angle(Double)

    /// Angle
    var radians: Double {
        switch self {
        case .clockwise:
            return .pi/2
        case .counterclockwise:
            return -.pi/2
        case .angle(let value):
            return value
        }
    }
}

/// Rotation enumeration
public struct Crop {
    private var size: CGSize?
    private var aligment: Alignment?
    private var rect: CGRect?
    private var origin: CGPoint?

    /// Initialize using size and alignment
    public init(size: CGSize, aligment: Alignment = .center) {
        self.size = size
        self.aligment = aligment
    }

    /// Initialize using rectangle
    public init(rect: CGRect) {
        self.rect = rect
    }

    /// Initialize using starting point and size
    public init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }

    /// Cropping area size
    public var cropSize: CGSize {
        return self.size ?? self.rect?.size ?? .zero
    }

    /// Calculate cropping rectangle
    public func makeCroppingRectangle(in size: CGSize) -> CGRect {
        if let aligment = self.aligment, let cropSize = self.size {
            let cropOrigin: CGPoint
            switch aligment {
            case .center:
                cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: (size.height - cropSize.height) / 2)
            case .topLeading:
                cropOrigin = CGPoint(x: 0, y: 0)
            case .top:
                cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: 0)
            case .topTrailing:
                cropOrigin = CGPoint(x: size.width - cropSize.width, y: 0)
            case .leading:
                cropOrigin = CGPoint(x: 0, y: (size.height - cropSize.height) / 2)
            case .trailing:
                cropOrigin = CGPoint(x: size.width - cropSize.width, y: (size.height - cropSize.height) / 2)
            case .bottom:
                cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: size.height - cropSize.height)
            case .bottomLeading:
                cropOrigin = CGPoint(x: 0, y: size.height - cropSize.height)
            case .bottomTrailing:
                cropOrigin = CGPoint(x: size.width - cropSize.width, y: size.height - cropSize.height)
            }
            return CGRect(origin: cropOrigin, size: cropSize)
        } else if let rect = self.rect {
            return rect
        } else if let origin = self.origin, let size = self.size {
            return CGRect(origin: origin, size: size)
        }

        return .zero
    }
}
