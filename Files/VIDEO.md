## Convert
Convert video and audio tracks between multiple formats. Converting __audio/video__ only track will preserve original __video/audio__ (lossless). In case the video and audio won't be modified based on source file and output settings the compression will __throw__ with ```CompressionError.redunantCompression```.

<!--__Supported video codecs:__
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

### Options
In addition to the video and audio codecs, you can also set the following parameters:-->

### Options
In addition to the video and audio codecs conversion provided with the following parameters:

| Parameter | Description | Values | Default |
| :---: | :---: | :---: | :---: |
| Video codec | Video codec used by encoder | `H.264`, `H.265/HEVC`, `ProRes`, `JPEG` | Source video codec |
| Video bitrate | Output video bitrate, used __only__ by `H.264` and `H.265/HEVC` codecs | `Auto` - Calculated based on resolution, frame rate and codec</br> `Encoder` - set by __AVAssetWriter__ internally</br>`Source` - Source video bitrate</br>`Custom` - custom bitrate value in __bps__</br>`Filesize` - Calculated based on target filesize in __MB__ | `Auto` |
| Video quality | Video quality in range from 0.0 to 1.0, __ignored__ when bitrate is set | `[0.0, 1.0]` | `1.0` |
<!--| Size | Video resolution | `CGSize` | Source video resolution |-->
| Preserve Alpha channel | Preserve or drop alpha channel from video file with transparency | `Boolean` | `true` |
| Profile | Video profile used by video encoder, `H.264` and `H.265/HEVC` codecs only | `Baseline`, `Main`, `High`, `Custom(String)` | Selected automatically |
| Color | Color primary, Transfer function, YCbCr Matrix combination | `SD`, `SD (PAL)`, `P3`, `HDTV`, `UHDTV SDR`, `UHDTV HDR HLG`, `UHDTV HDR PQ` | Selected automatically |
| Max Key Frame Interval | Maximum interval between keyframes | `Int` | Unset |
| Hardware Acceleration | Usage of hardware acceleration during the compression | `Auto`, `Disabled` | `Auto` |
| Optimize For Network Use | Allows video file to be streamed over network | `Boolean` | `true` |
| Audio codec | Audio codec used by encoder | `AAC`, `Opus`, `FLAC`, `Linear PCM`, `Apple Lossless Audio Codec` | Source audio codec |
| Audio bitrate | Audio bitrate, used by `AAC` and `Opus` codecs only | `Auto` - set internally by __AVAssetWriter__</br>`Custom(Int)` - custom bitrate value in __bps__ | `Auto` |
| Audio quality | Audio quality, `AAC` and `FLAC` only | `Low`, `Medium`, `High` | Unset |
| Sample Rate | Sample rate in Hz | `Int` | Source sample rate |

__Usage__
```Swift
// Video
CompressionVideoSettings(
    codec: .hevc,
    bitrate: .encoder,
    quality: 1.0,
    preserveAlphaChannel: true,
    profile: .hevcMain10,
    color: .itu2020_hlg,
    maxKeyFrameInterval: 30,
    hardwareAcceleration: .auto,
)

// Audio
CompressionAudioSettings(
    codec: .opus,
    bitrate: .value(96_000),
    quality: .high,
    sampleRate: 44100
)
```

## Resize
Resize video while preserving aspect ratio. Provide `CGSize` resolution for video to fit it. Width and height may be rounded to nearest even number.

Predefined resolutions are `SD`, `HD`, `Full HD`, `Ultra HD` which are accessible via `CGSize` extension.

Use `CGSize.explicit(width:height:)` or pass both __negative__ width and height to `CGSize` to force resolution without safety checks.

__Usage__
```Swift
CompressionVideoSettings(size: CGSize.uhd) // predefined values, size to fit
CompressionVideoSettings(size: CGSize(width: 720, height: 720)) // custom values, size to fit
CompressionVideoSettings(size: CGSize.explicit(width: 1280, height: 720)) // force exact resolution
```

## Crop
Crop the video. There are three initializers which at the end produce `CGRect` for cropping.

__Usage__
```Swift
CompressionVideoSettings(edit: [.crop(.init(size: CGSize(width: 1080, height: 1080), aligment: .center))])
CompressionVideoSettings(edit: [.crop(.init(origin: CGPoint(x: 256, y: 256), size: CGSize(width: 1080, height: 1080)))])
```

## Cut
Cut the video based on time interval. Time specified in seconds. If none of other video settings is modified, the cutting is lossless (no video re-encoding applied - original quality).

__Usage__
```Swift
CompressionVideoSettings(edit: [.cut(from: 0.5, to: 7.5)])
```

## Rotate, Mirror, Flip
Video transfrom operation, applied without re-encoding.
```Swift
// Rotate
CompressionVideoSettings(edit: [.rotate(.clockwise))]) // counterClockwise
CompressionVideoSettings(edit: [.rotate(.angle(.pi/2))])
// Mirror and Flip
CompressionVideoSettings(edit: [.mirror, .flip])
```

## Image Processing
Frame-by-frame callback handler which provides `CIImage`, frame `time` in seconds and frame `resolution`. Can be used to apply `CIFilter`, composite any images over source and many more operations supported by `CIImage`. `CIImage` size should not be modified.

Before | After
:-: | :-:
<video src='https://github.com/starkdmi/MediaToolSwift/assets/21260939/844fddfb-98a4-46e1-a65c-7dbedea5bdfb' type='video/quicktime; codecs=hvc1'/> | <video src='https://github.com/starkdmi/MediaToolSwift/assets/21260939/cb23174a-85d1-4b41-b04f-df67e81ba849' type='video/quicktime; codecs=hvc1'/>

__Usage__
```Swift
CompressionVideoSettings(edit: [
    .imageProcessing { (image: CIImage, size: CGSize, atTime: Double) -> CIImage in
        var blurred = image.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": 7.5
        ])

        // Do anything else
        
        return blurred
    }
])
```
Complex example is stored in [Video Tests](../Tests/VideoTests.swift#:~:text=testImageProcessing) under `testImageProcessing()`.

## CVPixelBuffer Processing
Frame-by-frame callback handler which provides access to [CVPixelBuffer](https://developer.apple.com/documentation/corevideo/cvpixelbuffer-q2e). Usefull to analyze/process video frames using `CoreML`. 

In case of resolution modification take attention to specify exact values using `CGSize.explicit(width:height:)` in `VideoSettings` to disable internal size-to-fit calculations and disable upscaling restriction.

While lowering frame rate the `.pixelBufferProcessing` will be called only on preserving frames. Call `.pixelBufferProcessing(:)` executed after `.sampleBufferProcessing`.

__Usage__
```Swift
// Upscale video 1280x720 by 4X
// Import `Vision`, load `VNCoreMLModel` upscaling model and initialize `VNCoreMLRequest`
CompressionVideoSettings(
    // Calculate desired resolution based on source and enforce it
    size: .explicit(width: 2560, height: 1440),
    edit: [
        .pixelBufferProcessing { pixelBuffer in
            // Run ML intereference
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])

            guard let result = request.results?.first as? VNPixelBufferObservation else {  
                // Return original buffer on failure
                return pixelBuffer
            }

            // Return modified pixel buffer for writing
            return result.pixelBuffer
        }
    ]
)
```

## CMSampleBuffer Processing
Frame-by-frame callback handler which provides access to [CMSampleBuffer](https://developer.apple.com/documentation/coremedia/cmsamplebuffer-u71). Allows more flexible control on sample processing.

While lowering frame rate using `frameRate` parameter the callback is applied only to the preserving frames.

Executed before `.pixelBufferProcessing(:)`.

__Usage__
```Swift
CompressionVideoSettings(
    edit: [
        .sampleBufferProcessing { sample in

            // ... Code here ... 

            return someNewBuffer
        }
    ]
)
```

## Thumbnails
Generate video thumbnails at specified times. Time specified in seconds. Available image formats are: `HEIF`, `PNG`, `JPEG`, `GIF`, `TIFF`, `BMP`, `ICO`. Use `ImageSettings` to adjust the image options and to post process the video thumbnails.

__Usage__
```Swift
try await VideoTool.thumbnailFiles(of: asset, at: [
        .init(time: 3.5, url: url1), 
        .init(time: 5.2, url: url2)
    ],
    settings: .init(format: .png, size: .fit(.hd))
)
```

## Frame Rate adjustment
Set custom video frame rate. Will not increase source video frame rate. Slo-mo supported but should preserve frame rate higher than 120 to display as Slo-mo on Apple devices.

__Usage__
```Swift
CompressionVideoSettings(frameRate: 24)
```

## Info
Extract video info without compression.

__Usage__
```Swift
let info = try await VideoTool.getInfo(source: url)
```

## Metadata
By default Xcode remove the metadata from output file, to prevent go to Build Settings tab, Under the __Other C Flags__ section, add the following flag: ```-fno-strip-metadata```.
- __File metadata__ - Copy asset metadata
- __Timed metadata__ - Copy source video metadata track
- __Extended attributes__ - Copy extended file system metadata tags used for media
- __Insert custom metadata__ - Add custom `[AVMetadataItem]` metadata tags
- __Skip metadata__
