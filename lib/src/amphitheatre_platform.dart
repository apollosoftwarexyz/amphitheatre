import 'dart:async';

import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
  AmphitheatrePlatform.ensureInitialized();
}

/// Returns the currently active [AmphitheatrePlatform] instance.
///
/// Code outside of the Amphitheatre ecosystem (i.e., apps or libraries using
/// [Amphitheatre]) should have no need to invoke this function.
AmphitheatrePlatform getAmphitheatrePlatform() =>
    AmphitheatrePlatform._instance;

/// The stage in the cropping process.
///
/// This can be used to display more specific progress in UIs.
enum AmphitheatreCropVideoStage {
  /// Exporting the video.
  export,

  /// Unknown stage.
  ///
  /// This is a fallback if the [AmphitheatrePlatform] returns an unknown stage
  /// for a [AmphitheatreCropVideoSession].
  unknown;

  /// Get the [AmphitheatreCropVideoStage] with the given name.
  ///
  /// If the name is not recognized, [AmphitheatreCropVideoStage.unknown] is
  /// returned instead.
  static AmphitheatreCropVideoStage withName(final String name) =>
      AmphitheatreCropVideoStage.values.firstWhere(
        (final stage) => stage.name == name,
        orElse: () => unknown,
      );
}

/// The output quality that was requested for the cropping process.
enum AmphitheatreCropVideoQuality {
  /// The video is processed in High Definition (1280x720).
  presetHD,

  /// The video is processed in Full High Definition (FHD) (1920x1080).
  presetFullHD,

  /// The video is processed at the highest available quality.
  highest,

  /// The video is processed in its original quality.
  passthrough,

  /// Unknown quality.
  ///
  /// This is a fallback if the [AmphitheatrePlatform] returns an unknown
  /// quality for a [AmphitheatreCropVideoSession].
  unknown;

  /// Get the [AmphitheatreCropVideoQuality] with the given raw value.
  ///
  /// If the quality value is not recognized,
  /// [AmphitheatreCropVideoQuality.unknown] is returned instead.
  static AmphitheatreCropVideoQuality withValue(final String rawValue) =>
      AmphitheatreCropVideoQuality.values.firstWhere(
        (final quality) => quality.name == rawValue,
        orElse: () => unknown,
      );
}

/// Contains status information returned by the [AmphitheatrePlatform]
/// performing a crop operation.
abstract class AmphitheatreCropVideoStatus {
  /// The editor session that the status belongs to.
  ///
  /// See [AmphitheatreCropVideoSession.id].
  String get sessionId;

  /// Get the current [AmphitheatreCropVideoStage] of the crop operation.
  AmphitheatreCropVideoStage get stage;

  /// Get the output quality that was requested for the crop operation.
  AmphitheatreCropVideoQuality get quality;

  /// Get the progress of the crop operation.
  double get progress;
}

/// The platform interface used internally by [Amphitheatre] and
/// [AmphitheatreEditor] to leverage OS or environment capabilities.
///
/// The [Amphitheatre] platform interface is not guaranteed for public
/// consumption. That is, whilst support for external *implementations* of the
/// platform interface is provided on a best effort basis, consumption of the
/// API methods will not be supported - use at your own risk!
///
/// External code should be using [Amphitheatre] or [AmphitheatreEditor] rather
/// than directly using the platform interface.
abstract class AmphitheatrePlatform extends PlatformInterface {
  /// Base constructor for [AmphitheatrePlatform].
  AmphitheatrePlatform() : super(token: _token);

  /// A non-fungible token used to verify inheritance from this base class.
  static final Object _token = Object();

  static AmphitheatrePlatform _instance = AmphitheatrePlatformMethodChannel()
    ..ensureInstanceInitialized();

  /// Ensure that whichever platform has been assigned (either automatically or
  /// supplied with [setAmphitheatrePlatform]) has been initialized.
  static void ensureInitialized() => _instance.ensureInstanceInitialized();

  // ---------------------------------------------------------------------------

  /// The character used to separate a path on the current platform.
  String get pathSeparator;

  /// Joins two path segments together.
  String joinPath(final String base, final String next) =>
      '$base$pathSeparator$next';

  /// Splits a path into its constituent segments.
  List<String> splitPath(final String path) => path.split(pathSeparator);

  /// Ensure the platform interface has been initialized.
  ///
  /// As the name implies, this function should be idempotent - that is, if the
  /// platform is initialized, it should not be initialized again.
  ///
  /// See [ensureInitialized].
  void ensureInstanceInitialized();

  /// Returns the path to the temporary directory that can be used for storing
  /// videos that are being processed.
  Future<String> getTemporaryDirectory();

  /// Delete the file at the given [path].
  Future<void> deleteFile(final String path);

  /// Crop the video at the [path] to start at [start] milliseconds from the
  /// start of the original video and similarly end at [end] milliseconds.
  ///
  /// The output video quality is set to the given [quality]. If the quality is
  /// not specified, a platform-specific optimal value will be chosen.
  ///
  /// The returned future completes when the crop operation has started. See
  /// [AmphitheatreCropVideoSession] for details.
  Future<AmphitheatreCropVideoSession> cropVideo({
    required final String path,
    required final int start,
    required final int end,
    final AmphitheatreCropVideoQuality? quality,
  });
}

/// Represents an in-progress crop session.
///
/// The [future] method on the session returns a future that completes once the
/// crop operation has concluded (or throws if the operation fails).
///
/// The [status] stream is populated with [AmphitheatreCropVideoStatus] objects
/// as the status of the crop operation changes. At least one status event
/// should be guaranteed before a crop completes, though it may be at 100%. UIs
/// should generally show an indeterminate (i.e., waiting) state until the first
/// status event is received.
abstract class AmphitheatreCropVideoSession {
  /// Get the unique session ID for this crop operation.
  String get id;

  /// Get a future that completes when the crop operation has completed
  /// successfully.
  ///
  /// The returned string is the path to the file containing the output of the
  /// crop operation.
  Future<String> get future;

  /// Get a stream of status events.
  ///
  /// As the status of the crop session changes, new status events are passed
  /// by the [AmphitheatrePlatform] with the current snapshot of the operation
  /// status.
  Stream<AmphitheatreCropVideoStatus> get status;
}

/// The default implementation of [AmphitheatrePlatform], using Flutter's
/// [MethodChannel] API.
final class AmphitheatrePlatformMethodChannel extends AmphitheatrePlatform {
  /// The Flutter [MethodChannel] that is used to invoke commands in the
  /// platform layer.
  static const _platform = MethodChannel('xyz.apollosoftware.amphitheatre');

  /// The Flutter [EventChannel] that is used to receive updates back from the
  /// platform layer.
  static const _platformEvents =
      EventChannel('xyz.apollosoftware.amphitheatre/events');

  bool _initialized = false;

  @override
  void ensureInstanceInitialized() {
    if (_initialized) {
      WidgetsFlutterBinding.ensureInitialized();
      unawaited(_platform.invokeMethod('_init'));
    }

    _initialized = true;
  }

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
  Future<void> deleteFile(final String path) async =>
      _platform.invokeMethod('deleteFile');

  @override
  Future<AmphitheatreCropVideoSession> cropVideo({
    required final String path,
    required final int start,
    required final int end,
    final AmphitheatreCropVideoQuality? quality,
  }) async {
    final String id = (await _platform.invokeMethod<String>('startCropVideo', {
      'quality': quality?.name,
      'path': path,
      'start': start,
      'end': end,
    }))!;

    return _MethodChannelCropVideoSession(
      id: id,
      quality: quality,
      path: path,
      start: start,
      end: end,
      channel: _platform,
      eventChannel: _platformEvents,
    );
  }
}

class _MethodChannelCropVideoSession implements AmphitheatreCropVideoSession {
  @override
  final String id;

  final Future<String> _future;
  final Stream<AmphitheatreCropVideoStatus> _events;

  _MethodChannelCropVideoSession({
    required this.id,
    required final String path,
    required final int start,
    required final int end,
    required final AmphitheatreCropVideoQuality? quality,
    required final MethodChannel channel,
    required final EventChannel eventChannel,
  })  : _future =
            (() async => (await channel.invokeMethod<String>('awaitCropVideo', {
                  'sessionId': id,
                }))!)(),
        _events = eventChannel
            .receiveBroadcastStream({'sessionId': id})
            .map(
              (final rawEvent) => _MethodChannelCropVideoStatus.from(
                rawEvent as Map<dynamic, dynamic>,
              ),
            )
            .where((final event) => event.sessionId == id);

  @override
  Future<String> get future => _future;

  @override
  Stream<AmphitheatreCropVideoStatus> get status => _events;
}

class _MethodChannelCropVideoStatus implements AmphitheatreCropVideoStatus {
  @override
  final String sessionId;

  @override
  final AmphitheatreCropVideoStage stage;

  @override
  final AmphitheatreCropVideoQuality quality;

  @override
  final double progress;

  const _MethodChannelCropVideoStatus({
    required this.sessionId,
    required this.stage,
    required this.quality,
    required this.progress,
  });

  factory _MethodChannelCropVideoStatus.from(
    final Map<dynamic, dynamic> map,
  ) =>
      _MethodChannelCropVideoStatus(
        sessionId: map['sessionId'] as String,
        stage: AmphitheatreCropVideoStage.withName(map['stage'] as String),
        quality:
            AmphitheatreCropVideoQuality.withValue(map['quality'] as String),
        progress: map['progress'] as double,
      );

  @override
  String toString() =>
      'AmphitheatreCropVideoStatus[sessionId=$sessionId, stage=${stage.name}, quality=${quality.name}, progress=$progress]';
}
