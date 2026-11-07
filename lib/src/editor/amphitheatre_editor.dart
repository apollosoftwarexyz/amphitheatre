import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui
    show Codec, Image, PictureRecorder, instantiateImageCodec;

import 'package:amphitheatre/amphitheatre.dart';
import 'package:amphitheatre/src/amphitheatre_platform.dart';
import 'package:amphitheatre/src/max_size_stack.dart';
import 'package:amphitheatre/src/raw_asset_image.dart';
import 'package:amphitheatre/src/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

part 'amphitheatre_editor_controller.dart';

/// Editing options for the [AmphitheatreEditor].
@immutable
final class AmphitheatreEditorOptions {
  /// Whether to auto-accept videos that are too short to trim (no longer than
  /// [minLength]).
  ///
  /// If the video is too long (i.e., its duration is greater than
  /// [maxLength]), the editor is used to prompt the user to crop the video
  /// down to size.
  ///
  /// If the video is too short, the video will be automatically accepted when
  /// [canAutoAccept] is true: the editor pops with the video's own path as
  /// soon as it has loaded, without showing itself. Only a video with a file
  /// path can be accepted this way (see [AmphitheatreController.getVideoPath]);
  /// any other source shows the editor.
  ///
  /// To automatically reject videos, applications should intercept the video
  /// before it is passed to the [AmphitheatreEditor] - this provides greater
  /// flexibility in how applications handle invalid videos.
  final bool canAutoAccept;

  /// The minimum length to allow the video can be cropped to. If not set to
  /// zero and the video is less than or equal to the [minLength], the video
  /// will be automatically accepted unless [canAutoAccept] is true.
  final Duration minLength;

  /// The maximum length to allow the video to be.
  final Duration maxLength;

  /// The behavior to employ when an edit operation is likely to use more disk
  /// space than is available.
  final AmphitheatreDiskSpacePolicy diskSpacePolicy;

  /// Invoked if an operation would exceed available disk space and the
  /// [AmphitheatreDiskSpacePolicy] is configured to
  /// [AmphitheatreDiskSpacePolicy.warnIfExceeds] or
  /// [AmphitheatreDiskSpacePolicy.abortIfExceeds].
  final OnExceedsDiskSpace? onExceedsDiskSpace;

  /// Construct the [AmphitheatreEditorOptions].
  const AmphitheatreEditorOptions({
    this.minLength = const Duration(seconds: 10),
    this.maxLength = const Duration(minutes: 5),
    this.canAutoAccept = false,
    this.diskSpacePolicy = AmphitheatreDiskSpacePolicy.abortIfExceeds,
    this.onExceedsDiskSpace,
  });

  /// If [canAutoAccept] is true and the video is no longer than [minLength],
  /// this method returns true to indicate that the video should be
  /// automatically accepted: a video exactly [minLength] long has nothing to
  /// trim.
  bool shouldAutoAccept(Duration duration) =>
      canAutoAccept && duration <= minLength;

  /// Returns the default start and end offsets for cropping. The offsets are
  /// based on computing the maximum length that can surround the middle of the
  /// video.
  (Duration start, Duration end) getDefaultOffsets(Duration duration) {
    final int middleMilliseconds =
        (duration.inMilliseconds.toDouble() / 2).round();

    final int startMilliseconds =
        max(middleMilliseconds - (maxLength.inMilliseconds ~/ 2), 0);
    final int endMilliseconds = min(
      middleMilliseconds + (maxLength.inMilliseconds ~/ 2),
      duration.inMilliseconds,
    );

    return (
      Duration(milliseconds: startMilliseconds),
      Duration(milliseconds: endMilliseconds)
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AmphitheatreEditorOptions &&
      minLength == other.minLength &&
      maxLength == other.maxLength &&
      canAutoAccept == other.canAutoAccept &&
      diskSpacePolicy == other.diskSpacePolicy &&
      onExceedsDiskSpace == other.onExceedsDiskSpace;

  @override
  int get hashCode => Object.hash(
        minLength,
        maxLength,
        canAutoAccept,
        diskSpacePolicy,
        onExceedsDiskSpace,
      );
}

/// Styling options for the [AmphitheatreEditor].
@immutable
final class AmphitheatreEditorStyle {
  /// The color to use when drawing the border around the playback slider.
  final Color borderColor;

  /// The radius to draw the corners of the playback slider with.
  final BorderRadius borderRadius;

  /// The thickness of the playback slider border.
  final double borderThickness;

  /// The color to use for the current progress line on the playback slider.
  final Color lineColor;

  /// The thickness to draw the current progress line with.
  final double lineThickness;

  /// The color to use for the cropping handles.
  final Color cropColor;

  /// The width to use for the cropping handles.
  final double cropHandleSize;

  /// If specified, the [RawAssetImage] to paint on the crop start handle.
  final RawAssetImage? cropStartIcon;

  /// The color to paint the [cropStartIcon].
  final Color cropStartIconColor;

  /// If specified, the [RawAssetImage] to paint on the crop end handle.
  final RawAssetImage? cropEndIcon;

  /// The color to paint the [cropEndIcon].
  final Color cropEndIconColor;

  /// Construct an [AmphitheatreEditorStyle].
  const AmphitheatreEditorStyle({
    this.borderColor = Colors.white,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.borderThickness = 2.0,
    this.lineColor = Colors.red,
    this.lineThickness = 2.0,
    this.cropColor = Colors.yellow,
    this.cropHandleSize = 15.0,
    this.cropStartIcon = const RawAssetImage(
      size: Size.square(20),
      assetPath: 'assets/crop_start.svg',
      package: 'amphitheatre',
    ),
    this.cropStartIconColor = Colors.black,
    this.cropEndIcon = const RawAssetImage(
      size: Size.square(20),
      assetPath: 'assets/crop_end.svg',
      package: 'amphitheatre',
    ),
    this.cropEndIconColor = Colors.black,
  });

  @override
  bool operator ==(Object other) =>
      other is AmphitheatreEditorStyle &&
      borderColor == other.borderColor &&
      borderRadius == other.borderRadius &&
      borderThickness == other.borderThickness &&
      lineColor == other.lineColor &&
      lineThickness == other.lineThickness &&
      cropColor == other.cropColor &&
      cropHandleSize == other.cropHandleSize;

  @override
  int get hashCode => Object.hashAll([
        borderColor,
        borderRadius,
        borderThickness,
        lineColor,
        lineThickness,
        cropColor,
        cropHandleSize,
      ]);
}

/// A builder for the [Route] that is used to open an [AmphitheatreEditor] when
/// [AmphitheatreEditor.launch] is called.
///
/// This can be used to customize the route and therefore the transition that is
/// used when an [AmphitheatreEditor] is launched.
typedef AmphitheatreEditorRouteBuilder = Route<String?> Function(Widget child);

Route<String?> _defaultAmphitheatreEditorRouteBuilder(Widget child) =>
    MaterialPageRoute<String?>(builder: (_) => child);

Widget _buildVideoControls(
  AmphitheatreController controller,
  bool showControls,
) =>
    AmphitheatreVideoControls(controller: controller);

/// A builder that returns a [Scaffold], rendered when the [AmphitheatreEditor]
/// is exporting the new video.
///
/// If the progress is null, the exporter progress indicator should be
/// indeterminate. Otherwise, the progress contains the latest progress reported
/// by the [AmphitheatrePlatform].
///
/// [onCancel], when not null, cancels the export and returns to the editor; the
/// screen should offer it to the user.
typedef AmphitheatreExporterProgressBuilder = Widget Function({
  required double? progress,
  VoidCallback? onCancel,
});

/// The Amphitheatre video editor.
class AmphitheatreEditor extends StatefulWidget {
  /// The controller for the [Amphitheatre] player.
  final AmphitheatreController controller;

  /// Editing options for the [AmphitheatreEditor].
  final AmphitheatreEditorOptions options;

  /// Styling options for the [AmphitheatreEditor].
  final AmphitheatreEditorStyle style;

  /// {@macro amphitheatre_build_video_controls}
  final AmphitheatreComponentBuilder buildVideoControls;

  /// The exporter progress screen builder.
  final AmphitheatreExporterProgressBuilder buildExporterProgress;

  /// See [Amphitheatre.consumedController].
  final bool consumedController;

  /// The default constructor for [AmphitheatreEditor].
  const AmphitheatreEditor({
    required this.controller,
    this.style = const AmphitheatreEditorStyle(),
    this.options = const AmphitheatreEditorOptions(),
    this.buildVideoControls = _buildVideoControls,
    this.buildExporterProgress = _buildAmphitheatreExporterProgress,
    super.key,
  }) : consumedController = false;

  /// See [Amphitheatre.consume].
  const AmphitheatreEditor.consume({
    required this.controller,
    this.style = const AmphitheatreEditorStyle(),
    this.options = const AmphitheatreEditorOptions(),
    this.buildVideoControls = _buildVideoControls,
    this.buildExporterProgress = _buildAmphitheatreExporterProgress,
    super.key,
  }) : consumedController = true;

  /// Launches the [AmphitheatreEditor] with the given controller, consuming the
  /// controller. See [AmphitheatreEditor.consume].
  ///
  /// Various [AmphitheatreEditorOptions] can be supplied by supplying
  /// [options]. If these are not specified, default values are used instead.
  ///
  /// If you require further customization, such as the ability to supply custom
  /// widgets for buttons, etc., then you should directly use the
  /// [AmphitheatreEditor.consume] API instead (which consumes an
  /// [AmphitheatreController]) - this function is simply a wrapper around that
  /// API.
  ///
  /// When the [AmphitheatreEditor] pops, it either pops with null (if no
  /// changes were made), or it pops with the path to the modified video.
  static Future<String?> launch(
    BuildContext context, {
    required AmphitheatreController controller,
    AmphitheatreEditorOptions options = const AmphitheatreEditorOptions(),
    AmphitheatreEditorRouteBuilder routeBuilder =
        _defaultAmphitheatreEditorRouteBuilder,
    bool useRootNavigator = false,
  }) async {
    final Widget child = AmphitheatreEditor.consume(
      controller: controller,
      options: options,
    );

    return Navigator.of(context, rootNavigator: useRootNavigator)
        .push<String?>(routeBuilder(child));
  }

  @override
  State<AmphitheatreEditor> createState() => AmphitheatreEditorState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      )
      ..add(DiagnosticsProperty<AmphitheatreEditorStyle>('style', style))
      ..add(DiagnosticsProperty<AmphitheatreEditorOptions>('options', options))
      ..add(
        ObjectFlagProperty<AmphitheatreComponentBuilder>.has(
          'buildVideoControls',
          buildVideoControls,
        ),
      )
      ..add(
        ObjectFlagProperty<AmphitheatreExporterProgressBuilder>.has(
          'buildExporterProgress',
          buildExporterProgress,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>('consumedController', consumedController),
      );
  }
}

/// The state for an [AmphitheatreEditor].
class AmphitheatreEditorState extends State<AmphitheatreEditor> {
  var _exporting = false;
  StreamSubscription<AmphitheatreCropVideoStatus>? _exportStatusStream;

  /// Counts the exports started, so that the continuation of an export that
  /// was cancelled (or whose editor went away) while it awaited the video path
  /// or the session can tell that it is no longer wanted.
  var _exportGeneration = 0;

  double? _progress;

  /// Whether [AmphitheatreEditorOptions.shouldAutoAccept] has been consulted
  /// for the loaded video.
  var _autoAcceptHandled = false;

  /// The filmstrip thumbnails, in timeline order. They are held here rather
  /// than in the slider because the slider is rebuilt every time the editor
  /// returns from the progress screen, and the extraction decodes the video
  /// again.
  List<ui.Image> _thumbnails = const [];
  var _thumbnailsRequested = false;

  /// When the video is exporting.
  bool get exporting => _exporting;

  /// The progress of the video export operation.
  ///
  /// If no status events have been received yet (i.e., the export is preparing)
  /// this is null.
  double? get progress => _progress;

  /// The editor state controller.
  final editorController =
      AmphitheatreEditorController();

  @override
  void initState() {
    editorController.addListener(() => setState(() {}));
    widget.controller.addListener(_maybeAutoAccept);
    super.initState();

    // The editor owns a consumed controller for its whole life, rather than
    // the player it builds: the player is swapped out for the progress screen
    // during an export, and a failed or cancelled export returns to it.
    if (widget.consumedController) {
      widget.controller.initialize(autoPlay: false);
    }

    // A controller handed over already initialized (and quiet) notifies
    // nothing more; it is looked at once the editor is in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAutoAccept();
    });
  }

  @override
  void dispose() {
    _exportGeneration++;
    unawaited(_exportStatusStream?.cancel());
    widget.controller.removeListener(_maybeAutoAccept);
    editorController.dispose();
    if (widget.consumedController) {
      unawaited(widget.controller.dispose());
    }
    for (final ui.Image thumbnail in _thumbnails) {
      thumbnail.dispose();
    }
    _thumbnails = const [];
    super.dispose();
  }

  /// Requests the filmstrip thumbnails from the platform, once per video,
  /// with the [count] and [maxHeight] the slider derived from its first
  /// layout. A later change of the slider's size does not request them again.
  ///
  /// The filmstrip is an enhancement: a video without a file path (see
  /// [AmphitheatreController.getVideoPath]) or any platform failure simply
  /// leaves the plain track visible.
  Future<void> _loadThumbnails({
    required int count,
    required int maxHeight,
  }) async {
    if (_thumbnailsRequested) return;
    _thumbnailsRequested = true;

    try {
      final AmphitheatreVideoPath videoPath = await widget.controller
          .getVideoPath(temporaryFileFallback: false);

      final List<Uint8List> encoded =
          await getAmphitheatrePlatform().getThumbnails(
        path: videoPath.path,
        count: count,
        maxHeight: maxHeight,
      );

      final List<ui.Image> thumbnails = await _decodeThumbnails(encoded);

      if (mounted) {
        setState(() => _thumbnails = thumbnails);
      } else {
        for (final thumbnail in thumbnails) {
          thumbnail.dispose();
        }
      }
    } catch (_) {/* ignored: the filmstrip is optional */}
  }

  /// Decodes every image in [encoded]. The images decoded so far are disposed
  /// if a later one fails, so a failure leaks nothing.
  static Future<List<ui.Image>> _decodeThumbnails(
    List<Uint8List> encoded,
  ) async {
    final List<ui.Image> thumbnails = [];
    try {
      for (final bytes in encoded) {
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        try {
          thumbnails.add((await codec.getNextFrame()).image);
        } finally {
          codec.dispose();
        }
      }
    } catch (_) {
      for (final thumbnail in thumbnails) {
        thumbnail.dispose();
      }
      rethrow;
    }
    return thumbnails;
  }

  /// Consults [AmphitheatreEditorOptions.shouldAutoAccept] once the video has
  /// loaded.
  void _maybeAutoAccept() {
    if (_autoAcceptHandled || !widget.controller.isInitialized) return;
    _autoAcceptHandled = true;

    if (widget.options.shouldAutoAccept(widget.controller.duration)) {
      unawaited(_autoAccept());
    }
  }

  /// Pops with the video's own path, as long as this editor is still the
  /// current route: the user may have left while the video loaded, and a pop
  /// then would take the route underneath with it. An editor that is not a
  /// route of its own is left showing.
  Future<void> _autoAccept() async {
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    final AmphitheatreVideoPath videoPath;
    try {
      videoPath =
          await widget.controller.getVideoPath(temporaryFileFallback: false);
    } on UnsupportedError {
      // Not a file: the editor is shown instead.
      return;
    }

    // Whatever the initialization still has queued for the player (an
    // autoplay, or the slider's play on load) must land before the pause
    // below, or it would restart the video.
    await widget.controller.whenInitialized;
    if (!mounted || !route.isCurrent) return;

    // Nothing should be heard while the route animates away.
    widget.controller.pause();
    route.navigator?.pop(videoPath.path);
  }

  /// Whether the changes can be accepted. This is currently based on whether
  /// there is a crop set as even if the video is of acceptable length, the crop
  /// options initialize to that full length. (So it is only null when the
  /// editor has not fully initialized).
  bool get canAcceptChanges => editorController.value.crop != null;

  /// Render the modified video.
  Future<void> produceOutputVideo() async {
    // A "try again" from the SnackBar can outlive the editor.
    if (_exporting || !mounted) return;
    final int generation = ++_exportGeneration;
    bool isCurrent() =>
        mounted && _exporting && _exportGeneration == generation;

    // Whether a newer export is running; this one must then leave the shared
    // temporary input alone.
    bool superseded() => _exporting && _exportGeneration != generation;

    // A handle still held when the export starts: the slider goes away with
    // the progress screen, so the gesture is abandoned here, while the slider
    // is still in the tree to be rebuilt.
    editorController.cancelCropGesture();

    // The player stays alive under the progress screen; it must not keep
    // playing there.
    widget.controller.pause();
    setState(() {
      _exporting = true;
      _progress = null;
    });

    AmphitheatreVideoPath? inputFilePath;
    var inputHandedBack = false;
    try {
      // Get the path to the video. The continuation of this await is the
      // first place a cancel can be noticed.
      inputFilePath = await widget.controller.getVideoPath();
      if (!isCurrent()) return;

      // Now step through each of the modifications (currently, just a crop).
      final AmphitheatreEditorActionCrop? crop = editorController.value.crop;
      String outputFilePath = inputFilePath.path;

      if (crop != null &&
          (crop.start > Duration.zero ||
              crop.end < widget.controller.duration)) {
        final AmphitheatreCropVideoSession session =
            await getAmphitheatrePlatform().cropVideo(
          path: inputFilePath.path,
          start: crop.start.inMilliseconds,
          end: crop.end.inMilliseconds,
          diskSpacePolicy: widget.options.diskSpacePolicy,
          onExceedsDiskSpace: widget.options.onExceedsDiskSpace,
        );

        if (!isCurrent()) {
          // Cancelled while the session was being set up: it has only just
          // started, and nothing is listening for it.
          _discardSession(session);
          return;
        }

        _exportStatusStream = session.status.listen((status) {
          if (mounted) {
            setState(() {
              _progress = status.progress;
            });
          }
        });

        outputFilePath = await session.future;

        if (!isCurrent()) {
          // The export concluded after the editor stopped waiting for it.
          _deleteQuietly(outputFilePath);
          return;
        }
      }

      // A full-length selection hands the input itself back.
      inputHandedBack = outputFilePath == inputFilePath.path;
      Navigator.of(context).pop(outputFilePath);
    } on PlatformException catch (error) {
      if (!isCurrent()) return;

      if (error.code == kExportCancelledErrorCode) {
        // Cancelled by the platform (rather than through cancelExport, which
        // has already returned to the editor): no error to show.
        _returnToEditor();
        return;
      }

      if (kDebugMode) {
        print(error);
      }

      // An export failure's message is the platform's fixed sentence (with
      // the cause in the details); every other code carries a message meant
      // for display, such as the disk-space check's.
      _showExportError(
        message: error.code == kExportFailedErrorCode
            ? getLocalizationDelegate(context).unknownError
            : error.message ?? getLocalizationDelegate(context).unknownError,
      );
    } catch (error) {
      if (!isCurrent()) return;

      if (kDebugMode) {
        print(error);
      }

      _showExportError(
        message: getLocalizationDelegate(context).unknownError,
      );
    } finally {
      // A newer export resolves the same temporary path for the same video
      // and deletes it when it is done.
      if (!inputHandedBack && !superseded()) {
        try {
          await inputFilePath?.deleteIfTemporary();
        } catch (_) {}
      }
    }
  }

  /// Cancel the export in progress and return to the editor.
  ///
  /// A running session is cancelled through its status subscription (the
  /// platform's cancel path); an export still preparing stands down once its
  /// current await returns.
  void cancelExport() {
    if (!_exporting) return;
    _returnToEditor();
  }

  /// Delete the file at [path], ignoring a failure: the platform may already
  /// have removed it (a cancelled session deletes its own output).
  static void _deleteQuietly(String path) => unawaited(
        getAmphitheatrePlatform().deleteFile(path).catchError((_) {}),
      );

  /// Dispose of a session nobody is waiting for: it is cancelled, and an
  /// output it still produces (the cancel arriving after the session
  /// concluded) is deleted.
  static void _discardSession(AmphitheatreCropVideoSession session) {
    unawaited(session.future.then(_deleteQuietly).catchError((_) {}));
    unawaited(session.cancel().catchError((_) {}));
  }

  /// Return the editor to its interactive state, abandoning any export: the
  /// status subscription is cancelled (which cancels the platform session) and
  /// the export's continuation is told to stand down.
  void _returnToEditor() {
    _exportGeneration++;
    unawaited(_exportStatusStream?.cancel());
    _exportStatusStream = null;

    if (!mounted) return;

    setState(() {
      _exporting = false;
      _progress = null;
    });
  }

  /// Display the error [message] raised whilst producing the output video and
  /// return the editor to its interactive state, offering to try again.
  void _showExportError({required String message}) {
    _returnToEditor();

    if (!mounted) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: getLocalizationDelegate(context).retry,
          onPressed: () => unawaited(produceOutputVideo()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_exporting) {
      return widget.buildExporterProgress(
        progress: progress,
        onCancel: cancelExport,
      );
    }

    // Never a consuming player: the controller outlives this widget (see
    // initState).
    return Amphitheatre(
      controller: widget.controller,
      enableToggleControls: false,
      enableReplayButton: false,
      autoPlay: false,
      buildCloseButton: (controller, _) =>
          AmphitheatreCancelButton(controller: controller),
      buildVideoControls: widget.buildVideoControls,
      buildDoneButton: (controller, _) => AmphitheatreDoneButton(
        controller: controller,
        onPressed: canAcceptChanges
            ? (_) => unawaited(produceOutputVideo())
            : null,
      ),
      buildProgressSlider: (controller, _) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AmphitheatreEditorSlider(
          controller: controller,
          editorController: editorController,
          options: widget.options,
          style: widget.style,
          thumbnails: _thumbnails,
          onThumbnailsNeeded: (count, maxHeight) => unawaited(
            _loadThumbnails(count: count, maxHeight: maxHeight),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AmphitheatreEditorController>(
          'editorController',
          editorController,
        ),
      )
      ..add(DiagnosticsProperty<bool>('exporting', exporting))
      ..add(DiagnosticsProperty<double>('progress', progress))
      ..add(DiagnosticsProperty<bool>('canAcceptChanges', canAcceptChanges));
  }
}

Widget _buildAmphitheatreExporterProgress({
  required double? progress,
  VoidCallback? onCancel,
}) =>
    AmphitheatreExporterProgress(progress: progress, onCancel: onCancel);

/// The default exporter progress screen for the [AmphitheatreEditor].
class AmphitheatreExporterProgress extends StatelessWidget {
  /// The progress of the export job.
  final double? progress;

  /// Cancels the export. When null, the export cannot be cancelled from this
  /// screen and no cancel button is shown.
  final VoidCallback? onCancel;

  /// Construct the [AmphitheatreExporterProgress] screen.
  const AmphitheatreExporterProgress({
    required this.progress,
    this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        // The system back gesture cancels the export rather than leaving the
        // screen underneath it.
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onCancel?.call();
        },
        child: Scaffold(
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value: _getSystemUiOverlayStyle(Theme.of(context)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    progress != null
                        ? getLocalizationDelegate(context)
                            .exportingVideo(progress!)
                        : getLocalizationDelegate(context)
                            .preparingToExportVideo,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: progress,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  if (onCancel != null) ...[
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: onCancel,
                      child: Text(getLocalizationDelegate(context).cancel),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

  /// Get the System UI overlay style from the theme, or a reasonable fallback.
  ///
  /// This aims to recreate the [AppBar] logic, without requiring an unnecessary
  /// or invisible [AppBar].
  static SystemUiOverlayStyle _getSystemUiOverlayStyle(ThemeData theme) {
    final SystemUiOverlayStyle? systemUiOverlayStyle =
        theme.appBarTheme.systemOverlayStyle;
    if (systemUiOverlayStyle != null) {
      return systemUiOverlayStyle;
    }

    final SystemUiOverlayStyle fallbackStyle =
        theme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark;

    return SystemUiOverlayStyle(
      statusBarColor: theme.scaffoldBackgroundColor,
      statusBarBrightness: fallbackStyle.statusBarBrightness,
      statusBarIconBrightness: fallbackStyle.statusBarIconBrightness,
      systemStatusBarContrastEnforced:
          fallbackStyle.systemStatusBarContrastEnforced,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('progress', progress))
      ..add(ObjectFlagProperty<VoidCallback>.has('onCancel', onCancel));
  }
}

enum _AmphitheatreEditorSliderDragMode {
  /// Just the playback head.
  playbackHead,

  /// The start crop handle.
  cropStart,

  /// The end crop handle.
  cropEnd,

  /// In-between the crop handles (the "intersection").
  cropIntersection;

  bool get isCropHandleOnly => this == cropStart || this == cropEnd;
  bool get isCrop => isCropHandleOnly || this == cropIntersection;
  bool get isNotCrop => !isCrop;

  bool get isCropStart => this == cropStart || this == cropIntersection;
  bool get isCropEnd => this == cropEnd || this == cropIntersection;
}

/// Geometry for the editor slider: the mapping between video time
/// (milliseconds) and x-positions on the track, shared by the painters and
/// the gesture handling.
///
/// The track is the space between the two crop handle gutters; positions are
/// in the slider's local coordinate space.
@immutable
final class _SliderMetrics {
  final Size size;
  final AmphitheatreEditorStyle style;
  final int max;

  const _SliderMetrics({
    required this.size,
    required this.style,
    required this.max,
  });

  /// The width reserved on each side of the track for a crop handle.
  double get inset => style.cropHandleSize + style.borderThickness;

  double get trackLeft => inset;
  double get trackRight => size.width - inset;

  Rect get trackRect => Rect.fromLTRB(trackLeft, 0, trackRight, size.height);

  RRect get trackRRect => RRect.fromRectAndCorners(
        trackRect,
        topLeft: style.borderRadius.topLeft,
        topRight: style.borderRadius.topRight,
        bottomLeft: style.borderRadius.bottomLeft,
        bottomRight: style.borderRadius.bottomRight,
      );

  /// The x-position on the track for the time [value] (milliseconds),
  /// accounting for the borders and the progress line. [max] must be
  /// positive.
  double positionFor(int value) =>
      inset +
      (value.floorToDouble() / max.floorToDouble()) *
          (size.width -
              (style.lineThickness / 2) -
              style.borderThickness -
              inset * 2) +
      (style.borderThickness / 2);

  /// The time (milliseconds) under the x-position [dx], for seeking the
  /// playback head.
  int valueFor(double dx) =>
      (((dx - inset) / (size.width - inset * 2)) * max).floor();

  /// The time delta (milliseconds) for a horizontal drag distance, for moving
  /// a crop handle. The same scale as [valueFor].
  int deltaValueFor(double dxDelta) =>
      ((dxDelta / (size.width - inset * 2)) * max).floor();
}

/// Invoked by an [AmphitheatreEditorSlider] once it knows the size of its
/// track, with the number of filmstrip thumbnails that fit across it and the
/// height (in physical pixels) to extract them at.
typedef AmphitheatreThumbnailsCallback = void Function(
  int count,
  int maxHeight,
);

/// The [AmphitheatreEditorSlider] replaces the existing editor slider with
/// a [CustomPainter]-based slider that paints a filmstrip of the video, the
/// playback head and handles for cropping the video down to size, with the
/// start, length and end of the selection underneath.
class AmphitheatreEditorSlider extends StatefulWidget {
  /// The [controller] for the [Amphitheatre] player.
  final AmphitheatreController controller;

  /// The [AmphitheatreEditorController], containing information about the
  /// actions to be applied.
  final AmphitheatreEditorController editorController;

  /// Editing options for the [AmphitheatreEditor].
  final AmphitheatreEditorOptions options;

  /// Additional styling options for the slider.
  final AmphitheatreEditorStyle style;

  /// The height of the slider.
  final double height;

  /// The filmstrip thumbnails to paint across the track, in timeline order.
  /// The slider does not own them; the owner disposes them. Empty leaves the
  /// plain track visible.
  final List<ui.Image> thumbnails;

  /// Invoked once, with the first finite, non-empty track size laid out after
  /// the video initialised, so that the owner can extract [thumbnails] to
  /// fit. A later change of size does not invoke it again.
  final AmphitheatreThumbnailsCallback? onThumbnailsNeeded;

  /// Construct the [AmphitheatreEditorSlider].
  const AmphitheatreEditorSlider({
    required this.controller,
    required this.editorController,
    required this.options,
    required this.style,
    this.height = 72,
    this.thumbnails = const [],
    this.onThumbnailsNeeded,
    super.key,
  });

  @override
  State<AmphitheatreEditorSlider> createState() =>
      _AmphitheatreEditorSliderState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      )
      ..add(
        DiagnosticsProperty<AmphitheatreEditorController>(
          'editorController',
          editorController,
        ),
      )
      ..add(DiagnosticsProperty<AmphitheatreEditorOptions>('options', options))
      ..add(DiagnosticsProperty<AmphitheatreEditorStyle>('style', style))
      ..add(DoubleProperty('height', height))
      ..add(IntProperty('thumbnails', thumbnails.length))
      ..add(
        ObjectFlagProperty<AmphitheatreThumbnailsCallback>.has(
          'onThumbnailsNeeded',
          onThumbnailsNeeded,
        ),
      );
  }
}

class _AmphitheatreEditorSliderState extends State<AmphitheatreEditorSlider> {
  /// The cached start (LHS) crop icon.
  ui.Image? _cropStartIcon;

  /// The cached end (RHS) crop icon.
  ui.Image? _cropEndIcon;

  var _thumbnailsRequested = false;

  /// The [_AmphitheatreEditorSliderDragMode] of the current 'drag session'.
  _AmphitheatreEditorSliderDragMode? _dragMode;

  /// The offset at which the user started dragging.
  Offset? _dragLocalOffset;

  Duration? _cachedCropStart;
  Duration? _cachedCropEnd;

  /// Whether a horizontal drag has been accepted for the current interaction.
  /// A drag recognizer that loses the arena to a tap also reports a cancel,
  /// which must not touch the tap's state.
  var _dragStarted = false;

  /// Whether the system cancelled the pointer of the current interaction. The
  /// recognizer reports that as a drag end, which must roll back rather than
  /// commit.
  var _pointerCancelled = false;

  /// When the slider last seeked the player on its own (to keep the playback
  /// head within the selection, or to preview a dragged handle). Those seeks
  /// are throttled so that position updates and handle drags do not flood the
  /// player.
  var _lastAutoSeek = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    unawaited(_loadImages());

    widget.editorController.addListener(_didEditVideo);

    if (widget.controller.isInitialized &&
        widget.editorController.value.crop != null) {
      // Loaded and cropped already: the editor is back from an export.
      widget.controller.addListener(_didControllerUpdate);
    } else {
      widget.controller.addListener(_didVideoLoad);

      if (widget.controller.isInitialized) {
        // Loaded before the slider existed, and quiet: nothing would notify
        // the listener, so the default crop is applied once the first frame
        // is in (a notification during the build is not allowed).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _didVideoLoad();
        });
      }
    }
  }

  @override
  void dispose() {
    // A gesture interrupted by the slider going away is the owner's to
    // abandon (see AmphitheatreEditorState.produceOutputVideo): a restore
    // from here would notify a tree that is being torn down.
    widget.editorController.removeListener(_didEditVideo);
    widget.controller.removeListener(_didControllerUpdate);
    widget.controller.removeListener(_didVideoLoad);
    _cropStartIcon?.dispose();
    _cropEndIcon?.dispose();
    _cropStartIcon = null;
    _cropEndIcon = null;
    super.dispose();
  }

  /// A handler to be invoked once when the video loads. The handler will remove
  /// itself automatically once successfully invoked.
  void _didVideoLoad() {
    if (widget.controller.isInitialized &&
        widget.editorController.value.crop == null) {
      final (Duration initialStart, Duration initialEnd) =
          widget.options.getDefaultOffsets(widget.controller.duration);
      widget.editorController
          .crop(start: initialStart, end: initialEnd, writeHistory: false);
      widget.editorController.clearHistory();

      _ensurePlaybackWithinCropRegion(force: true);
      widget.controller.play();
      widget.controller.removeListener(_didVideoLoad);
      widget.controller.addListener(_didControllerUpdate);
    }
  }

  void _didControllerUpdate() {
    if (widget.controller.isInitialized &&
        widget.editorController.value.crop != null) {
      _ensurePlaybackWithinCropRegion();
    }
  }

  void _didEditVideo() {
    if (mounted) setState(() {});
  }

  /// Ensures that the playback head always resides within the crop region.
  void _ensurePlaybackWithinCropRegion({bool force = false}) {
    final AmphitheatreEditorActionCrop? crop =
        widget.editorController.value.crop;
    if (crop == null) return;

    final Duration position = widget.controller.position;
    final bool isPlaying = widget.controller.isPlaying;

    Duration? target;
    if (position < crop.start) {
      target = crop.start;
    } else if (position > crop.end) {
      // Loop back to the start of the selection during playback; hold at the
      // end of the selection while paused.
      target = isPlaying ? crop.start : crop.end;
    }

    if (target != null) _autoSeek(target, force: force);
  }

  /// Seek the player to [target] unless another automatic seek happened in
  /// the last 200 ms; [force] bypasses the throttle so that the final seek of
  /// a gesture is never dropped.
  void _autoSeek(Duration target, {bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastAutoSeek) < const Duration(milliseconds: 200)) {
      return;
    }

    _lastAutoSeek = now;
    widget.controller.seekTo(target);
  }

  @override
  void didUpdateWidget(AmphitheatreEditorSlider oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.style.cropStartIcon != widget.style.cropStartIcon ||
        oldWidget.style.cropEndIcon != widget.style.cropEndIcon) {
      unawaited(_loadImages());
    }
  }

  static Future<ui.Image> _loadRawAssetImage(RawAssetImage image) async {
    if (!image.size.isFinite) {
      throw ArgumentError('RawAssetImage size must be finite.', 'size');
    }

    final imageBuffer =
        Uint8List.view((await rootBundle.load(image.path)).buffer);

    if (image.assetPath.endsWith('.svg')) {
      final PictureInfo picture =
          await vg.loadPicture(SvgStringLoader(utf8.decode(imageBuffer)), null);

      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
        Offset.zero & Size(image.size.width, image.size.height),
      )
        ..scale(
          image.size.width.roundToDouble() / picture.size.width,
          image.size.height.roundToDouble() / picture.size.height,
        )
        ..drawPicture(picture.picture);

      final ui.Image decodedImage = await recorder.endRecording().toImage(
            image.size.width.round(),
            image.size.height.round(),
          );

      picture.picture.dispose();
      return decodedImage;
    } else {
      final ui.Codec codec = await ui.instantiateImageCodec(
        imageBuffer,
        targetWidth: image.size.width.round(),
        targetHeight: image.size.height.round(),
        allowUpscaling: true,
      );

      return (await codec.getNextFrame()).image;
    }
  }

  Future<void> _loadImages() async {
    if (widget.style.cropStartIcon != null) {
      try {
        _cropStartIcon = await _loadRawAssetImage(widget.style.cropStartIcon!);
      } catch (_) {/* ignored */}
    }

    if (widget.style.cropEndIcon != null) {
      try {
        _cropEndIcon = await _loadRawAssetImage(widget.style.cropEndIcon!);
      } catch (_) {/* ignored */}
    }

    if (mounted) setState(() {});
  }

  /// Asks the owner for filmstrip thumbnails, once, sized for the first
  /// finite, non-empty track [size] laid out after the video initialised (see
  /// [AmphitheatreEditorSlider.onThumbnailsNeeded]).
  void _maybeRequestThumbnails(Size size) {
    if (_thumbnailsRequested ||
        widget.onThumbnailsNeeded == null ||
        !widget.controller.isInitialized ||
        widget.controller.duration <= Duration.zero ||
        !size.isFinite ||
        size.isEmpty) {
      return;
    }
    _thumbnailsRequested = true;

    final double aspectRatio = widget.controller.aspectRatio.isFinite &&
            widget.controller.aspectRatio > 0
        ? widget.controller.aspectRatio.clamp(0.4, 2.4)
        : 1.0;

    final int count =
        (size.width / (size.height * aspectRatio)).ceil().clamp(3, 24);
    final int maxHeight =
        (size.height * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(32, 320);

    widget.onThumbnailsNeeded!(count, maxHeight);
  }

  int get _max => widget.controller.duration.inMilliseconds;

  void _processInteraction(
    Size size, {
    required Offset localPosition,
    bool isStart = false,
    bool isEnd = false,

    /// Whether the interaction is a simple tap rather than a drag.
    bool isTap = false,
  }) {
    final metrics = _SliderMetrics(size: size, style: widget.style, max: _max);

    if (isStart) {
      if (_dragMode == null) {
        _dragMode = computeDragMode(localPosition, size: size);
        _dragLocalOffset = localPosition;
        _cachedCropStart = widget.editorController.value.crop?.start;
        _cachedCropEnd = widget.editorController.value.crop?.end;
        _pointerCancelled = false;

        if (_dragMode!.isCrop) {
          // The crop is previewed until the gesture ends, with the player
          // paused so the preview can follow the handle.
          widget.controller.pause();
          widget.editorController.beginCropGesture();
        }
      }
    } else if (_dragMode == null) {
      // An update or end without a start (the start was cancelled).
      return;
    }

    if (isEnd && _pointerCancelled) {
      // The system took the pointer away mid-gesture; the recognizer reports
      // that as an end, but nothing was released on purpose.
      _cancelInteraction();
      return;
    }

    if ((_dragMode?.isCrop ?? false) &&
        !widget.editorController.isInCropGesture) {
      // The transaction was ended from outside the slider (an undo, a reset);
      // the rest of this gesture is void.
      _resetInteraction();
      return;
    }

    if (_dragMode == _AmphitheatreEditorSliderDragMode.playbackHead ||
        (_dragMode == _AmphitheatreEditorSliderDragMode.cropIntersection &&
            isTap) ||
        (_dragMode == _AmphitheatreEditorSliderDragMode.cropIntersection &&
            _cachedCropStart == Duration.zero &&
            _cachedCropEnd == widget.controller.duration)) {
      _handleNewPlayerPosition(
        metrics,
        localPosition: localPosition,
        pauseBefore: isStart,
        playAfter: isEnd,
      );
    } else if ((_dragMode?.isCrop ?? false) &&
        _dragLocalOffset != null &&
        _cachedCropStart != null &&
        _cachedCropEnd != null) {
      _handleNewCropPosition(
        metrics,
        dragMode: _dragMode!,
        localPosition: localPosition,
        localOrigin: _dragLocalOffset!,
        isEnd: isEnd,
      );
    }

    if (isEnd) {
      // The gesture is one history entry, written now that it is 'locked in'.
      widget.editorController.endCropGesture();
      _resetInteraction();
    }
  }

  /// Abandons the current gesture: the crop captured when it began is
  /// restored (without a history entry) and the drag state is cleared.
  ///
  /// Also invoked when a drag wins the gesture arena over the tap that
  /// preceded it; the drag then starts afresh from the pointer-down position
  /// (see [DragStartBehavior.down]).
  void _cancelInteraction() {
    if (_dragMode == null) return;

    if (_dragMode!.isCrop) {
      widget.editorController.cancelCropGesture();
    }
    _resetInteraction();
  }

  void _resetInteraction() {
    _dragMode = null;
    _dragLocalOffset = null;
    _cachedCropStart = null;
    _cachedCropEnd = null;
    _dragStarted = false;
    _pointerCancelled = false;
  }

  void _onHorizontalDragStart(Size size, DragStartDetails details) {
    _dragStarted = true;
    _processInteraction(
      size,
      localPosition: details.localPosition,
      isStart: true,
    );
  }

  /// The drag recognizer also reports a cancel when it loses the arena to the
  /// tap that preceded it (on every plain tap, in fact); only a drag that
  /// started has anything to cancel.
  void _onHorizontalDragCancel() {
    if (_dragStarted) _cancelInteraction();
  }

  void _handleNewCropPosition(
    _SliderMetrics metrics, {
    required _AmphitheatreEditorSliderDragMode dragMode,
    required Offset localPosition,
    required Offset localOrigin,
    required bool isEnd,
  }) {
    final Duration duration = widget.controller.duration;
    final int durationMilliseconds = duration.inMilliseconds;

    final dragOffset = Duration(
      milliseconds: metrics.deltaValueFor(localPosition.dx - localOrigin.dx),
    );

    Duration cropStart = dragMode.isCropStart
        ? Duration(
            milliseconds: (_cachedCropStart! + dragOffset)
                .inMilliseconds
                .clamp(0, durationMilliseconds),
          )
        : _cachedCropStart!;

    Duration cropEnd = dragMode.isCropEnd
        ? Duration(
            milliseconds: (_cachedCropEnd! + dragOffset)
                .inMilliseconds
                .clamp(0, durationMilliseconds),
          )
        : _cachedCropEnd!;

    // Measure the difference between the cached times and likewise for the new
    // times.
    final Duration cachedDiff = _cachedCropEnd! - _cachedCropStart!;
    final Duration diff = cropEnd - cropStart;

    if (dragMode == _AmphitheatreEditorSliderDragMode.cropIntersection) {
      if (diff != cachedDiff) {
        // If the difference has changed, but we're in intersection mode,
        // re-compute the correct end value such that the difference remains.
        if (dragOffset.isNegative) {
          cropEnd = cropStart + cachedDiff;
        } else {
          cropStart = cropEnd - cachedDiff;
        }
      }
    } else if (dragMode.isCropHandleOnly) {
      if (diff >= widget.options.maxLength) {
        // If the maximum difference has been exceeded, 'drag' the other end
        // such that the maximum length is maintained.
        if (dragMode.isCropStart) {
          cropEnd = cropStart + widget.options.maxLength;
        } else {
          cropStart = cropEnd - widget.options.maxLength;
        }
      } else if (diff >= widget.options.minLength) {
        // Alternatively, reset the other end to where it would have been.
        // (This ensures it returns to the correct place if the user amends
        // their selection to be less than the maximum length after it was equal
        // to or exceeded the max length).
        if (dragMode.isCropStart) {
          cropEnd = _cachedCropEnd!;
        } else {
          cropStart = _cachedCropStart!;
        }
      } else {
        // If the difference is less than the minimum difference, similarly
        // adjust the other handle.
        if (dragMode.isCropStart) {
          cropEnd = cropStart + widget.options.minLength;

          if (cropEnd >= duration) {
            // A video shorter than minLength selects all of it: the start
            // must not go negative, or the handle leaves the slider.
            cropStart = Duration(
              milliseconds: max(
                0,
                (duration - widget.options.minLength).inMilliseconds,
              ),
            );
            cropEnd = duration;
          }
        } else {
          cropStart = cropEnd - widget.options.minLength;

          if (cropStart <= Duration.zero) {
            cropStart = Duration.zero;
            // Likewise the end must not pass the video.
            cropEnd = Duration(
              milliseconds: min(
                widget.options.minLength.inMilliseconds,
                durationMilliseconds,
              ),
            );
          }
        }
      }
    }

    widget.editorController.previewCrop(start: cropStart, end: cropEnd);

    // Preview the frame under the handle being dragged. The release always
    // seeks, so the preview ends on the frame the handle was left on.
    _autoSeek(
      dragMode.isCropEnd && !dragMode.isCropStart ? cropEnd : cropStart,
      force: isEnd,
    );
  }

  void _handleNewPlayerPosition(
    _SliderMetrics metrics, {
    required Offset localPosition,
    bool pauseBefore = false,
    bool playAfter = false,
  }) {
    if (pauseBefore) {
      widget.controller.pause();
    }

    widget.controller.seekTo(
      Duration(milliseconds: metrics.valueFor(localPosition.dx)),
    );

    if (playAfter) {
      widget.controller.play();
    }
  }

  static const _timestampStyle = TextStyle(
    color: Colors.white70,
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// The row under the track: the selection's start, its length, and its end.
  Widget _buildTimestamps(BuildContext context) {
    final AmphitheatreEditorActionCrop? crop =
        widget.editorController.value.crop;
    if (crop == null || !widget.controller.isInitialized) {
      return const SizedBox.shrink();
    }

    final bool hours = widget.controller.duration.hasHours;

    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        left: widget.style.cropHandleSize,
        right: widget.style.cropHandleSize,
      ),
      // Each cell gives way rather than overflow the row at a large text
      // scale or with the hours format.
      child: Row(
        children: [
          Expanded(
            child: Text(
              crop.start.format(hours: hours),
              style: _timestampStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              getLocalizationDelegate(context)
                  .selectedDuration((crop.end - crop.start).format()),
              style: _timestampStyle.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              crop.end.format(hours: hours),
              style: _timestampStyle,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(widget.style.borderThickness / 2),
            child: SizedBox.fromSize(
              size: Size.fromHeight(widget.height),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);

                  _maybeRequestThumbnails(size);

                  return Listener(
                    // Seen before the recognizers see the event, so a drag
                    // end that follows a system cancel can roll back.
                    onPointerCancel: (_) => _pointerCancelled = true,
                    child: GestureDetector(
                      // A drag that wins over the preceding tap starts from
                      // the pointer-down position, so the handle it began on
                      // is the handle it moves (see _cancelInteraction).
                      dragStartBehavior: DragStartBehavior.down,
                      onTapDown: (details) => _processInteraction(
                        size,
                        localPosition: details.localPosition,
                        isStart: true,
                        // We can't use isTap here because we don't know if
                        // it's a tap or not!
                      ),
                      onTapUp: (details) => _processInteraction(
                        size,
                        localPosition: details.localPosition,
                        isEnd: true,
                        isTap: true,
                      ),
                      onTapCancel: _cancelInteraction,
                      onHorizontalDragStart: (details) =>
                          _onHorizontalDragStart(size, details),
                      onHorizontalDragUpdate: (details) =>
                          _processInteraction(
                        size,
                        localPosition: details.localPosition,
                      ),
                      onHorizontalDragEnd: (details) => _processInteraction(
                        size,
                        localPosition: details.localPosition,
                        isEnd: true,
                      ),
                      onHorizontalDragCancel: _onHorizontalDragCancel,
                      child: CustomPaint(
                        willChange: true,
                        size: size,
                        painter: _AmphitheatreEditorSliderPainter(
                          style: widget.style,
                          value: widget.controller.position.inMilliseconds,
                          max: _max,
                          thumbnails: widget.thumbnails,
                        ),
                        foregroundPainter:
                            (widget.editorController.value.crop != null)
                                ? _AmphitheatreEditorSliderCropPainter(
                                    size: size,
                                    style: widget.style,
                                    cropStart: widget.editorController.value
                                        .crop!.start.inMilliseconds,
                                    cropEnd: widget.editorController.value
                                        .crop!.end.inMilliseconds,
                                    max: _max,
                                    cropStartIcon: _cropStartIcon,
                                    cropEndIcon: _cropEndIcon,
                                  )
                                : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          _buildTimestamps(context),
        ],
      );

  _AmphitheatreEditorSliderDragMode computeDragMode(
    Offset position, {
    required Size size,
  }) =>
      _AmphitheatreEditorSliderCropPainter.computeCropDragMode(
        position,
        size: size,
        style: widget.style,
        cropStart: widget.editorController.value.crop!.start.inMilliseconds,
        cropEnd: widget.editorController.value.crop!.end.inMilliseconds,
        max: widget.controller.duration.inMilliseconds,
      ) ??
      _AmphitheatreEditorSliderDragMode.playbackHead;
}

/// Paints the timeline itself: the track, the filmstrip thumbnails, the
/// playback head and the border. The crop selection is painted on top by
/// [_AmphitheatreEditorSliderCropPainter].
class _AmphitheatreEditorSliderPainter extends CustomPainter {
  /// The color of the track behind the filmstrip: visible until the
  /// thumbnails arrive, and wherever a frame does not cover the track.
  static const _trackColor = Colors.transparent;

  final int value;
  final int max;
  final AmphitheatreEditorStyle style;
  final List<ui.Image> thumbnails;

  const _AmphitheatreEditorSliderPainter({
    required this.value,
    required this.max,
    required this.style,
    required this.thumbnails,
  });

  @override
  bool operator ==(Object other) =>
      other is _AmphitheatreEditorSliderPainter &&
      value == other.value &&
      max == other.max &&
      style == other.style &&
      listEquals(thumbnails, other.thumbnails);

  @override
  int get hashCode =>
      Object.hashAll([value, max, style, Object.hashAll(thumbnails)]);

  @override
  bool shouldRepaint(_AmphitheatreEditorSliderPainter old) => old != this;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _SliderMetrics(size: size, style: style, max: max);
    final RRect borderRRect = metrics.trackRRect;

    canvas
      ..save()
      ..clipRRect(borderRRect)
      ..drawRect(metrics.trackRect, Paint()..color = _trackColor);

    _paintFilmstrip(canvas, metrics);

    if (max > 0) {
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.lineThickness
        ..color = style.lineColor;

      final double linePosition = metrics.positionFor(value);

      canvas.drawLine(
        Offset(linePosition, 0),
        Offset(linePosition, size.height),
        linePaint,
      );
    }

    canvas.restore();

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.borderThickness
      ..color = style.borderColor;

    canvas.drawRRect(borderRRect, borderPaint);
  }

  /// Paints the filmstrip thumbnails in equal cells across the track, each
  /// cover-fitted (centered and cropped) into its cell.
  void _paintFilmstrip(Canvas canvas, _SliderMetrics metrics) {
    if (thumbnails.isEmpty) return;

    final Rect track = metrics.trackRect;
    final double cellWidth = track.width / thumbnails.length;
    final paint = Paint()..filterQuality = FilterQuality.low;

    for (var i = 0; i < thumbnails.length; i++) {
      final ui.Image image = thumbnails[i];
      final cell = Rect.fromLTWH(
        track.left + i * cellWidth,
        track.top,
        cellWidth,
        track.height,
      );

      final double imageWidth = image.width.toDouble();
      final double imageHeight = image.height.toDouble();
      // Cover-fit: the larger scale fills the cell on both axes.
      final double scaleX = cell.width / imageWidth;
      final double scaleY = cell.height / imageHeight;
      final scale = scaleX > scaleY ? scaleX : scaleY;
      final double sourceWidth = cell.width / scale;
      final double sourceHeight = cell.height / scale;
      final source = Rect.fromLTWH(
        (imageWidth - sourceWidth) / 2,
        (imageHeight - sourceHeight) / 2,
        sourceWidth,
        sourceHeight,
      );

      canvas.drawImageRect(image, source, cell, paint);
    }
  }
}

class _AmphitheatreEditorSliderCropPainter extends CustomPainter {
  /// The color drawn over the parts of the track outside the selection.
  static const _selectionDimColor = Colors.black54;

  final Size size;
  final AmphitheatreEditorStyle style;

  final int cropStart;
  final int cropEnd;
  final int max;

  final ui.Image? cropStartIcon;
  final ui.Image? cropEndIcon;

  const _AmphitheatreEditorSliderCropPainter({
    required this.size,
    required this.style,
    required this.cropStart,
    required this.cropEnd,
    required this.max,
    required this.cropStartIcon,
    required this.cropEndIcon,
  });

  @override
  bool operator ==(Object other) =>
      other is _AmphitheatreEditorSliderCropPainter &&
      size == other.size &&
      style == other.style &&
      cropStart == other.cropStart &&
      cropEnd == other.cropEnd &&
      max == other.max &&
      cropStartIcon == other.cropStartIcon &&
      cropEndIcon == other.cropEndIcon;

  @override
  int get hashCode => Object.hashAll(
        [size, style, cropStart, cropEnd, max, cropStartIcon, cropEndIcon],
      );

  @override
  bool shouldRepaint(_AmphitheatreEditorSliderCropPainter old) =>
      old != this;

  /// Compute the [_AmphitheatreEditorSliderDragMode] of a drag action at the
  /// given [position]. The [style] is used to account for border thickness,
  /// etc.,
  ///
  /// If [cropStart] and [cropEnd] are null (e.g., because the crop state has
  /// not yet been initialized) this function always returns null to indicate
  /// that a crop action should not be performed.
  ///
  /// See also: [_SliderMetrics.positionFor].
  static _AmphitheatreEditorSliderDragMode? computeCropDragMode(
    Offset position, {
    required AmphitheatreEditorStyle style,
    required int? cropStart,
    required int? cropEnd,
    required int max,
    required Size size,
  }) {
    if (cropStart == null || cropEnd == null) return null;

    final double cropHitboxWidth = style.borderThickness + style.cropHandleSize;
    final metrics = _SliderMetrics(size: size, style: style, max: max);

    final double startOffset =
        metrics.positionFor(cropStart) - (style.borderThickness / 2);

    final double endOffset =
        metrics.positionFor(cropEnd) - (style.borderThickness / 2);

    final leftCropHandleHitbox = RRect.fromRectAndCorners(
      Offset(startOffset - cropHitboxWidth, 0) &
          Size(cropHitboxWidth, size.height),
      topLeft: style.borderRadius.topLeft,
      bottomLeft: style.borderRadius.bottomLeft,
    );

    if (leftCropHandleHitbox.contains(position)) {
      return _AmphitheatreEditorSliderDragMode.cropStart;
    }

    final rightCropHandleHitbox = RRect.fromRectAndCorners(
      Offset(endOffset + style.lineThickness, 0) &
          Size(cropHitboxWidth, size.height),
      topRight: style.borderRadius.topRight,
      bottomRight: style.borderRadius.bottomRight,
    );

    if (rightCropHandleHitbox.contains(position)) {
      return _AmphitheatreEditorSliderDragMode.cropEnd;
    }

    final Rect intersectionHitbox =
        Offset(startOffset, 0) & Size(endOffset - startOffset, size.height);
    if (intersectionHitbox.contains(position)) {
      return _AmphitheatreEditorSliderDragMode.cropIntersection;
    }

    return null;
  }

  @override
  bool? hitTest(Offset position) {
    final _AmphitheatreEditorSliderDragMode? cropDragMode = computeCropDragMode(
      position,
      style: style,
      cropStart: cropStart,
      cropEnd: cropEnd,
      max: max,
      size: size,
    );

    if (cropDragMode?.isCrop ?? false) {
      return true;
    }

    return super.hitTest(position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (this.size != size) {
      throw ArgumentError(
        [
          'Inconsistent sizes provided to _AmphitheatreEditorSliderCropPainter.',
          '',
          'The provided size and rendered size must match to ensure the correct hitTest semantics are applied.',
          '',
          'The easiest way to fix this is to wrap the _AmphitheatreEditorSliderCropPainter in a LayoutBuilder and pass the constraints down as a Size.',
        ].join('\n'),
        'size',
      );
    }

    if (max > 0) {
      final cropBorderStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.borderThickness
        ..color = style.cropColor;

      final cropBorderFill = Paint.from(cropBorderStroke)
        ..style = PaintingStyle.fill;

      final metrics = _SliderMetrics(size: size, style: style, max: max);
      final double startPosition = metrics.positionFor(cropStart);
      final double endPosition =
          metrics.positionFor(cropEnd) + style.borderThickness;

      // Start and end positions that factor in the border.
      final double startPositionWithBorder =
          startPosition - (style.borderThickness / 2);
      final double endPositionWithBorder =
          (endPosition - startPosition) + (style.lineThickness / 2);

      // Dim the parts of the timeline outside of the selection.
      final scrimPaint = Paint()..color = _selectionDimColor;
      canvas
        ..save()
        ..clipRRect(metrics.trackRRect)
        ..drawRect(
          Rect.fromLTRB(
            metrics.trackLeft,
            0,
            startPositionWithBorder,
            size.height,
          ),
          scrimPaint,
        )
        ..drawRect(
          Rect.fromLTRB(
            startPositionWithBorder + endPositionWithBorder,
            0,
            metrics.trackRight,
            size.height,
          ),
          scrimPaint,
        )
        ..restore();

      // Draw the main rectangle.
      final outerCropBorder = RRect.fromRectAndRadius(
        Offset(startPositionWithBorder, 0) &
            Size(endPositionWithBorder, size.height),
        Radius.zero,
      );
      final innerCropBorder = RRect.fromRectAndCorners(
        Offset(startPositionWithBorder, 0) &
            Size(endPositionWithBorder, size.height),
        topLeft: style.borderRadius.topLeft,
        bottomLeft: style.borderRadius.bottomLeft,
        topRight: style.borderRadius.topRight,
        bottomRight: style.borderRadius.bottomRight,
      );

      final leftCropBorder = RRect.fromRectAndCorners(
        Offset(startPositionWithBorder - style.cropHandleSize, 0) &
            Size(style.cropHandleSize, size.height),
        topLeft: style.borderRadius.topLeft,
        bottomLeft: style.borderRadius.bottomLeft,
      );
      final rightCropBorder = RRect.fromRectAndCorners(
        Offset(startPositionWithBorder + endPositionWithBorder, 0) &
            Size(style.cropHandleSize, size.height),
        topRight: style.borderRadius.topRight,
        bottomRight: style.borderRadius.bottomRight,
      );

      canvas
        ..drawDRRect(outerCropBorder, innerCropBorder, cropBorderStroke)
        ..drawDRRect(outerCropBorder, innerCropBorder, cropBorderFill)

        // Draw the LHS and RHS rectangles.
        ..drawRRect(leftCropBorder, cropBorderFill)
        ..drawRRect(leftCropBorder, cropBorderStroke)
        ..drawRRect(rightCropBorder, cropBorderFill)
        ..drawRRect(rightCropBorder, cropBorderStroke);

      // Draw additional shapes to fill in the corners when the crop handles are
      // exceptionally close together.
      final Path topLeftCorner =
          _computeBaseCornerPath(style.borderRadius.topLeft)
              .shift(Offset(startPositionWithBorder, 0));
      final Path topRightCorner =
          _computeBaseCornerPath(style.borderRadius.topRight).flipX.shift(
                Offset(startPositionWithBorder + endPositionWithBorder, 0),
              );
      final Path bottomLeftCorner =
          _computeBaseCornerPath(style.borderRadius.bottomLeft)
              .flipY
              .shift(Offset(startPositionWithBorder, size.height));
      final Path bottomRightCorner =
          _computeBaseCornerPath(style.borderRadius.bottomRight).flipXY.shift(
                Offset(
                  startPositionWithBorder + endPositionWithBorder,
                  size.height,
                ),
              );

      canvas
        ..drawPath(topLeftCorner, cropBorderFill)
        ..drawPath(topLeftCorner, cropBorderStroke)
        ..drawPath(bottomLeftCorner, cropBorderFill)
        ..drawPath(bottomLeftCorner, cropBorderStroke)
        ..drawPath(topRightCorner, cropBorderFill)
        ..drawPath(topRightCorner, cropBorderStroke)
        ..drawPath(bottomRightCorner, cropBorderFill)
        ..drawPath(bottomRightCorner, cropBorderStroke);

      // Draw the images on the LHS and RHS rectangles (if they're specified).
      if (cropStartIcon != null) {
        canvas.drawImage(
          cropStartIcon!,
          Offset(
            startPositionWithBorder - style.cropHandleSize,
            (size.height / 2) - (cropStartIcon!.height / 2),
          ),
          Paint()
            ..colorFilter = ColorFilter.mode(
              style.cropStartIconColor,
              BlendMode.srcIn,
            ),
        );
      }

      if (cropEndIcon != null) {
        canvas.drawImage(
          cropEndIcon!,
          Offset(
            startPositionWithBorder +
                endPositionWithBorder -
                style.lineThickness * 2,
            (size.height / 2) - (cropEndIcon!.height / 2),
          ),
          Paint()
            ..colorFilter = ColorFilter.mode(
              style.cropEndIconColor,
              BlendMode.srcIn,
            ),
        );
      }
    }
  }

  Path _computeBaseCornerPath(
    Radius radius,
  ) =>
      Path()
        ..moveTo(radius.x, 0)
        ..relativeLineTo(-radius.x, 0)
        ..relativeLineTo(0, radius.y)
        ..arcToPoint(Offset(radius.x, 0), radius: radius)
        ..close();
}

extension _Flip on Path {
  Path flip({
    bool x = false,
    bool y = false,
  }) =>
      transform(
        Matrix4.diagonal3Values(
          x ? -1.0 : 1.0,
          y ? -1.0 : 1.0,
          1,
        ).storage,
      );

  /// Returns a copy of the path that has been transformed by being flipped in
  /// the x-axis.
  Path get flipX => flip(x: true);

  /// Returns a copy of the path that has been transformed by being flipped in
  /// the y-axis.
  Path get flipY => flip(y: true);

  /// Returns a copy of the path that has been transformed by being flipped in
  /// both the x and y-axis.
  Path get flipXY => flip(x: true, y: true);
}
