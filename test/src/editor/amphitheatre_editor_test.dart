// The tests reach into the editor's state to configure crops and observe its
// controllers, which requires dynamic member access (the state class itself
// is private).
// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:io';

import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_screenshot/test_screenshot.dart';
import 'package:video_player/video_player.dart';

import '../fake_video_player_platform.dart';
import '../stub_platform_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AmphitheatreEditor', () {
    late StubAmphitheatrePlatform host;
    late AmphitheatreController controller;

    setUp(() => FakeVideoPlayerPlatform().register());

    /// Whether the editor under test consumed its controller (and so disposes
    /// it itself).
    var consumedController = false;

    /// Pump the editor inside an app shell and initialize the video (which
    /// sets the default full-length crop), returning the editor route's
    /// result.
    ///
    /// With [coverRoute], a second route is pushed on top of the editor before
    /// the video initializes, so the editor is not the current route. With
    /// [consume], the editor consumes (initializes and disposes) its
    /// controller. [videoController] replaces the default file source.
    Future<Future<String?>> pumpEditor(
      WidgetTester tester, {
      AmphitheatreEditorOptions options = const AmphitheatreEditorOptions(),
      bool consume = false,
      bool coverRoute = false,
      VideoPlayerController? videoController,
    }) async {
      host = StubAmphitheatrePlatform()
        ..register()
        ..valid = true;
      AmphitheatrePlatform.ensureInitialized();
      consumedController = consume;

      controller = AmphitheatreController(
        controller: videoController ??
            VideoPlayerController.file(File('/videos/example.mp4')),
      );

      await tester.pumpWidget(
        const Screenshotter(
          child: MaterialApp(home: Scaffold(body: SizedBox.expand())),
        ),
      );

      final NavigatorState navigator = tester.state(find.byType(Navigator));
      final Future<String?> result = navigator.push<String?>(
        MaterialPageRoute<String?>(
          builder: (_) => consume
              ? AmphitheatreEditor.consume(
                  controller: controller,
                  options: options,
                )
              : AmphitheatreEditor(controller: controller, options: options),
        ),
      );

      if (coverRoute) {
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          ),
        );
      }

      if (!consume) controller.initialize(autoPlay: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      return result;
    }

    /// Unmount the editor and dispose the video controller, ensuring that no
    /// timers outlive the test.
    Future<void> unmountEditor(WidgetTester tester) async {
      host.unregister();
      await tester.pumpWidget(const SizedBox.shrink());
      if (!consumedController) unawaited(controller.dispose());
      await tester.pump();
    }

    /// Apply a non-trivial crop and start the export via the done button.
    Future<void> startExport(WidgetTester tester) async {
      final AmphitheatreEditorState editor =
          tester.state(find.byType(AmphitheatreEditor));
      editor.editorController.crop(
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 5),
      );
      await tester.pump();

      await tester.tap(find.byType(AmphitheatreDoneButton));
      await tester.pump();
    }

    testWidgets('a successful export pops with the output video path',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      await startExport(tester);

      expect(find.byType(AmphitheatreExporterProgress), findsOneWidget);
      await tester.pump();

      final String sessionId = host.cropSessions.keys.single;
      await host.completeCropVideo(sessionId);
      await tester.pump();

      expect(
        await result,
        equals(
          '${StubAmphitheatrePlatform.kMockTemporaryDirectory}/'
          '$sessionId.mp4',
        ),
      );

      await unmountEditor(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('progress updates are reflected on the exporter screen',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      await startExport(tester);

      final String sessionId = host.cropSessions.keys.single;
      await host.emitCropStatus(sessionId, progress: 0.25);
      await tester.pump();

      final LinearProgressIndicator indicator =
          tester.widget(find.byType(LinearProgressIndicator));
      expect(indicator.value, equals(0.25));

      await host.emitCropStatus(sessionId, progress: 0.5);
      await tester.pump();
      expect(indicator.value, equals(0.25));

      await host.completeCropVideo(sessionId);
      await tester.pump();
      expect(await result, isNotNull);

      await unmountEditor(tester);
    });

    testWidgets('a failed export shows the error and restores the editor',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      host.hasSufficientDiskSpace = false;

      var popped = false;
      unawaited(result.then((_) => popped = true));

      await startExport(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('There is not enough free space on this device to '
            'process the video.'),
        findsOneWidget,
      );
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(find.byType(AmphitheatreExporterProgress), findsNothing);
      expect(popped, isFalse);

      // Allow the snack bar to expire before unmounting.
      await tester.pump(const Duration(seconds: 5));
      await unmountEditor(tester);
    });

    testWidgets('an unimplemented host restores the editor without popping',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      var popped = false;
      unawaited(result.then((_) => popped = true));

      // Simulate a platform without the crop implementation, which raises a
      // MissingPluginException (notably not a PlatformException).
      host.valid = false;

      await startExport(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(popped, isFalse);

      // Allow the snack bar to expire before unmounting.
      await tester.pump(const Duration(seconds: 5));
      await unmountEditor(tester);
    });

    testWidgets('a full-length crop pops with the input path without cropping',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);

      // The default crop spans the entire video, so no crop is needed.
      final AmphitheatreEditorState editor =
          tester.state(find.byType(AmphitheatreEditor));
      editor.editorController.crop(
        start: Duration.zero,
        end: const Duration(seconds: 60),
      );
      expect(editor.editorController.value.crop, isNotNull);

      await tester.pumpAndSettle();
      await tester.screenshotWithImages(() async {}, path: 'screenshot.png');

      await tester.tap(find.byType(AmphitheatreDoneButton));
      await tester.pumpAndSettle();

      expect(await result, equals((await controller.getVideoPath()).path));
      expect(
        host.log.where((call) => call.method == 'startCropVideo'),
        isEmpty,
      );

      await unmountEditor(tester);
    });

    testWidgets(
        'a short video with canAutoAccept pops with its own path and starts '
        'no session', (tester) async {
      FakeVideoPlayerPlatform(duration: const Duration(seconds: 5)).register();
      final Future<String?> result = await pumpEditor(
        tester,
        options: const AmphitheatreEditorOptions(
          canAutoAccept: true,
          minLength: Duration(seconds: 10),
        ),
      );
      await tester.pumpAndSettle();

      expect(await result, equals((await controller.getVideoPath()).path));
      expect(
        host.log.where((call) => call.method == 'startCropVideo'),
        isEmpty,
      );

      await unmountEditor(tester);
    });

    testWidgets('a short video does not auto-accept behind another route',
        (tester) async {
      FakeVideoPlayerPlatform(duration: const Duration(seconds: 5)).register();
      final Future<String?> result = await pumpEditor(
        tester,
        options: const AmphitheatreEditorOptions(
          canAutoAccept: true,
          minLength: Duration(seconds: 10),
        ),
        coverRoute: true,
      );
      var popped = false;
      unawaited(result.then((_) => popped = true));
      await tester.pumpAndSettle();

      expect(find.text('cover'), findsOneWidget);
      expect(popped, isFalse);

      // Back from the covering route, the editor is still there.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(popped, isFalse);

      await unmountEditor(tester);
    });

    testWidgets(
        'cancel on the progress screen cancels the session and returns to the '
        'editor without a message', (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      var popped = false;
      unawaited(result.then((_) => popped = true));

      await startExport(tester);
      expect(find.byType(AmphitheatreExporterProgress), findsOneWidget);
      final String sessionId = host.cropSessions.keys.single;

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(host.cancelledSessions, equals([sessionId]));
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(find.byType(AmphitheatreExporterProgress), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(popped, isFalse);

      await unmountEditor(tester);
    });

    testWidgets('a failed export offers to try again, which starts a second '
        'session', (tester) async {
      final Future<String?> result = await pumpEditor(tester);

      await startExport(tester);
      final String firstSession = host.cropSessions.keys.single;
      await host.failCropVideo(firstSession, message: 'the muxer gave up');
      await tester.pumpAndSettle();

      expect(find.text('the muxer gave up'), findsOneWidget);
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(
        host.log.where((call) => call.method == 'startCropVideo'),
        hasLength(2),
      );
      final String secondSession = host.cropSessions.keys.single;
      expect(secondSession, isNot(equals(firstSession)));

      await host.completeCropVideo(secondSession);
      await tester.pumpAndSettle();
      expect(
        await result,
        equals(
          '${StubAmphitheatrePlatform.kMockTemporaryDirectory}/'
          '$secondSession.mp4',
        ),
      );

      await unmountEditor(tester);
    });

    testWidgets(
        'a consumed controller survives a failed export and a second attempt '
        'succeeds', (tester) async {
      final Future<String?> result = await pumpEditor(tester, consume: true);

      await startExport(tester);
      await host.failCropVideo(host.cropSessions.keys.single);
      await tester.pumpAndSettle();

      // Back in the editor with the same, working player.
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(controller.isInitialized, isTrue);
      expect(controller.hasError, isFalse);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      final String secondSession = host.cropSessions.keys.single;
      await host.completeCropVideo(secondSession);
      await tester.pumpAndSettle();

      expect(
        await result,
        equals(
          '${StubAmphitheatrePlatform.kMockTemporaryDirectory}/'
          '$secondSession.mp4',
        ),
      );

      await unmountEditor(tester);
    });

    testWidgets('a cancel during preparation starts no session',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      var popped = false;
      unawaited(result.then((_) => popped = true));

      final AmphitheatreEditorState editor =
          tester.state(find.byType(AmphitheatreEditor));
      editor.editorController.crop(
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 5),
      );
      await tester.pump();

      // The export is still resolving the video path when it is cancelled.
      unawaited(editor.produceOutputVideo());
      expect(editor.exporting, isTrue);
      editor.cancelExport();
      await tester.pumpAndSettle();

      expect(
        host.log.where((call) => call.method == 'startCropVideo'),
        isEmpty,
      );
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(popped, isFalse);

      await unmountEditor(tester);
    });

    testWidgets('a video path failure returns to the editor', (tester) async {
      // An asset that does not exist: resolving its path fails before any
      // session is started.
      final Future<String?> result = await pumpEditor(
        tester,
        videoController: VideoPlayerController.asset('missing.mp4'),
      );
      var popped = false;
      unawaited(result.then((_) => popped = true));

      await startExport(tester);
      await tester.pumpAndSettle();

      expect(find.text('An unknown error occurred.'), findsOneWidget);
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(
        host.log.where((call) => call.method == 'startCropVideo'),
        isEmpty,
      );
      expect(popped, isFalse);

      // Allow the snack bar to expire before unmounting.
      await tester.pump(const Duration(seconds: 5));
      await unmountEditor(tester);
    });
  });
}
