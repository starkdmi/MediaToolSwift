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
AAC payloads, portrait resize with an image processor, and compressed video
passthrough. The SDR pixel test uses an independent Apple basic compositor as
its conversion reference on iOS; macOS accepts DCI-P3 and compares against the
source. High-quality SDR encoding isolates color conversion from quantization.
A negative control reinterprets unchanged RGB values in the output color space;
the export must have less than half that control's mean linear-RGB error.
These synthetic controls prove the writer failure class and the tested export
contracts; they do not establish camera HDR quality or dynamic HDR preservation.

Local evidence (2026-10-02, Swift 6.4 / macOS 27.2): the unchanged writer setup
failed on iOS Simulator 26.5 with the exception above. After the fix, all six
regressions passed on that simulator and macOS. The complete default suite in
Swift 6 strict-concurrency mode passed 73 tests, skipped its two opt-in extended
media tests, and had no failures. The iOS SDR pixel error against the independent
native reference was 0.0, versus 0.005241061 for the retag-only control.
With an image-composition callback, it was 0.0007348501 versus the same control.
`-warnings-as-errors` on this SDK stops at the existing deprecated
`kUTTypeJPEG2000` reference in `ImageFormat.swift`; this change adds no compiler
warnings. HDR controls use bitrate settings: a separate maximum-quality HDR
probe crashed inside the simulator's `VCPHEVC` encoder.

Run the six regressions:

```sh
swift test --disable-sandbox --filter VideoColorConversionTests
xcodebuild test -scheme MediaToolSwift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
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
ffmpeg -i Tests/ColorFixtures/dci-p3.mov -map 0 -c copy \
  -metadata:s:v:0 rotate=90 Tests/ColorFixtures/dci-p3-portrait.mov
```
