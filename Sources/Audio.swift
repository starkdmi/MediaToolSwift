import AVFoundation

/// Audio-related singleton interface.
public struct AudioTool {

    /// Compress an audio file.
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
        callback: @escaping (CompressionState) -> Void
    ) async -> CompressionTask {
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
            callback: callback
        )
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
