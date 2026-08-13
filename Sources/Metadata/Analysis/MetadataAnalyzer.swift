@preconcurrency import AVFoundation
import Foundation

// To support both SwiftPM and CocoaPods
#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

// MARK: - Metadata Track Analyzer

/// Analyzes and extracts metadata track information from an asset
internal struct MetadataTrackAnalyzer {

    /// Result of metadata track analysis.
    internal struct AnalysisResult {
        /// Whether a timed metadata track exists
        internal let hasTimedMetadataTrack: Bool

        /// The metadata track if found
        internal let metadataTrack: AVAssetTrack?

        /// Format description for the metadata track
        internal let formatDescription: CMFormatDescription?

        /// Asset metadata items (container-level metadata)
        internal let assetMetadata: [AVMetadataItem]

    }

    /// Analyzes the asset for metadata information
    /// - Parameters:
    ///   - asset: The source asset to analyze
    ///   - skipSourceMetadata: Whether to skip reading source metadata
    /// - Returns: Analysis result with metadata track and asset metadata
    internal func analyze(asset: AVAsset, skipSourceMetadata: Bool) async -> AnalysisResult {
        guard !skipSourceMetadata else {
            return AnalysisResult(
                hasTimedMetadataTrack: false,
                metadataTrack: nil,
                formatDescription: nil,
                assetMetadata: []
            )
        }

        // Check for timed metadata track
        let metadataTrack = await asset.getFirstTrack(withMediaType: .metadata)
        let hasTimedMetadataTrack = metadataTrack != nil

        // Get format description if track exists
        var formatDescription: CMFormatDescription?
        if let track = metadataTrack,
           let firstDesc = await track.getFormatDescriptions().first {
            formatDescription = firstDesc
        }

        // Collect asset metadata
        let assetMetadata = await asset.getMetadata()

        return AnalysisResult(
            hasTimedMetadataTrack: hasTimedMetadataTrack,
            metadataTrack: metadataTrack,
            formatDescription: formatDescription,
            assetMetadata: assetMetadata
        )
    }
}

// MARK: - Metadata I/O Factory

/// Creates reader outputs and writer inputs for metadata tracks
internal struct MetadataIOFactory {

    /// Result of creating metadata I/O.
    internal struct IOResult {
        /// Reader output for the metadata track
        internal let readerOutput: AVAssetReaderTrackOutput?

        /// Writer input for the metadata track
        internal let writerInput: AVAssetWriterInput?

        /// Whether the I/O was successfully created
        internal var isValid: Bool {
            readerOutput != nil && writerInput != nil
        }

        internal init(readerOutput: AVAssetReaderTrackOutput?, writerInput: AVAssetWriterInput?) {
            self.readerOutput = readerOutput
            self.writerInput = writerInput
        }
    }

    /// Creates reader output and writer input for a metadata track
    /// - Parameters:
    ///   - metadataTrack: The metadata track to create I/O for
    ///   - formatDescription: The format description for the track
    /// - Returns: IOResult with reader output and writer input, or nil if creation fails
    internal func createIO(
        metadataTrack: AVAssetTrack,
        formatDescription: CMFormatDescription
    ) -> IOResult {
        // Create reader output
        let readerOutput = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)

        // Create writer input with ObjC exception handling
        var writerInput: AVAssetWriterInput?

        #if canImport(ObjCExceptionCatcher)
        do {
            try ObjCExceptionCatcher.catchException {
                writerInput = AVAssetWriterInput(
                    mediaType: .metadata,
                    outputSettings: nil,
                    sourceFormatHint: formatDescription
                )
            }
        } catch {
            // Metadata track will not be added, while metadata still could be set via writer.metadata
            writerInput = nil
        }
        #else
        writerInput = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
        #endif

        return IOResult(readerOutput: readerOutput, writerInput: writerInput)
    }
}

// MARK: - Metadata Resolver

/// Resolves final metadata configuration combining source and custom metadata
internal struct MetadataResolver {

    /// Combines source metadata with custom metadata items
    /// - Parameters:
    ///   - sourceMetadata: Metadata from the source asset
    ///   - customMetadata: Custom metadata items to add
    /// - Returns: Combined array of metadata items
    internal func resolve(
        sourceMetadata: [AVMetadataItem],
        customMetadata: [AVMetadataItem]
    ) -> [AVMetadataItem] {
        var result = sourceMetadata
        result.append(contentsOf: customMetadata)
        return result
    }
}
