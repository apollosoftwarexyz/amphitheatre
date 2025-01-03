# amphitheatre

A Flutter video player and editor.

<div align="center">
    <table>
        <tbody>
            <tr>
                <td align="center">
                    <img src="screenshots/player.png" width="256px" alt="Screenshot of player" />
                </td>
                <td align="center">
                    <img src="screenshots/editor.png" width="256px" alt="Screenshot of editor" />
                </td>
            </tr>
            <tr>
                <td align="center">
                    <a href="https://pub.dev/documentation/amphitheatre/latest/amphitheatre/Amphitheatre-class.html" target="_blank"><code>Amphitheatre</code></a>
                </td>
                <td align="center">
                    <a href="https://pub.dev/documentation/amphitheatre/latest/amphitheatre/AmphitheatreEditor-class.html" target="_blank"><code>AmphitheatreEditor</code></a>
                </td>
            </tr>
        </tbody>
    </table>
</div>

<table>
    <tbody>
        <tr>
            <td></td>
            <td><b>Android</b></td>
            <td><b>iOS</b></td>
        </tr>
        <tr>
            <td><b>Supported Versions</b></td>
            <td>SDK 21+</td>
            <td>13.0+ *</td>
        </tr>
        <tr>
            <td><b>Supported Devices<br/><small>(as of Jan 3, 2025)</small></b></td>
            <td><a href="https://web.archive.org/web/20241222230146/https://apilevels.com/" target="_blank">99.7%</a></td>
            <td><a href="https://web.archive.org/web/20250102215257/https://iosref.com/ios-usage" target="_blank">96.8%</a></td>
        </tr>
    </tbody>
</table>

<small>* NB: support for older versions can be implemented if needed, it has been omitted at present for simplicity of
the platform channel implementation.</small>

## Quick Start

First, refer to [Setup for the `video_player` package](https://pub.dev/packages/video_player#setup) to ensure the media
can be played from your desired source.

### Localization (l10n) Support

This package has built-in support for `flutter_localizations`, with the long-term goal of getting any community-sourced
localizations merged into this repository so that applications can benefit from them automatically. (PRs welcome!)

We will provide our own 'official' localizations for the package if we write our own, which will be done on an
'as-needed' basis and will aim to review/merge community translations on a 'best-effort' basis.

To activate the library's localization, add the `AmphitheatreLocalization` delegate to your `MaterialApp`:

```dart
void main() {
  runApp(
    MaterialApp(
      home: const MyAppHome(),
      debugShowCheckedModeBanner: false,
      
      // Add this property:
      localizationsDelegates: [
        // This adds the AmphitheatreLocalizations delegate.
        AmphitheatreLocalizations.delegate,
        // This ensures you retain Flutter's built-in localization.
        // See here for details:
        // https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization
        ...GlobalMaterialLocalizations.delegates,
      ],
    ),
  );
}
```

## Development

### Adding translations

Don't forget to run the following command after updating any of the `.arb` files:

```bash
flutter gen-l10n
```
