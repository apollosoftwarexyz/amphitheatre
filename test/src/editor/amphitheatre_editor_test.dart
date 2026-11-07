// The tests reach into the editor's state to configure crops and observe its
// controllers, which requires dynamic member access (the state class itself
// is private).
// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    late FakeVideoPlayerPlatform videoPlatform;

    setUp(() => videoPlatform = FakeVideoPlayerPlatform()..register());

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
    /// controller. [videoController] replaces the default file source, and
    /// [configureHost] adjusts the stub host before the editor is pumped.
    Future<Future<String?>> pumpEditor(
      WidgetTester tester, {
      AmphitheatreEditorOptions options = const AmphitheatreEditorOptions(),
      bool consume = false,
      bool coverRoute = false,
      VideoPlayerController? videoController,
      void Function(StubAmphitheatrePlatform host)? configureHost,
    }) async {
      host = StubAmphitheatrePlatform()
        ..register()
        ..valid = true;
      configureHost?.call(host);
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

      expect(await result, endsWith('/videos/example.mp4'));
      expect(
        host.log.where((call) => call.method == 'startCropVideo'),
        isEmpty,
      );

      await unmountEditor(tester);
    });

    testWidgets(
        'a short video with canAutoAccept pops with its own path and starts '
        'no session', (tester) async {
      videoPlatform =
          FakeVideoPlayerPlatform(duration: const Duration(seconds: 5))
            ..register();
      final Future<String?> result = await pumpEditor(
        tester,
        options: const AmphitheatreEditorOptions(
          canAutoAccept: true,
          minLength: Duration(seconds: 10),
        ),
      );
      await tester.pumpAndSettle();

      expect(await result, endsWith('/videos/example.mp4'));
      expect(
        host.log.where((call) => call.method == 'startCropVideo'),
        isEmpty,
      );

      await unmountEditor(tester);
    });

    testWidgets('a short video does not auto-accept behind another route',
        (tester) async {
      videoPlatform =
          FakeVideoPlayerPlatform(duration: const Duration(seconds: 5))
            ..register();
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

      // The platform's fixed sentence is not shown; the localized one is.
      expect(find.text('the muxer gave up'), findsNothing);
      expect(find.text('An unknown error occurred.'), findsOneWidget);
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

      // produceOutputVideo runs synchronously up to its first await (the video
      // path), so the cancel on the next line lands while that await is
      // pending; an earlier await or early return in the editor would move
      // what this covers.
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

    testWidgets('a cancel from the platform returns to the editor silently',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      var popped = false;
      unawaited(result.then((_) => popped = true));

      await startExport(tester);
      await host.failCropVideo(
        host.cropSessions.keys.single,
        code: 'EXPORT_CANCELLED',
        message: 'The export session was cancelled.',
      );
      await tester.pumpAndSettle();

      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(find.byType(AmphitheatreExporterProgress), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(popped, isFalse);

      await unmountEditor(tester);
    });

    testWidgets('the back gesture on the progress screen cancels the export',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      var popped = false;
      unawaited(result.then((_) => popped = true));

      await startExport(tester);
      final String sessionId = host.cropSessions.keys.single;

      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();

      expect(host.cancelledSessions, equals([sessionId]));
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(popped, isFalse);

      await unmountEditor(tester);
    });

    testWidgets('a cancel while the session starts cancels it once it has',
        (tester) async {
      final Future<String?> result = await pumpEditor(tester);
      var popped = false;
      unawaited(result.then((_) => popped = true));

      final gate = Completer<void>();
      host.startCropVideoGate = gate;
      await startExport(tester);
      expect(find.byType(AmphitheatreExporterProgress), findsOneWidget);
      expect(host.cropSessions, isEmpty);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(host.cancelRequests, equals(['stub-session-0']));
      expect(host.cropSessions, isEmpty);
      expect(host.deletedFiles, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(popped, isFalse);

      await unmountEditor(tester);
    });

    testWidgets(
        'a new export after a cancel cancels the superseded session and '
        'completes on its own', (tester) async {
      final Future<String?> result = await pumpEditor(tester);

      final gate = Completer<void>();
      host.startCropVideoGate = gate;
      await startExport(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Both exports resolve their session when the gate opens. (The
      // indeterminate progress screen never settles, so plain pumps.)
      await tester.tap(find.byType(AmphitheatreDoneButton));
      await tester.pump();
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(host.cancelRequests, equals(['stub-session-0']));
      expect(host.cropSessions.keys, equals(['stub-session-1']));
      expect(find.byType(AmphitheatreExporterProgress), findsOneWidget);

      await host.completeCropVideo('stub-session-1');
      await tester.pumpAndSettle();
      expect(await result, endsWith('stub-session-1.mp4'));
      expect(host.deletedFiles, isEmpty);

      await unmountEditor(tester);
    });

    testWidgets('a non-file video with canAutoAccept shows the editor',
        (tester) async {
      videoPlatform =
          FakeVideoPlayerPlatform(duration: const Duration(seconds: 5))
            ..register();
      final Future<String?> result = await pumpEditor(
        tester,
        options: const AmphitheatreEditorOptions(
          canAutoAccept: true,
          minLength: Duration(seconds: 10),
        ),
        videoController: VideoPlayerController.asset('missing.mp4'),
      );
      var popped = false;
      unawaited(result.then((_) => popped = true));
      await tester.pumpAndSettle();

      expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
      expect(popped, isFalse);

      await unmountEditor(tester);
    });

    testWidgets('a consumed short video is paused before it auto-accepts',
        (tester) async {
      videoPlatform =
          FakeVideoPlayerPlatform(duration: const Duration(seconds: 5))
            ..register();
      final Future<String?> result = await pumpEditor(
        tester,
        options: const AmphitheatreEditorOptions(
          canAutoAccept: true,
          minLength: Duration(seconds: 10),
        ),
        consume: true,
      );
      await tester.pumpAndSettle();

      expect(await result, endsWith('/videos/example.mp4'));
      expect(videoPlatform.pauseCalls, greaterThan(0));

      await unmountEditor(tester);
    });

    group('slider', () {
      /// A 1x1 PNG, for a host that answers one thumbnail.
      final Uint8List onePixel = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC'
        'hwGA60e6kgAAAABJRU5ErkJggg==',
      );

      /// The slider's track, in global coordinates.
      Rect trackRect(WidgetTester tester) => tester.getRect(
            find
                .descendant(
                  of: find.byType(AmphitheatreEditorSlider),
                  matching: find.byType(CustomPaint),
                )
                .first,
          );

      /// The x-position on screen of [time], as the default style paints it
      /// (see _SliderMetrics.positionFor).
      double xFor(WidgetTester tester, Duration time) {
        final Rect track = trackRect(tester);
        const style = AmphitheatreEditorStyle();
        final double inset = style.cropHandleSize + style.borderThickness;
        final double scale = track.width -
            style.lineThickness / 2 -
            style.borderThickness -
            inset * 2;
        return track.left +
            inset +
            time.inMilliseconds / controller.duration.inMilliseconds * scale +
            style.borderThickness / 2;
      }

      /// A point on the start crop handle.
      Offset startHandle(WidgetTester tester) {
        final Rect track = trackRect(tester);
        final AmphitheatreEditorActionCrop crop = tester
            .state<AmphitheatreEditorState>(find.byType(AmphitheatreEditor))
            .editorController
            .value
            .crop!;
        return Offset(xFor(tester, crop.start) - 8, track.center.dy);
      }

      AmphitheatreEditorController editorController(WidgetTester tester) =>
          tester
              .state<AmphitheatreEditorState>(find.byType(AmphitheatreEditor))
              .editorController;

      /// Pump the editor with a 10 s - 30 s crop committed.
      Future<void> pumpCroppedEditor(
        WidgetTester tester, {
        void Function(StubAmphitheatrePlatform host)? configureHost,
      }) async {
        await pumpEditor(tester, configureHost: configureHost);
        editorController(tester).crop(
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 30),
        );
        await tester.pump();
      }

      testWidgets('a handle drag previews the crop and writes one entry',
          (tester) async {
        await pumpCroppedEditor(tester);
        final AmphitheatreEditorController editor = editorController(tester);

        final TestGesture gesture =
            await tester.startGesture(startHandle(tester));
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();

        expect(editor.isInCropGesture, isTrue);
        final Duration previewed = editor.value.crop!.start;
        expect(previewed, greaterThan(const Duration(seconds: 10)));
        expect(editor.value.crop!.end, equals(const Duration(seconds: 30)));

        await gesture.up();
        await tester.pumpAndSettle();

        expect(editor.isInCropGesture, isFalse);
        expect(editor.value.crop!.start, equals(previewed));
        // The release always seeks, to the frame under the handle.
        expect(videoPlatform.seeks.last, equals(previewed));

        // One entry for the whole drag.
        editor.undo();
        expect(editor.value.crop!.start, equals(const Duration(seconds: 10)));
        editor.undo();
        expect(editor.value.crop!.start, equals(Duration.zero));

        await unmountEditor(tester);
      });

      testWidgets('a cancelled pointer restores the crop', (tester) async {
        await pumpCroppedEditor(tester);
        final AmphitheatreEditorController editor = editorController(tester);

        final TestGesture gesture =
            await tester.startGesture(startHandle(tester));
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
        expect(
          editor.value.crop!.start,
          greaterThan(const Duration(seconds: 10)),
        );

        await gesture.cancel();
        await tester.pumpAndSettle();

        expect(editor.isInCropGesture, isFalse);
        expect(editor.value.crop!.start, equals(const Duration(seconds: 10)));
        // Nothing was written for the abandoned drag.
        editor.undo();
        expect(editor.value.crop!.start, equals(Duration.zero));

        await unmountEditor(tester);
      });

      testWidgets('starting an export abandons a drag in flight',
          (tester) async {
        await pumpCroppedEditor(tester);
        final AmphitheatreEditorController editor = editorController(tester);

        final TestGesture gesture =
            await tester.startGesture(startHandle(tester));
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
        expect(editor.isInCropGesture, isTrue);

        await tester.tap(find.byType(AmphitheatreDoneButton));
        await tester.pump();

        expect(find.byType(AmphitheatreExporterProgress), findsOneWidget);
        expect(editor.isInCropGesture, isFalse);
        expect(editor.value.crop!.start, equals(const Duration(seconds: 10)));
        expect(tester.takeException(), isNull);

        await gesture.up();
        await host.completeCropVideo(host.cropSessions.keys.single);
        await tester.pumpAndSettle();
        await unmountEditor(tester);
      });

      testWidgets('a video shorter than minLength keeps both handles',
          (tester) async {
        videoPlatform =
            FakeVideoPlayerPlatform(duration: const Duration(seconds: 5))
              ..register();
        await pumpEditor(
          tester,
          options: const AmphitheatreEditorOptions(
            minLength: Duration(seconds: 10),
          ),
        );
        final AmphitheatreEditorController editor = editorController(tester);
        expect(
          editor.value.crop,
          equals(
            AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(seconds: 5),
            ),
          ),
        );

        final TestGesture gesture =
            await tester.startGesture(startHandle(tester));
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(editor.value.crop!.start, equals(Duration.zero));
        expect(editor.value.crop!.end, equals(const Duration(seconds: 5)));

        await unmountEditor(tester);
      });

      testWidgets('thumbnails are requested for the track once and kept '
          'across a return from the progress screen', (tester) async {
        await pumpEditor(
          tester,
          configureHost: (host) => host.thumbnails = [onePixel],
        );
        // The images decode outside the test's fake clock.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();

        MethodCall thumbnailsCall() =>
            host.log.singleWhere((call) => call.method == 'getThumbnails');
        final Rect track = trackRect(tester);
        final double devicePixelRatio =
            tester.view.devicePixelRatio;
        // The path is pinned with endsWith like the route results above: on
        // Windows the controller reports it with the drive prefix.
        expect(
          thumbnailsCall().arguments,
          allOf(
            hasLength(3),
            containsPair('path', endsWith('/videos/example.mp4')),
            containsPair(
              'count',
              (track.width / (track.height * 1920 / 1080)).ceil(),
            ),
            containsPair(
              'maxHeight',
              (track.height * devicePixelRatio).round(),
            ),
          ),
        );

        int paintedThumbnails() => (tester
                .widget<CustomPaint>(
                  find
                      .descendant(
                        of: find.byType(AmphitheatreEditorSlider),
                        matching: find.byType(CustomPaint),
                      )
                      .first,
                )
                .painter as dynamic)
            .thumbnails
            .length as int;
        expect(paintedThumbnails(), equals(1));

        await startExport(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AmphitheatreEditorSlider), findsOneWidget);
        expect(thumbnailsCall(), isNotNull);
        expect(paintedThumbnails(), equals(1));

        await unmountEditor(tester);
      });

      testWidgets('a failing thumbnail extraction leaves the track usable',
          (tester) async {
        await pumpCroppedEditor(
          tester,
          configureHost: (host) =>
              host.thumbnailsError = PlatformException(code: 'SEARCH_FAIL'),
        );
        await tester.pumpAndSettle();
        final AmphitheatreEditorController editor = editorController(tester);

        final TestGesture gesture =
            await tester.startGesture(startHandle(tester));
        await gesture.moveBy(const Offset(40, 0));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          editor.value.crop!.start,
          greaterThan(const Duration(seconds: 10)),
        );
        expect(tester.takeException(), isNull);

        await unmountEditor(tester);
      });
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
