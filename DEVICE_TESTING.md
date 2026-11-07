# Device testing

The native side of the plugin (Media3 Transformer on Android, `AVAssetExportSession`
on iOS) is verified on physical devices rather than by unit tests. Run this plan
before merging a change that touches `android/`, `ios/`, the export flow in
`lib/src/editor/`, or the `video_player` dependency, and record the results in the
pull request.

## Setup

- Build the example app for each device: `cd example && flutter run --release`.
  A release build is required for representative export timings.
- Clips, copied to the device's gallery beforehand:
  - **Phone**: a clip recorded with the device's own camera, portrait, 30-60 s.
  - **Landscape**: a landscape clip from another device (e.g. a GoPro or a camera),
    1-2 GB, with a key-frame interval of a second or more.
  - **Short**: a clip shorter than 10 s (the default `minLength`).
  - **Audio-only**: an `.m4a` or an MP4 without a video track.
  - **Corrupt**: a file with an `.mp4` extension that is not a video.
- Some cases need options the example does not set; pass them to
  `AmphitheatreEditor.launch` in `example/lib/main.dart` for the run and do not
  commit the change.
- Inspect outputs with `adb shell ls -la /data/data/<id>/cache/xyz.apollosoftware.amphitheatre`
  on Android, or through Xcode's container download on iOS, and by playing them
  back in the example's player.

## Devices

Cover at least one device from each row that applies to the change.

| Row | Why |
| --- | --- |
| Android, API 28 or newer | Passthrough trims snap to the previous sync sample here. |
| Android, API 23-27 | Passthrough trims are transcoded instead; the lowest supported level. |
| iOS 18 or newer | `export(to:as:)` with native progress. |
| iOS 13-17 | The legacy `export()` path with the polled progress timer. |

## Cases

Each case lists what to do and what must be true. Anything else counts as a failure.

### Player

1. **Playback.** Open the phone clip in the player. Controls hide and show on tap;
   seeking, replay and the close button work.
2. **Unplayable video.** Open the corrupt clip in the player. "This video can't be
   played." is shown instead of a black frame, only the close button is available,
   and the close button leaves the screen.

### Editor timeline

3. **Filmstrip.** Open the phone clip in the editor. Thumbnails fill the track
   within a couple of seconds, in order, in the clip's orientation, with the
   parts outside the selection dimmed, and the start / selected / end times under
   it. Repeat with the landscape clip.
4. **Handle drag.** Drag the start handle: the frame under the handle is previewed
   while dragging, and the preview lands on the frame the handle was released on.
   Undo once restores the selection from before the drag; a second undo restores
   the original selection (one history entry per drag).
5. **Window drag.** Drag the selection by its middle: both handles move together
   and the length is unchanged.
6. **Interrupted drag.** Start dragging a handle, then let a notification or a
   call take over the screen (or drag off the edge of the screen). The selection
   is back where it was before the drag.
7. **Short video.** Open the short clip. Both handles stay on the track and the
   selection covers the whole clip; dragging a handle does not move it off.
8. **Timestamps at large text.** Set the system font size to its largest and open
   the editor. The row under the track does not overflow.

### Export

9. **Passthrough trim (default quality).** On the landscape clip, select a
   30 s window starting well past zero and accept. The export finishes in
   seconds, not minutes. The output plays from its first frame without
   corruption, starts at or up to about one key-frame interval before the start
   handle, and ends at the end handle. On API 23-27 the export instead takes
   roughly real time (a transcode) and starts exactly at the handle.
10. **Full selection.** Accept with the handles at both ends. No export runs and
    the editor returns the original file's path (the example shows the same
    video).
11. **Preset on a portrait clip.** With `quality: presetHD` on the phone clip, the
    output is 720 wide by 1280 tall (the short side is capped), H.264/AAC, and
    not upscaled. Repeat with `presetFullHD` (1080 x 1920). Check with the
    gallery's details view or `ffprobe`.
12. **Preset on a landscape clip.** `presetHD` on the landscape clip gives
    1280 x 720.
13. **Highest.** `quality: highest` keeps the source size.
14. **Audio-only file.** A trim of the audio-only clip exports (no video effect
    is applied) and plays.
15. **Output location.** Outputs are `<sessionId>.mp4` in the plugin's cache
    directory, not next to the input. Only outputs that were handed back
    remain; cancelled and failed exports leave no file behind.

### Cancel and retry

16. **Cancel mid-export.** Start a long export and tap Cancel while the progress
    bar is moving. The editor returns immediately with the selection intact, no
    message is shown, no partial file remains, and CPU use drops (the export is
    not still running in the background).
17. **Back gesture.** Same as 16, using the system back gesture instead of the
    button.
18. **Cancel while preparing.** Tap Cancel the instant the progress screen
    appears, before the bar moves. Same result as 16.
19. **Cancel then accept again.** Cancel an export, then accept again at once.
    Exactly one output results, the gallery shows one new file, and the first
    export is not still running (check CPU or the cache directory while the
    second one runs).
20. **Progress.** The bar advances during a transcode (preset or API 23-27
    passthrough) and reaches the end; for a passthrough stream copy it may jump
    from indeterminate to done.

### Errors

21. **Export failure.** Force a failure (e.g. revoke storage permission mid-run,
    or export a file that is deleted after the editor opened it). The editor
    returns with a message and a "Try again" action; tapping it starts a new
    export.
22. **Low disk space.** With `diskSpacePolicy: abortIfExceeds`, fill the device
    until free space is below the clip's size and accept a partial trim of the
    landscape clip. The export is refused with the disk-space message before it
    starts, and `onExceedsDiskSpace` is invoked. With `warnIfExceeds` the
    callback is invoked and the export proceeds.
23. **Unplayable video in the editor.** Open the corrupt clip in the editor. The
    error state is shown, the done button is absent, and close leaves.

### Auto-accept

24. **Short clip, `canAutoAccept: true`.** Open the short clip. The editor pops
    with the clip's own path without being shown (at most a flash), and no
    export runs.
25. **Not current.** As 24, but navigate away (open another screen on top)
    before the video has loaded. The editor does not pop the screen above it.

### Lifecycle

26. **Background during export.** Start an export and background the app for
    ten seconds. On return the export has finished or is still progressing; the
    app has not crashed and the output plays.
27. **Rotation.** Rotate the device in the editor. The selection and filmstrip
    survive; no exception is logged.
28. **Leave during load.** Open the editor and close it before the video has
    loaded. No exception is logged (`flutter run` console).

## Recording results

Add a comment to the pull request with one table per device:

```
Device: Pixel 7, Android 15 (API 35), release build

| Case | Result | Notes |
| ---- | ------ | ----- |
| 1    | pass   |       |
| 9    | pass   | 1.2 GB GoPro clip, 30 s window, 4 s export, starts 0.9 s early |
| 22   | skip   | could not fill the disk |
```

Mark a case `pass`, `fail` (with what happened) or `skip` (with why). A `fail`
blocks the merge unless the pull request says why it is acceptable.
