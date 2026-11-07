import 'dart:async';

import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The error code returned by an [AmphitheatrePlatform] when an operation was
/// aborted (or a warning was raised) because it would likely exceed the
/// available disk space.
///
/// The error message accompanying this code is human-readable and suitable
/// for display.
const String kExceedsDiskSpaceErrorCode = 'EXCEEDS_DISK_SPACE';

/// Set the platform interface implementation for [Amphitheatre] and
/// [AmphitheatreEditor].
///
/// If the specified [platform] is null, the default platform implementation
/// (which uses Flutter's [MethodChannel] API) is restored.
///
/// The primary purpose of the platform interface is to make use of
/// OS/environment-provided multimedia capabilities.
void setAmphitheatrePlatform(AmphitheatrePlatform? platform) {
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

/// Returns the number of bytes available, as reported by the
/// [AmphitheatrePlatform].
///
/// You must ensure [AmphitheatrePlatform.ensureInitialized] has been invoked
/// before calling this method.
Future<int> getAvailableDiskSpace() =>
    getAmphitheatrePlatform().getAvailableDiskSpace();

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
  static AmphitheatreCropVideoStage withName(String name) =>
      AmphitheatreCropVideoStage.values.firstWhere(
        (stage) => stage.name == name,
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
  static AmphitheatreCropVideoQuality withValue(String rawValue) =>
      AmphitheatreCropVideoQuality.values.firstWhere(
        (quality) => quality.name == rawValue,
        orElse: () => unknown,
      );
}

/// The behavior to employ when an operation would exceed available disk space.
enum AmphitheatreDiskSpacePolicy {
  /// Continue silently, disregarding available disk space (or lack thereof).
  ///
  /// The operation is unlikely to succeed under these conditions and, as a
  /// result of not checking, may fail less gracefully.
  ignore,

  /// Warn, but attempt to continue, if the operation would require more disk
  /// space than is available.
  ///
  /// As with [ignore], the operation is unlikely to succeed and may fail less
  /// gracefully but [warnIfExceeds] indicates that the disk space policy
  /// callback should be invoked in cases where the available disk space is
  /// likely to be exceeded (which allows tracking cases where the disk
  /// space limits would be reached).
  warnIfExceeds,

  /// Abort the operation if it would likely require more disk space than is
  /// available.
  ///
  /// This invokes the disk space policy callback (which allows tracking cases
  /// where the disk space limits would be reached).
  abortIfExceeds,
}

/// Invoked if the [AmphitheatreDiskSpacePolicy] check triggers a warning or
/// abort because the operation would exceed the available disk space.
typedef OnExceedsDiskSpace = void Function(
  AmphitheatreDiskSpacePolicy diskSpacePolicy,
);

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
  String joinPath(String base, String next) =>
      '$base$pathSeparator$next';

  /// Splits a path into its constituent segments.
  List<String> splitPath(String path) => path.split(pathSeparator);

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

  /// Get the number of bytes available for media. This is checked against the
  /// volume used for [getTemporaryDirectory].
  Future<int> getAvailableDiskSpace();

  /// Delete the file at the given [path].
  Future<void> deleteFile(String path);

  /// Crop the video at the [path] to start at [start] milliseconds from the
  /// start of the original video and similarly end at [end] milliseconds.
  ///
  /// The output video quality is set to the given [quality]. If the quality is
  /// not specified, a platform-specific optimal value will be chosen.
  ///
  /// The [diskSpacePolicy] specifies whether to check for and, how to deal with
  /// a lack of, available disk space.
  ///
  /// The returned future completes when the crop operation has started. See
  /// [AmphitheatreCropVideoSession] for details.
  Future<AmphitheatreCropVideoSession> cropVideo({
    required String path,
    required int start,
    required int end,
    required AmphitheatreDiskSpacePolicy diskSpacePolicy,
    OnExceedsDiskSpace? onExceedsDiskSpace,
    AmphitheatreCropVideoQuality? quality,
  });

  /// Extract [count] thumbnails from the video at [path], evenly spaced across
  /// it, each scaled (preserving the aspect ratio) to at most [maxHeight]
  /// pixels tall and encoded as JPEG.
  ///
  /// Fewer than [count] images are returned when frames cannot be decoded, and
  /// an unreadable video yields an empty list. The default implementation
  /// throws [UnimplementedError], so external implementations keep compiling.
  Future<List<Uint8List>> getThumbnails({
    required String path,
    required int count,
    required int maxHeight,
  }) =>
      throw UnimplementedError('getThumbnails has not been implemented.');
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
///
/// Cancelling a subscription to the [status] stream instructs the platform to
/// cancel the crop operation (if it is still running, causing [future] to
/// complete with an error) and discard the session. This avoids dangling
/// background work when the consumer of a session goes away, so the stream
/// should remain subscribed for as long as the result is wanted.
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
    // If the instance is already initialized, pass the _init message to the
    // platform to clean up the previous state and reinitialize (the first time,
    // it's already cleanly initialized so there's no need to do this).
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
  Future<int> getAvailableDiskSpace() async =>
      (await _platform.invokeMethod<int>('getAvailableDiskSpace'))!;

  @override
  Future<void> deleteFile(String path) async =>
      _platform.invokeMethod('deleteFile', {'path': path});

  @override
  Future<AmphitheatreCropVideoSession> cropVideo({
    required String path,
    required int start,
    required int end,
    required AmphitheatreDiskSpacePolicy diskSpacePolicy,
    OnExceedsDiskSpace? onExceedsDiskSpace,
    AmphitheatreCropVideoQuality? quality,
  }) async {
    if (diskSpacePolicy != AmphitheatreDiskSpacePolicy.ignore) {
      try {
        await _platform.invokeMethod('checkCropVideoDiskSpace', {
          'quality': quality?.name,
          'path': path,
          'start': start,
          'end': end,
        });
      } on PlatformException catch (error) {
        if (error.code != kExceedsDiskSpaceErrorCode) rethrow;

        onExceedsDiskSpace?.call(diskSpacePolicy);
        if (diskSpacePolicy == AmphitheatreDiskSpacePolicy.abortIfExceeds) {
          rethrow;
        }
      }
    }

    final String id = (await _platform.invokeMethod<String>('startCropVideo', {
      'quality': quality?.name,
      'path': path,
      'start': start,
      'end': end,
    }))!;

    return _MethodChannelCropVideoSession(
      id: id,
      channel: _platform,
      eventChannel: _platformEvents,
    );
  }

  @override
  Future<List<Uint8List>> getThumbnails({
    required String path,
    required int count,
    required int maxHeight,
  }) async {
    final List<Object?>? thumbnails =
        await _platform.invokeMethod<List<Object?>>('getThumbnails', {
      'path': path,
      'count': count,
      'maxHeight': maxHeight,
    });

    return (thumbnails ?? const []).whereType<Uint8List>().toList();
  }
}

class _MethodChannelCropVideoSession implements AmphitheatreCropVideoSession {
  @override
  final String id;

  final Future<String> _future;
  final Stream<AmphitheatreCropVideoStatus> _events;

  _MethodChannelCropVideoSession({
    required this.id,
    required MethodChannel channel,
    required EventChannel eventChannel,
  })  : _future = channel.invokeMethod<String>('awaitCropVideo', {
          'sessionId': id,
        }).then<String>((output) => output!)
          ..ignore(),
        _events =
            eventChannel.receiveBroadcastStream({'sessionId': id}).transform(
          StreamTransformer<dynamic,
              _MethodChannelCropVideoStatus>.fromHandlers(
            handleData: (rawEvent, sink) {
              sink.add(
                _MethodChannelCropVideoStatus.from(
                  rawEvent as Map<dynamic, dynamic>,
                ),
              );
            },
          ),
        ).where((event) => event.sessionId == id);

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
    Map<dynamic, dynamic> map,
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
