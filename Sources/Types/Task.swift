import Foundation

/// Cancellable compression operation
public class CompressionTask: NSObject, ProgressReporting {
    /// Protected property
    private var _isCancelled = false

    /// Getter for cancellation state
    public var isCancelled: Bool { _isCancelled }

    /// Cancel the compression process
    public func cancel() {  _isCancelled = true }

    /// Processing progress
    public var progress: Progress

    /// File writing (saving) progress
    /// Warning: based on estimated final file size, so is:
    /// - used only for videos
    /// - skipped for small output files (under 25MB)
    /// - likely precise for `.auto`, `.source`, `.filesize(:)`
    /// - maybe be inaccurate for `.encoder` or small bitrate passed to `.value(:)`
    /// - not include audio track in file size calculation
    /// - is indeterminate in any other case
    public var writingProgress: Progress

    /// Public initializer
    public init(destination: URL) {
        // Init additional progress in indeterminate state
        writingProgress = Progress(totalUnitCount: -1)
        writingProgress.isCancellable = false
        // writingProgress.kind = .file // will be set on writing progress usage
        writingProgress.fileURL = destination

        // Init main progress in indeterminate state
        progress = Progress(totalUnitCount: -1)
        super.init()
        // Cancellation callback
        progress.isCancellable = true
        progress.cancellationHandler = { [weak self] in
            self?.cancel()
        }
    }
}
