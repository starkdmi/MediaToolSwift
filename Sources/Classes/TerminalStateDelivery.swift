import Foundation

/// Serializes a conversion's `.started` and terminal state onto one queue.
///
/// This is an ordering primitive, not a callback-compatibility shim. The video
/// session hands it the same queue as the public frame processor so a terminal
/// state can never overlap an in-flight processor, and the audio session gives
/// it a private queue. Both rely on the delivery happening after any work
/// already queued ahead of it.
internal final class TerminalStateDelivery<Value: Sendable>: @unchecked Sendable {
    private let queue: DispatchQueue
    private let handler: @Sendable (Value) -> Void

    internal init(
        label: String,
        queue: DispatchQueue? = nil,
        handler: @escaping @Sendable (Value) -> Void
    ) {
        self.queue = queue ?? DispatchQueue(label: label)
        self.handler = handler
    }

    internal func enqueue(_ value: Value) {
        enqueue(value, completion: nil)
    }

    internal func enqueue(_ value: Value, completion: (@Sendable () -> Void)?) {
        queue.async { [self, value] in
            handler(value)
            completion?()
        }
    }
}
