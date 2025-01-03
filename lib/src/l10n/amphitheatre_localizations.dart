/// Automatically generated localizations for Amphitheatre.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'amphitheatre_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AmphitheatreLocalizations
/// returned by `AmphitheatreLocalizations.of(context)`.
///
/// Applications need to include `AmphitheatreLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/amphitheatre_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AmphitheatreLocalizations.localizationsDelegates,
///   supportedLocales: AmphitheatreLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AmphitheatreLocalizations.supportedLocales
/// property.
abstract class AmphitheatreLocalizations {
  AmphitheatreLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AmphitheatreLocalizations? of(BuildContext context) {
    return Localizations.of<AmphitheatreLocalizations>(context, AmphitheatreLocalizations);
  }

  static const LocalizationsDelegate<AmphitheatreLocalizations> delegate = _AmphitheatreLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en')
  ];

  /// Label for the cancel button. This replaces the close button in the editor.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Label for the close button. Shown in the top-left of the video player and editor.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Label for the done button. Shown in the top-right of the video editor, used to confirm the crop.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Label for the button that skips backwards in the video, by 10 seconds.
  ///
  /// In en, this message translates to:
  /// **'-10s'**
  String get back10Seconds;

  /// Label for the button that skips forwards in the video, by 10 seconds.
  ///
  /// In en, this message translates to:
  /// **'+10s'**
  String get forward10Seconds;

  /// Label for the button that pauses the video.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Label for the button that plays the video.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// Label for the button that replays the video.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get replay;

  /// Label indicating the progress when exporting a video with percentage progress.
  ///
  /// In en, this message translates to:
  /// **'Exporting video ({progress})...'**
  String exportingVideo(double progress);
}

class _AmphitheatreLocalizationsDelegate extends LocalizationsDelegate<AmphitheatreLocalizations> {
  const _AmphitheatreLocalizationsDelegate();

  @override
  Future<AmphitheatreLocalizations> load(Locale locale) {
    return SynchronousFuture<AmphitheatreLocalizations>(lookupAmphitheatreLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AmphitheatreLocalizationsDelegate old) => false;
}

AmphitheatreLocalizations lookupAmphitheatreLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AmphitheatreLocalizationsEn();
  }

  throw FlutterError(
    'AmphitheatreLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
