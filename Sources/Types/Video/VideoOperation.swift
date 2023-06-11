import Foundation

/// Video operations
public enum VideoOperation: Equatable, Hashable {
    /// Cutting
    case cut(from: Double = 0.0, to: Double = .infinity)

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
