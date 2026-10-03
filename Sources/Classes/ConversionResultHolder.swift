import Foundation

/// Bridges a conversion pipeline's one-shot terminal callback to a continuation.
///
/// The terminal state can arrive before the caller reaches its suspension point,
/// so the holder buffers a result delivered early and hands it over on `attach`.
///
/// The pipelines still arbitrate racing terminal events themselves — AVFoundation
/// can report a failure and a cancellation for the same conversion, and
/// `CompressionTask.claim*TerminalOutcome` decides which one wins. Resuming a
/// continuation twice is a crash rather than a lost callback, so the holder
/// enforces single-resume independently instead of trusting that arbitration.
internal final class ConversionResultHolder<Info: MediaInfo>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Info, any Error>?
    private var pending: Result<Info, any Error>?
    private var isResumed = false

    /// Hands the buffered result over, or stores the continuation until one arrives.
    internal func attach(_ continuation: CheckedContinuation<Info, any Error>) {
        lock.lock()

        guard !isResumed else {
            // Unreachable: `attach` runs once, before any resume can be observed.
            lock.unlock()
            return
        }

        if let pending {
            isResumed = true
            self.pending = nil
            lock.unlock()
            continuation.resume(with: pending)
            return
        }

        self.continuation = continuation
        lock.unlock()
    }

    /// Translates a pipeline state into the continuation's result.
    ///
    /// `.started` carries no value for an `async` caller and is dropped; the
    /// pipeline's own post-`.started` completion handler still runs.
    internal func deliver(_ state: CompressionState) {
        let result: Result<Info, any Error>
        switch state {
        case .started:
            return
        case .completed(let info):
            if let info = info as? Info {
                result = .success(info)
            } else {
                result = .failure(CompressionError.unexpectedConversionResult)
            }
        case .failed(let error):
            result = .failure(error)
        case .cancelled:
            result = .failure(CancellationError())
        }

        lock.lock()

        guard !isResumed else {
            lock.unlock()
            return
        }

        guard let continuation else {
            pending = result
            lock.unlock()
            return
        }

        isResumed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}
