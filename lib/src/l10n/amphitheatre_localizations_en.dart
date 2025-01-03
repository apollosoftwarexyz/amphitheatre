/// Automatically generated localizations for Amphitheatre.

import 'package:intl/intl.dart' as intl;

import 'amphitheatre_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AmphitheatreLocalizationsEn extends AmphitheatreLocalizations {
  AmphitheatreLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get done => 'Done';

  @override
  String get back10Seconds => '-10s';

  @override
  String get forward10Seconds => '+10s';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get replay => 'Replay';

  @override
  String exportingVideo(double progress) {
    final intl.NumberFormat progressNumberFormat = intl.NumberFormat.decimalPercentPattern(
      locale: localeName,
      decimalDigits: 1
    );
    final String progressString = progressNumberFormat.format(progress);

    return 'Exporting video ($progressString)...';
  }
}
