import Foundation

private final class CompressionTaskCancellationRelay: @unchecked Sendable {
    weak var task: CompressionTask?

    func cancel(progressID: UUID) {
        task?.cancel(fromProgressWithID: progressID)
    }
}

internal enum CompressionTaskFailureClaim {
    case failure
    case cancellation
    case unavailable
}

/// Cancellable compression operation
public final class CompressionTask: NSObject, ProgressReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    private var hasTerminalOutcome = false
    private var cancellationHandlers: [UUID: @Sendable () -> Void] = [:]
    private let cancellationRelay = CompressionTaskCancellationRelay()
    private var progressCancellationID = UUID()
    private var _progress: Progress
    private var _writingProgress: Progress

    /// Getter for cancellation state
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    /// Cancel the compression process
    public func cancel() {
        cancel(fromProgressWithID: nil)
    }

    fileprivate func cancel(fromProgressWithID progressID: UUID?) {
        let handlers: [@Sendable () -> Void]
        let progress: Progress
        let writingProgress: Progress

        lock.lock()
        if let progressID, progressID != progressCancellationID {
            lock.unlock()
            return
        }
        guard !_isCancelled, !hasTerminalOutcome else {
            lock.unlock()
            return
        }
        _isCancelled = true
        progress = _progress
        writingProgress = _writingProgress
        handlers = Array(cancellationHandlers.values)
        cancellationHandlers.removeAll()
        lock.unlock()

        // Propagate to active reader/writer sessions before invoking public
        // `Progress` cancellation handlers, which callers may replace with
        // arbitrary or blocking work.
        handlers.forEach { $0() }
        cancel(progress)
        cancel(writingProgress)
    }

    /// Register work that should be notified when cancellation is requested.
    /// The handler is invoked immediately when the task is already cancelled.
    @discardableResult
    internal func registerCancellationHandler(
        _ handler: @escaping @Sendable () -> Void
    ) -> UUID? {
        lock.lock()
        guard !hasTerminalOutcome else {
            lock.unlock()
            return nil
        }

        if _isCancelled {
            lock.unlock()
            handler()
            return nil
        }

        let id = UUID()
        cancellationHandlers[id] = handler
        lock.unlock()
        return id
    }

    internal func removeCancellationHandler(_ id: UUID?) {
        guard let id else { return }
        lock.lock()
        cancellationHandlers[id] = nil
        lock.unlock()
    }

    /// Atomically decides whether a successful terminal callback may win over
    /// a concurrent cancellation request. The caller must emit its terminal
    /// callback immediately after this returns `true`.
    internal func claimSuccessfulTerminalOutcome() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !_isCancelled, !hasTerminalOutcome else { return false }
        hasTerminalOutcome = true
        cancellationHandlers.removeAll()
        return true
    }

    /// Atomically resolves a failure racing with cancellation. Once
    /// cancellation has changed the public task state, the conversion must
    /// report `.cancelled` rather than allowing a later failure to win.
    internal func claimFailureTerminalOutcome() -> CompressionTaskFailureClaim {
        lock.lock()
        defer { lock.unlock() }

        guard !hasTerminalOutcome else { return .unavailable }
        hasTerminalOutcome = true
        cancellationHandlers.removeAll()
        return _isCancelled ? .cancellation : .failure
    }

    /// Claims a cancellation terminal event, including cancellation initiated
    /// by AVFoundation rather than through the public task.
    internal func claimCancellationTerminalOutcome() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !hasTerminalOutcome else { return false }
        _isCancelled = true
        hasTerminalOutcome = true
        cancellationHandlers.removeAll()
        return true
    }

    /// Processing progress
    public var progress: Progress {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _progress
        }
        set {
            let cancellationID = UUID()

            let taskWasCancelled: Bool
            lock.lock()
            _progress = newValue
            progressCancellationID = cancellationID
            taskWasCancelled = _isCancelled
            lock.unlock()

            repairCurrentProgressCancellationHandler()
            if taskWasCancelled {
                cancel(newValue)
            }
        }
    }

    /// File writing (saving) progress
    /// Warning: based on estimated final file size, so is:
    /// - used only for videos
    /// - skipped for small output files (under 25MB)
    /// - likely precise for `.auto`, `.source`, `.filesize(:)`
    /// - maybe be inaccurate for `.encoder` or small bitrate passed to `.value(:)`
    /// - not include audio track in file size calculation
    /// - is indeterminate in any other case
    public var writingProgress: Progress {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _writingProgress
        }
        set {
            let taskWasCancelled: Bool
            lock.lock()
            _writingProgress = newValue
            taskWasCancelled = _isCancelled
            lock.unlock()

            if taskWasCancelled {
                cancel(newValue)
            }
        }
    }

    /// Public initializer
    public init(destination: URL) {
        // Init additional progress in indeterminate state
        _writingProgress = Progress(totalUnitCount: -1)
        _writingProgress.isCancellable = false
        // writingProgress.kind = .file // will be set on writing progress usage
        _writingProgress.fileURL = destination

        // Init main progress in indeterminate state
        _progress = Progress(totalUnitCount: -1)
        super.init()
        cancellationRelay.task = self
        installCancellationHandler(on: _progress, cancellationID: progressCancellationID)
    }

    private func installCancellationHandler(on progress: Progress, cancellationID: UUID) {
        progress.isCancellable = true
        let relay = cancellationRelay
        progress.cancellationHandler = {
            relay.cancel(progressID: cancellationID)
        }
    }

    private func repairCurrentProgressCancellationHandler() {
        while true {
            let progress: Progress
            let cancellationID: UUID
            let taskWasCancelled: Bool
            lock.lock()
            progress = _progress
            cancellationID = progressCancellationID
            taskWasCancelled = _isCancelled
            lock.unlock()

            // Foundation mutations may synchronously invoke KVO/subclass code,
            // so never hold an internal lock here. Stale handlers are harmless:
            // their generation is rejected by `cancel(fromProgressWithID:)`.
            installCancellationHandler(on: progress, cancellationID: cancellationID)

            lock.lock()
            let isStable = _progress === progress && progressCancellationID == cancellationID
            lock.unlock()
            guard isStable else { continue }

            if taskWasCancelled {
                cancel(progress)
            } else if progress.isCancelled {
                cancel(fromProgressWithID: cancellationID)
            }
            return
        }
    }

    private func cancel(_ progress: Progress) {
        guard !progress.isCancelled else { return }
        progress.cancel()
    }
}
