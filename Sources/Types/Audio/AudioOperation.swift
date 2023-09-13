import Foundation

/// Audio operations
public enum AudioOperation: Equatable, Hashable {
    /// Cutting
    case cut(from: Double = 0.0, to: Double = .infinity)

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .cut(from: from, to: to):
            hasher.combine("cut")
            hasher.combine(from)
            hasher.combine(to)
        }
    }

    /// Equatable conformance
    public static func == (lhs: AudioOperation, rhs: AudioOperation) -> Bool {
        switch (lhs, rhs) {
        case (let .cut(lhsFrom, lhsTo), let .cut(rhsFrom, rhsTo)):
            return lhsFrom == rhsFrom && lhsTo == rhsTo
        }
    }
}
