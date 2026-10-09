## Migrating from 1.x to 2.x

### Async results instead of callbacks
The terminal `callback:` on `VideoTool.convert` and `AudioTool.convert` is gone,
as are the `thumbnailImages` and `thumbnailFiles` completions: all four now
return their result and throw on failure.

```Swift
// 1.x
let task = await VideoTool.convert(source: input, destination: output, callback: { state in
    switch state {
    case .completed(let info): print("Done: \(info.url.path)")
    case .failed(let error): print("Error: \(error.localizedDescription)")
    default: break
    }
})

// 2.x
let task = CompressionTask(destination: output) // optional, for progress and cancellation
let info = try await VideoTool.convert(source: input, destination: output, task: task)
print("Done: \(info.url.path)")
```

A `CompressionTask` tracks one conversion. Passing a task that is already in
flight or finished throws `CompressionError.taskAlreadyUsed` - create a new task
per conversion. Cancel with `task.cancel()` or by cancelling the enclosing Swift `Task`.

### Sendable closures
Closures you hand to MediaToolSwift run on library-managed queues, not on your
caller's actor. All of them are now `@Sendable` and reject unsynchronized
captures at compile time:

* `VideoFrameProcessor` (every case)
* `CompressionVideoBitrate.dynamic`
* `CompressionVideoSize.dynamic`
* `ImageProcessor`

`@preconcurrency import` does not soften this - `@Sendable` is part of the
function type rather than a conformance. Move captured state into a synchronized
box or an actor, and hop explicitly before touching actor-isolated state.

### Thumbnails
`thumbnailImages` and `thumbnailFiles` inherit the caller's isolation, so an
`AVAsset` held by a `@MainActor` view model can be passed directly even though
`AVAsset` is not `Sendable`. Thumbnail decoding and encoding still run off your
actor.

### Platforms
Minimum deployment targets are now macOS 12, iOS 15, tvOS 15, Mac Catalyst 15
and visionOS 1, built with Xcode 16 or later.
