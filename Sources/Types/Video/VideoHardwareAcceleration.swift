/// Hardware acceleration 
public enum CompressionHardwareAcceleration: Sendable {
  /// Automatically, Hardware accelerated video encoder used if available
  case auto

  /// Disabled, Hardware encode will never be used
  case disabled
}
