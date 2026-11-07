import 'dart:async';

import 'package:amphitheatre/src/amphitheatre_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stub_platform_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AmphitheatrePlatformMethodChannel', () {
    late StubAmphitheatrePlatform host;
    final AmphitheatrePlatform platform = getAmphitheatrePlatform();

    setUp(() {
      host = StubAmphitheatrePlatform()..register();
      AmphitheatrePlatform.ensureInitialized();
    });

    tearDown(() => host.unregister());

    test('setPlatform can supply a valid platform interface', () {
      expect(() => setAmphitheatrePlatform(null), returnsNormally);

      expect(
        () => setAmphitheatrePlatform(AmphitheatrePlatformMethodChannel()),
        returnsNormally,
      );
    });

    test('getTemporaryDirectory returns the path reported by the host',
        () async {
      expect(
        await platform.getTemporaryDirectory(),
        equals(host.temporaryDirectory),
      );
    });

    test('deleteFile passes the path to the host', () async {
      await platform.deleteFile('/videos/example.mp4');
      expect(host.deletedFiles, equals(['/videos/example.mp4']));
    });

    test('deleteFile propagates a failure from the host', () async {
      host.failFileDeletion = true;

      await expectLater(
        platform.deleteFile('/videos/example.mp4'),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'FILE_REMOVAL_FAILED'),
        ),
      );
      expect(host.deletedFiles, isEmpty);
    });

    test('getThumbnails passes its arguments to the host', () async {
      host.thumbnails = [Uint8List.fromList([1, 2, 3])];

      final List<Uint8List> thumbnails = await platform.getThumbnails(
        path: '/videos/example.mp4',
        count: 12,
        maxHeight: 144,
      );

      final MethodCall call =
          host.log.singleWhere((call) => call.method == 'getThumbnails');
      expect(
        call.arguments,
        equals({
          'path': '/videos/example.mp4',
          'count': 12,
          'maxHeight': 144,
        }),
      );
      expect(thumbnails, equals([Uint8List.fromList([1, 2, 3])]));
    });

    test('getThumbnails keeps only the byte lists the host answers', () async {
      host.thumbnails = [
        Uint8List.fromList([1]),
        'not bytes',
        null,
        Uint8List.fromList([2]),
      ];

      final List<Uint8List> thumbnails = await platform.getThumbnails(
        path: '/videos/example.mp4',
        count: 2,
        maxHeight: 64,
      );

      expect(
        thumbnails,
        equals([Uint8List.fromList([1]), Uint8List.fromList([2])]),
      );
    });

    test('cropVideo starts a session with the correct arguments', () async {
      final AmphitheatreCropVideoSession session = await platform.cropVideo(
        path: '/videos/example.mp4',
        start: 1000,
        end: 5000,
        diskSpacePolicy: AmphitheatreDiskSpacePolicy.abortIfExceeds,
        quality: AmphitheatreCropVideoQuality.presetHD,
      );

      final MethodCall call =
          host.log.singleWhere((call) => call.method == 'startCropVideo');
      expect(
        call.arguments,
        equals({
          'quality': 'presetHD',
          'path': '/videos/example.mp4',
          'start': 1000,
          'end': 5000,
        }),
      );
      expect(host.cropSessions, contains(session.id));
    });

    test('cropVideo session future resolves to the output path', () async {
      final AmphitheatreCropVideoSession session = await platform.cropVideo(
        path: '/videos/example.mp4',
        start: 1000,
        end: 5000,
        diskSpacePolicy: AmphitheatreDiskSpacePolicy.abortIfExceeds,
      );

      await host.completeCropVideo(session.id);

      expect(
        await session.future,
        equals(
          '${StubAmphitheatrePlatform.kMockTemporaryDirectory}/'
          '${session.id}.mp4',
        ),
      );
      expect(host.cropSessions, isEmpty);
    });

    group('status events', () {
      Future<AmphitheatreCropVideoSession> startSession({
        AmphitheatreCropVideoQuality? quality,
      }) =>
          platform.cropVideo(
            path: '/videos/example.mp4',
            start: 1000,
            end: 5000,
            diskSpacePolicy: AmphitheatreDiskSpacePolicy.abortIfExceeds,
            quality: quality,
          );

      test('subscribing passes the session ID to the host', () async {
        final AmphitheatreCropVideoSession session = await startSession();
        final StreamSubscription<AmphitheatreCropVideoStatus> subscription =
            session.status.listen((_) {});

        // emitCropStatus completes once the host has a bound listener.
        await host.emitCropStatus(session.id, progress: 0);

        expect(
          host.statusListenArguments,
          equals([
            {'sessionId': session.id},
          ]),
        );

        await subscription.cancel();
      });

      test('status events are parsed and delivered', () async {
        final AmphitheatreCropVideoSession session =
            await startSession(quality: AmphitheatreCropVideoQuality.presetHD);

        final Future<void> expectation = expectLater(
          session.status,
          emits(
            isA<AmphitheatreCropVideoStatus>()
                .having((s) => s.sessionId, 'sessionId', session.id)
                .having(
                  (s) => s.stage,
                  'stage',
                  AmphitheatreCropVideoStage.export,
                )
                .having(
                  (s) => s.quality,
                  'quality',
                  AmphitheatreCropVideoQuality.presetHD,
                )
                .having((s) => s.progress, 'progress', 0.5)
                .having(
                  (s) => s.toString(),
                  'toString',
                  'AmphitheatreCropVideoStatus[sessionId=${session.id}, stage=export, quality=presetHD, progress=0.5]',
                ),
          ),
        );

        await host.emitCropStatus(session.id, progress: 0.5);
        await expectation;
      });

      test('an unspecified quality resolves to the platform default', () async {
        final AmphitheatreCropVideoSession session = await startSession();

        final Future<void> expectation = expectLater(
          session.status,
          emits(
            isA<AmphitheatreCropVideoStatus>().having(
              (s) => s.quality,
              'quality',
              AmphitheatreCropVideoQuality.passthrough,
            ),
          ),
        );

        await host.emitCropStatus(session.id, progress: 0.25);
        await expectation;
      });

      test('unrecognized stage and quality values map to unknown', () async {
        final AmphitheatreCropVideoSession session = await startSession();

        final Future<void> expectation = expectLater(
          session.status,
          emits(
            isA<AmphitheatreCropVideoStatus>()
                .having(
                  (s) => s.stage,
                  'stage',
                  AmphitheatreCropVideoStage.unknown,
                )
                .having(
                  (s) => s.quality,
                  'quality',
                  AmphitheatreCropVideoQuality.unknown,
                ),
          ),
        );

        await host.emitCropStatus(
          session.id,
          stage: 'nonsense',
          quality: 'nonsense',
          progress: 0,
        );
        await expectation;
      });

      test('events for other sessions are filtered out', () async {
        final AmphitheatreCropVideoSession session = await startSession();

        final List<AmphitheatreCropVideoStatus> received = [];
        final StreamSubscription<AmphitheatreCropVideoStatus> subscription =
            session.status.listen(received.add);

        await host.emitCropStatus(
          session.id,
          overrideSessionId: 'another-session',
          progress: 0.1,
        );
        await host.emitCropStatus(session.id, progress: 0.9);
        await pumpEventQueue();

        expect(received, hasLength(1));
        expect(received.single.sessionId, equals(session.id));
        expect(received.single.progress, equals(0.9));

        await subscription.cancel();
      });

      test('the status stream closes when the host ends it', () async {
        final AmphitheatreCropVideoSession session = await startSession();

        final Future<void> expectation = expectLater(
          session.status,
          emitsDone,
        );

        await host.endCropStatus(session.id);
        await expectation;
      });

      test(
          'completion delivers a final 100% status event and closes the '
          'stream', () async {
        final AmphitheatreCropVideoSession session = await startSession();

        final Future<void> expectation = expectLater(
          session.status,
          emitsInOrder([
            isA<AmphitheatreCropVideoStatus>()
                .having((s) => s.progress, 'progress', 1),
            emitsDone,
          ]),
        );

        await host.completeCropVideo(session.id);
        await expectation;
      });

      test('subscribing after completion ends the stream', () async {
        final AmphitheatreCropVideoSession session = await startSession();
        await host.completeCropVideo(session.id);
        expect(
          await session.future,
          equals(
            '${StubAmphitheatrePlatform.kMockTemporaryDirectory}/'
            '${session.id}.mp4',
          ),
        );

        await expectLater(session.status, emitsDone);
      });

      test('cancelling the subscription cancels the crop session', () async {
        final AmphitheatreCropVideoSession session = await startSession();
        final StreamSubscription<AmphitheatreCropVideoStatus> subscription =
            session.status.listen((_) {});

        await host.emitCropStatus(session.id, progress: 0);
        await subscription.cancel();
        await pumpEventQueue();

        expect(host.cancelledSessions, equals([session.id]));
        expect(host.cropSessions, isEmpty);
        await expectLater(
          session.future,
          throwsA(
            isA<PlatformException>()
                .having((e) => e.code, 'code', 'EXPORT_CANCELLED'),
          ),
        );
      });
    });

    group('disk space policy', () {
      Future<AmphitheatreCropVideoSession> startSession(
        AmphitheatreDiskSpacePolicy diskSpacePolicy, {
        OnExceedsDiskSpace? onExceedsDiskSpace,
      }) =>
          platform.cropVideo(
            path: '/videos/example.mp4',
            start: 1000,
            end: 5000,
            diskSpacePolicy: diskSpacePolicy,
            onExceedsDiskSpace: onExceedsDiskSpace,
          );

      test('ignore skips the disk space check', () async {
        await startSession(AmphitheatreDiskSpacePolicy.ignore);

        expect(
          host.log.where(
            (call) => call.method == 'checkCropVideoDiskSpace',
          ),
          isEmpty,
        );
      });

      test('the check passes the crop arguments to the host', () async {
        await startSession(AmphitheatreDiskSpacePolicy.warnIfExceeds);

        final MethodCall call = host.log.singleWhere(
          (call) => call.method == 'checkCropVideoDiskSpace',
        );
        expect(
          call.arguments,
          equals({
            'quality': null,
            'path': '/videos/example.mp4',
            'start': 1000,
            'end': 5000,
          }),
        );
      });

      test('the callback is not invoked when space is sufficient', () async {
        final List<AmphitheatreDiskSpacePolicy> exceeded = [];
        await startSession(
          AmphitheatreDiskSpacePolicy.abortIfExceeds,
          onExceedsDiskSpace: exceeded.add,
        );

        expect(exceeded, isEmpty);
      });

      test('warnIfExceeds invokes the callback and continues', () async {
        host.hasSufficientDiskSpace = false;

        final List<AmphitheatreDiskSpacePolicy> exceeded = [];
        final AmphitheatreCropVideoSession session = await startSession(
          AmphitheatreDiskSpacePolicy.warnIfExceeds,
          onExceedsDiskSpace: exceeded.add,
        );

        expect(exceeded, equals([AmphitheatreDiskSpacePolicy.warnIfExceeds]));
        expect(host.cropSessions, contains(session.id));

        // The warned crop must still complete end-to-end.
        await host.completeCropVideo(session.id);
        expect(
          await session.future,
          equals(
            '${StubAmphitheatrePlatform.kMockTemporaryDirectory}/'
            '${session.id}.mp4',
          ),
        );
      });

      test('the check runs before the crop is started', () async {
        await startSession(AmphitheatreDiskSpacePolicy.abortIfExceeds);

        final List<String> methods =
            host.log.map((call) => call.method).toList();
        expect(
          methods.indexOf('checkCropVideoDiskSpace'),
          lessThan(methods.indexOf('startCropVideo')),
        );
      });

      test('abortIfExceeds invokes the callback and aborts', () async {
        host.hasSufficientDiskSpace = false;

        final List<AmphitheatreDiskSpacePolicy> exceeded = [];
        await expectLater(
          startSession(
            AmphitheatreDiskSpacePolicy.abortIfExceeds,
            onExceedsDiskSpace: exceeded.add,
          ),
          throwsA(
            isA<PlatformException>()
                .having(
                  (e) => e.code,
                  'code',
                  kExceedsDiskSpaceErrorCode,
                )
                .having((e) => e.message, 'message', isNotNull),
          ),
        );

        expect(exceeded, equals([AmphitheatreDiskSpacePolicy.abortIfExceeds]));
        expect(host.cropSessions, isEmpty);
        expect(
          host.log.where((call) => call.method == 'startCropVideo'),
          isEmpty,
        );
      });

      test('errors other than exceeding disk space bypass the callback',
          () async {
        final List<AmphitheatreDiskSpacePolicy> exceeded = [];

        // An inverted crop range fails the check with INVALID_ARGS, which
        // must propagate even under warnIfExceeds.
        await expectLater(
          platform.cropVideo(
            path: '/videos/example.mp4',
            start: 5000,
            end: 1000,
            diskSpacePolicy: AmphitheatreDiskSpacePolicy.warnIfExceeds,
            onExceedsDiskSpace: exceeded.add,
          ),
          throwsA(
            isA<PlatformException>()
                .having((e) => e.code, 'code', 'INVALID_ARGS'),
          ),
        );

        expect(exceeded, isEmpty);
        expect(host.cropSessions, isEmpty);
      });
    });

    group('path helpers', () {
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      test('pathSeparator is correct for each supported platform', () {
        const Map<TargetPlatform, String> separators = {
          TargetPlatform.android: '/',
          TargetPlatform.iOS: '/',
          TargetPlatform.windows: r'\',
        };

        for (final MapEntry<TargetPlatform, String> entry
            in separators.entries) {
          debugDefaultTargetPlatformOverride = entry.key;
          expect(
            platform.pathSeparator,
            equals(entry.value),
            reason: 'for ${entry.key.name}',
          );
        }
      });

      test('pathSeparator does not return for an unsupported platform', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;

        expect(() => platform.pathSeparator, throwsA(isA<UnsupportedError>()));
      });

      test('joinPath and splitPath use the POSIX separator', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        expect(
          platform.joinPath('/videos', 'example.mp4'),
          equals('/videos/example.mp4'),
        );
        expect(
          platform.splitPath('/videos/example.mp4'),
          equals(['', 'videos', 'example.mp4']),
        );
      });

      test('joinPath and splitPath use the Windows separator', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;

        expect(
          platform.joinPath(r'C:\videos', 'example.mp4'),
          equals(r'C:\videos\example.mp4'),
        );
        expect(
          platform.splitPath(r'C:\videos\example.mp4'),
          equals(['C:', 'videos', 'example.mp4']),
        );
      });
    });
  });
}
