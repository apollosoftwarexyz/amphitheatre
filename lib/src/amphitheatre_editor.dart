import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui
    show Codec, Image, PictureRecorder, instantiateImageCodec;

import 'package:amphitheatre/src/amphitheatre.dart';
import 'package:amphitheatre/src/amphitheatre_components.dart';
import 'package:amphitheatre/src/amphitheatre_controller.dart';
import 'package:amphitheatre/src/raw_asset_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Editing options for the [AmphitheatreEditor].
@immutable
final class AmphitheatreEditorOptions {
  /// Whether to strictly require that videos conform to the specified
  /// [minLength] and [maxLength]. If the video can never conform to the
  /// constraints (i.e., it is too short), the video will be automatically
  /// accepted when [strict] is true.
  ///
  /// See [minLength].
  final bool strict;

  /// The minimum length to allow the video can be cropped to. If not set to
  /// zero and the video is less than or equal to the [minLength], the video
  /// will be automatically accepted unless [strict] is true.
  final Duration minLength;

  /// The maximum length to allow the video to be.
  final Duration maxLength;

  /// Construct the [AmphitheatreEditorOptions].
  const AmphitheatreEditorOptions({
    this.minLength = const Duration(seconds: 10),
    this.maxLength = const Duration(minutes: 5),
    this.strict = false,
  });

  /// Whether [strict] and the constraints [minLength] and [maxLength] indicate
  /// that the video with the given [duration] should be automatically accepted.
  bool shouldAutoAccept(final Duration duration) =>
      strict && duration <= minLength;

  /// Returns the default start and end offsets for cropping. The offsets are
  /// based on computing the maximum length that can surround the middle of the
  /// video.
  (Duration start, Duration end) getDefaultOffsets(final Duration duration) {
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
  bool operator ==(final Object other) =>
      other is AmphitheatreEditorOptions &&
      minLength == other.minLength &&
      maxLength == other.maxLength;

  @override
  int get hashCode => Object.hash(minLength, maxLength);
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
  bool operator ==(final Object other) =>
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
typedef AmphitheatreEditorRouteBuilder = Route<void> Function(Widget child);

Route<void> _defaultAmphitheatreEditorRouteBuilder(final Widget child) =>
    MaterialPageRoute<void>(builder: (final _) => child);

/// The Amphitheatre video editor.
class AmphitheatreEditor extends StatefulWidget {
  /// The controller for the [AmphitheatreEditor].
  final AmphitheatreController controller;

  /// Editing options for the [AmphitheatreEditor].
  final AmphitheatreEditorOptions options;

  /// Styling options for the [AmphitheatreEditor].
  final AmphitheatreEditorStyle style;

  /// See [Amphitheatre.consumedController].
  final bool consumedController;

  /// The default constructor for [AmphitheatreEditor].
  const AmphitheatreEditor({
    required this.controller,
    this.style = const AmphitheatreEditorStyle(),
    this.options = const AmphitheatreEditorOptions(),
    super.key,
  }) : consumedController = false;

  /// See [Amphitheatre.consume].
  const AmphitheatreEditor.consume({
    required this.controller,
    this.style = const AmphitheatreEditorStyle(),
    this.options = const AmphitheatreEditorOptions(),
    super.key,
  }) : consumedController = true;

  /// Launches the [AmphitheatreEditor] with the given controller, consuming the
  /// controller. See [AmphitheatreEditor.consume].
  static void launch(
    final BuildContext context, {
    required final AmphitheatreController controller,
    final AmphitheatreEditorRouteBuilder routeBuilder =
        _defaultAmphitheatreEditorRouteBuilder,
  }) {
    final Widget child = AmphitheatreEditor.consume(controller: controller);
    unawaited(Navigator.of(context).push(routeBuilder(child)));
  }

  @override
  State<AmphitheatreEditor> createState() => _AmphitheatreEditorState();

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      )
      ..add(DiagnosticsProperty<AmphitheatreEditorStyle>('style', style))
      ..add(DiagnosticsProperty<AmphitheatreEditorOptions>('options', options))
      ..add(
        DiagnosticsProperty<bool>('consumedController', consumedController),
      );
  }
}

class _AmphitheatreEditorState extends State<AmphitheatreEditor> {
  late final _createAmphitheatre =
      widget.consumedController ? Amphitheatre.consume : Amphitheatre.new;

  @override
  Widget build(final BuildContext context) => _createAmphitheatre(
        controller: widget.controller,
        enableToggleControls: false,
        enableReplayButton: false,
        autoPlay: false,
        buildCloseButton: (final controller, final _) =>
            AmphitheatreCloseButton(
          controller: controller,
          showCaption: AmphitheatreVisibility.never,
        ),
        buildProgressSlider: (final controller, final __) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AmphitheatreEditorSlider(
            controller: controller,
            options: widget.options,
            style: widget.style,
          ),
        ),
      );
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

/// The [AmphitheatreEditorSlider] replaces the existing editor slider with
/// a [CustomPainter]-based slider that includes handles for cropping the video
/// down to size.
class AmphitheatreEditorSlider extends StatefulWidget {
  /// The [controller] for the [Amphitheatre] player.
  final AmphitheatreController controller;

  /// Editing options for the [AmphitheatreEditor].
  final AmphitheatreEditorOptions options;

  /// Additional styling options for the slider.
  final AmphitheatreEditorStyle style;

  /// The height of the slider.
  final double height;

  /// Construct the [AmphitheatreEditorSlider].
  const AmphitheatreEditorSlider({
    required this.controller,
    required this.options,
    required this.style,
    this.height = 72,
    super.key,
  });

  @override
  State<AmphitheatreEditorSlider> createState() =>
      _AmphitheatreEditorSliderState();

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      )
      ..add(DiagnosticsProperty<AmphitheatreEditorOptions>('options', options))
      ..add(DiagnosticsProperty<AmphitheatreEditorStyle>('style', style))
      ..add(DoubleProperty('height', height));
  }
}

class _AmphitheatreEditorSliderState extends State<AmphitheatreEditorSlider> {
  /// The cached start (LHS) crop icon.
  ui.Image? _cropStartIcon;

  /// The cached end (RHS) crop icon.
  ui.Image? _cropEndIcon;

  /// The [_AmphitheatreEditorSliderDragMode] of the current 'drag session'.
  _AmphitheatreEditorSliderDragMode? _dragMode;

  /// The offset at which the user started dragging.
  Offset? _dragLocalOffset;

  Duration _cropStart = Duration.zero;
  Duration _cropEnd = Duration.zero;

  Duration? _cachedCropStart;
  Duration? _cachedCropEnd;

  @override
  void initState() {
    super.initState();
    unawaited(_loadImages());

    widget.controller.addListener(_didVideoLoad);
  }

  @override
  void dispose() {
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
    if (widget.controller.isInitialized && _cropEnd == Duration.zero) {
      final (Duration initialStart, Duration initialEnd) =
          widget.options.getDefaultOffsets(widget.controller.duration);
      _cropStart = initialStart;
      _cropEnd = initialEnd;

      _ensurePlaybackWithinCropRegion();
      widget.controller.play();
      widget.controller.removeListener(_didVideoLoad);
      widget.controller.addListener(_didControllerUpdate);
    }
  }

  void _didControllerUpdate() {
    if (widget.controller.isInitialized && _cropEnd != Duration.zero) {
      _ensurePlaybackWithinCropRegion();
    }
  }

  /// Ensures that the playback head always resides within the crop region.
  void _ensurePlaybackWithinCropRegion() {
    final bool isPlaying = widget.controller.isPlaying;

    if (widget.controller.position < _cropStart) {
      widget.controller.seekTo(_cropStart);
    } else if (widget.controller.position > _cropEnd) {
      if (isPlaying) {
        widget.controller.seekTo(_cropStart);
      } else {
        widget.controller.seekTo(_cropEnd);
      }
    }
  }

  @override
  void didUpdateWidget(final AmphitheatreEditorSlider oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.style.cropStartIcon != widget.style.cropStartIcon ||
        oldWidget.style.cropEndIcon != widget.style.cropEndIcon) {
      unawaited(_loadImages());
    }
  }

  static Future<ui.Image> _loadRawAssetImage(final RawAssetImage image) async {
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

  int get _max => widget.controller.duration.inMilliseconds;

  void _processInteraction(
    final Size size, {
    required final Offset localPosition,
    final bool isStart = false,
    final bool isEnd = false,

    /// Whether the interaction is a simple tap rather than a drag.
    final bool isTap = false,
  }) {
    if (isStart) {
      if (_dragMode == null) {
        _dragMode = computeDragMode(localPosition, size: size);
        _dragLocalOffset = localPosition;
        _cachedCropStart = _cropStart;
        _cachedCropEnd = _cropEnd;
      }
    }

    if (_dragMode == _AmphitheatreEditorSliderDragMode.playbackHead ||
        (_dragMode == _AmphitheatreEditorSliderDragMode.cropIntersection &&
            isTap) ||
        (_dragMode == _AmphitheatreEditorSliderDragMode.cropIntersection &&
            _cachedCropStart == Duration.zero &&
            _cachedCropEnd == widget.controller.duration)) {
      _handleNewPlayerPosition(
        size,
        localPosition: localPosition,
        pauseBefore: isStart,
        playAfter: isEnd,
      );
    } else if ((_dragMode?.isCrop ?? false) &&
        _dragLocalOffset != null &&
        _cachedCropStart != null &&
        _cachedCropEnd != null) {
      _handleNewCropPosition(
        size,
        dragMode: _dragMode!,
        localPosition: localPosition,
        localOrigin: _dragLocalOffset!,
      );
    }

    if (isEnd) {
      _dragMode = null;
      _dragLocalOffset = null;
      _cachedCropStart = null;
      _cachedCropEnd = null;
    }
  }

  void _handleNewCropPosition(
    final Size size, {
    required final _AmphitheatreEditorSliderDragMode dragMode,
    required final Offset localPosition,
    required final Offset localOrigin,
  }) {
    final Duration duration = widget.controller.duration;
    final int durationMilliseconds = duration.inMilliseconds;

    final double padding =
        widget.style.cropHandleSize * 2 + widget.style.borderThickness * 3;

    final double dragOffsetPercentage =
        (localPosition.dx - localOrigin.dx) / (size.width - padding);

    final dragOffset = Duration(
      milliseconds: (dragOffsetPercentage * _max).floor(),
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
            cropStart = duration - widget.options.minLength;
            cropEnd = duration;
          }
        } else {
          cropStart = cropEnd - widget.options.minLength;

          if (cropStart <= Duration.zero) {
            cropStart = Duration.zero;
            cropEnd = widget.options.minLength;
          }
        }
      }
    }

    setState(() {
      _cropStart = cropStart;
      _cropEnd = cropEnd;
    });
  }

  void _handleNewPlayerPosition(
    final Size size, {
    required final Offset localPosition,
    final bool pauseBefore = false,
    final bool playAfter = false,
  }) {
    if (pauseBefore) {
      widget.controller.pause();
    }

    final double startPadding =
        widget.style.cropHandleSize + widget.style.borderThickness;

    final double endPadding =
        (widget.style.cropHandleSize + widget.style.borderThickness) * 2;

    final double dragPercentage =
        (localPosition.dx - startPadding) / (size.width - endPadding);

    widget.controller.seekTo(
      Duration(
        milliseconds: (dragPercentage * _max).floor(),
      ),
    );

    if (playAfter) {
      widget.controller.play();
    }
  }

  @override
  Widget build(final BuildContext context) => Padding(
        padding: EdgeInsets.all(widget.style.borderThickness / 2),
        child: SizedBox.fromSize(
          size: Size.fromHeight(widget.height),
          child: LayoutBuilder(
            builder: (final context, final constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);

              return GestureDetector(
                onTapDown: (final details) => _processInteraction(
                  size,
                  localPosition: details.localPosition,
                  isStart: true,
                  // We can't use isTap here because we don't know if it's a
                  // tap or not!
                ),
                onTapUp: (final details) => _processInteraction(
                  size,
                  localPosition: details.localPosition,
                  isEnd: true,
                  isTap: true,
                ),
                onHorizontalDragStart: (final details) => _processInteraction(
                  size,
                  localPosition: details.localPosition,
                  isStart: true,
                ),
                onHorizontalDragUpdate: (final details) => _processInteraction(
                  size,
                  localPosition: details.localPosition,
                ),
                onHorizontalDragEnd: (final details) => _processInteraction(
                  size,
                  localPosition: details.localPosition,
                  isEnd: true,
                ),
                child: CustomPaint(
                  willChange: true,
                  size: size,
                  painter: _AmphitheatreEditorSliderPainter(
                    style: widget.style,
                    value: widget.controller.position.inMilliseconds,
                    max: _max,
                  ),
                  foregroundPainter: _AmphitheatreEditorSliderCropPainter(
                    size: size,
                    style: widget.style,
                    cropStart: _cropStart.inMilliseconds,
                    cropEnd: _cropEnd.inMilliseconds,
                    max: _max,
                    cropStartIcon: _cropStartIcon,
                    cropEndIcon: _cropEndIcon,
                  ),
                ),
              );
            },
          ),
        ),
      );

  _AmphitheatreEditorSliderDragMode computeDragMode(
    final Offset position, {
    required final Size size,
  }) =>
      _AmphitheatreEditorSliderCropPainter.computeCropDragMode(
        position,
        size: size,
        style: widget.style,
        start: _cropStart.inMilliseconds,
        end: _cropEnd.inMilliseconds,
        max: widget.controller.duration.inMilliseconds,
      ) ??
      _AmphitheatreEditorSliderDragMode.playbackHead;
}

class _AmphitheatreEditorSliderPainter extends CustomPainter {
  final int value;
  final int max;
  final AmphitheatreEditorStyle style;

  const _AmphitheatreEditorSliderPainter({
    required this.value,
    required this.max,
    required this.style,
  });

  @override
  bool operator ==(final Object other) =>
      other is _AmphitheatreEditorSliderPainter &&
      value == other.value &&
      max == other.max &&
      style == other.style;

  @override
  int get hashCode => Object.hashAll([value, max, style]);

  @override
  bool shouldRepaint(final _AmphitheatreEditorSliderPainter old) => old != this;

  @override
  void paint(final Canvas canvas, final Size size) {
    final borderRRect = RRect.fromRectAndCorners(
      Offset(style.cropHandleSize + style.borderThickness, 0) &
          Size(
            size.width - ((style.cropHandleSize + style.borderThickness) * 2),
            size.height,
          ),
      topLeft: style.borderRadius.topLeft,
      topRight: style.borderRadius.topRight,
      bottomLeft: style.borderRadius.bottomLeft,
      bottomRight: style.borderRadius.bottomRight,
    );

    if (max > 0) {
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.lineThickness
        ..color = style.lineColor;

      final double linePosition =
          _valueToPosition(style: style, value: value, max: max, size: size);

      canvas
        ..saveLayer(Offset.zero & size, Paint())
        ..clipRRect(borderRRect)
        ..drawLine(
          Offset(linePosition, 0),
          Offset(linePosition, size.height),
          linePaint,
        )
        ..restore();
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.borderThickness
      ..color = style.borderColor;

    canvas.drawRRect(borderRRect, borderPaint);
  }

  static double _valueToPosition({
    required final AmphitheatreEditorStyle style,
    required final int value,
    required final int max,
    required final Size size,
  }) =>
      style.cropHandleSize +
      style.borderThickness +
      (value.floorToDouble() / max.floorToDouble()) *
          (size.width -
              (style.lineThickness / 2) -
              style.borderThickness -
              (style.cropHandleSize + style.borderThickness) * 2) +
      (style.borderThickness / 2);
}

class _AmphitheatreEditorSliderCropPainter extends CustomPainter {
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
  bool operator ==(final Object other) =>
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
  bool shouldRepaint(final _AmphitheatreEditorSliderCropPainter old) =>
      old != this;

  static _AmphitheatreEditorSliderDragMode? computeCropDragMode(
    final Offset position, {
    required final AmphitheatreEditorStyle style,
    required final int start,
    required final int end,
    required final int max,
    required final Size size,
  }) {
    final double cropHitboxWidth = style.borderThickness + style.cropHandleSize;

    final double startOffset =
        _AmphitheatreEditorSliderPainter._valueToPosition(
              style: style,
              value: start,
              max: max,
              size: size,
            ) -
            (style.borderThickness / 2);

    final double endOffset = _AmphitheatreEditorSliderPainter._valueToPosition(
          style: style,
          value: end,
          max: max,
          size: size,
        ) -
        (style.borderThickness / 2);

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
  bool? hitTest(final Offset position) {
    final _AmphitheatreEditorSliderDragMode? cropDragMode = computeCropDragMode(
      position,
      style: style,
      start: cropStart,
      end: cropEnd,
      max: max,
      size: size,
    );

    if (cropDragMode?.isCrop ?? false) {
      return true;
    }

    return super.hitTest(position);
  }

  @override
  void paint(final Canvas canvas, final Size size) {
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

      final double startPosition =
          _AmphitheatreEditorSliderPainter._valueToPosition(
        style: style,
        value: cropStart,
        max: max,
        size: size,
      );
      final double endPosition =
          _AmphitheatreEditorSliderPainter._valueToPosition(
                style: style,
                value: cropEnd,
                max: max,
                size: size,
              ) +
              style.borderThickness;

      // Start and end positions that factor in the border.
      final double startPositionWithBorder =
          startPosition - (style.borderThickness / 2);
      final double endPositionWithBorder =
          (endPosition - startPosition) + (style.lineThickness / 2);

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
    final Radius radius,
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
    final bool x = false,
    final bool y = false,
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