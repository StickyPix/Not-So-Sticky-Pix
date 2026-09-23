import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

abstract final class EditorIconAssets {
  static const brightness = 'assets/icons/brightness.svg';
  static const contrast = 'assets/icons/contrast.svg';
  static const saturation = 'assets/icons/saturation.svg';
  static const sharpness = 'assets/icons/sharpness.svg';
  static const highlights = 'assets/icons/highlights.svg';
  static const shadows = 'assets/icons/shadows.svg';
  static const ratio = 'assets/icons/ratio.svg';
  static const filter = 'assets/icons/filter.svg';
  static const transform = 'assets/icons/transform.svg';
  static const compare = 'assets/icons/compare.svg';
  static const landscape = 'assets/icons/landscape.svg';
  static const palette = 'assets/icons/palette.svg';

  static const all = [
    brightness,
    contrast,
    saturation,
    sharpness,
    highlights,
    shadows,
    ratio,
    filter,
    transform,
    compare,
    landscape,
    palette,
  ];
}

/// Renders an editor SVG with a verified Flutter icon at every fallback stage.
///
/// Both loading and decoding failures resolve to [fallback], so callers can
/// never expose an SVG error or missing-glyph placeholder in the UI.
Widget editorIcon({
  required String svg,
  required IconData fallback,
  required Color color,
  double size = 26,
  Key? key,
}) {
  Widget fallbackIcon() => Icon(
    fallback,
    key: const ValueKey('editor-icon-fallback'),
    size: size,
    color: color,
    opticalSize: size,
  );

  return SvgPicture.asset(
    svg,
    key: key,
    width: size,
    height: size,
    fit: BoxFit.contain,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    placeholderBuilder: (_) => fallbackIcon(),
    errorBuilder: (_, _, _) => fallbackIcon(),
  );
}
