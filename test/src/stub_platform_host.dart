import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The arguments provided to `startCropVideo` for a session, along with the
/// session's computed output path.
final class StubCropSession {
  /// The path of the input video.
  final String path;

  /// The crop start time, in milliseconds.
  final int start;

  /// The crop end time, in milliseconds.
  final int end;

  /// The requested output quality.
  final String quality;

  /// The output path that the session will produce.
  final String outputPath;

  /// Construct a [StubCropSession].
  const StubCropSession({
    required this.path,
    required this.start,
    required this.end,
    required this.quality,
    required this.outputPath,
  });
}

/// A stub implementation of the host (native) side of the Amphitheatre
/// platform channel.
///
/// This emulates the contract that the platform implementations (e.g.,
/// Android and iOS) are expected to fulfill, so that the Dart side of the
/// channel (`AmphitheatrePlatformMethodChannel`) can be exercised in unit
/// tests - notably, that it invokes the correct methods with the correct
/// arguments.
final class StubAmphitheatrePlatform {
  /// The name of the plugin's method channel.
  static const String channelName = 'xyz.apollosoftware.amphitheatre';

  /// The default fake path reported by `getTemporaryDirectory`.
  static const String kMockTemporaryDirectory =
      '/tmp/xyz.apollosoftware.amphitheatre';

  /// A [MethodChannel] identical (by name) to the one used by the plugin.
  static const MethodChannel channel = MethodChannel(channelName);

  /// An [EventChannel] identical (by name) to the one used by the plugin.
  static const EventChannel eventChannel = EventChannel('$channelName/events');

  /// The fake path reported by `getTemporaryDirectory`.
  final String temporaryDirectory;

  /// Every [MethodCall] received by the stub, in order.
  final List<MethodCall> log = [];

  /// The paths passed to `deleteFile`, in order.
  final List<String> deletedFiles = [];

  /// The crop sessions started via `startCropVideo`, keyed by session ID.
  final Map<String, StubCropSession> cropSessions = {};

  /// Pending `awaitCropVideo` results, keyed by session ID. Resolved by
  /// [completeCropVideo].
  final Map<String, Completer<String>> _pendingExports = {};

  /// Whether the host reports sufficient disk space for crop operations.
  bool hasSufficientDiskSpace = true;

  /// Whether the host fails `deleteFile` calls with `FILE_REMOVAL_FAILED`.
  bool failFileDeletion = false;

  /// Whether to mock a valid platform channel, or not.
  bool valid = true;

  /// The arguments received by the event channel's `onListen`, in order.
  final List<Object?> statusListenArguments = [];

  /// The session IDs whose status streams have been cancelled, in order.
  final List<String> cancelledSessions = [];

  /// Status event sinks, keyed by session ID. A sink's [Completer] completes
  /// once the stream has a listener.
  final Map<String, Completer<MockStreamHandlerEventSink>> _statusSinks = {};

  int _nextSessionId = 0;

  /// Construct a [StubAmphitheatrePlatform].
  StubAmphitheatrePlatform({
    this.temporaryDirectory = kMockTemporaryDirectory,
  });

  /// Register the stub as the handler for the plugin's method channel.
  ///
  /// Call this in `setUp`, and [unregister] in `tearDown`.
  void register() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, _handleMethodCall)
      ..setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: _onStatusListen,
          onCancel: _onStatusCancel,
        ),
      );
  }

  /// Unregister the stub as the handler for the plugin's method channel.
  void unregister() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockStreamHandler(eventChannel, null);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    log.add(call);

    void missingImplementation() {
      throw MissingPluginException(
        'No implementation found for method ${call.method} '
        'on channel $channelName',
      );
    }

    if (!valid) {
      missingImplementation();
    }

    switch (call.method) {
      case '_init':
        return true;
      case 'getTemporaryDirectory':
        return temporaryDirectory;
      case 'deleteFile':
        _deleteFile(call);
        return null;
      case 'checkCropVideoDiskSpace':
        _checkCropVideoDiskSpace(call);
        return null;
      case 'startCropVideo':
        return _startCropVideo(call);
      case 'awaitCropVideo':
        return _awaitCropVideo(call);
      default:
        missingImplementation();
    }
  }

  void _deleteFile(MethodCall call) {
    final String path = _arg<String>(call, 'path');

    if (failFileDeletion) {
      throw PlatformException(
        code: 'FILE_REMOVAL_FAILED',
        message: 'failed to delete file at path',
        details: path,
      );
    }

    deletedFiles.add(path);
  }

  void _checkCropVideoDiskSpace(MethodCall call) {
    _arg<String>(call, 'path');
    _validateCropRange(_arg<int>(call, 'start'), _arg<int>(call, 'end'));

    if (!hasSufficientDiskSpace) {
      throw PlatformException(
        code: 'EXCEEDS_DISK_SPACE',
        message: 'There is not enough free space on this device to process '
            'the video.',
        details: {'requiredBytes': 2048, 'availableBytes': 1024},
      );
    }
  }

  String _startCropVideo(MethodCall call) {
    final String path = _arg<String>(call, 'path');
    final int start = _arg<int>(call, 'start');
    final int end = _arg<int>(call, 'end');
    final String? quality = _arg<String?>(call, 'quality');
    _validateCropRange(start, end);

    final sessionId = 'stub-session-${_nextSessionId++}';
    cropSessions[sessionId] = StubCropSession(
      path: path,
      start: start,
      end: end,
      // A null quality resolves to the platform default.
      quality: quality ?? 'presetFullHD',
      // The output is a session-unique file in the temporary directory.
      outputPath: '$temporaryDirectory/$sessionId.mp4',
    );
    _pendingExports[sessionId] = Completer<String>();
    return sessionId;
  }

  /// Conclude the export for [sessionId] successfully: the `awaitCropVideo`
  /// future resolves with the output path and the session is discarded;
  /// then, if a listener is bound, a final 100% status event is emitted and
  /// the status stream is ended.
  ///
  /// The session bookkeeping is settled before any events are delivered:
  /// ending the stream causes the Dart side to cancel its subscription, and
  /// that cancellation must not observe (and abort) a still-live session.
  Future<void> completeCropVideo(String sessionId) async {
    final Completer<MockStreamHandlerEventSink>? sink = _statusSinks[sessionId];
    final StubCropSession session = cropSessions.remove(sessionId)!;
    _pendingExports.remove(sessionId)!.complete(session.outputPath);

    if (sink != null && sink.isCompleted) {
      final MockStreamHandlerEventSink events = await sink.future;

      events
        ..success({
          'sessionId': sessionId,
          'stage': 'export',
          'quality': session.quality,
          'progress': 1.0,
        })
        ..endOfStream();
    }
  }

  /// Reject a crop range whose [start] is after its [end], mirroring the
  /// platform implementations.
  static void _validateCropRange(int start, int end) {
    if (start > end) {
      throw PlatformException(
        code: 'INVALID_ARGS',
        message: "Invalid arguments for cropVideo: 'start' must not be after "
            "'end'.",
      );
    }
  }

  Future<String> _awaitCropVideo(MethodCall call) {
    final String sessionId = _arg<String>(call, 'sessionId');
    final Completer<String>? pending = _pendingExports[sessionId];

    if (pending == null) {
      throw PlatformException(
        code: 'UNKNOWN_SESSION',
        message: 'Invalid session ID.',
        details: sessionId,
      );
    }

    return pending.future;
  }

  /// Emit a crop status event to [sessionId]'s status stream, delivered once
  /// the stream has a listener.
  ///
  /// The event echoes back the arguments provided to `startCropVideo`.
  /// [stage], [quality], and [overrideSessionId] may be specified to override
  /// the respective fields.
  Future<void> emitCropStatus(
    String sessionId, {
    required double progress,
    String stage = 'export',
    String? quality,
    String? overrideSessionId,
  }) async {
    (await _statusSink(sessionId).future).success({
      'sessionId': overrideSessionId ?? sessionId,
      'stage': stage,
      'quality': quality ?? cropSessions[sessionId]!.quality,
      'progress': progress,
    });
  }

  /// End the status stream for [sessionId].
  Future<void> endCropStatus(String sessionId) async {
    (await _statusSink(sessionId).future).endOfStream();
  }

  Completer<MockStreamHandlerEventSink> _statusSink(String sessionId) =>
      _statusSinks.putIfAbsent(sessionId, Completer.new);

  void _onStatusListen(
    Object? arguments,
    MockStreamHandlerEventSink events,
  ) {
    statusListenArguments.add(arguments);

    final Object? sessionId =
        arguments is Map<Object?, Object?> ? arguments['sessionId'] : null;

    if (sessionId is! String || !cropSessions.containsKey(sessionId)) {
      events.error(
        code: 'UNKNOWN_SESSION',
        message: 'Invalid session ID.',
        details: sessionId,
      );
      return;
    }

    final Completer<MockStreamHandlerEventSink> sink = _statusSink(sessionId);
    if (sink.isCompleted) {
      events.error(
        code: 'CONFLICTING_BIND',
        message:
            'Tried to bind an event sink to a session that was already bound.',
      );
      return;
    }

    sink.complete(events);
  }

  void _onStatusCancel(Object? arguments) {
    final Object? sessionId =
        arguments is Map<Object?, Object?> ? arguments['sessionId'] : null;

    if (sessionId is String) {
      cancelledSessions.add(sessionId);
      _statusSinks.remove(sessionId);

      // Cancelling the status subscription cancels the crop operation and
      // discards the session.
      if (cropSessions.remove(sessionId) != null) {
        _pendingExports.remove(sessionId)!.completeError(
              PlatformException(
                code: 'EXPORT_CANCELLED',
                message: 'The export session was cancelled.',
              ),
            );
      }
    }
  }

  /// Read the argument with the given [name] from the [call], ensuring that
  /// it is present and of type [T] (where [T] may or may not be nullable).
  ///
  /// Throws a [PlatformException] mirroring the error a real platform
  /// implementation produces for missing or invalid arguments.
  static T _arg<T>(
    MethodCall call,
    String name,
  ) {
    final Object? arguments = call.arguments;
    final Object? value =
        arguments is Map<Object?, Object?> ? arguments[name] : null;

    final isNullable = null is T;

    expect(
      value,
      isNullable ? anyOf(isA<T>(), isNull) : isA<T>(),
      reason:
          "${call.method} argument '$name' must be of type $T but was ${value == null ? "null" : value.runtimeType}",
    );

    return value as T;
  }
}
