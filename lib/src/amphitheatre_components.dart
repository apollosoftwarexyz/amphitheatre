import 'dart:math';

import 'package:amphitheatre/src/amphitheatre.dart';
import 'package:amphitheatre/src/amphitheatre_controller.dart';
import 'package:amphitheatre/src/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Visibility types for Amphitheatre components.
enum AmphitheatreVisibility {
  /// Always show the component.
  always,

  /// Show the component only when the video has ended.
  whenVideoEnded,

  /// Never show the components
  never;

  /// Evaluates whether the [controller] indicates that a component should be
  /// shown for the given [AmphitheatreVisibility].
  bool shouldShow(final AmphitheatreController controller) {
    switch (this) {
      case never:
        return false;
      case always:
        return true;
      case whenVideoEnded:
        return controller.isCompleted;
    }
  }
}

sealed class _AmphitheatreAnimatedOpacityIconButton extends StatelessWidget {
  /// See [AmphitheatreController].
  final AmphitheatreController controller;

  /// The size of the icon.
  final double size;

  /// The color of the icon and, where applicable, the caption.
  final Color color;

  /// If specified, sets the background color of the button.
  final Color? backgroundColor;

  /// If specified to true, the button is always visible, if specified to false,
  /// the button is never visible. When null, falls back to the button's default
  /// behavior for visibility. (e.g., a replay button will only show when the
  /// video is over).
  final AmphitheatreVisibility show;

  /// Optionally, a caption can be shown under the icon with the same text as
  /// the tooltip. See [AmphitheatreVisibility].
  final AmphitheatreVisibility showCaption;

  const _AmphitheatreAnimatedOpacityIconButton({
    required this.controller,
    required this.size,
    this.color = Colors.white,
    this.show = AmphitheatreVisibility.always,
    this.showCaption = AmphitheatreVisibility.whenVideoEnded,
    this.backgroundColor,
    super.key,
  });

  // -- BEGIN: TO OVERRIDE

  /// The tooltip to display when the button is held.
  String _getTooltip(final BuildContext context);

  /// The icon to display on the button.
  Widget get _icon;

  /// Returns true when the button should be disabled (e.g., because
  /// [_onPressed] is null).
  bool get _disabled => false;

  /// The action to perform when the button is pressed.
  void _onPressed(final BuildContext context);

  // -- END: TO OVERRIDE

  bool get _visible => show.shouldShow(controller);
  bool get _captionVisible => showCaption.shouldShow(controller);

  @override
  Widget build(final BuildContext context) => IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _disabled
              ? 0.6
              : _visible
                  ? 1
                  : 0,
          duration: controller.animationDuration,
          curve: controller.animationCurve,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                color: color,
                iconSize: size,
                onPressed: _disabled ? null : () => _onPressed(context),
                icon: _icon,
                tooltip: _captionVisible ? null : _getTooltip(context),
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(color),
                  backgroundColor: WidgetStatePropertyAll(backgroundColor),
                ),
              ),
              if (_captionVisible)
                IgnorePointer(
                  ignoring: !_captionVisible,
                  child: AnimatedOpacity(
                    opacity: _captionVisible ? 1 : 0,
                    duration: controller.animationDuration,
                    curve: controller.animationCurve,
                    child: GestureDetector(
                      onTap: _disabled ? null : () => _onPressed(context),
                      child: Text(
                        _getTooltip(context),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('color', color))
      ..add(ColorProperty('backgroundColor', backgroundColor))
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      )
      ..add(DiagnosticsProperty<AmphitheatreVisibility>('show', show))
      ..add(
        DiagnosticsProperty<AmphitheatreVisibility>('showCaption', showCaption),
      )
      ..add(DoubleProperty('size', size));
  }
}

/// A skip button that skips either forward or back in time when tapped.
class AmphitheatreSkipButton extends _AmphitheatreAnimatedOpacityIconButton {
  /// If true, skips backwards instead of forwards.
  final bool back;

  /// The delta to skip by.
  final Duration delta;

  /// Construct an [AmphitheatreSkipButton].
  const AmphitheatreSkipButton({
    required super.controller,
    super.size = 36,
    super.color,
    super.show = AmphitheatreVisibility.always,
    super.showCaption = AmphitheatreVisibility.never,
    this.back = false,
    this.delta = const Duration(seconds: 10),
    super.key,
  });

  @override
  Widget get _icon => Icon(
        back ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      );

  @override
  String _getTooltip(final BuildContext context) => back
      ? getLocalizationDelegate(context).back10Seconds
      : getLocalizationDelegate(context).forward10Seconds;

  @override
  void _onPressed(final BuildContext context) =>
      controller.seek(back ? -delta : delta);

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<bool>('reverse', back))
      ..add(DiagnosticsProperty<Duration>('delta', delta));
  }
}

/// An action that is performed when the close button is pressed. Typically,
/// this is just to pop the current navigation context (which is what
/// [_defaultOnCloseButtonPressed] does).
typedef AmphitheatreCloseButtonAction = void Function(BuildContext context);

void _defaultOnCloseButtonPressed(final BuildContext context) =>
    Navigator.of(context).pop();

/// A simple 'Close' button with a tooltip. Pops the [Navigator] when tapped.
class AmphitheatreCloseButton extends _AmphitheatreAnimatedOpacityIconButton {
  /// The action to perform when the button is pressed.
  final AmphitheatreCloseButtonAction onPressed;

  /// Construct an [AmphitheatreCloseButton].
  const AmphitheatreCloseButton({
    required super.controller,
    super.size = 40,
    super.color,
    super.backgroundColor = const Color(0x3F000000),
    super.show = AmphitheatreVisibility.always,
    super.showCaption = AmphitheatreVisibility.whenVideoEnded,
    this.onPressed = _defaultOnCloseButtonPressed,
    super.key,
  });

  @override
  Widget get _icon => const Icon(Icons.close);

  @override
  String _getTooltip(final BuildContext context) =>
      getLocalizationDelegate(context).close;

  @override
  void _onPressed(final context) => onPressed(context);

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      ObjectFlagProperty<AmphitheatreCloseButtonAction>.has(
        'onPressed',
        onPressed,
      ),
    );
  }
}

/// A simple 'Cancel' button that inherits its icon and other semantics from
/// [AmphitheatreCloseButton]. The default differences between the cancel and
/// close buttons are that the cancel button will naturally have a 'Cancel'
/// tooltip and the caption will always be shown.
class AmphitheatreCancelButton extends AmphitheatreCloseButton {
  /// Construct an [AmphitheatreCancelButton].
  const AmphitheatreCancelButton({
    required super.controller,
    super.size,
    super.color,
    super.backgroundColor,
    super.show,
    super.showCaption = AmphitheatreVisibility.always,
    super.onPressed,
    super.key,
  });

  @override
  String _getTooltip(final BuildContext context) =>
      getLocalizationDelegate(context).cancel;
}

/// A simple 'Done' button with a tooltip. Performs the [onPressed] action when
/// pressed.
class AmphitheatreDoneButton extends _AmphitheatreAnimatedOpacityIconButton {
  /// The action to perform when the [AmphitheatreDoneButton] is pressed.
  final void Function(BuildContext context)? onPressed;

  /// Construct an [AmphitheatreDoneButton].
  const AmphitheatreDoneButton({
    required super.controller,
    this.onPressed,
    super.size = 40,
    super.color,
    super.show = AmphitheatreVisibility.always,
    super.showCaption = AmphitheatreVisibility.always,
    super.key,
  });

  @override
  String _getTooltip(final BuildContext context) =>
      getLocalizationDelegate(context).done;

  @override
  Widget get _icon => const Icon(Icons.check);

  @override
  bool get _disabled => onPressed == null;

  @override
  void _onPressed(final BuildContext context) => onPressed?.call(context);

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      ObjectFlagProperty<void Function(BuildContext context)>.has(
        'onPressed',
        onPressed,
      ),
    );
  }
}

/// A simple 'Replay' icon with tooltip. Instructs the [controller] to replay
/// the video when tapped.
class AmphitheatreReplayButton extends _AmphitheatreAnimatedOpacityIconButton {
  /// Construct an [AmphitheatreReplayButton].
  const AmphitheatreReplayButton({
    required super.controller,
    super.size = 52,
    super.color,
    super.show = AmphitheatreVisibility.whenVideoEnded,
    super.showCaption = AmphitheatreVisibility.always,
    super.key,
  });

  @override
  String _getTooltip(final BuildContext context) =>
      getLocalizationDelegate(context).replay;

  @override
  Widget get _icon => const Icon(Icons.replay);

  @override
  void _onPressed(final context) => controller.replay();
}

/// An animated play/pause button.
class AmphitheatreAnimatedPlayPauseButton extends StatefulWidget {
  /// The [AmphitheatreController] that the play button should drive/be driven
  /// by.
  final AmphitheatreController controller;

  /// The constructor for the [AmphitheatreAnimatedPlayPauseButton].
  const AmphitheatreAnimatedPlayPauseButton({
    required this.controller,
    super.key,
    this.color = Colors.white,
    this.size = 72,
    this.padding = const EdgeInsets.all(8),
  });

  /// The color of the icon.
  final Color color;

  /// The size of the icon.
  final double size;

  /// The padding to wrap around the icon.
  final EdgeInsetsGeometry padding;

  @override
  State<AmphitheatreAnimatedPlayPauseButton> createState() =>
      _AmphitheatreAnimatedPlayPauseButtonState();

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('color', color))
      ..add(DoubleProperty('size', size))
      ..add(DiagnosticsProperty<EdgeInsetsGeometry>('padding', padding))
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      );
  }
}

class _AmphitheatreAnimatedPlayPauseButtonState
    extends State<AmphitheatreAnimatedPlayPauseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  bool get isPausingOrPaused => _animationController.isForwardOrCompleted;

  void _updateIcon(final bool playing) =>
      playing ? _animationController.reverse() : _animationController.forward();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );

    _animationController
      ..value = widget.controller.isPlaying ? 0.0 : 1.0
      ..addListener(didChangeAnimation);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void didChangeAnimation() => setState(() {});

  @override
  void didUpdateWidget(final AmphitheatreAnimatedPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller.isPlaying != isPausingOrPaused) {
      _updateIcon(!widget.controller.isPlaying);
    }
  }

  @override
  Widget build(final BuildContext context) {
    final String label = widget.controller.isPlaying
        ? getLocalizationDelegate(context).pause
        : getLocalizationDelegate(context).play;

    return Material(
      type: MaterialType.transparency,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: widget.controller.isPlaying
              ? widget.controller.pause
              : widget.controller.play,
          borderRadius: BorderRadius.circular(72),
          child: Padding(
            padding: widget.padding,
            child: AnimatedIcon(
              icon: AnimatedIcons.play_pause,
              progress: _animation,
              size: widget.size,
              semanticLabel: label,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
        .add(DiagnosticsProperty<bool>('isPausingOrPaused', isPausingOrPaused));
  }
}

/// The video info for [Amphitheatre].
class AmphitheatreVideoInfoDisplay extends StatelessWidget {
  /// The controller with the video info to display.
  final AmphitheatreController controller;

  /// The base style for the [AmphitheatreVideoInfoDisplay].
  final TextStyle baseStyle;

  /// Construct the [AmphitheatreVideoInfoDisplay].
  const AmphitheatreVideoInfoDisplay({
    required this.controller,
    this.baseStyle = const TextStyle(color: Colors.white),
    super.key,
  });

  @override
  Widget build(final BuildContext context) {
    final AmphitheatreVideoInfo? info = controller.info;
    if (info == null || info.isEmpty) return const SizedBox.shrink();

    return DefaultTextStyle(
      style: baseStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.title != null)
            Text(
              info.title!,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          if (info.subtitle != null)
            Text(
              info.subtitle!,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          if (info.description != null)
            Text(
              info.description!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      )
      ..add(DiagnosticsProperty<TextStyle>('baseStyle', baseStyle));
  }
}

/// The video controls for [Amphitheatre].
class AmphitheatreVideoControls extends StatefulWidget {
  /// The controller for the [AmphitheatreVideoControls].
  final AmphitheatreController controller;

  /// The constructor for the [AmphitheatreVideoControls].
  const AmphitheatreVideoControls({required this.controller, super.key});

  @override
  State<AmphitheatreVideoControls> createState() =>
      _AmphitheatreVideoControlsState();

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<AmphitheatreController>('controller', controller),
    );
  }
}

class _AmphitheatreVideoControlsState extends State<AmphitheatreVideoControls> {
  @override
  Widget build(final BuildContext context) => IgnorePointer(
        ignoring: !widget.controller.isInitialized,
        child: AnimatedOpacity(
          opacity: widget.controller.isInitialized ? 1 : 0,
          duration: widget.controller.animationDuration,
          curve: widget.controller.animationCurve,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 20,
            children: [
              AmphitheatreSkipButton(controller: widget.controller, back: true),
              AmphitheatreAnimatedPlayPauseButton(
                controller: widget.controller,
              ),
              AmphitheatreSkipButton(controller: widget.controller),
            ],
          ),
        ),
      );
}

/// The progress slider for [Amphitheatre]. This renders a progress bar (by
/// default with the application's primary color) and timestamps underneath.
class AmphitheatreProgressSlider extends StatefulWidget {
  /// The controller for the [AmphitheatreProgressSlider].
  final AmphitheatreController controller;

  /// Whether to show timestamps.
  final bool showTimestamps;

  /// The padding to apply around the timestamps.
  final EdgeInsets timestampsPadding;

  /// The color to draw the current progress in the video with. If not
  /// specified, defaults to the primary color of the application.
  final Color? activeColor;

  /// The color to draw secondary progress with (i.e., the amount of the video
  /// that has been buffered). Defaults to the application's primary color with
  /// alpha transparency.
  final Color? secondaryColor;

  /// The color to draw auxiliary information, such as the timestamps, in.
  /// If not specified, defaults to white.
  final Color infoColor;

  /// The constructor for the [AmphitheatreProgressSlider].
  const AmphitheatreProgressSlider({
    required this.controller,
    this.timestampsPadding = const EdgeInsets.symmetric(horizontal: 4),
    this.showTimestamps = true,
    this.activeColor,
    this.secondaryColor,
    this.infoColor = Colors.white,
    super.key,
  });

  @override
  State<AmphitheatreProgressSlider> createState() =>
      _AmphitheatreProgressSliderState();

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      )
      ..add(
        DiagnosticsProperty<EdgeInsets>('timestampsPadding', timestampsPadding),
      )
      ..add(DiagnosticsProperty<bool>('showTimestamps', showTimestamps))
      ..add(ColorProperty('activeColor', activeColor))
      ..add(ColorProperty('secondaryColor', secondaryColor))
      ..add(ColorProperty('infoColor', infoColor));
  }
}

class _AmphitheatreProgressSliderState
    extends State<AmphitheatreProgressSlider> {
  bool get _isBuffering =>
      !widget.controller.isInitialized ||
      (widget.controller.isPlaying && widget.controller.isBuffering);

  @override
  Widget build(final BuildContext context) => Column(
        children: [
          if (_isBuffering)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26)
                  .copyWith(bottom: 22),
              child: LinearProgressIndicator(
                minHeight: 4,
                borderRadius: BorderRadius.circular(100),
                color: widget.activeColor,
              ),
            )
          else
            Slider(
              activeColor: widget.activeColor ?? Theme.of(context).primaryColor,
              secondaryActiveColor: widget.secondaryColor ??
                  Theme.of(context).primaryColor.withAlpha(120),
              value: widget.controller.position.inMilliseconds.toDouble(),
              secondaryTrackValue:
                  widget.controller.buffered?.inMilliseconds.toDouble(),
              onChanged: (final value) {
                widget.controller.seekTo(
                  Duration(
                    milliseconds: min(
                      value.round(),
                      widget.controller.duration.inMilliseconds,
                    ),
                  ),
                );
              },
              min: 0,
              max: widget.controller.duration.inMilliseconds.toDouble(),
              onChangeStart: (final _) => widget.controller.pause(),
              onChangeEnd: (final value) {
                if (!widget.controller.isCompleted) {
                  widget.controller.play();
                }
              },
            ),
          if (widget.showTimestamps)
            AnimatedOpacity(
              opacity: !widget.controller.isInitialized ? 0 : 1,
              duration: widget.controller.animationDuration,
              curve: widget.controller.animationCurve,
              child: Padding(
                padding: widget.timestampsPadding,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.controller.formattedPosition,
                      style: TextStyle(
                        color: widget.infoColor,
                      ),
                    ),
                    Text(
                      widget.controller.formattedDuration,
                      style: TextStyle(
                        color: widget.infoColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
}
