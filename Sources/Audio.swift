import AVFoundation

/// Audio-related singleton interface.
public struct AudioTool {

    /// Compress an audio file.
    ///
    /// Returns when the conversion finishes, throwing the underlying error on
    /// failure and `CancellationError` when the conversion is cancelled.
    ///
    /// Pass a `task` you created yourself to observe `progress` while the
    /// conversion runs, or to cancel it from outside the awaiting context.
    /// Cancelling the enclosing Swift `Task` cancels the conversion too.
    public static func convert(
        source: URL,
        destination: URL,
        fileType: AudioFileType = .m4a,
        settings: CompressionAudioSettings? = nil,
        edit: Set<AudioOperation> = [],
        skipSourceMetadata: Bool = false,
        customMetadata: [AVMetadataItem] = [],
        copyExtendedFileMetadata: Bool = true,
        cacheDirectory: URL? = nil,
        overwrite: Bool = false,
        deleteSourceFile: Bool = false,
        progressQueue: DispatchQueue = .main,
        task: CompressionTask? = nil
    ) async throws -> AudioInfo {
        let task = task ?? CompressionTask(destination: destination)
        guard task.claimForConversion(destination: destination) else {
            throw CompressionError.taskAlreadyUsed
        }
        let holder = ConversionResultHolder<AudioInfo>()

        // Start before suspending: the pipeline may reach a terminal state
        // during preparation, and the holder buffers it until `attach`.
        await convertImpl(
            source: source,
            destination: destination,
            fileType: fileType,
            settings: settings,
            edit: edit,
            skipSourceMetadata: skipSourceMetadata,
            customMetadata: customMetadata,
            copyExtendedFileMetadata: copyExtendedFileMetadata,
            cacheDirectory: cacheDirectory,
            overwrite: overwrite,
            deleteSourceFile: deleteSourceFile,
            progressQueue: progressQueue,
            task: task,
            callback: { holder.deliver($0) }
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { holder.attach($0) }
        } onCancel: {
            task.cancel()
        }
    }

    /// Retrieve audio file information.
    public static func getInfo(source: URL) async throws -> AudioInfo {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CompressionError.sourceFileNotFound
        }

        let asset = AVAsset(url: source)
        guard let audioTrack = await asset.getFirstTrack(withMediaType: .audio) else {
            throw CompressionError.audioTrackNotFound
        }

        let analysis = try await AudioTrackAnalyzer().analyze(track: audioTrack)
        let rawData = FileExtendedAttributes.getExtendedMetadata(from: source.path)

        return AudioInfo(
            url: source,
            duration: (await asset.getDuration()).seconds,
            codec: analysis.codec,
            bitrate: analysis.estimatedBitrate,
            extendedInfo: FileExtendedAttributes.extractExtendedFileInfo(from: rawData)
        )
    }
}
