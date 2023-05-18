import Foundation

/// Custom compression error
public struct CompressionError: LocalizedError {
    /// Error description
    public let description: String

    /// Public initializer
    public init(description: String = "Compression Error") {
        self.description = description
    }

    /// Localized description
    public var errorDescription: String? {
        self.description
    }
}
