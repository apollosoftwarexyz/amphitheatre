import 'dart:io';

import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'fake_video_player_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Amphitheatre', () {
    /// Pump a consuming player (which initializes the controller) over the
    /// given fake platform and let the initialization settle.
    Future<AmphitheatreController> pumpPlayer(
      WidgetTester tester,
      FakeVideoPlayerPlatform platform,
    ) async {
      platform.register();

      final controller = AmphitheatreController(
        controller: VideoPlayerController.file(File('/videos/example.mp4')),
      );

      await tester.pumpWidget(
        MaterialApp(home: Amphitheatre.consume(controller: controller)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      return controller;
    }

    testWidgets('a working video shows the player and its controls',
        (tester) async {
      final AmphitheatreController controller =
          await pumpPlayer(tester, FakeVideoPlayerPlatform());

      expect(controller.hasError, isFalse);
      expect(find.text("This video can't be played."), findsNothing);
      expect(find.byType(AmphitheatreProgressSlider), findsOneWidget);
    });

    testWidgets(
        'a failure before the video player registers its error handler shows '
        'that the video cannot be played', (tester) async {
      final AmphitheatreController controller = await pumpPlayer(
        tester,
        FakeVideoPlayerPlatform(
          creationError: PlatformException(
            code: 'VideoError',
            message: 'no decoder for this stream',
          ),
        ),
      );

      expect(controller.hasError, isTrue);
      expect(find.text("This video can't be played."), findsOneWidget);
      expect(find.byType(AmphitheatreCloseButton), findsOneWidget);
      expect(find.byType(AmphitheatreProgressSlider), findsNothing);
      expect(find.byType(AmphitheatreReplayButton), findsNothing);
    });

    testWidgets('a player error event shows that the video cannot be played',
        (tester) async {
      final AmphitheatreController controller = await pumpPlayer(
        tester,
        FakeVideoPlayerPlatform(errorDescription: 'the file is corrupt'),
      );

      expect(controller.hasError, isTrue);
      expect(find.text("This video can't be played."), findsOneWidget);
      expect(find.byType(AmphitheatreCloseButton), findsOneWidget);
      expect(find.byType(AmphitheatreProgressSlider), findsNothing);
    });
  });
}
