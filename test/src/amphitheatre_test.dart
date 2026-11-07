import 'dart:async';
import 'dart:io';

import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter/foundation.dart';
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
        MaterialApp(
          home: Amphitheatre.consume(
            controller: controller,
            buildDoneButton: (controller, _) =>
                AmphitheatreDoneButton(controller: controller),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      return controller;
    }

    /// The opacity the close button is rendered at.
    double closeButtonOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(AmphitheatreCloseButton),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('a working video shows the player and its controls',
        (tester) async {
      final AmphitheatreController controller =
          await pumpPlayer(tester, FakeVideoPlayerPlatform());

      expect(controller.hasError, isFalse);
      expect(find.text("This video can't be played."), findsNothing);
      expect(find.byType(AmphitheatreProgressSlider), findsOneWidget);
      expect(find.byType(AmphitheatreDoneButton), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      // Only the close button is left, and it is shown.
      expect(closeButtonOpacity(tester), 1.0);
      expect(find.byType(AmphitheatreDoneButton), findsNothing);
      expect(find.byType(AmphitheatreProgressSlider), findsNothing);
      expect(find.byType(AmphitheatreReplayButton), findsNothing);

      // The failure stays observable beyond the flag: it is reported through
      // FlutterError.reportError, which the test binding collects.
      expect(
        tester.takeException(),
        isA<PlatformException>()
            .having((e) => e.message, 'message', 'no decoder for this stream'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a player error event shows that the video cannot be played',
        (tester) async {
      final AmphitheatreController controller = await pumpPlayer(
        tester,
        FakeVideoPlayerPlatform(errorDescription: 'the file is corrupt'),
      );

      expect(controller.hasError, isTrue);
      expect(find.text("This video can't be played."), findsOneWidget);
      expect(closeButtonOpacity(tester), 1.0);
      expect(find.byType(AmphitheatreDoneButton), findsNothing);
      expect(find.byType(AmphitheatreProgressSlider), findsNothing);
      expect(tester.takeException(), isA<PlatformException>());
    });

    testWidgets('tapping an unplayable video does not hide the close button',
        (tester) async {
      await pumpPlayer(
        tester,
        FakeVideoPlayerPlatform(errorDescription: 'the file is corrupt'),
      );

      expect(tester.takeException(), isA<PlatformException>());

      await tester.tap(find.text("This video can't be played."));
      await tester.pump(const Duration(milliseconds: 400));

      expect(closeButtonOpacity(tester), 1.0);
    });
  });

  group('AmphitheatreController.whenInitialized', () {
    test('is already complete when initialize was never called', () async {
      FakeVideoPlayerPlatform().register();
      final controller = AmphitheatreController(
        controller: VideoPlayerController.file(File('/videos/example.mp4')),
      );

      var completed = false;
      unawaited(controller.whenInitialized.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);

      expect(completed, isTrue);
    });

    test('completes after the autoplay has been issued', () async {
      final platform = FakeVideoPlayerPlatform()..register();
      final controller = AmphitheatreController(
        controller: VideoPlayerController.file(File('/videos/example.mp4')),
      )..initialize();

      await controller.whenInitialized;

      expect(platform.playCalls, 1);
      expect(controller.hasError, isFalse);
    });

    test('completes when the initialization fails', () async {
      final List<FlutterErrorDetails> reported = [];
      final FlutterExceptionHandler? originalOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = originalOnError);

      final platform = FakeVideoPlayerPlatform(
        creationError: PlatformException(code: 'VideoError'),
      )..register();
      final controller = AmphitheatreController(
        controller: VideoPlayerController.file(File('/videos/example.mp4')),
      )..initialize();

      await controller.whenInitialized;

      expect(controller.hasError, isTrue);
      expect(platform.playCalls, 0);
      expect(reported, hasLength(1));
    });
  });
}
