## Main
- __Logger__ - Simple logging feature plus operations descriptions like [this](https://stackoverflow.com/a/23271969/20387962). Add kvImagePrintDiagnosticsToConsole to each kVImageFlags in vImage code.
- __Command line tool__ - command line application like avconvert and ffmpeg
- __Split voices/sounds in Video and Audio__ - Split different noises in audio track into multiple separate audio tracks (wind noise, music, voice #1, voice #2)

## Video
__Base__
- __AVAssetReaderOutput.alwaysCopiesSampleData__ - `videoOutput.alwaysCopiesSampleData` set to `false` may improve the perfomance, default to `true`. Check if applicable
- __AVAssetWriterInput.performsMultiPassEncodingIfSupported__ - `videoInput.performsMultiPassEncodingIfSupported` may improve the compression in some cases, check availability via `videoInput.canPerformMultiplePasses`
- __Multiple video/audio/metadata tracks support__ - option to save all video/audio/metadata tracks from source file to output (now only first track for each track media type is stored)
- __VP9 and AV1 video codecs support using VideoToolBox__ - VTDecompressionSession and VTCompressionSession can be used inside sample buffer processing block for frame by frame decoding/encoding
- __vImage Image Processing__ - another callback with `vImage` instead of `CIImage` - [docs](https://developer.apple.com/documentation/accelerate/applying_vimage_operations_to_video_sample_buffers), [docs](https://developer.apple.com/documentation/accelerate/core_video_interoperability),
    [github demo](https://github.com/madhaviKumari/ApplyingVImageOperationsToVideoSampleBuffers)
- __Video thumbnails threading__ - check the main thread isn't busy
- __Video thumbnails cancellation feature__ - generator.cancelAllCGImageGeneration()
- __Video thumbnails progress feature__
- __Video thumbnails overwrite option__
- __Audio only__ - remove video and metadata tracks

__Codecs__
```
VP9, AV1
```

__Video to GIF__

__Video to Images__ - With specified frame rate and directory - 001.png, 002.png

__Video Preview__ - animated image/video file with a little of best video frames stitched together at a small frame rate, GIF can be used instead of WebP

__Insert video__ - insert/add video track before/after the source video

__Advanced Cutting__ - select multiple ranges of audio/video track and stitch them together while removing unselected parts. this feature can be done without re-encoding video frames (losslessly)

__Editor (Example)__ - Draw on video in real time playback [HandDrawn](https://github.com/starkdmi/HandDrawn) or something like [this](https://github.com/ltebean/LTVideoRecorder). Each Curve, shape added to current video frame, pause/continue feature.

__Frame rate and resolution upscaling__ - combine nearest frames to produce middle one, upscale/enlarge/unblur pixels

__Video Stabilization__ - only using native Swift code (no 3rd party libraries like OpenCV and ffmpeg)
[VNHomographicImageRegistrationRequest](https://developer.apple.com/documentation/vision/VNHomographicImageRegistrationRequest) + [vImage](https://developer.apple.com/documentation/accelerate/vimage) + [VNTranslationalImageRegistrationRequest](https://developer.apple.com/documentation/vision/VNTranslationalImageRegistrationRequest)

__AI__ - face landmark, pose detections, atd. using Vision framework

## Audio
__Base__
- __AudioToolbox__ - Instead of using `VideoToolBox` (AVAssetReader/AVAssetWriter) try `AudioToolBox` framework
- __MP3 support__ - Add `MP3` support to the `plus` branch via [libmp3lame.a](https://github.com/maysamsh/Swift-MP3Converter) (slow, 2MB of size)

| Speed adjustment | [Reverse](https://www.limit-point.com/blog/2022/reverse-audio/) | Waveform | Custom Chunk Processor |
| :---: | :---: | :---: | :---: |
| 🚧 | 🚧 |➖ | ➖ |

__Info__
``` 
filesize, sample rate, waveform
```

## Image

__Base__
- Quality options should also apply to lossless formats to decrease file size when converting PNG to PNG
- Prefer `CIImage` load/edit when output format is HEIF/HEIF10
- `CGColorSpace` and `CIFormat` optional parameters
- Reuse `CGContext` for similar operations on animated images (inout parameter or store in `ImageProcessor` with all temp buffers and contexts)
- `vImageScale_ARGB8888` takes temporary buffer as argument - reuse (but not the same one used for rotation)
- `CGImage` loading should accept floating point via `kCGImageSourceShouldAllowFloat`?
- Test images with HDR Gain Map, fallback to `CIImage` if contains gain map?
- Frame rate adjustment performance improvement - when `settings.frameRate` is specified, load properties, calculate duration and frame rate and do NOT load unused frames.
- Animated image concurency
- Instead of custom `imageProcessing()` for images use the `CGAffineTransform`? Supported by all three image frameworks.
- New image/video operation - blur region of interest - `vImage_Buffer.blurred_ARGB8888(regionOfInterest:blurRadius:)`
- Strip GPS metadata using `kCGImageMetadataShouldExcludeGPS`?
- Resolve invalid frame rate (rounding))
- Background remover (lift an object via [VNGenerateForegroundInstanceMaskRequest](https://developer.apple.com/videos/play/wwdc2023/10176/)) iOS 17+ or `VNGeneratePersonSegmentationRequest` iOS 15+)
- BlurHash

__Formats__
```
WebP

[AVIF](https://github.com/SDWebImage/SDWebImageAVIFCoder)

SVG (PNG, JPEG, ... in SVG tag) - https://github.com/dagronf/SwiftImageReadWrite

PDF
```

__Panoramas, Portraits, Live Photos, Raw Images__
- Live Photo = Heic image + QuickTime video, [LivePhoto.Swift](https://github.com/LimitPoint/LivePhoto), `UTType.livePhoto`
- Panoramas = extra wide photo (?)

__BlurHash__
Can be implemented using [BlurHashKit](https://github.com/woltapp/blurhash/blob/master/Swift/BlurHashEncode.swift) Swift implementation - one standalone files - rewrite to use `CGImage` instead of `UIImage`.

__AI__ - [FILM: Frame Interpolation](https://film-net.github.io/)
