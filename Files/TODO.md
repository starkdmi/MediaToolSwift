## Main
- __AVAssetReaderOutput.alwaysCopiesSampleData__ - `videoOutput.alwaysCopiesSampleData` set to `false` may improve the perfomance, default to `true`. Check if applicable
- __AVAssetWriterInput.performsMultiPassEncodingIfSupported__ - `videoInput.performsMultiPassEncodingIfSupported` may improve the compression in some cases, check availability via `videoInput.canPerformMultiplePasses`
- __Logger__ - Simple logging feature plus operations descriptions like - https://stackoverflow.com/a/23271969/20387962
- __VP9 and AV1 video codecs support using VideoToolBox__ - VTDecompressionSession and VTCompressionSession can be used inside sample buffer processing block for frame by frame decoding/encoding
- __Multiple video/audio/metadata tracks support__ - option to save all video/audio/metadata tracks from source file to output (now only first track for each track media type is stored)
- __Command line tool__ - command line application like avconvert and ffmpeg
- __visionOS support__

## Video
__Info__ - function to extract info from a video file:
```
resolution, rotation, filesize, duration, frame rate,
video - codec, bitrate, hasAlpha, isHDR, color primaries, pixel format,
audio - codec, bitrate, sample rate, waveform,
metadata - date, location, where from, original filename with raw extended attributes dictionary + asset.getMetadata() list + track.metadata
```

__Codecs__
```
VP9, AV1
```

__Base__
- __Video thumbnails size performance__ - calculate max size based on ImageOperations (Crop, Rotate) and request a low-res thumbnail even before cropping, rotating
- __Video thumbnails cancellation feature__ - generator.cancelAllCGImageGeneration()
- __Video thumbnails threading__ - check the main thread isn't busy

__Video to GIF__

__Video to Images__ - With specified frame rate and directory - 001.png, 002.png

__Video Preview__ - animated image/video file with a little of best video frames stitched together at a small frame rate, GIF can be used instead of WebP

__Insert video__ - insert/add video track before/after the source video

__Advanced Cutting__ - select multiple ranges of audio/video track and stitch them together while removing unselected parts. this feature can be done without re-encoding video frames (losslessly)

__Frame rate and resolution upscaling__ - combine nearest frames to produce middle one, upscale/enlarge/unblur pixels

__Video Stabilization__ - only using native Swift code (no 3rd party libraries like OpenCV and ffmpeg)
[VNHomographicImageRegistrationRequest](https://developer.apple.com/documentation/vision/VNHomographicImageRegistrationRequest) + [vImage](https://developer.apple.com/documentation/accelerate/vimage) + [VNTranslationalImageRegistrationRequest](https://developer.apple.com/documentation/vision/VNTranslationalImageRegistrationRequest)

__AI__ - face landmark, pose detections, atd. using Vision framework

## Audio
| Convert | Cut | Speed | Waveform | Info |
| :---: | :---: | :---: | :---: | :---: |
| 🚧 | ➖ | ➖ | 🚧 | 🚧 |

__Info__
``` 
format, filesize, bitrate, duration, sample rate, waveform
```

__Formats__
```
AAC, Opus, FLAC
```

## Image
| Convert | Resize | Crop | Rotate, Flip, Mirror | Filter\* | Background | Blurhash | Custom FPS | Info |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ➖ | ➖ | ✔️ | ✔️ |

__Info__
```
format, resolution, filesize, has alpha, is animated, pixel format,
animated - duration, frame rate,
metadata - date, location, device/camera/lens
```

__Formats__
```
WebP
```

__Panoramas, Portraits, Live Photos, Raw Images__
- Live Photo = Heic image + QuickTime video, [LivePhoto.Swift](https://github.com/LimitPoint/LivePhoto), `UTType.livePhoto`
- Panoramas = extra wide photo (?)

__AI__ - [FILM: Frame Interpolation](https://film-net.github.io/)
