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
