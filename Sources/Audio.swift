import AVFoundation
import Foundation
import CoreMedia
import CoreImage
import VideoToolbox
import Accelerate

// To support both SwiftPM and CocoaPods
#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

/// Audio related singletone interface
public struct AudioTool {

    /// Compress audio file
    /// - Parameters:
    ///   - source: Input audio URL
    ///   - destination: Output audio URL
    ///   - fileType: Audio file contrainer type
    ///   - settings: Audio related settings including
    ///      - codec: Audio codec used by encoder: AAC, Opus, FLAC, Linear PCM, Apple Lossless Audio Codec
    ///      - bitrate: Audio bitrate, used by aac and opus codecs only
    ///      - quality: Audio quality, AAC and FLAC only: low, medium, high
    ///      - sampleRate: Sample rate in Hz
    ///   - skipSourceMetadata: Skip source audio file metadata
    ///   - customMetadata: Provide custom metadata to be added to asset metadata, ignores `skipSourceMetadata`
    ///   - copyExtendedFileMetadata: Copy extended file system metadata tags used for media from source
    ///   - cacheDirectory: Directory for AVAssetWriter to save temporary files before copying to destination
    ///   - overwrite: Replace destination file if exists, for `false` error will be raised when file already exists
    ///   - deleteSourceFile: Delete source file on success
    ///   - callback: Compression process state notifier, including error handling and completion
    /// - Returns: Task with option to control the compression process
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
        callback: @escaping (CompressionState) -> Void
    ) async -> CompressionTask {
        let task = CompressionTask()

        // Check source file existence
        if !FileManager.default.fileExists(atPath: source.path) {
            // Also caused by insufficient permissions
            callback(.failed(CompressionError.sourceFileNotFound))
            return task
        }

        // Check destination file existence and overwrite setting
        let destinationExists: Bool = FileManager.default.fileExists(atPath: destination.path)
        if destinationExists, !overwrite {
            callback(.failed(CompressionError.destinationFileExists))
            return task
        }

        let asset = AVAsset(url: source)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            callback(.failed(error))
            return task
        }

        // Confirm the file type is set to correct value by comparing with destination file extension
        if destination.pathExtension.lowercased() != fileType.rawValue {
            callback(.failed(CompressionError.invalidFileType))
            return task
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: destination, fileType: fileType.value)
        } catch let error {
            callback(.failed(error))
            return task
        }

        // MARK: Audio

        var audioVariables: AudioVariables!
        do {
            audioVariables = try await VideoTool.initAudio(asset: asset, audioSettings: settings)
        } catch let error {
            callback(.failed(error))
            return task
        }

        // Append audio to reader
        guard reader.canAdd(audioVariables.audioOutput!) else {
            callback(.failed(CompressionError.failedToReadAudio))
            return task
        }
        reader.add(audioVariables.audioOutput!)

        // MARK: Edit

        var duration = asset.duration
        var timeRange: CMTimeRange?
        for operation in edit {
            switch operation {
            case let .cut(from: start, to: end):
                // Apply only one cutting operation, confirm the range is valid
                guard timeRange == nil else { break }

                guard let range = CMTimeRange(
                    start: start,
                    end: end,
                    duration: duration.seconds,
                    timescale: duration.timescale
                ) else { break }
                timeRange = range
                duration = range.duration
            }
        }

        // Prevent the compression when audio settings are same as the source file
        if audioVariables.skipAudio || !(audioVariables.hasChanges || timeRange != nil) {
            callback(.failed(CompressionError.redunantCompression))
            return task
        }

        // Append audio to writer
        guard writer.canAdd(audioVariables.audioInput!) else {
            callback(.failed(CompressionError.failedToWriteAudio))
            return task
        }
        writer.add(audioVariables.audioInput!)

        // MARK: Metadata

        // Load file metadata
        var metadata = await asset.getMetadata()
        // Convert ID3 and other tags to common key space when possible
        if !metadata.isEmpty {
            var commonMetadata: [AVMetadataItem] = []

            for item in metadata {
                guard let key = item.commonKey else { continue }

                let metadataItem = AVMutableMetadataItem()
                metadataItem.key = key as NSString
                metadataItem.keySpace = AVMetadataKeySpace.common
                metadataItem.value = item.value
                metadataItem.dataType = item.dataType

                commonMetadata.append(metadataItem)
            }

            // Append converted tags without removing original items
            metadata.append(contentsOf: commonMetadata)
        }

        // Append custom metadata
        metadata.append(contentsOf: customMetadata)

        // Insert source file and custom metadata
        writer.metadata = metadata

        // MARK: Compression

        // Delete file at destination path
        if destinationExists {
            try? FileManager.default.removeItem(at: destination)
        }

        // Initiate read-write process
        if let timeRange = timeRange {
            // Cut movie - read only required part of clip
            reader.timeRange = timeRange
        }
        reader.startReading()
        writer.startWriting()
        if let timeRange = timeRange {
            // Cut movie - start writing from specified point
            writer.startSession(atSourceTime: timeRange.start)
        } else {
            writer.startSession(atSourceTime: .zero)
        }

        // Notify caller
        callback(.started)

        // Progress related variables
        let progress = Progress(totalUnitCount: duration.value)
        let group = DispatchGroup()
        var success = 0 // amount of completed operations
        var processes = 0 // amount of operations to be done
        var error: Error? // reading/writing failure

        func run(
            input: AVAssetWriterInput,
            output: AVAssetReaderOutput,
            queue: DispatchQueue,
            sampleHandler: ((CMSampleBuffer) -> Void)? = nil
        ) {
            group.enter()
            processes += 1
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData, !task.isCancelled {
                    // Read
                    guard let sample = output.copyNextSampleBuffer() else {
                        if reader.status == .failed {
                            // Reader fails
                            error = reader.error
                        } else {
                            success += 1
                        }

                        // Complete
                        input.markAsFinished()
                        group.leave()
                        return
                    }

                    // Write
                    if let handler = sampleHandler {
                        handler(sample)
                    } else if !input.append(sample), writer.status == .failed {
                        // Writing fails
                        error = writer.error
                        input.markAsFinished()
                        group.leave()
                        return
                    }

                    // Progress
                    if input.mediaType == .audio {
                        progress.completedUnitCount = Int64(sample.presentationTimeStamp.value)
                        callback(.progress(progress))
                    }
                }

                if task.isCancelled {
                    // Cancelled
                    input.markAsFinished()
                    group.leave()
                }
            }
        }

        // Audio
        let audioQueue = DispatchQueue(label: "MediaToolSwift.audio.queue")
        run(input: audioVariables.audioInput!, output: audioVariables.audioOutput!, queue: audioQueue)

        let completionQueue = DispatchQueue(label: "MediaToolSwift.completion.queue")
        group.notify(queue: completionQueue) {
            if let error = error {
                // Error in reading/writing process
                reader.cancelReading()
                writer.cancelWriting()
                callback(.failed(error))
            } else if !task.isCancelled || success == processes {
                // Confirm the progress is 1.0
                if progress.completedUnitCount != progress.totalUnitCount {
                    progress.completedUnitCount = Int64(progress.totalUnitCount)
                    callback(.progress(progress))
                }

                // Wasn't cancelled and reached OR all operation was completed
                reader.cancelReading()
                writer.finishWriting(completionHandler: {
                    // Extended file metadata
                    if copyExtendedFileMetadata {
                        FileExtendedAttributes.copyExtendedMetadata(
                            from: source.path,
                            to: destination.path,
                            customAttributes: [:]
                        )
                    }

                    if deleteSourceFile, source.path != destination.path {
                        // Delete input audio file
                        try? FileManager.default.removeItem(at: source)
                    }

                    // Finish
                    callback(.completed(writer.outputURL))
                })
            } else { // Cancelled
                // Wait for sample in progress to complete, 0.5 sec is more than enough
                usleep(500_000)

                // This method should not be called concurrently with any calls to `output.copyNextSampleBuffer()`
                // The documentation of that is unclear - https://developer.apple.com/documentation/avfoundation/avassetreader/1390258-cancelreading
                reader.cancelReading()

                // This method also should not be called concurrently with `input.append()`
                writer.cancelWriting()
                callback(.cancelled)
            }
        }

        return task
    }
}