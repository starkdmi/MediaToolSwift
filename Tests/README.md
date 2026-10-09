# Media test fixtures

`Tests/media` is divided by execution cost rather than by implementation detail.

- The default macOS smoke suite uses checked-in fixtures that cover JPEG, animated GIF, HDR HEIF, PNG with alpha, MP3, and H.264 video. Missing required fixtures are test failures.
- The extended suite covers high-resolution HDR, gain maps, alpha video, ProRes, and slow motion, and runs on a scheduled macOS runner. Its existing assets remain in Git during 1.x stabilization; do not add new large fixtures until a separate storage decision is made.
- Alpha parity uses `transparent_ball_hevc.mov`, which AVFoundation decodes with alpha. `transparent_ball_prores.mov` remains ProRes resize coverage only: although its FFmpeg-authored container advertises alpha, Apple decodes its samples as opaque, and whether the encoder keeps that opaque alpha plane in the output differs between macOS versions, so its outputs assert no alpha expectation.
- Tests never download media during `setUp`. External files are not fixtures: a test that requires one must be explicitly skipped with a reason.

Generated output belongs in `FileManager.default.temporaryDirectory`; `Tests/media/temp` is ignored and must not be used as an input fixture.

Run the extended suite locally when its fixtures are available:

```sh
MEDIATOOLSWIFT_EXTENDED_MEDIA=1 swift test --disable-sandbox
```

Run the default suite locally with:

```sh
swift test --disable-sandbox
```

Run the strict-concurrency build with:

```sh
swift build --disable-sandbox -Xswiftc -swift-version -Xswiftc 6 -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

## Writer primary compatibility regression

`ColorFixtures` contains four synthetic one-second, 160×96 HEVC clips (80,286
bytes total), bundled with SwiftPM so the same tests run on macOS and iOS.
The base pattern is FFmpeg `testsrc2` with a 440 Hz AAC tone, tagged DCI-P3.
HLG/PQ variants contain 10-bit HEVC; the portrait variant only adds a 90°
track transform. No user recordings are included.

On iOS, the unpatched writer initializer throws:

```text
Value for AVVideoColorPrimariesKey must be one of: P3_D65, ITU_R_2020, ITU_R_709_2, SMPTE_C
```

`testDCIP3WriterSetupBeforeEncoding` exercises that initializer directly.
The export tests check supported output tags, HLG/PQ transfer functions,
encoded 10-bit depth from `hvcC`, duration, dimensions, metadata, byte-identical
AAC payloads, portrait resize with an image processor, `.fit` resizing without
a processor or crop in both orientations, and compressed video passthrough.
Resize output is compared with an independent basic compositor and cropped,
stretched, mirrored, and rotated negative controls. The portrait test also
checks the source fixture's display dimensions so a missing track transform
cannot silently turn it into a landscape test. A rejected-profile test verifies
both writer setup errors remain available through `NSMultipleUnderlyingErrorsKey`.
The SDR pixel test uses an independent Apple basic compositor as
its conversion reference on iOS; macOS accepts DCI-P3 and compares against the
source. High-quality SDR encoding isolates color conversion from quantization.
Mean error must stay below one normalized 8-bit level (1/255). A negative control
reinterprets unchanged RGB values in the output color space; the export must
have less than half that control's mean linear-RGB error.
These synthetic controls prove the writer failure class and the tested export
contracts; they do not establish camera HDR quality or dynamic HDR preservation.

Run the color conversion regressions:

```sh
swift test --disable-sandbox --filter VideoColorConversionTests
# Replace SIMULATOR_UDID with an available device from `xcrun simctl list devices`.
xcodebuild test -scheme MediaToolSwift \
  -destination "platform=iOS Simulator,id=SIMULATOR_UDID" \
  -only-testing:MediaToolSwiftTests/VideoColorConversionTests \
  -parallel-testing-enabled NO
```

Regenerate the fixtures with FFmpeg and libx265:

```sh
for name in dci-p3 dci-p3-hlg dci-p3-pq; do
  pixel=yuv420p
  transfer=bt709
  matrix=bt709
  case "$name" in
    dci-p3-hlg) pixel=yuv420p10le; transfer=arib-std-b67; matrix=bt2020nc ;;
    dci-p3-pq) pixel=yuv420p10le; transfer=smpte2084; matrix=bt2020nc ;;
  esac
  ffmpeg -f lavfi -i 'testsrc2=size=160x96:rate=6:duration=1' \
    -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=1' \
    -c:v libx265 -pix_fmt "$pixel" -color_primaries smpte431 \
    -color_trc "$transfer" -colorspace "$matrix" \
    -x265-params "colorprim=smpte431:transfer=$transfer:colormatrix=$matrix:log-level=error" \
    -tag:v hvc1 -c:a aac -b:a 64k -movflags +write_colr \
    "Tests/ColorFixtures/$name.mov"
done
ffmpeg -display_rotation:v:0 90 -i Tests/ColorFixtures/dci-p3.mov \
  -map 0 -c copy Tests/ColorFixtures/dci-p3-portrait.mov
ffprobe -v error -select_streams v:0 -show_entries stream_side_data=rotation \
  -of default=noprint_wrappers=1 Tests/ColorFixtures/dci-p3-portrait.mov
```

The portrait command uses FFmpeg's input [`-display_rotation`](https://ffmpeg.org/ffmpeg.html#Video-Options)
option to write the track transform during stream copy. Verify that the final
command reports `rotation=90`.

## Video orientation regression

`VideoOrientationTests` encodes a 128×64 four-color quadrant frame once for each
of the eight axis-aligned track transforms, including the reflected quarter
turns (transposes). The expected displayed layout of every output is derived
from the transform matrices, not from the library, and compared with the first
frame decoded by `AVAssetImageGenerator` with `appliesPreferredTrackTransform`.
The tests cover `getInfo`, plain re-encoding, resize, crop, and the `.image`,
`.pixelBuffer`, and `.imageComposition` processors, including the orientation
the processors receive. Combined rotate, flip, and mirror operations must match
`ImageTool` output for all three image frameworks: rotate first, then flip, then
mirror, regardless of `Set` iteration order.

```sh
swift test --disable-sandbox --filter VideoOrientationTests
```
