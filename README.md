## MediaToolSwift
> Advanced media converter for iOS, macOS and tvOS

## Requirements
* macOS 11.0+
* iOS 13.0+
* tvOS 13.0+

## Installation
### Swift Package Manager
To install library with Swift Package Manager, add the following code to your __Package.swift__ file:
```
dependencies: [
    .package(url: "https://github.com/starkdmi/MediaToolSwift.git", .upToNextMajor(from: "1.0.9"))
]
```

### CocoaPods
To install library with CocoaPods, add the following line to your __Podfile__ file:
```
pod 'MediaToolSwift', '~> 1.0.9'
```

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
| Convert | Resize | Crop | Cut | Rotate, Flip, Mirror | Image Processing[\*](Tests/VideoTests.swift#:~:text=testImageProcessing) | FPS | Thumbnail | Info |
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
// Run video compression
let task = await VideoTool.convert(
    source: URL(fileURLWithPath: "input.mp4"),
    destination: URL(fileURLWithPath: "output.mov"),
    // Video
    fileType: .mov, // mov, mp4, m4v
    videoSettings: .init(
        codec: .hevc,
        bitrate: .value(2_000_000), // optional
        size: .hd, // CGSize to aspect fit in
        // quality, fps, alpha channel, profile, color primary, atd.
        edit: [
            .cut(from: 2.5, to: 15.0), // cut, in seconds
            .rotate(.clockwise), // rotate
            // crop, flip, mirror, atd.

            // modify video frames as images
            .imageProcessing { image, size, _ in
                image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                    "inputRadius": 7.5
                ]).cropped(to: CGRect(origin: .zero, size: size))
            }
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
    // State notifier
    callback: { state in
        switch state {
        case .started:
            print("Started")
        case .progress(let progress):
            print("Progress: \(progress.fractionCompleted)")
        case .completed(let info):
            print("Done: \(info.url.path)")
        case .failed(let error):
            print("Error: \(error.localizedDescription)")
        case .cancelled:
            print("Cancelled")
        }
})

// Cancel the compression
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
| ✔️ | ✔️ | ✔️ | ✔️ | 🚧 | ✔️ | ✔️ |

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
- ICO

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
// Run audio conversion
let task = await AudioTool.convert(
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
    // State notifier
    callback: { state in
        switch state {
        case .started:
            print("Started")
        case .progress(let progress):
            print("Progress: \(progress.fractionCompleted)")
        case .completed(let info):
            print("Done: \(info.url.path)")
        case .failed(let error):
            print("Error: \(error.localizedDescription)")
        case .cancelled:
            print("Cancelled")
        }
})

// Cancel the conversion
task.cancel()
```

## Documentation
Swift DocC documentation is hosted on [Github Pages](https://starkdmi.github.io/MediaToolSwift/documentation/mediatoolswift)

More info on video and image features and operations can be found [here](Files/VIDEO.md) and [here](Files/IMAGE.md) respectively.
