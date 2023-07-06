/// Rotation enumeration
public enum Rotate: Equatable, Hashable {
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

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine("rotate")
        hasher.combine(radians)
    }
}
