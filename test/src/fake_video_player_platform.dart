import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A fake [VideoPlayerPlatform] that reports a fixed-duration video without
/// performing any real playback.
final class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  /// The duration reported for every created video.
  final Duration duration;

  int _nextPlayerId = 0;

  /// Construct a [FakeVideoPlayerPlatform].
  FakeVideoPlayerPlatform({this.duration = const Duration(seconds: 60)});

  /// Install this fake as the [VideoPlayerPlatform] instance.
  void register() => VideoPlayerPlatform.instance = this;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(final int playerId) async {}

  @override
  Future<int?> createWithOptions(final VideoCreationOptions options) async =>
      _nextPlayerId++;

  @override
  Stream<VideoEvent> videoEventsFor(final int playerId) => Stream.value(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          size: const Size(1920, 1080),
          rotationCorrection: 0,
        ),
      );

  @override
  Future<void> setLooping(final int playerId, final bool looping) async {}

  @override
  Future<void> play(final int playerId) async {}

  @override
  Future<void> pause(final int playerId) async {}

  @override
  Future<void> setVolume(final int playerId, final double volume) async {}

  @override
  Future<void> seekTo(final int playerId, final Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(
    final int playerId,
    final double speed,
  ) async {}

  @override
  Future<Duration> getPosition(final int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(final VideoViewOptions options) =>
      const SizedBox.expand();

  @override
  Future<void> setMixWithOthers(final bool mixWithOthers) async {}
}
