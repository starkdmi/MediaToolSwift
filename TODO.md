## TODO
- __VP9 and AV1 video codecs support using VideoToolBox__ - VTDecompressionSession and VTCompressionSession can be used inside sample buffer processing block for frame by frame decoding/encoding
- __Multiple video/audio/metadata tracks support__ - Option to save all video/audio/metadata tracks from source file to output (now only first track for each track media type is stored)
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