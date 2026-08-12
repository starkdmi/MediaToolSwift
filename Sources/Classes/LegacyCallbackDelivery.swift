import Foundation

/// Delivers a legacy, unconstrained callback without exposing `@Sendable` in
/// the public API.
///
/// The callback and each value are transferred to this private serial owner.
/// This preserves the library's released unconstrained callback contract; it is
/// intentionally a legacy compatibility boundary, not a claim that arbitrary
/// actor-isolated captures are Sendable.
internal final class LegacyCallbackDelivery<Value>: @unchecked Sendable {
    private final class Event: @unchecked Sendable {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private let queue: DispatchQueue
    private let callback: (Value) -> Void

    internal init(
        label: String,
        queue: DispatchQueue? = nil,
        callback: @escaping (Value) -> Void
    ) {
        self.queue = queue ?? DispatchQueue(label: label)
        self.callback = callback
    }

    internal func enqueue(_ value: Value) {
        enqueue(value, completion: nil)
    }

    internal func enqueue(_ value: Value, completion: (@Sendable () -> Void)?) {
        let event = Event(value)
        queue.async { [self, event] in
            callback(event.value)
            completion?()
        }
    }
}
