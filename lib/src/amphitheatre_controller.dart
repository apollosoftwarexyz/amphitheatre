import 'dart:async';

import 'package:amphitheatre/src/amphitheatre.dart';
import 'package:amphitheatre/src/amphitheatre_platform.dart'
    show AmphitheatrePlatform, getAmphitheatrePlatform;
import 'package:amphitheatre/src/editor/amphitheatre_editor.dart';
import 'package:amphitheatre/src/utils.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Stores non-technical information about the video.
/// See [AmphitheatreController.info].
class AmphitheatreVideoInfo {
  /// The title of the video.
  final String? title;

  /// The subtitle of the video.
  final String? subtitle;

  /// The video description.
  final String? description;

  /// Construct an [AmphitheatreVideoInfo] instance.
  const AmphitheatreVideoInfo({
    required this.title,
    required this.subtitle,
    required this.description,
  });

  List<Object?> get _nullableElements => [title, subtitle, description];

  /// Returns true if none of the video info elements are set.
  bool get isEmpty => _nullableElements.every((item) => item == null);

  /// Returns true if any of the video info elements are set.
  bool get isNotEmpty => _nullableElements.any((item) => item != null);
}

/// Controls the Amphitheatre video player.
class AmphitheatreController with ChangeNotifier {
  /// The controller for the underlying [VideoPlayer].
  final VideoPlayerController controller;

  /// Human-readable auxiliary information about the video. This can be used by
  /// components that display the video information, but it has no impact on the
  /// video itself (i.e., it is not technical metadata).
  ///
  /// If omitted, any components that display the [AmphitheatreVideoInfo] will
  /// not be rendered.
  final AmphitheatreVideoInfo? info;

  /// The duration to use for animations and transitions.
  Duration animationDuration;

  /// The curve to use for animations and transitions.
  Curve animationCurve;

  /// Construct the [AmphitheatreController].
  AmphitheatreController({
    required this.controller,
    this.info,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeInOut,
  });

  /// Returns true if the [info] is not null and the
  /// [AmphitheatreVideoInfo.isNotEmpty].
  bool get hasVideoInfo => info != null && info!.isNotEmpty;

  /// Returns whether the video has been completed.
  bool get isCompleted => controller.value.isCompleted;

  /// Returns whether the video is playing.
  bool get isPlaying => controller.value.isPlaying;

  /// Returns whether the video is buffering.
  bool get isBuffering => controller.value.isBuffering;

  /// Returns the greatest position that the player has buffered to, within the
  /// video. The value is clamped to the maximum duration of the video.
  ///
  /// If there is no data buffered (i.e., the list of buffers from the
  /// underlying [controller] is empty), this returns null.
  ///
  /// This is therefore a fairly simple heuristic that may be off if more
  /// advanced buffering logic is used internally.
  Duration? get buffered {
    final DurationRange? buffer = controller.value.buffered.lastOrNull;
    if (buffer == null) return null;

    return buffer.end > controller.value.duration
        ? controller.value.duration
        : buffer.end;
  }

  /// Returns the position of the player, within the video.
  Duration get position => controller.value.position;

  /// Returns the duration of the entire video.
  Duration get duration => controller.value.duration;

  /// Returns the formatted position of the player, within the video.
  String get formattedPosition => controller.value.position
      .format(hours: controller.value.duration.hasHours);

  /// Returns the formatted duration of the entire video.
  String get formattedDuration => controller.value.duration.format();

  /// Returns true when the underlying [controller] has been initialized. This
  /// is triggered by calling the [initialize] function on the
  /// [AmphitheatreController].
  bool get isInitialized => controller.value.isInitialized;

  /// Returns the aspect ratio of the video.
  double get aspectRatio => controller.value.aspectRatio;

  /// Whether the video cannot be played: the underlying [controller] reports
  /// an error, or its initialization threw.
  ///
  /// The latter is tracked here because the video player throws from
  /// `setMixWithOthers` and `createWithOptions` before it has registered the
  /// error handler that feeds `value.hasError`, so those failures never reach
  /// the value.
  bool get hasError => controller.value.hasError || _initializationFailed;

  var _initialized = false;
  var _initializationFailed = false;
  var _disposed = false;
  Completer<void>? _initialization;

  /// Completes once [initialize] has finished (successfully or not) and any
  /// autoplay has been issued to the [controller]. Commands sent to the
  /// [controller] after this future completes are therefore ordered after
  /// the autoplay (see [AmphitheatreEditorOptions.canAutoAccept]); the play
  /// itself is not awaited. Already complete when [initialize] was never
  /// called on this controller (the underlying [controller] was initialized
  /// directly).
  Future<void> get whenInitialized =>
      _initialization?.future ?? Future<void>.value();

  /// Initialize the underlying [controller].
  ///
  /// A failure is reported through [hasError] (and to listeners), and is also
  /// forwarded to [FlutterError.reportError] so that it remains visible in
  /// logs and crash reporting.
  void initialize({bool autoPlay = true, bool looping = false}) {
    // Ensure the controller is not re-initialized when it is already
    // initialized.
    if (_initialized) return;
    _initialized = true;

    final initialization = Completer<void>();
    _initialization = initialization;

    controller.addListener(_onControllerUpdate);
    unawaited(controller.setLooping(looping));

    unawaited(
      controller.initialize().then((_) {
        // The controller may have been disposed during the initialization.
        if (_disposed) return;
        if (autoPlay) play();
      }).catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'amphitheatre',
            context: ErrorDescription('while initializing a video'),
          ),
        );

        if (_disposed) return;
        _initializationFailed = true;
        notifyListeners();
      }).whenComplete(initialization.complete),
    );
  }

  /// Instruct the [controller] to start playing the video.
  void play() => unawaited(controller.play());

  /// Instruct the [controller] to pause the video, whilst retaining the
  /// position.
  void pause() => unawaited(controller.pause());

  /// Instruct the [controller] to start playing the video from the start.
  void replay() => unawaited(
        controller.seekTo(Duration.zero).then((_) => controller.play()),
      );

  /// Instruct the [controller] to seek by [delta], relative to the current
  /// position.
  void seek(Duration delta) => seekTo(controller.value.position + delta);

  /// Instruct the [controller] to seek to the given [time].
  void seekTo(Duration time) => unawaited(() async {
        if (controller.value.isCompleted) {
          await controller.play();
        }

        return controller.seekTo(time);
      }());

  void _onControllerUpdate() => notifyListeners();

  /// Dispose the underlying [controller], then the [AmphitheatreController].
  ///
  /// The controller cannot be used (or initialized) again afterwards: the
  /// underlying [VideoPlayerController] is disposed with it.
  @override
  Future<void> dispose() async {
    // Set before the await: a continuation of initialize() that lands while
    // the underlying controller is being disposed must not play or notify.
    _disposed = true;
    await controller.dispose();
    super.dispose();
  }

  /// Fetch the path for the video from the underlying controller (e.g., so it
  /// can be used by the [AmphitheatreEditor]).
  ///
  /// The controller must have been initialized (see [initialize]), or this
  /// function throws an error.
  ///
  /// If [temporaryFileFallback] is false, this currently only supports
  /// [DataSourceType.file]. When the fallback is true, this method calls
  /// [getVideo] to buffer the data into a temporary file and returns the path
  /// to the temporary file instead.
  ///
  /// The returned [AmphitheatreVideoPath] specifies a normalized file path with
  /// an indication of whether the temporary fallback described above was used.
  Future<AmphitheatreVideoPath> getVideoPath({
    bool temporaryFileFallback = true,
  }) async {
    if (!controller.value.isInitialized) {
      throw StateError('The controller has not been initialized yet.');
    }

    if (controller.dataSourceType == DataSourceType.file) {
      return AmphitheatreVideoPath(
        path: Uri.parse(controller.dataSource).normalizePath().path,
        isTemporary: false,
      );
    }

    if (!temporaryFileFallback) {
      throw UnsupportedError('Data source does not have a natively supported path and temporaryFileFallback is false.');
    }

    final AmphitheatrePlatform platform = getAmphitheatrePlatform();
    final String tempDir = await platform.getTemporaryDirectory();

    final AmphitheatreVideo video = await getVideo();
    final inputFile = XFile.fromData(video.data);
    final String inputFilePath = platform.joinPath(tempDir, video.name);
    await inputFile.saveTo(inputFilePath);
    return AmphitheatreVideoPath(path: inputFilePath, isTemporary: true);
  }

  /// Fetch the data for the video from the underlying controller (e.g., so it
  /// can be used by the [AmphitheatreEditor]).
  ///
  /// The controller must have been initialized (see [initialize]), or this
  /// function throws an error.
  ///
  /// This currently only supports [DataSourceType.file] and
  /// [DataSourceType.asset]. At present, the simplest workaround is to load
  /// unsupported file types using XFile, then save it into a temporary file and
  /// then construct a [VideoPlayerController.file] with it, when initializing
  /// the [AmphitheatreController].
  Future<AmphitheatreVideo> getVideo() async {
    if (!controller.value.isInitialized) {
      throw StateError('The controller has not been initialized yet.');
    }

    String name;
    Uint8List data;
    final Duration duration = controller.value.duration;

    switch (controller.dataSourceType) {
      case DataSourceType.file:
        final Uri uri = Uri.parse(controller.dataSource).normalizePath();
        name = uri.pathSegments.last;
        data = await XFile(uri.path).readAsBytes();
      case DataSourceType.asset:
        // Assets use keys which are always delimited by a forward slash.
        name = controller.dataSource.split('/').last;
        data = Uint8List.view(
          (await rootBundle.load(controller.dataSource)).buffer,
        );
      case DataSourceType.network:
        // NOTE: Not yet implemented as I didn't want to introduce a dependency
        // on the HTTP package yet and I haven't considered the final UX 'flow'.

        // NOTE: when implementing network, don't forget that the dataSource is
        // presumably just the URL. In which case, if there are any query
        // parameters, the platform.splitPath(controller.dataSource).last
        // heuristic won't work. (It also wouldn't be a backslash on Windows).
        // So proper URL parsing will need to be used to isolate the path
        // segment of the URL.
        throw UnimplementedError(
          '[Amphitheatre] Data source type not yet supported: network',
        );
      default:
        throw UnsupportedError(
          '[Amphitheatre] Unknown or unsupported data source type: ${controller.dataSourceType}',
        );
    }

    return AmphitheatreVideo(
      name: name,
      data: data,
      duration: duration,
    );
  }
}

/// A path to a video being displayed by [Amphitheatre].
///
/// For details, see [AmphitheatreController.getVideoPath].
@immutable
final class AmphitheatreVideoPath {
  /// The path to the video file.
  final String path;

  /// If the video data had to be buffered into a temporary file (to return a
  /// valid path), this is true. Otherwise, if the video path could be used
  /// directly (e.g., because the video was already specified from a file path),
  /// this is false.
  ///
  /// This can be used to determine whether to clean up the file after usage.
  final bool isTemporary;

  /// Construct an [AmphitheatreVideoPath].
  const AmphitheatreVideoPath({
    required this.path,
    required this.isTemporary,
  });

  /// If the [AmphitheatreVideoPath] is a temporary file ([isTemporary]), this
  /// will delete the file.
  Future<void> deleteIfTemporary() async {
    if (isTemporary) {
      await getAmphitheatrePlatform().deleteFile(path);
    }
  }
}

/// Holds data about a video being displayed by [Amphitheatre].
@immutable
final class AmphitheatreVideo {
  /// The name of the video file.
  final String name;

  /// The duration of the video.
  final Duration duration;

  /// The raw data of the video.
  final Uint8List data;

  /// Construct an [AmphitheatreVideo].
  const AmphitheatreVideo({
    required this.name,
    required this.duration,
    required this.data,
  });
}
