/// Automatically generated localizations for Amphitheatre.

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'amphitheatre_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AmphitheatreLocalizationsEs extends AmphitheatreLocalizations {
  AmphitheatreLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get done => 'Hecho';

  @override
  String get back10Seconds => '-10 s';

  @override
  String get forward10Seconds => '+10 s';

  @override
  String get pause => 'Pausa';

  @override
  String get play => 'Reproducir';

  @override
  String get replay => 'Repetir';

  @override
  String get preparingToExportVideo => 'Preparando la exportación del video...';

  @override
  String exportingVideo(double progress) {
    final intl.NumberFormat progressNumberFormat =
        intl.NumberFormat.decimalPercentPattern(
          locale: localeName,
          decimalDigits: 1,
        );
    final String progressString = progressNumberFormat.format(progress);

    return 'Exportando el video ($progressString)...';
  }

  @override
  String get unknownError => 'Se ha producido un error desconocido.';

  @override
  String selectedDuration(String time) {
    return '$time seleccionados';
  }
}

/// The translations for Spanish Castilian, as used in Latin America and the Caribbean (`es_419`).
class AmphitheatreLocalizationsEs419 extends AmphitheatreLocalizationsEs {
  AmphitheatreLocalizationsEs419() : super('es_419');

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get done => 'Listo';

  @override
  String get back10Seconds => '-10 s';

  @override
  String get forward10Seconds => '+10 s';

  @override
  String get pause => 'Pausa';

  @override
  String get play => 'Reproducir';

  @override
  String get replay => 'Repetir';

  @override
  String get preparingToExportVideo => 'Preparando la exportación del video...';

  @override
  String exportingVideo(double progress) {
    final intl.NumberFormat progressNumberFormat =
        intl.NumberFormat.decimalPercentPattern(
          locale: localeName,
          decimalDigits: 1,
        );
    final String progressString = progressNumberFormat.format(progress);

    return 'Exportando el video ($progressString)...';
  }

  @override
  String get unknownError => 'Ocurrió un error desconocido.';

  @override
  String selectedDuration(String time) {
    return '$time seleccionados';
  }
}
