import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Set the platform interface implementation for [Amphitheatre] and
/// [AmphitheatreEditor].
///
/// If the specified [platform] is null, the default platform implementation
/// (which uses Flutter's [MethodChannel] API) is restored.
///
/// The primary purpose of the platform interface is to make use of
/// OS/environment-provided multimedia capabilities.
void setAmphitheatrePlatform(final AmphitheatrePlatform? platform) {
  final AmphitheatrePlatform instance =
      platform ?? AmphitheatrePlatformMethodChannel();

  PlatformInterface.verify(instance, AmphitheatrePlatform._token);
  AmphitheatrePlatform._instance = instance;
}

/// Returns the currently active [AmphitheatrePlatform] instance.
///
/// For internal use within [Amphitheatre] and [AmphitheatreEditor] only.
AmphitheatrePlatform getAmphitheatrePlatform() =>
    AmphitheatrePlatform._instance;

/// The platform interface for [Amphitheatre] and [AmphitheatreEditor].
///
/// The primary purpose of the platform interface is to make use of
/// OS/environment-provided multimedia capabilities.
abstract class AmphitheatrePlatform extends PlatformInterface {
  /// Base constructor for [AmphitheatrePlatform].
  AmphitheatrePlatform() : super(token: _token);

  /// A non-fungible token used to verify inheritance from this base class.
  static final Object _token = Object();

  static AmphitheatrePlatform _instance = AmphitheatrePlatformMethodChannel();

  // ---------------------------------------------------------------------------

  /// The character used to separate a path on the current platform.
  String get pathSeparator;

  /// Joins two path segments together.
  String joinPath(final String base, final String next) =>
      '$base$pathSeparator$next';

  /// Splits a path into its constituent segments.
  List<String> splitPath(final String path) => path.split(pathSeparator);

  /// Returns the path to the temporary directory that can be used for storing
  /// videos that are being processed.
  Future<String> getTemporaryDirectory() => throw UnimplementedError();

  /// Crop the video at the [path] to start at [start] milliseconds from the
  /// start of the original video and similarly end at [end] milliseconds.
  ///
  /// The path to the file containing the output of the crop operation is
  /// returned and the original video is deleted.
  Future<String> cropVideo({
    required final String path,
    required final int start,
    required final int end,
  }) =>
      throw UnimplementedError();
}

/// The default implementation of [AmphitheatrePlatform], using Flutter's
/// [MethodChannel] API.
final class AmphitheatrePlatformMethodChannel extends AmphitheatrePlatform {
  static const _platform = MethodChannel('xyz.apollosoftware.amphitheatre');

  @override
  String get pathSeparator {
    if ([
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.fuchsia,
    ].contains(defaultTargetPlatform)) {
      return '/';
    }

    if (defaultTargetPlatform == TargetPlatform.windows) return r'\';
    throw UnsupportedError('Unsupported platform: $defaultTargetPlatform');
  }

  @override
  Future<String> getTemporaryDirectory() async =>
      (await _platform.invokeMethod<String>('getTemporaryDirectory'))!;

  @override
  Future<String> cropVideo({
    required final String path,
    required final int start,
    required final int end,
  }) async =>
      (await _platform.invokeMethod<String>('cropVideo', <dynamic, dynamic>{
        'path': path,
        'start': start,
        'end': end,
      }))!;
}
