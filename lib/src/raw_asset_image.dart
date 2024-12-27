import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// A [RawAssetImage] is a binary asset (as in the assets section in
/// pubspec.yaml) that contains an image. This is used to render glyphs/icons
/// on [CustomPainter]s.
@immutable
final class RawAssetImage {
  /// The size of the asset. The asset might be scaled, but the [size] can be
  /// used to determine the correct aspect ratio in that case.
  final Size size;

  /// The path to the asset. (Omit any trailing slashes).
  final String assetPath;

  /// The package that the [assetPath] belongs to. (This can be used to extract
  /// images from an external package that contains icons/images).
  ///
  /// If the package is not specified, the asset is loaded from the
  /// [rootBundle].
  final String? package;

  /// The computed path to the asset (this factors in whether [package] is
  /// specified or not).
  String get path =>
      package != null ? 'packages/$package/$assetPath' : assetPath;

  /// Construct a [RawAssetImage].
  const RawAssetImage({
    required this.size,
    required this.assetPath,
    this.package,
  });

  @override
  bool operator ==(final Object other) =>
      other is RawAssetImage &&
      size == other.size &&
      assetPath == other.assetPath &&
      package == other.package;

  @override
  int get hashCode => Object.hashAll([size, assetPath, package]);
}
