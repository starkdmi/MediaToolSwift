## MediaToolSwift
> Advanced media converter for Apple devices

## Requirements
* macOS 12.0+
* iOS 15.0+
* tvOS 15.0+
* Mac Catalyst 15.0+
* visionOS 1.0+
* Xcode 16.0+

## Installation
### Swift Package Manager
To install library with Swift Package Manager, add the following code to your __Package.swift__ file:
```
dependencies: [
    .package(url: "https://github.com/starkdmi/MediaToolSwift.git", .upToNextMajor(from: "1.3.0"))
]
```

### CocoaPods
To install library with CocoaPods, add the following line to your __Podfile__ file:
```
pod 'MediaToolSwift'
```

### Swift 6 concurrency

Closures you hand to MediaToolSwift run on library-managed queues, not on your
caller's actor. All of them are now `@Sendable` and reject unsynchronized
captures at compile time:

* `VideoFrameProcessor` (every case)
* `CompressionVideoBitrate.dynamic`
* `CompressionVideoSize.dynamic`
* `ImageProcessor`

This is a source-breaking change from 1.x, and `@preconcurrency import` does not
soften it — `@Sendable` is part of the function type rather than a conformance.
Move captured state into a synchronized box or an actor, and hop explicitly
before touching actor-isolated state.

The terminal `callback:` on `VideoTool.convert` and `AudioTool.convert` is gone,
as are the `thumbnailImages` and `thumbnailFiles` completions: all four now
return their result and throw on failure, so there is no state closure left to
constrain.

A `CompressionTask` tracks one conversion. Passing a task that is already in
flight or finished throws `CompressionError.taskAlreadyUsed` — create a new task
per conversion.

`thumbnailImages` and `thumbnailFiles` inherit the caller's isolation, so an
`AVAsset` held by a `@MainActor` view model can be passed directly even though
`AVAsset` is not `Sendable`. Thumbnail decoding and encoding still run off your
actor.

## VideoTool
__Video compressor focused on:__
- Multiple video and audio codecs
- Lossless
- HDR content
- Alpha channel
- Slow motion
- Metadata
- Hardware Acceleration
- Progress and cancellation

__[Features](Files/VIDEO.md)__

Transcoding preserves static HDR color tags, but codec-private dynamic HDR and
Dolby Vision metadata may not survive an AVFoundation re-encode. Use passthrough
settings when exact dynamic-metadata preservation is required. Explicit color
space or transfer-function overrides remain unsupported. On platforms with
video-composition support, a writer rejecting DCI-P3, EBU 3213, or P22 source
primaries uses Apple's native compositor to convert the pixels into supported
primaries in the same encode.
DCI-P3 SDR retains wide color in P3-D65; HLG/PQ retain their transfer function and
10-bit depth in BT.2020. Accepted source profiles and video passthrough retain
their original color tags.

| Convert | Resize | Crop | Cut | Rotate, Flip, Mirror | Frame Processing[\*](Files/VIDEO.md#frame-processing) | FPS | Thumbnail | Info |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| ✔️ | ✔️ | ✔️ | ⭐️ | ⭐️ | ✔️ | ✔️ | ✔️ | ✔️ |

⭐️ - _do not require re-encoding (lossless)_

__Supported video codecs:__
- H.264
- H.265/HEVC
- ProRes
- JPEG

> Additionally decoding is supported for: H.263, MPEG-1, MPEG-2, MPEG-4 Part 2

__Supported audio codecs:__
- AAC
- Opus
- FLAC
- Linear PCM
- Apple Lossless

__Example:__
```Swift
// A task is optional - pass one to report progress or to cancel the
// conversion from outside the awaiting context.
let task = CompressionTask(destination: URL(fileURLWithPath: "output.mov"))

// Observe progress
task.progress.observe(\.fractionCompleted) { progress, _ in
    print("Progress", progress.fractionCompleted)
}

// Run video compression
let info = try await VideoTool.convert(
    source: URL(fileURLWithPath: "input.mp4"),
    destination: URL(fileURLWithPath: "output.mov"),
    // Video
    fileType: .mov, // mov, mp4, m4v
    videoSettings: .init(
        codec: .hevc,
        bitrate: .value(2_000_000), // optional
        size: .fit(.hd), // size to fit or fill
        // quality, fps, alpha channel, profile, color primary, atd.
        edit: [
            .cut(from: 2.5, to: 15.0), // cut, in seconds
            .rotate(.clockwise), // rotate
            // crop, flip, mirror, atd.

            // modify video frames as images or access pixel buffers
            .process(.image { image, _, _ in
                image.applyingGaussianBlur(sigma: 7)
            })
        ]
    ),
    optimizeForNetworkUse: true,
    // Audio
    skipAudio: false,
    audioSettings: .init(
        codec: .opus,
        bitrate: .value(96_000)
        // quality, sample rate, volume, atd.
    ),
    // Metadata
    skipSourceMetadata: false,
    customMetadata: [],
    copyExtendedFileMetadata: true,
    // File options
    overwrite: false,
    deleteSourceFile: false,
    task: task
)
print("Done: \(info.url.path)")

// Cancel compression - from anywhere holding the task, or by cancelling
// the enclosing Swift `Task`
task.cancel()
```
Complex example can be found in [this](Example/) directory.

## ImageTool
__Image converter focused on:__
- Popular image formats
- Animated image sequences
- HDR content
- Metadata
- Orientation
- Multiple Frameworks

__[Features](Files/IMAGE.md)__
| Convert | Resize | Crop | Rotate, Flip, Mirror | Image Processing | FPS | Info |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |

__Supported image formats:__
- HEIF
- HEIF 10-bit
- HEIC
- HEICS (HEIFS) ✨
- PNG ✨
- GIF ✨
- JPEG
- TIFF
- BMP
- JPEG 2000
- OpenEXR
- ICO
- PDF

> Additionally decoding is supported for: WebP ✨, AVIF and others

✨ - _support animated image sequences_

__Example:__
```Swift
let info = try ImageTool.convert(
    source: URL(fileURLWithPath: "input.webp"),
    destination: URL(fileURLWithPath: "output.png"),
    settings: .init(
        format: .png,
        size: .fit(.fhd), // size to fit in
        // size: .crop(options: .init(size: CGSize(width: 512, height: 512), aligment: .center)), // or cropping area
        // quality, frame rate, background color, atd.
        edit: [
            .rotate(.clockwise), // rotate and crop
            // .rotate(.angle(.pi/4), fill: .blur(kernel: 55)), // rotate extend blurred
            // .rotate(.angle(.pi/4), fill: .color(alpha: 255, red: 255, green: 255, blue: 255)), // rotate extend with color
            // flip, mirror, atd.

            // modify image frame(s)
            .imageProcessing { ciImage, cgImage, _, _ in
                guard let ciImage = ciImage else { return (ciImage, cgImage) }
                return (ciImage.applyingGaussianBlur(sigma: 7), nil)
            }
        ]
    )
)
```

## AudioTool
__Audio converter focused on:__
- Multiple audio formats
- Lossless
- Metadata
- Hardware Acceleration
- Progress and cancellation

__[Features](Files/AUDIO.md)__
| Convert | Cut | Info |
| :---: | :---: | :---: |
| ✔️ | ⭐️ | ✔️ |

⭐️ - _do not require re-encoding (lossless)_

__Supported audio formats:__
- AAC
- Opus
- FLAC
- Linear PCM
- Apple Lossless

> Supported audio file containers are `M4A`, `WAV`, `CAF`, `AIFF`, `AIFC`, `AMR`

__Example:__
```Swift
let task = CompressionTask(destination: URL(fileURLWithPath: "output.m4a"))

// Observe progress
task.progress.observe(\.fractionCompleted) { progress, _ in
    print("Progress", progress.fractionCompleted)
}

// Run audio conversion
let info = try await AudioTool.convert(
    source: URL(fileURLWithPath: "input.mp3"),
    destination: URL(fileURLWithPath: "output.m4a"),
    // Audio
    fileType: .m4a,
    settings: .init(
        codec: .flac,
        bitrate: .value(96_000)
        // quality, sample rate, volume, atd.
    ),
    edit: [
        .cut(from: 2.5, to: 15.0), // cut, in seconds
    ],
    // Metadata
    skipSourceMetadata: false,
    customMetadata: [],
    copyExtendedFileMetadata: true,
    // File options
    overwrite: false,
    deleteSourceFile: false,
    task: task
)
print("Done: \(info.url.path)")

// Cancel conversion
task.cancel()
```

## Documentation
Swift DocC documentation is hosted on [Github Pages](https://starkdmi.github.io/MediaToolSwift/documentation/mediatoolswift)

Use those links for more info on [video](Files/VIDEO.md), [image](Files/IMAGE.md) and [audio](Files/AUDIO.md) features and operations.

## Testing

The required macOS suite runs only the deterministic smoke corpus. Large HDR, alpha, slow-motion, ProRes, and gain-map coverage runs in the scheduled extended suite. Those existing fixtures remain in Git for this 1.x stabilization branch: an LFS history rewrite would not reduce normal full-clone size while the published `1.2.0` tag is retained, and would add release risk. New large fixtures should not be added until a separate storage and history-migration decision is made. See [Tests/README.md](Tests/README.md) for fixture tiers and local commands.

## Flutter
`MediaToolSwift` is available in [Flutter](https://github.com/flutter/flutter) via [media_tool_flutter](https://pub.dev/packages/media_tool_flutter) plugin.

## Media Tool
There is a standalone macOS application based on `MediaToolSwift` source, more info can be found at [mediatool.pro](https://mediatool.pro)
