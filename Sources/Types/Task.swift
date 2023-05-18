/// Cancellable compression operation
public class CompressionTask {
    /// Protected property
    private var _isCancelled = false

    /// Getter for cancellation state
    public var isCancelled: Bool { _isCancelled }

    /// Cancel the compression process
    public func cancel() {  _isCancelled = true }
}
