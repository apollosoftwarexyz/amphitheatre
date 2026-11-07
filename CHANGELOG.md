## 0.0.4

* Add history management functions to `AmphitheatreEditorController`.
  * `undo`
  * `redo`
  * `clearHistory`
  * `reset`
* Rename `AmphitheatreEditorOptions.strict` to `AmphitheatreEditorOptions.canAutoAccept`.
* Export through the platform's media framework (Media3 Transformer on Android, `AVAssetExportSession` on iOS) with
  progress, cancellation and quality presets; check the available disk space first (`AmphitheatreDiskSpacePolicy`).
* Paint a filmstrip of the video on the editor's timeline, dim the parts outside the selection, and show the
  selection's start, length and end under it (`AmphitheatrePlatform.getThumbnails`;
  `AmphitheatreEditorStyle.trackColor` and `selectionDimColor`).
* Passthrough trims start at the key frame at or before the start handle and copy the streams without re-encoding.
  Previously a trim whose start was past zero was re-encoded in full with a frame-accurate start; it now starts up to one
  group of pictures early and finishes in seconds. The output may exceed `maxLength` by that much.
* Apply the requested quality on Android (`presetHD`, `presetFullHD` and `highest` produce H.264/AAC, re-encoding
  where the source differs; the presets scale down where the source is taller) and default to `passthrough` on both
  platforms.
* Write the Android output to the plugin's temporary directory (as `<session>.mp4`) rather than next to the input.
* Offer to cancel an export from the progress screen, return to the editor silently when it is cancelled, and offer
  "Try again" when it fails. `AmphitheatreExporterProgressBuilder` gains an `onCancel` parameter.
* Accept a video no longer than `minLength` without showing the editor when `canAutoAccept` is set, and keep both
  handles on the timeline for a video shorter than `minLength`.
* A drag of a crop handle is one history entry, and a cancelled gesture restores the selection
  (`AmphitheatreEditorController.beginCropGesture`, `previewCrop`, `endCropGesture`, `cancelCropGesture`).
* Show why a video cannot be played in place of the black frame (`AmphitheatreController.hasError`).
* Fix the iOS disk-space estimate, which never fired for a partial trim, and report cancelled iOS exports as
  `EXPORT_CANCELLED`.
* Ship a privacy manifest declaring the disk-space API the iOS plugin reads.
* Translate the new strings to Spanish (`es`, `es_419`).
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
