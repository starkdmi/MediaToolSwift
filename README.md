## MediaToolSwift
> Advanced media converter for iOS, macOS and tvOS

## Video
__Video compressor focused on:__
- Multiple video and audio codecs
- Lossless
- HDR content
- Alpha channel
- Slow motion
- Metadata (File metadata, Timed metadata, Extended attributes)
- Hardware Acceleration
- Progress and cancellation

__[Features](Files/VIDEO.md)__
| Convert | Resize | Crop | Cut | Rotate, Flip, Mirror | Image Processing[\*](Tests/VideoTests.swift#:~:text=testImageProcessing) | FPS | Thumbnail | Video Preview | Info |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| ✔️ | ✔️ | ✔️ | ⭐️ | ⭐️ | ✔️ | ✔️ | 🚧 | ➖ | 🚧 |

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
        case .completed(let url):
            print("Done: \(url.path)")
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

## Requirements
* iOS 13.0+
* macOS 11.0+
* tvOS 13.0+

## Documentation
Swift DocC documentation is hosted on [Github Pages](https://starkdmi.github.io/MediaToolSwift/documentation/mediatoolswift)

More info on video features and operations can be found [here](Files/VIDEO.md).

## Installation
### Swift Package Manager
To install library with Swift Package Manager, add the following code to your __Package.swift__ file:
```
dependencies: [
    .package(url: "https://github.com/starkdmi/MediaToolSwift.git", .upToNextMajor(from: "1.0.6"))
]
```

### CocoaPods
To install library with CocoaPods, add the following line to your __Podfile__ file:
```
pod 'MediaToolSwift', :git => 'https://github.com/starkdmi/MediaToolSwift.git', :version => '1.0.6'
```

## Problem Resolving
### Metadata Stripping
By default Xcode remove the metadata from output file, to prevent go to Build Settings tab, Under the __Other C Flags__ section, add the following flag: ```-fno-strip-metadata```

### Redunant Compression
In case the video and audio won't be modified based on source file and output settings the compression will fail with ```CompressionError.redunantCompression```
