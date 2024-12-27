import 'dart:async';

import 'package:amphitheatre/src/utils.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
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
  bool get isEmpty => _nullableElements.every((final item) => item == null);

  /// Returns true if any of the video info elements are set.
  bool get isNotEmpty => _nullableElements.any((final item) => item != null);
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

  bool _initialized = false;

  /// Initialize the underlying [controller].
  void initialize({final bool autoPlay = true, final bool looping = false}) {
    // Ensure the controller is not re-initialized when it is already
    // initialized.
    if (_initialized) return;

    _initialized = true;

    controller.addListener(_onControllerUpdate);
    unawaited(controller.setLooping(looping));
    unawaited(controller.initialize());

    if (autoPlay) play();
  }

  /// Instruct the [controller] to start playing the video.
  void play() => unawaited(controller.play());

  /// Instruct the [controller] to pause the video, whilst retaining the
  /// position.
  void pause() => unawaited(controller.pause());

  /// Instruct the [controller] to start playing the video from the start.
  void replay() => unawaited(
        controller.seekTo(Duration.zero).then((final _) => controller.play()),
      );

  /// Instruct the [controller] to seek by [delta], relative to the current
  /// position.
  void seek(final Duration delta) => seekTo(controller.value.position + delta);

  /// Instruct the [controller] to seek to the given [time].
  void seekTo(final Duration time) => unawaited(() async {
        if (controller.value.isCompleted) {
          await controller.play();
        }

        return controller.seekTo(time);
      }());

  void _onControllerUpdate() => notifyListeners();

  /// Dispose the underlying [controller], then the [AmphitheatreController].
  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();

    // As everything is now disposed, mark that the controller can be
    // re-initialized if desired.
    _initialized = false;
  }
}
