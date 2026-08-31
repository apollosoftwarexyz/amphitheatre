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

    /// Pump the editor inside an app shell and initialize the video (which
    /// sets the default full-length crop), returning the editor route's
    /// result.
    Future<Future<String?>> pumpEditor(final WidgetTester tester) async {
      host = StubAmphitheatrePlatform()
        ..register()
        ..valid = true;
      AmphitheatrePlatform.ensureInitialized();

      controller = AmphitheatreController(
        controller: VideoPlayerController.file(File('/videos/example.mp4')),
      );

      await tester.pumpWidget(
        const Screenshotter(
          child: MaterialApp(home: Scaffold(body: SizedBox.expand())),
        ),
      );

      final NavigatorState navigator = tester.state(find.byType(Navigator));
      final Future<String?> result = navigator.push<String?>(
        MaterialPageRoute<String?>(
          builder: (final _) => AmphitheatreEditor(controller: controller),
        ),
      );

      controller.initialize(autoPlay: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      return result;
    }

    /// Unmount the editor and dispose the video controller, ensuring that no
    /// timers outlive the test.
    Future<void> unmountEditor(final WidgetTester tester) async {
      host.unregister();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.pump();
    }

    /// Apply a non-trivial crop and start the export via the done button.
    Future<void> startExport(final WidgetTester tester) async {
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
        (final tester) async {
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
        (final tester) async {
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
        (final tester) async {
      final Future<String?> result = await pumpEditor(tester);
      host.hasSufficientDiskSpace = false;

      var popped = false;
      unawaited(result.then((final _) => popped = true));

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
        (final tester) async {
      final Future<String?> result = await pumpEditor(tester);
      var popped = false;
      unawaited(result.then((final _) => popped = true));

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
        (final tester) async {
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

      expect(await result, equals('/videos/example.mp4'));
      expect(
        host.log.where((final call) => call.method == 'startCropVideo'),
        isEmpty,
      );

      await unmountEditor(tester);
    });
  });
}
