## Main
- __Slow Motion__ - check slo-mo video compression
- __AVAssetReaderOutput.alwaysCopiesSampleData__ - `videoOutput.alwaysCopiesSampleData` set to `false` may improve the perfomance, default to `true`. Check if applicable
- __AVAssetWriterInput.performsMultiPassEncodingIfSupported__ - `videoInput.performsMultiPassEncodingIfSupported` may improve the compression in some cases, check availability via `videoInput.canPerformMultiplePasses`
- __VP9 and AV1 video codecs support using VideoToolBox__ - VTDecompressionSession and VTCompressionSession can be used inside sample buffer processing block for frame by frame decoding/encoding
- __Multiple video/audio/metadata tracks support__ - option to save all video/audio/metadata tracks from source file to output (now only first track for each track media type is stored)
- __Command line tool__ - command line application like avconvert and ffmpeg

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

__Thumbnails and Video Preview__ - [Apple Documentation](https://developer.apple.com/documentation/avfoundation/media_reading_and_writing/creating_images_from_a_video_asset)

__Advanced Cutting__ - select multiple ranges of audio/video track and stitch them together while removing unselected parts. this feature can be done without re-encoding video frames (losslessly)

__Watermark or Overlay__ - place any image as overlay, can have time interval

__Video Filters__ - [vImage #1](https://developer.apple.com/documentation/accelerate/applying_vimage_operations_to_video_sample_buffers), [vImage #2](https://developer.apple.com/documentation/accelerate/using_vimage_pixel_buffers_to_generate_video_effects#4225030), [Core Image Filters](https://developer.apple.com/documentation/coreimage/processing_an_image_using_built-in_filters)

__Video Stabilization__ - only using native Swift code (no 3rd party libraries like OpenCV and ffmpeg)
[VNHomographicImageRegistrationRequest](https://developer.apple.com/documentation/vision/vnhomographicimageregistrationrequest) + [vImage](https://developer.apple.com/documentation/accelerate/vimage)

__AI__ - face landmark, pose detections, atd. using Vision framework

## Audio
| Convert | Cut | Speed | Waveform | Info |
| :---: | :---: | :---: | :---: | :---: |
| 🟠 | ❌ | ❌ | 🟠 | 🟠 |

__Info__
``` 
format, filesize, bitrate, duration, sample rate, waveform
```

__Formats__
```
AAC, Opus, FLAC
```

## Image
| Convert | Resize | Crop | Rotate | Flip | Filter | Background | Blurhash | Custom FPS | Thumbnail | Info |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 🟠 | 🟠 | 🟠 | ❌ | ❌ | ❌ | ❌ | 🟠 | Animated 🟠 | Animated 🟠 | 🟠 |

__Info__
```
format, resolution, filesize, hasAlpha, isAnimated, pixel format,
animated - duration, frame rate,
metadata - date, location, device/camera/lens
```

__Formats__
```
JPEG, PNG, TIFF, GIF, HEIF (No built-in WEBP support)
```
