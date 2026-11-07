## 0.0.4

* Add history management functions to `AmphitheatreEditorController`.
  * `undo`
  * `redo`
  * `clearHistory`
  * `reset`
* Rename `AmphitheatreEditorOptions.strict` to `AmphitheatreEditorOptions.canAutoAccept`.
* **Breaking:** Android `minSdk` is now 23.
* **Breaking:** `AmphitheatreExporterProgressBuilder` gains an `onCancel` parameter.
* Passthrough trims copy the streams from the nearest preceding key frame instead of re-encoding.
* Show a filmstrip and selection timestamps on the editor's timeline.
* Allow cancelling an export from the progress screen, and retrying after a failure.
* Accept short videos without showing the editor when `canAutoAccept` is set.
* Show an error state for videos that cannot be played.
* Add an iOS privacy manifest.
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
