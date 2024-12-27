import 'dart:async';

import 'package:amphitheatre/src/amphitheatre_components.dart';
import 'package:amphitheatre/src/amphitheatre_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A builder for a [Amphitheatre] component. [controller] is for the video
/// player that the component is being rendered for. [showControls] is true
/// when the screen has been tapped and the controls should be shown and false
/// otherwise.
///
/// The close and replay buttons are an exception; the close button is always
/// built and the replay button is only built when the video has ended.
///
/// You do not need to manually handle [showControls] - the widget that the
/// controls are being rendered in is hidden and ignored with [AnimatedOpacity]
/// and [IgnorePointer], respectively, when [showControls] is false. It can,
/// however, be used to optimize your controls when they are not being shown.
typedef AmphitheatreComponentBuilder = Widget Function(
  AmphitheatreController controller,
  bool showControls,
);

Widget _buildCloseButton(
  final AmphitheatreController controller,
  final bool showControls,
) =>
    AmphitheatreCloseButton(
      show: showControls
          ? AmphitheatreVisibility.always
          : AmphitheatreVisibility.whenVideoEnded,
      controller: controller,
    );

Widget _buildReplayButton(
  final AmphitheatreController controller,
  final bool showControls,
) =>
    AmphitheatreReplayButton(controller: controller);

Widget _buildProgressSlider(
  final AmphitheatreController controller,
  final bool showControls,
) =>
    AmphitheatreProgressSlider(controller: controller);

Widget _buildVideoControls(
  final AmphitheatreController controller,
  final bool showControls,
) =>
    AmphitheatreVideoControls(controller: controller);

Widget _buildVideoInfo(
  final AmphitheatreController controller,
  final bool showControls,
) =>
    AmphitheatreVideoInfoDisplay(controller: controller);

/// A builder for the [Route] that is used to open [Amphitheatre] when
/// [Amphitheatre.launch] is called.
///
/// This can be used to customize the route and therefore the transition that is
/// used when an [Amphitheatre] is launched.
typedef AmphitheatreRouteBuilder = Route<void> Function(Widget child);

Route<void> _defaultAmphitheatreRouteBuilder(final Widget child) =>
    MaterialPageRoute<void>(builder: (final _) => child);

/// The Amphitheatre video player.
class Amphitheatre extends StatefulWidget {
  /// The controller for the [Amphitheatre].
  final AmphitheatreController controller;

  /// Builder for the close button. This button shows in the top-left of the
  /// screen when the controls are not hidden.
  final AmphitheatreComponentBuilder buildCloseButton;

  /// Builder for the replay button. This button shows in the center of the
  /// screen when the video has ended.
  ///
  /// Naturally, this is never built when [enableReplayButton] is false.
  final AmphitheatreComponentBuilder buildReplayButton;

  /// Builder for the progress slider. This button shows in the bottom third
  /// of the screen when the controls are not hidden.
  final AmphitheatreComponentBuilder buildProgressSlider;

  /// Builder for the video controls (e.g., skip back, play/pause, skip
  /// forward). This button shows in the bottom third of the screen when the
  /// controls are not hidden.
  final AmphitheatreComponentBuilder buildVideoControls;

  /// Builder for the video information. This shows underneath the video
  /// controls ([buildVideoControls]).
  ///
  /// **Note:** The builder is only invoked when the
  /// [AmphitheatreController.hasVideoInfo] and the
  /// [AmphitheatreVideoInfo.isNotEmpty].
  final AmphitheatreComponentBuilder buildVideoInfo;

  /// When true (as is the default), tapping outside of the controls (i.e., on
  /// the video) will hide the controls and tapping again will show them. If
  /// this is false, that behavior is disabled.
  final bool enableToggleControls;

  /// When true (as is the default) once the video has ended the controls will
  /// be hidden and only the replay and close buttons will be rendered instead.
  final bool enableReplayButton;

  /// If enabled, the video starts playing as soon as the controller has
  /// initialized and buffered it.
  ///
  /// This has no effect if the controller has already been initialized, hence
  /// the option is not available on the default constructor. Instead, see
  /// [Amphitheatre.consume].
  final bool autoPlay;

  /// If true, the [Amphitheatre] will automatically dispose of the [controller]
  /// when it is disposed.
  ///
  /// See [Amphitheatre.consume] and [launch].
  final bool consumedController;

  /// The default constructor for [Amphitheatre].
  const Amphitheatre({
    required this.controller,
    this.buildCloseButton = _buildCloseButton,
    this.buildReplayButton = _buildReplayButton,
    this.buildProgressSlider = _buildProgressSlider,
    this.buildVideoControls = _buildVideoControls,
    this.buildVideoInfo = _buildVideoInfo,
    this.enableToggleControls = true,
    this.enableReplayButton = true,
    this.autoPlay = true,
    super.key,
  }) : consumedController = false;

  /// Equivalent to the default constructor, [Amphitheatre.new], but indicates
  /// to [Amphitheatre] that the [controller] has been 'consumed'.
  ///
  /// This means that the [Amphitheatre] state will automatically initialize and
  /// dispose of the controller in accordance with its own lifecycle.
  ///
  /// This is intended for where the [controller] is ephemerally linked to the
  /// [Amphitheatre] lifecycle (e.g., in the case of [launch]).
  const Amphitheatre.consume({
    required this.controller,
    this.buildCloseButton = _buildCloseButton,
    this.buildReplayButton = _buildReplayButton,
    this.buildProgressSlider = _buildProgressSlider,
    this.buildVideoControls = _buildVideoControls,
    this.buildVideoInfo = _buildVideoInfo,
    this.enableToggleControls = true,
    this.enableReplayButton = true,
    this.autoPlay = true,
    super.key,
  }) : consumedController = true;

  /// Launches the [Amphitheatre] with the given controller, consuming the
  /// controller. See [Amphitheatre.consume].
  static void launch(
    final BuildContext context, {
    required final AmphitheatreController controller,
    final AmphitheatreRouteBuilder routeBuilder =
        _defaultAmphitheatreRouteBuilder,
  }) {
    final Widget child = Amphitheatre.consume(controller: controller);
    unawaited(Navigator.of(context).push(routeBuilder(child)));
  }

  @override
  State<Amphitheatre> createState() => _AmphitheatreState();

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AmphitheatreController>('controller', controller),
      )
      ..add(
        ObjectFlagProperty<AmphitheatreComponentBuilder>.has(
          'buildCloseButton',
          buildCloseButton,
        ),
      )
      ..add(
        ObjectFlagProperty<AmphitheatreComponentBuilder>.has(
          'buildReplayButton',
          buildReplayButton,
        ),
      )
      ..add(
        ObjectFlagProperty<AmphitheatreComponentBuilder>.has(
          'buildProgressSlider',
          buildProgressSlider,
        ),
      )
      ..add(
        ObjectFlagProperty<AmphitheatreComponentBuilder>.has(
          'buildVideoControls',
          buildVideoControls,
        ),
      )
      ..add(
        ObjectFlagProperty<AmphitheatreComponentBuilder>.has(
          'buildVideoInfo',
          buildVideoInfo,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'enableToggleControls',
          enableToggleControls,
        ),
      )
      ..add(DiagnosticsProperty<bool>('enableReplayButton', enableReplayButton))
      ..add(DiagnosticsProperty<bool>('autoPlay', autoPlay))
      ..add(
        DiagnosticsProperty<bool>('consumedController', consumedController),
      );
  }
}

class _AmphitheatreState extends State<Amphitheatre> {
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    if (widget.consumedController) {
      widget.controller.initialize(autoPlay: widget.autoPlay);
    } else {
      if (widget.controller.isPlaying != widget.autoPlay) {
        if (widget.controller.isPlaying) {
          widget.controller.pause();
        } else {
          widget.controller.play();
        }
      }
    }

    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    if (widget.consumedController) {
      widget.controller.dispose();
    } else {
      widget.controller.removeListener(_onControllerUpdate);
    }
    super.dispose();
  }

  void _onControllerUpdate() => setState(() {});
  void _toggleControls() {
    if ((widget.enableReplayButton && !widget.controller.isCompleted) &&
        widget.enableToggleControls) {
      setState(() => _showControls = !_showControls);
    }
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: _toggleControls,
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: widget.controller.aspectRatio,
                    child: AnimatedOpacity(
                      opacity: widget.enableReplayButton &&
                              widget.controller.isCompleted
                          ? 0
                          : 1,
                      duration: widget.controller.animationDuration,
                      curve: widget.controller.animationCurve,
                      child: VideoPlayer(
                        widget.controller.controller,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 20,
              left: 20,
              child: SafeArea(
                child: widget.buildCloseButton(
                  widget.controller,
                  _showControls,
                ),
              ),
            ),
            if (widget.enableReplayButton)
              Center(
                child: widget.buildReplayButton(
                  widget.controller,
                  _showControls,
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _controlsWrapper([
                widget.buildProgressSlider(
                  widget.controller,
                  _showControls,
                ),
                widget.buildVideoControls(
                  widget.controller,
                  _showControls,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: widget.buildVideoInfo(
                    widget.controller,
                    _showControls,
                  ),
                ),
              ]),
            ),
          ],
        ),
      );

  Widget _controlsWrapper(final List<Widget> controls) {
    final bool showControls = _showControls &&
        (!widget.controller.isCompleted || !widget.enableReplayButton);

    return IgnorePointer(
      ignoring: !showControls,
      child: AnimatedOpacity(
        opacity: showControls ? 1 : 0,
        duration: widget.controller.animationDuration,
        curve: widget.controller.animationCurve,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [
                0,
                0.05,
                0.2,
                0.6,
                1.0,
              ],
              colors: <Color>[
                Colors.black.withAlpha(0),
                Colors.black.withAlpha(20),
                Colors.black.withAlpha(90),
                Colors.black45,
                Colors.black54,
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: controls,
            ),
          ),
        ),
      ),
    );
  }
}
