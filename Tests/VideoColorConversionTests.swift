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
        let sourceImage = try await firstFrame(AVURLAsset(url: source))
        XCTAssertEqual(sourceImage.width, 96, "The fixture must carry a portrait track transform")
        XCTAssertEqual(sourceImage.height, 160, "The fixture must carry a portrait track transform")
        let targetSize = CGSize(width: 48, height: 80)
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        let info = try await convert(source, to: destination,
            settings: .init(codec: .hevc, size: .scale(targetSize),
                profile: .hevcMain, edit: [.process(.image { image, _, _ in image })]))
        XCTAssertEqual(info.resolution, targetSize)
        let image = try await firstFrame(AVURLAsset(url: destination))
        XCTAssertEqual(image.width, Int(targetSize.width))
        XCTAssertEqual(image.height, Int(targetSize.height))
    }

    func testDCIP3PortraitRotationReportsDisplayedResolution() async throws {
        // iOS rejects DCI-P3 in the writer, so its retry renders through a video
        // composition that already applies the track transform; the reported
        // resolution must still follow the user's rotation exactly once. macOS
        // accepts DCI-P3 and covers the track-output path instead.
        let source = try fixture("dci-p3-portrait")
        let settings = CompressionVideoSettings(codec: .hevc, bitrate: .encoder, quality: 1,
            profile: .hevcMain, edit: [.rotate(.clockwise)])
        let configured = try await VideoTool.initializeVideo(asset: AVURLAsset(url: source), videoSettings: settings)
        #if !os(macOS)
        XCTAssertTrue(configured.videoOutput is AVAssetReaderVideoCompositionOutput,
            "Expected the DCI-P3 conversion retry to use a video composition")
        #endif
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        let info = try await convert(source, to: destination, settings: settings, skipAudio: true)
        XCTAssertEqual(info.resolution, CGSize(width: 160, height: 96))
        let image = try await firstFrame(AVURLAsset(url: destination))
        XCTAssertEqual(CGSize(width: image.width, height: image.height), info.resolution)
    }

    func testDCIP3FitResizeWithoutFrameProcessor() async throws {
        // A square bounding box must preserve the fixture's 5:3 aspect ratio.
        let boundingSize = CGSize(width: 80, height: 80)
        let cases = [
            ("dci-p3", CGSize(width: 80, height: 48)),
            ("dci-p3-portrait", CGSize(width: 48, height: 80))
        ]
        for (name, expectedSize) in cases {
            let source = try fixture(name)
            let destination = temporaryOutput()
            defer { try? FileManager.default.removeItem(at: destination) }
            let info = try await convert(source, to: destination,
                settings: .init(codec: .hevc, bitrate: .encoder, quality: 1,
                    size: .fit(boundingSize), profile: .hevcMain))
            XCTAssertEqual(info.resolution, expectedSize, name)
            let image = try await firstFrame(AVURLAsset(url: destination))
            XCTAssertEqual(image.width, Int(expectedSize.width), name)
            XCTAssertEqual(image.height, Int(expectedSize.height), name)

            // The independent basic compositor applies the track transform;
            // the image generator then scales uniformly to the requested size.
            let original = AVURLAsset(url: source)
            let composition = AVMutableVideoComposition(propertiesOf: original)
            #if !os(macOS)
            composition.colorPrimaries = AVVideoColorPrimaries_P3_D65
            composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
            composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            #endif
            let reference = try await firstFrame(original, composition: composition, maximumSize: expectedSize)
            XCTAssertEqual(reference.width, Int(expectedSize.width), name)
            XCTAssertEqual(reference.height, Int(expectedSize.height), name)
            let expected = try linearPixels(reference)
            let actual = try linearPixels(image)
            XCTAssertEqual(actual.count, expected.count)
            let exportError = meanAbsoluteError(actual, expected)

            // Controls lose half the image and stretch it, mirror it, or rotate
            // it. Correct geometry must be at least twice as close to reference.
            let referenceImage = CIImage(cgImage: reference)
            let halfBounds = referenceImage.extent.divided(atDistance: expectedSize.width / 2, from: .minXEdge).slice
            let controls = [
                referenceImage.cropped(to: halfBounds).resizing(to: expectedSize),
                referenceImage.oriented(.upMirrored),
                referenceImage.oriented(.down)
            ]
            let minimumImprovementFactor: Float = 2
            for control in controls {
                let controlImage = try XCTUnwrap(CIContext().createCGImage(control, from: control.extent))
                let controlPixels = try linearPixels(controlImage)
                XCTAssertEqual(controlPixels.count, expected.count)
                let controlError = meanAbsoluteError(controlPixels, expected)
                print("DCI-P3 \(name) geometry mean error: export=\(exportError), control=\(controlError)")
                XCTAssertLessThan(exportError * minimumImprovementFactor, controlError, name)
            }
        }
    }

    func testDCIP3WriterSetupRetainsBothErrors() async throws {
        let asset = AVURLAsset(url: try fixture("dci-p3"))
        do {
            // An invalid encoder profile makes both writer-input attempts fail,
            // including on macOS where DCI-P3 primaries themselves are accepted.
            _ = try await VideoTool.initializeVideo(asset: asset,
                videoSettings: .init(codec: .hevc, profile: .value("invalid-profile")))
            XCTFail("Invalid profile must fail writer setup")
        } catch {
            let diagnostic = error as NSError
            let underlying = try XCTUnwrap(diagnostic.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError])
            XCTAssertEqual(underlying.count, 2)
            let original = try XCTUnwrap(underlying.first)
            let retry = try XCTUnwrap(underlying.last)
            XCTAssertEqual((diagnostic.userInfo[NSUnderlyingErrorKey] as? NSError), original)
            XCTAssertTrue(retry.localizedDescription.contains(AVVideoProfileLevelKey))
            XCTAssertTrue(diagnostic.localizedDescription.contains(original.localizedDescription))
            XCTAssertTrue(diagnostic.localizedDescription.contains(retry.localizedDescription))
        }
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

    func testExplicitSDRColorConversion() async throws {
        // SMPTE-C is the case the writer alone retags without converting.
        for color in [CompressionColorPrimary.smpteC, .ebu3213, .itu2020] {
            try await checkExplicitColor("dci-p3", color: color)
        }
    }

    func testExplicitHDRToSDRToneMapping() async throws {
        // Main10 keeps 8-bit quantization of the tone-mapped 10-bit source out of
        // the budget. Re-subsampling tone-mapped chroma moves single pixels along
        // the fixture's sharp edges; compare 8x8 block means for the tone curve.
        let info = try await checkExplicitColor("dci-p3-hlg", color: .itu709_2, profile: .hevcMain10, blockSize: 8)
        XCTAssertFalse(info.isHDR)
    }

    func testExplicitSDRToHDRColor() async throws {
        let source = try fixture("dci-p3")
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        let info = try await convert(source, to: destination,
            settings: .init(codec: .hevc, color: .itu2020_hlg), skipAudio: true)
        XCTAssertTrue(info.isHDR)
        let description = try await videoDescription(AVURLAsset(url: destination))
        XCTAssertEqual(description.colorPrimaries, AVVideoColorPrimaries_ITU_R_2020)
        XCTAssertEqual(description.transferFunction, AVVideoTransferFunction_ITU_R_2100_HLG)
        XCTAssertEqual(description.matrix, AVVideoYCbCrMatrix_ITU_R_2020)
        // HDR transfer functions in an 8-bit stream would band visibly.
        try checkHEVCBitDepth(description, expected: 10)
    }

    func testAnamorphicPortraitThroughCompositor() async throws {
        // 2:1 pixels under a 90° track transform. The compositor applies the
        // turn to encoded pixels, so the horizontal spacing must not survive it.
        let source = try fixture("anamorphic-portrait")
        let displayedSize = CGSize(width: 96, height: 320)
        let reference = try await firstFrame(AVURLAsset(url: source))
        XCTAssertEqual(CGSize(width: reference.width, height: reference.height), displayedSize,
            "The fixture must carry non-square pixels and a portrait track transform")
        let expected = try linearPixels(reference)

        // Controls: the regression squeezed the picture into the lower half,
        // and an upside-down frame stands in for a wrong orientation.
        let referenceImage = CIImage(cgImage: reference)
        let squeezed = referenceImage.transformed(by: CGAffineTransform(scaleX: 1, y: 0.5))
            .composited(over: CIImage(color: .black).cropped(to: referenceImage.extent))
        var controls: [[Float]] = []
        for control in [squeezed, referenceImage.oriented(.down)] {
            let controlImage = try XCTUnwrap(CIContext().createCGImage(control, from: referenceImage.extent))
            controls.append(try linearPixels(controlImage))
        }

        let cases: [(String, CompressionVideoSettings)] = [
            ("color", .init(codec: .hevc, bitrate: .encoder, quality: 1, profile: .hevcMain, color: .p3D65)),
            ("imageComposition", .init(codec: .hevc, bitrate: .encoder, quality: 1, profile: .hevcMain,
                edit: [.process(.imageComposition { image, _, _ in image })])),
            ("color and image processor", .init(codec: .hevc, bitrate: .encoder, quality: 1, profile: .hevcMain,
                color: .p3D65, edit: [.process(.image { image, _, _ in image })]))
        ]
        for (name, settings) in cases {
            let destination = temporaryOutput()
            defer { try? FileManager.default.removeItem(at: destination) }
            let info = try await convert(source, to: destination, settings: settings, skipAudio: true)
            XCTAssertEqual(info.resolution, displayedSize, name)
            let image = try await firstFrame(AVURLAsset(url: destination))
            XCTAssertEqual(CGSize(width: image.width, height: image.height), displayedSize, name)
            guard image.width == reference.width, image.height == reference.height else { continue }
            let exportError = meanAbsoluteError(try linearPixels(image), expected)
            let minimumImprovementFactor: Float = 2
            for controlPixels in controls {
                let controlError = meanAbsoluteError(controlPixels, expected)
                print("Anamorphic \(name) mean error: export=\(exportError), control=\(controlError)")
                XCTAssertLessThan(exportError * minimumImprovementFactor, controlError, name)
            }
        }
    }

    func testAnamorphicPortraitResize() async throws {
        // Bounds and exact sizes apply to the displayed 96x320 picture, and
        // resized output has square pixels on every frame-processing path.
        let source = try fixture("anamorphic-portrait")
        let reference = CIImage(cgImage: try await firstFrame(AVURLAsset(url: source)))
        let processors: [(String, VideoFrameProcessor?)] = [
            ("track output", nil),
            ("imageComposition", .imageComposition { image, _, _ in image }),
            ("image", .image { image, _, _ in image })
        ]
        let sizes: [(CompressionVideoSize, CGSize)] = [
            (.fit(CGSize(width: 200, height: 200)), CGSize(width: 60, height: 200)),
            (.scale(CGSize(width: 48, height: 160)), CGSize(width: 48, height: 160))
        ]
        for (size, expectedSize) in sizes {
            // Independent reference: stretch the displayed frame on both axes.
            let expectedImage = reference.samplingLinear().transformed(by: CGAffineTransform(
                scaleX: expectedSize.width / reference.extent.width,
                y: expectedSize.height / reference.extent.height))
            let expectedFrame = try XCTUnwrap(CIContext().createCGImage(expectedImage,
                from: CGRect(origin: .zero, size: expectedSize)))
            let expected = try linearPixels(expectedFrame)
            let upsideDown = try XCTUnwrap(CIContext().createCGImage(expectedImage.oriented(.down),
                from: CGRect(origin: .zero, size: expectedSize)))
            let controlError = meanAbsoluteError(try linearPixels(upsideDown), expected)
            for (name, processor) in processors {
                let label = "\(name) \(size)"
                let destination = temporaryOutput()
                defer { try? FileManager.default.removeItem(at: destination) }
                let info = try await convert(source, to: destination, settings: .init(codec: .hevc,
                    bitrate: .encoder, quality: 1, size: size, profile: .hevcMain,
                    edit: processor.map { [.process($0)] } ?? []), skipAudio: true)
                XCTAssertEqual(info.resolution, expectedSize, label)
                let result = AVURLAsset(url: destination)
                let description = try await videoDescription(result)
                let spacing = description.pixelAspectRatio
                XCTAssertEqual(spacing?.horizontalSpacing ?? 1, spacing?.verticalSpacing ?? 1, label)
                let image = try await firstFrame(result)
                XCTAssertEqual(CGSize(width: image.width, height: image.height), expectedSize, label)
                guard image.width == expectedFrame.width, image.height == expectedFrame.height else { continue }
                let exportError = meanAbsoluteError(try linearPixels(image), expected)
                print("Anamorphic resize \(label) mean error: export=\(exportError), control=\(controlError)")
                XCTAssertLessThan(exportError * 2, controlError, label)
            }
        }
    }

    #if os(macOS)
    func testProResHDRWithImageProcessor() async throws {
        // Core Image cannot render into the 10-bit 4:2:2 buffers used for
        // ProRes HDR; an identity image processor must match no processor.
        let cases: [(String, CompressionColorPrimary?)] = [("dci-p3-hlg", nil), ("dci-p3", .itu2020_hlg)]
        for (name, color) in cases {
            let source = try fixture(name)
            var pixels: [[Float]] = []
            for edit: Set<VideoOperation> in [[], [.process(.image { image, _, _ in image })]] {
                let destination = temporaryOutput()
                defer { try? FileManager.default.removeItem(at: destination) }
                let info = try await convert(source, to: destination,
                    settings: .init(codec: .proRes422, color: color, edit: edit), skipAudio: true)
                XCTAssertTrue(info.isHDR, name)
                let result = AVURLAsset(url: destination)
                let description = try await videoDescription(result)
                XCTAssertEqual(description.transferFunction, AVVideoTransferFunction_ITU_R_2100_HLG, name)
                pixels.append(try await decodedPixels(result))
            }
            let processorError = meanAbsoluteError(pixels[1], pixels[0])
            print("\(name) ProRes HLG image-processor mean error: \(processorError)")
            XCTAssertLessThan(processorError, 1 / Float(UInt8.max), name)
        }
    }
    #endif

    @discardableResult
    private func checkExplicitColor(
        _ name: String,
        color: CompressionColorPrimary,
        profile: CompressionVideoProfile = .hevcMain,
        blockSize: Int = 1
    ) async throws -> VideoInfo {
        let source = try fixture(name)
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        // Maximum SDR quality keeps quantization below the color-error budget.
        let info = try await convert(source, to: destination,
            settings: .init(codec: .hevc, bitrate: .encoder, quality: 1, profile: profile, color: color),
            skipAudio: true)

        let expectedColor = VideoColorInformation(for: color)
        let original = AVURLAsset(url: source)
        let result = AVURLAsset(url: destination)
        let description = try await videoDescription(result)
        XCTAssertEqual(description.colorPrimaries, expectedColor.colorPrimaries, "\(color)")
        XCTAssertEqual(description.transferFunction, expectedColor.transferFunction, "\(color)")
        XCTAssertEqual(description.matrix, expectedColor.matrix, "\(color)")

        // Apple's basic compositor is the independent conversion reference.
        // Decode through AVAssetReader: AVAssetImageGenerator tone-maps HDR
        // sources differently from the reader composition used for export.
        let composition = AVMutableVideoComposition(propertiesOf: original)
        composition.colorPrimaries = expectedColor.colorPrimaries
        composition.colorYCbCrMatrix = expectedColor.matrix
        composition.colorTransferFunction = expectedColor.transferFunction
        let expected = try await decodedPixels(original, composition: composition, blockSize: blockSize)
        let actual = try await decodedPixels(result, blockSize: blockSize)
        let retagged = try await decodedPixels(original, retaggedAs: expectedColor, blockSize: blockSize)
        XCTAssertEqual(actual.count, expected.count)
        let conversionError = meanAbsoluteError(actual, expected)
        let retaggingError = meanAbsoluteError(retagged, expected)
        let maximumMeanError = 1 / Float(UInt8.max)
        let minimumImprovementFactor: Float = 2
        print("\(name) -> \(color) linear-RGB mean error: export=\(conversionError), retag-only=\(retaggingError)")
        XCTAssertLessThan(conversionError, maximumMeanError, "\(color)")
        XCTAssertLessThan(conversionError * minimumImprovementFactor, retaggingError,
            "\(color): changing tags alone must not satisfy the pixel-color check")
        return info
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
        let conversionError = meanAbsoluteError(actual, expected)
        let retaggingError = meanAbsoluteError(retagged, expected)
        // At most one normalized 8-bit level of mean linear-RGB error, and
        // at least twice as close to the reference as the retag-only control.
        let maximumMeanError = 1 / Float(UInt8.max)
        let minimumImprovementFactor: Float = 2
        print("DCI-P3 linear-RGB mean error: export=\(conversionError), retag-only=\(retaggingError)")
        XCTAssertLessThan(conversionError, maximumMeanError)
        XCTAssertLessThan(conversionError * minimumImprovementFactor, retaggingError,
            "Changing tags alone must not satisfy the pixel-color check")
    }

    private func meanAbsoluteError(_ actual: [Float], _ expected: [Float]) -> Float {
        zip(actual, expected).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(expected.count)
    }

    private func firstFrame(
        _ asset: AVAsset,
        composition: AVVideoComposition? = nil,
        maximumSize: CGSize = .zero
    ) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = composition
        generator.maximumSize = maximumSize
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if #available(macOS 13, iOS 16, tvOS 16, *) {
            return try await generator.image(at: .zero).image
        } else {
            return try generator.copyCGImage(at: .zero, actualTime: nil)
        }
    }

    /// First-frame RGB in linear sRGB, color-managed from the buffer's tags.
    private func decodedPixels(
        _ asset: AVAsset,
        composition: AVVideoComposition? = nil,
        retaggedAs color: VideoColorInformation? = nil,
        blockSize: Int = 1
    ) async throws -> [Float] {
        let maybeTrack = await asset.getFirstTrack(withMediaType: .video)
        let track = try XCTUnwrap(maybeTrack)
        let reader = try AVAssetReader(asset: asset)
        let settings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf]
        let output: AVAssetReaderOutput
        if let composition {
            let compositionOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: settings)
            compositionOutput.videoComposition = composition
            output = compositionOutput
        } else {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        }
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        defer { reader.cancelReading() }
        let sample = try XCTUnwrap(output.copyNextSampleBuffer())
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        if let color {
            // Control: keep the decoded values but reinterpret them in the target space.
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey,
                color.colorPrimaries as CFString, .shouldPropagate)
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey,
                color.transferFunction as CFString, .shouldPropagate)
            CVBufferRemoveAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey)
        }
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if blockSize > 1 {
            let blockScale = 1 / CGFloat(blockSize)
            image = image.applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: blockSize / 2])
                .cropped(to: image.extent)
                .transformed(by: CGAffineTransform(scaleX: blockScale, y: blockScale))
        }
        let context = CIContext()
        let cgImage = try XCTUnwrap(context.createCGImage(image, from: image.extent,
            format: .RGBAh, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)))
        return try linearPixels(cgImage)
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
    ) async throws -> VideoInfo {
        do {
            return try await VideoTool.convert(
                source: source, destination: destination,
                videoSettings: settings, skipAudio: skipAudio, customMetadata: metadata
            )
        } catch is CancellationError {
            throw ConversionFailure(errorDescription: "Unexpected cancellation")
        } catch {
            // The exception catcher's underlying NSException cannot be archived
            // by XCTest on iOS; preserve its reason in a serializable test error.
            throw ConversionFailure(errorDescription: error.localizedDescription)
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
