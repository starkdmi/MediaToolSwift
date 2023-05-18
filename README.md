## MediaToolSwift
> Advanced media converter for iOS and macOS

## Video
__Video compressor focused on:__
- Multiple video and audio codecs
- HDR content
- Alpha channel
- Metadata (File metadata, Timed metadata, Extended attributes)
- Resizing with aspect ratio
- Frame rate adjustment
- Progress and cancellation

__Features:__
| Convert | Resize | Trim | Crop | Custom FPS | Thumbnail | Video Preview | Info |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| ✅ | ✅ | ❌ | ❌ | ✅ | 🟠 | 🟠 | 🟠 |

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

__Example:__
```Swift
// Run video compression
let task = await VideoTool.convert(
    source: URL(fileURLWithPath: "input.mp4"),
    destination: URL(fileURLWithPath: "output.mov"),
    // Video container (mov, mp4, m4v)
    fileType: .mov,
    // Video settings including codec, bitrate, size, atd.
    videoSettings: CompressionVideoSettings(codec: .hevc, size: CGSize(width: 1280.0, height: 1280.0)),
    // Audio settings including codec, bitrate and others
    audioSettings: CompressionAudioSettings(codec: .opus, bitrate: 96_000),
    // State notifier
    callback: { state in
        switch state {
        case .started:
            print("Started")
            break
        case .progress(let progress):
            print("Progress: \(progress.fractionCompleted)")
            break
        case .completed(let url):
            print("Done: \(url.path)")
            break
        case .failed(let error):
            print("Error: \(error.localizedDescription)")
            break
        case .cancelled:
            print("Cancelled")
            break
        }
})

// Cancel the compression
task.cancel()
```
Complex example can be found in [this](./Example/) directory.

## Requirements
* iOS 13.0+
* macOS 11.0+

## Documentation
Documentation is hosted on [Github Pages](https://starkdmi.github.io/MediaToolSwift/documentation/mediatoolswift)

## Installation
### Swift Package Manager
To install library with Swift Package Manager, add the following code to your __Package.swift__ file:
```
dependencies: [
    .package(url: "https://github.com/starkdmi/MediaToolSwift.git", .upToNextMajor(from: "1.0.0"))
]
```

### CocoaPods
To install library with CocoaPods, add the following line to your __Podfile__ file:
```
pod 'MediaToolSwift', :git => 'https://github.com/starkdmi/MediaToolSwift.git', :version => '1.0.0'
```

## Problem Solving
### Metadata Stripping
By default Xcode remove the metadata from output file, to prevent go to Build Settings tab, Under the __Other C Flags__ section, add the following flag: ```-fno-strip-metadata```