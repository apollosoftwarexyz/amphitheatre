import 'dart:convert' show base64;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:amphitheatre/src/l10n/amphitheatre_localizations.dart';
import 'package:amphitheatre/src/l10n/amphitheatre_localizations_en.dart';
import 'package:flutter/widgets.dart';

/// Get the most secure form of random available.
///
/// If [permitFallback] is true and [Random.secure] is not available (or
/// supported), this falls back to ordinary non-CS PRNG. Otherwise, this
/// acquires [Random.secure] and preserves the normal behavior of throwing if it
/// is not supported.
Random getRandom({bool permitFallback = true}) {
  try {
    return Random.secure();
  } on UnsupportedError catch (_) {
    if (permitFallback) {
      return Random();
    }

    rethrow;
  }
}

/// Byte array extensions for [Random].
extension RandomBytes on Random {
  /// Generates a [Uint8List] of bytes of the specified length.
  Uint8List nextBytes(int length) {
    final result = Uint8List(length);
    for (var i = 0; i < length; i++) {
      result[i] = nextInt(256);
    }
    return result;
  }

  /// Generates a base64 string, from bytes of the given length.
  String nextString(int length) => base64.encode(nextBytes(length));
}

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
  String format({bool? hours}) => [
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
AmphitheatreLocalizations getLocalizationDelegate(BuildContext context) =>
    AmphitheatreLocalizations.of(context) ?? AmphitheatreLocalizationsEn();
