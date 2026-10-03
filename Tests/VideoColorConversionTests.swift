import AVFoundation
import CoreImage
import XCTest
@testable import MediaToolSwift

#if !os(visionOS)
final class VideoColorConversionTests: XCTestCase {
    func testDCIP3WriterSetupBeforeEncoding() async throws {
        let asset = AVURLAsset(url: try fixture("dci-p3"))
        do {
            let configured = try await VideoTool.initializeVideo(asset: asset,
                videoSettings: .init(codec: .hevc, profile: .hevcMain))
            XCTAssertNotNil(configured.videoInput)
        } catch {
            XCTFail("Writer setup failed: \(error.localizedDescription)")
        }
    }

    func testDCIP3SDRConversion() async throws {
        // Maximum SDR quality keeps quantization below the color-error budget.
        try await checkConversion("dci-p3", hdrTransfer: nil,
            settings: .init(codec: .hevc, bitrate: .encoder, quality: 1, profile: .hevcMain))
        #if !os(macOS)
        try await checkConversion("dci-p3", hdrTransfer: nil,
            settings: .init(codec: .hevc, bitrate: .encoder, quality: 1, profile: .hevcMain,
                edit: [.process(.imageComposition { image, _, _ in image })]))
        #endif
    }

    func testDCIP3HLGConversion() async throws {
        try await checkConversion("dci-p3-hlg", hdrTransfer: AVVideoTransferFunction_ITU_R_2100_HLG,
            settings: .init(codec: .hevc, bitrate: .encoder, profile: .hevcMain10))
    }

    func testDCIP3PQConversion() async throws {
        try await checkConversion("dci-p3-pq", hdrTransfer: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
            settings: .init(codec: .hevc, bitrate: .encoder, profile: .hevcMain10))
    }

    func testDCIP3PortraitResizeWithImageProcessor() async throws {
        let source = try fixture("dci-p3-portrait")
        let targetSize = CGSize(width: 48, height: 80)
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await convert(source, to: destination,
            settings: .init(codec: .hevc, size: .scale(targetSize),
                profile: .hevcMain, edit: [.process(.image { image, _, _ in image })]))
        let info = try XCTUnwrap(result as? VideoInfo)
        XCTAssertEqual(info.resolution, targetSize)
        let image = try await firstFrame(AVURLAsset(url: destination))
        XCTAssertEqual(image.width, Int(targetSize.width))
        XCTAssertEqual(image.height, Int(targetSize.height))
    }

    func testDCIP3VideoPassthroughWhileDroppingAudio() async throws {
        let source = try fixture("dci-p3")
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        try await convert(source, to: destination, settings: .init(bitrate: .source), skipAudio: true)
        let original = AVURLAsset(url: source)
        let result = AVURLAsset(url: destination)
        let description = try await videoDescription(result)
        XCTAssertEqual(description.colorPrimaries, kCMFormatDescriptionColorPrimaries_DCI_P3 as String)
        let originalVideo = try await payload(original, type: .video)
        let resultVideo = try await payload(result, type: .video)
        XCTAssertEqual(resultVideo, originalVideo)
        let audioTracks = await result.getTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks?.count, 0)
    }

    private func checkConversion(_ name: String, hdrTransfer: String?, settings: CompressionVideoSettings) async throws {
        let source = try fixture(name)
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        let metadata = AVMutableMetadataItem()
        metadata.identifier = .quickTimeMetadataDescription
        metadata.value = "color-conversion-regression" as NSString
        try await convert(
            source, to: destination,
            settings: settings,
            metadata: [metadata]
        )

        let original = AVURLAsset(url: source)
        let result = AVURLAsset(url: destination)
        let description = try await videoDescription(result)
        #if os(macOS)
        XCTAssertEqual(description.colorPrimaries, kCMFormatDescriptionColorPrimaries_DCI_P3 as String)
        #else
        XCTAssertEqual(description.colorPrimaries, hdrTransfer == nil
            ? AVVideoColorPrimaries_P3_D65 : AVVideoColorPrimaries_ITU_R_2020)
        #endif
        XCTAssertEqual(description.transferFunction, hdrTransfer ?? AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(description.isHDRVideo, hdrTransfer != nil)
        if hdrTransfer != nil {
            try checkHEVCBitDepth(description, expected: 10)
        }
        let sourceDescription = try await videoDescription(original)
        let sourceDimensions = CMVideoFormatDescriptionGetDimensions(sourceDescription)
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        XCTAssertEqual(dimensions.width, sourceDimensions.width)
        XCTAssertEqual(dimensions.height, sourceDimensions.height)
        // AAC uses 1,024 samples per packet; allow two packets of container padding.
        let aacPacketDuration = 1_024.0 / 44_100 // Fixture sample rate, in Hz.
        let duration = await result.getDuration().seconds
        let sourceDuration = await original.getDuration().seconds
        XCTAssertEqual(duration, sourceDuration, accuracy: 2 * aacPacketDuration)
        let originalAudio = try await payload(original, type: .audio)
        let resultAudio = try await payload(result, type: .audio)
        XCTAssertEqual(resultAudio, originalAudio, "Audio must not be re-encoded")
        let resultMetadata = await result.getMetadata()
        let descriptionItem = try XCTUnwrap(resultMetadata.first { $0.identifier == .quickTimeMetadataDescription })
        let descriptionValue = await descriptionItem.getValue() as? String
        XCTAssertEqual(descriptionValue, "color-conversion-regression")
        if hdrTransfer == nil {
            try await checkSDRPixels(original, result)
        }
    }

    private func checkHEVCBitDepth(_ description: CMFormatDescription, expected: Int) throws {
        // BitsPerComponent is optional in Apple-created HEVC descriptions.
        // ISO/IEC 14496-15 hvcC stores bitDepthLumaMinus8 and bitDepthChromaMinus8
        // in the low three bits of bytes 17 and 18, respectively.
        let componentOffsets = [("luma", 17), ("chroma", 18)]
        let depthMask: UInt8 = 0b0000_0111
        let baseDepth = 8
        let atoms = CMFormatDescriptionGetExtension(description,
            extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data]
        let hevc = try XCTUnwrap(atoms?["hvcC"])
        for (component, offset) in componentOffsets {
            let field = try XCTUnwrap(hevc.dropFirst(offset).first, "Missing hvcC \(component) depth")
            XCTAssertEqual(Int(field & depthMask) + baseDepth, expected, "Encoded \(component) depth")
        }
    }

    private func checkSDRPixels(_ original: AVAsset, _ result: AVAsset) async throws {
        let sourceImage = try await firstFrame(original)
        let resultImage = try await firstFrame(result)
        #if os(macOS)
        let retaggingSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.itur_709))
        #else
        let retaggingSpace = try XCTUnwrap(resultImage.colorSpace)
        #endif
        let incorrectlyRetagged = try XCTUnwrap(sourceImage.copy(colorSpace: retaggingSpace))
        #if os(macOS)
        let referenceImage = sourceImage
        #else
        // Use Apple's independent basic compositor as the color reference.
        // CGImage color matching applies a different white-point adaptation.
        let composition = AVMutableVideoComposition(propertiesOf: original)
        composition.colorPrimaries = AVVideoColorPrimaries_P3_D65
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        let referenceImage = try await firstFrame(original, composition: composition)
        #endif
        let expected = try linearPixels(referenceImage)
        let actual = try linearPixels(resultImage)
        let retagged = try linearPixels(incorrectlyRetagged)
        XCTAssertEqual(actual.count, expected.count)
        func meanError(_ pixels: [Float]) -> Float {
            zip(pixels, expected).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(expected.count)
        }
        let conversionError = meanError(actual)
        let retaggingError = meanError(retagged)
        // At most one normalized 8-bit level of mean linear-RGB error, and
        // at least twice as close to the reference as the retag-only control.
        let maximumMeanError = 1 / Float(UInt8.max)
        let minimumImprovementFactor: Float = 2
        print("DCI-P3 linear-RGB mean error: export=\(conversionError), retag-only=\(retaggingError)")
        XCTAssertLessThan(conversionError, maximumMeanError)
        XCTAssertLessThan(conversionError * minimumImprovementFactor, retaggingError,
            "Changing tags alone must not satisfy the pixel-color check")
    }

    private func firstFrame(_ asset: AVAsset, composition: AVVideoComposition? = nil) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = composition
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if #available(macOS 13, iOS 16, tvOS 16, *) {
            return try await generator.image(at: .zero).image
        } else {
            return try generator.copyCGImage(at: .zero, actualTime: nil)
        }
    }

    private func linearPixels(_ image: CGImage) throws -> [Float] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        var rgba = [SIMD4<Float>](repeating: .zero, count: image.width * image.height)
        rgba.withUnsafeMutableBytes {
            CIContext().render(CIImage(cgImage: image), toBitmap: $0.baseAddress!,
                rowBytes: image.width * MemoryLayout<SIMD4<Float>>.stride,
                bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                format: .RGBAf, colorSpace: colorSpace)
        }
        let rgb = rgba.flatMap { [$0.x, $0.y, $0.z] } // Alpha is not part of the color comparison.
        XCTAssertTrue(rgb.allSatisfy(\.isFinite))
        return rgb.map { min(max($0, 0), 1) }
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "mov", subdirectory: "ColorFixtures"))
    }

    private func temporaryOutput() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MediaToolColor-\(UUID()).mov")
    }

    @discardableResult
    private func convert(
        _ source: URL, to destination: URL,
        settings: CompressionVideoSettings,
        skipAudio: Bool = false,
        metadata: [AVMetadataItem] = []
    ) async throws -> MediaInfo {
        let terminal = expectation(description: "Conversion terminal state")
        let state = LockedValue<CompressionState?>(nil)
        _ = await VideoTool.convert(
            source: source, destination: destination,
            videoSettings: settings, skipAudio: skipAudio, customMetadata: metadata
        ) { value in
            switch value {
            case .completed, .failed, .cancelled:
                state.set(value)
                terminal.fulfill()
            case .started:
                break
            }
        }
        await fulfillment(of: [terminal], timeout: 30)
        switch state.read() {
        case .completed(let info): return info
        case .failed(let error):
            // The exception catcher's underlying NSException cannot be archived
            // by XCTest on iOS; preserve its reason in a serializable test error.
            throw ConversionFailure(errorDescription: error.localizedDescription)
        case .cancelled: throw ConversionFailure(errorDescription: "Unexpected cancellation")
        case .started, .none: throw ConversionFailure(errorDescription: "No terminal state")
        }
    }

    private func videoDescription(_ asset: AVAsset) async throws -> CMFormatDescription {
        let maybeTrack = await asset.getFirstTrack(withMediaType: .video)
        let track = try XCTUnwrap(maybeTrack)
        let descriptions = await track.getFormatDescriptions()
        return try XCTUnwrap(descriptions.first)
    }

    private func payload(_ asset: AVAsset, type: AVMediaType) async throws -> Data {
        let maybeTrack = await asset.getFirstTrack(withMediaType: type)
        let track = try XCTUnwrap(maybeTrack)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var payload = Data()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            XCTAssertEqual(status, kCMBlockBufferNoErr)
            payload.append(bytes)
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertFalse(payload.isEmpty)
        return payload
    }
}

private struct ConversionFailure: LocalizedError {
    let errorDescription: String?
}
#endif
