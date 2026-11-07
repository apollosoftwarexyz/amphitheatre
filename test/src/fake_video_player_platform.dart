import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A fake [VideoPlayerPlatform] that reports a fixed-duration video without
/// performing any real playback.
final class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  /// The duration reported for every created video.
  final Duration duration;

  /// When set, [createWithOptions] throws it, as the video player does from
  /// `setMixWithOthers` or `createWithOptions` before its error handler is
  /// registered.
  final Exception? creationError;

  /// When set, the video's event stream delivers this error instead of the
  /// initialization event.
  final String? errorDescription;

  var _nextPlayerId = 0;

  /// Construct a [FakeVideoPlayerPlatform].
  FakeVideoPlayerPlatform({
    this.duration = const Duration(seconds: 60),
    this.creationError,
    this.errorDescription,
  });

  /// Install this fake as the [VideoPlayerPlatform] instance.
  void register() => VideoPlayerPlatform.instance = this;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (creationError != null) throw creationError!;
    return _nextPlayerId++;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (errorDescription != null) {
      return Stream.error(
        PlatformException(code: 'VideoError', message: errorDescription),
      );
    }

    return Stream.value(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: duration,
        size: const Size(1920, 1080),
        rotationCorrection: 0,
      ),
    );
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(
    int playerId,
    double speed,
  ) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}
