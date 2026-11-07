## 0.0.4

* Add history management functions to `AmphitheatreEditorController`.
  * `undo`
  * `redo`
  * `clearHistory`
  * `reset`
* Rename `AmphitheatreEditorOptions.strict` to `AmphitheatreEditorOptions.canAutoAccept`.
* **Breaking:** Android `minSdk` is now 23, and `AmphitheatreExporterProgressBuilder` gains an `onCancel` parameter.
* Passthrough trims copy the streams from the key frame at or before the start handle instead of re-encoding, so they
  take seconds rather than minutes; the named qualities now re-encode on Android too, and the default is `passthrough`.
* The editor's timeline shows a filmstrip of the video with the selection's start, length and end, and a handle drag is
  a single history entry.
* An export can be cancelled from the progress screen and retried after a failure, and a video no longer than
  `minLength` is accepted without the editor when `canAutoAccept` is set.
* Show why a video cannot be played instead of a black frame, and ship an iOS privacy manifest.
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
