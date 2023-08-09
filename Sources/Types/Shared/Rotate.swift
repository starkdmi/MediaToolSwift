/// Rotation enumeration
public enum Rotate: Equatable, Hashable {
    /// Rotate in a rightward direction
    case clockwise

    /// Rotate in a leftward direction
    case counterClockwise

    /// Rotate upside down
    case upsideDown

    /// Custom rotation angle in radians, most likely will be displayed as nearest 90' value when applied to video
    case angle(Double)

    /// Angle
    var radians: Double {
        switch self {
        case .clockwise:
            return .pi/2
        case .counterClockwise:
            return -.pi/2
        case .upsideDown:
            return .pi
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
