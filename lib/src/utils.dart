import 'package:amphitheatre/src/l10n/amphitheatre_localizations.dart';
import 'package:amphitheatre/src/l10n/amphitheatre_localizations_en.dart';
import 'package:flutter/widgets.dart';

/// Formatting extensions for [Duration]s.
extension FormatDuration on Duration {
  /// Returns true if the [Duration] has at least one full hour.
  bool get hasHours => inHours > 0;

  /// Format the duration. If [hours] is specified it determines whether the
  /// number of hours are included in the formatted text (i.e., false means
  /// hours are never included and true means hours are always included).
  ///
  /// If [hours] is not specified, the hours are included automatically when the
  /// Duration [hasHours].
  String format({final bool? hours}) => [
        if (hours ?? hasHours) inHours.toString().padLeft(2, '0'),
        inMinutes.remainder(60).toString().padLeft(2, '0'),
        inSeconds.remainder(60).toString().padLeft(2, '0'),
      ].join(':');
}

/// Gets the [AmphitheatreLocalizations] delegate for the current [BuildContext]
/// or, if that is not possible (e.g., because the consumer forgot to load it),
/// returns the English localizations ([AmphitheatreLocalizationsEn]) instead.
///
/// **This is for internal use within Amphitheatre only.**
AmphitheatreLocalizations getLocalizationDelegate(final BuildContext context) =>
    AmphitheatreLocalizations.of(context) ?? AmphitheatreLocalizationsEn();
