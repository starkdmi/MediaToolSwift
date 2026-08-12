@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

// To support both SwiftPM and CocoaPods
#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

/// Builds the reader/output configuration shared by the audio-only and video
/// conversion paths. It is deliberately internal: callers continue to use the
/// stable `AudioTool` and `VideoTool` entry points.
internal enum AudioTrackConfiguration {
    internal static func makeVariables(
        track: AVAssetTrack,
        settings: CompressionAudioSettings?
    ) async throws -> AudioVariables {
        // AVFoundation raises an Objective-C exception for invalid decoder
        // sample rates, which Swift cannot catch.
        if let sampleRate = settings?.sampleRate,
           !(8_000 ... 192_000).contains(sampleRate) {
            throw CompressionError.failedToReadAudio
        }

        guard let formatDescription = await track.getFormatDescriptions().first else {
            throw CompressionError.failedToReadAudio
        }

        var variables = AudioVariables()
        variables.audioTrack = track

        guard let settings else {
            variables.hasChanges = false
            variables.codec = CompressionAudioCodec(
                formatId: CMFormatDescriptionGetMediaSubType(formatDescription)
            ) ?? .default
            variables.audioOutput = try makeReaderOutput(track: track, outputSettings: nil)
            variables.audioInput = try makeWriterInput(
                outputSettings: nil,
                sourceFormatHint: formatDescription
            )
            return variables
        }

        let analyzer = AudioTrackAnalyzer()
        let analysis = try await analyzer.analyze(track: track)
        let bitsPerChannel = analyzer.calculateBitsPerChannel(
            settings: settings,
            sourceAnalysis: analysis
        )
        let resolution = AudioCodecResolver().resolve(
            settings: settings,
            sourceAnalysis: analysis,
            calculatedBitsPerChannel: bitsPerChannel
        )

        variables.codec = resolution.codec
        variables.hasChanges = resolution.hasChanges
        variables.bitrate = resolution.targetBitrate
        variables.audioOutput = try makeReaderOutput(
            track: track,
            outputSettings: resolution.hasChanges ? resolution.decoderSettings : nil
        )
        variables.audioInput = try makeWriterInput(
            outputSettings: resolution.hasChanges ? resolution.encoderParameters : nil,
            sourceFormatHint: resolution.hasChanges ? nil : analysis.formatDescription
        )
        return variables
    }

    private static func makeReaderOutput(
        track: AVAssetTrack,
        outputSettings: [String: Any]?
    ) throws -> AVAssetReaderTrackOutput {
        #if canImport(ObjCExceptionCatcher)
        var output: AVAssetReaderTrackOutput?
        try ObjCExceptionCatcher.catchException {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        }
        guard let output else {
            throw CompressionError.failedToReadAudio
        }
        return output
        #else
        return AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        #endif
    }

    private static func makeWriterInput(
        outputSettings: [String: Any]?,
        sourceFormatHint: CMFormatDescription?
    ) throws -> AVAssetWriterInput {
        #if canImport(ObjCExceptionCatcher)
        var input: AVAssetWriterInput?
        try ObjCExceptionCatcher.catchException {
            input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: outputSettings,
                sourceFormatHint: sourceFormatHint
            )
        }
        guard let input else {
            throw CompressionError.failedToWriteAudio
        }
        return input
        #else
        return AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: outputSettings,
            sourceFormatHint: sourceFormatHint
        )
        #endif
    }
}

extension VideoTool {
    /// Initializes audio configuration for the video conversion pipeline.
    internal static func initializeAudio(
        asset: AVAsset,
        audioSettings: CompressionAudioSettings?
    ) async throws -> AudioVariables {
        guard let track = await asset.getFirstTrack(withMediaType: .audio) else {
            var variables = AudioVariables()
            variables.skipAudio = true
            variables.hasChanges = false
            return variables
        }

        return try await AudioTrackConfiguration.makeVariables(track: track, settings: audioSettings)
    }
}

extension AudioTool {
    internal static func convertImpl(
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
        let task = CompressionTask(destination: destination)
        let request = AudioConversionRequest(
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
        let session = AudioConversionSession(request: request, task: task)
        await withTaskCancellationHandler {
            await session.prepareAndStart()
        } onCancel: {
            task.cancel()
        }
        return task
    }
}
