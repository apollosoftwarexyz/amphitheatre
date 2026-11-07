## 0.0.4

* Add history management functions to `AmphitheatreEditorController`.
  * `undo`
  * `redo`
  * `clearHistory`
  * `reset`
* Rename `AmphitheatreEditorOptions.strict` to `AmphitheatreEditorOptions.canAutoAccept`.
* **Breaking:** Android `minSdk` is now 23 (Media3 Transformer's baseline), up from 21.
* **Breaking** for custom `buildExporterProgress` builders: `AmphitheatreExporterProgressBuilder` gains a
  `VoidCallback? onCancel` named parameter, which the screen should offer to the user.
* Android default quality is `passthrough` (was `presetFullHD`); `presetHD`, `presetFullHD` and `highest` now re-encode
  to H.264/AAC on Android (the presets cap the short side at 720 or 1080 pixels, never scaling up).
* A passthrough trim starts at the sync sample at or before the start handle (Android 9+ and iOS) and copies the streams,
  so it starts up to one group of pictures early and the output can exceed `maxLength` by that much.
* The Android output is `<cache>/xyz.apollosoftware.amphitheatre/<sessionId>.mp4` (was `<base>.out.<ext>` next to the
  input); outputs accumulate until the app deletes them, as on iOS.
* `AmphitheatreCropVideoSession.cancel` cancels a session that is not being listened to.
* Status stream: listening for an unknown session ends the stream (was `UNKNOWN_SESSION`); a cancelled iOS export is
  `EXPORT_CANCELLED` (was `CANCELLED` / `UNEXPECTED_ERROR`); a failed Android export is `EXPORT_FAILED` (was
  `UNEXPECTED_ERROR`) with a fixed message and the cause in the details, as on iOS.
* The iOS disk-space check now fires for partial trims (an integer quotient made it a no-op), so `warnIfExceeds` and
  `abortIfExceeds` can trigger where they never did.
* `canAutoAccept` now pops the editor with the video's own path (it was inert), and `shouldAutoAccept` is
  `duration <= minLength` (was `<`); a video shorter than `minLength` keeps both handles on the timeline.
* Paint a filmstrip of the video on the editor's timeline (`AmphitheatrePlatform.getThumbnails`, which throws
  `UnimplementedError` unless an implementation overrides it), dim the parts outside the selection, and show the
  selection's start, length and end under it.
* A drag of a crop handle is one history entry and a cancelled gesture restores the selection
  (`AmphitheatreEditorController.beginCropGesture`, `previewCrop`, `endCropGesture`, `cancelCropGesture`,
  `isInCropGesture`).
* Offer to cancel an export from the progress screen (the back gesture cancels too), return to the editor silently when
  it is cancelled, and offer "Try again" when it fails.
* Show why a video cannot be played in place of the black frame (`AmphitheatreController.hasError`); an initialization
  failure is reported through `FlutterError.reportError` rather than left unhandled. `AmphitheatreController.whenInitialized`.
* Ship a privacy manifest declaring the disk-space API the iOS plugin reads, and limit the published package to its
  sources (`.pubignore`).
* Bump dependencies

## 0.0.3

* Allow customizing the playback controls in the editor.

## 0.0.2

* [Video Limit #1](https://github.com/apollosoftwarexyz/amphitheatre/issues/1) Add basic options to
  `Amphitheatre.consume` and `AmphitheatreEditor.consume` to facilitate setting - amongst other options - the video 
  length for the editor.
* [Autoplay not working #2](https://github.com/apollosoftwarexyz/amphitheatre/issues/2): Trigger autoplay logic after
  initialization.
* Add `useRootNavigator` convenience property to launch methods (useful for opening a full screen editor or player in
  nested navigation contexts).
* Documentation changes
* Bump dependencies

## 0.0.1+1

* Documentation changes

## 0.0.1

* Initial release
