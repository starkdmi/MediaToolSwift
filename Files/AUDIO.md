## Convert
Convert audio between multiple formats.

### Options
The following parameters may be set for audio conversion operation:

| Parameter | Description | Values | Default |
| :---: | :---: | :---: | :---: |
| File type | Audio file contrainer type | `MPEG-4`, `Core Audio`, `WAV`, `AIFF`, `AIFC`, `Adaptive Multirate` | `MPEG-4` |
| Audio codec | Audio codec used by encoder | `AAC`, `Opus`, `FLAC`, `Linear PCM`, `Apple Lossless Audio Codec` | Source audio codec |
| Audio bitrate | Audio bitrate, used by `AAC` and `Opus` codecs only | `Auto` - set internally by __AVAssetWriter__</br>`Custom(Int)` - custom bitrate value in __bps__ | `Auto` |
| Audio quality | Audio quality, `AAC` and `FLAC` only | `Low`, `Medium`, `High` | Unset |
| Sample Rate | Sample rate in Hz | `Int` | Source sample rate |

__Usage__
```Swift
CompressionAudioSettings(
    codec: .flac,
    bitrate: .value(96_000),
    quality: .high,
    sampleRate: 44100
)
```

## Cut
Cut the audio based on time interval. Time specified in seconds. If none of other audio settings is modified, the cutting is lossless (no audio re-encoding applied - original quality).

__Usage__
```Swift
AudioTool.convert(
    ...
    edit: [
        .cut(from: 0.5, to: 7.5)
    ]
)
```

## Info
Extract audio info without compression.

__Usage__
```Swift
let info = try await AudioTool.getInfo(source: url)
```
