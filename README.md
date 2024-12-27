# amphitheatre

A Flutter video player and editor.

## Getting Started

TODO!

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
