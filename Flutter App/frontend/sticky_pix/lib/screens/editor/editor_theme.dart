import 'dart:ui' as ui;

import 'package:flutter/material.dart';

abstract final class EditorTheme {
  static const background = Color(0xFFF7F7F9);
  static const backgroundWarm = Color(0xFFFAF9F7);
  static const purple = Color(0xFF7052C9);
  static const lavender = Color(0xFFEDE8FA);
  static const label = Color(0xFF27252C);
  static const secondaryLabel = Color(0xFF85818D);
  static const inactiveTrack = Color(0xFFE7E5EA);

  static ThemeData materialTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: purple,
        brightness: Brightness.light,
        surface: backgroundWarm,
      ),
      textTheme: Theme.of(
        context,
      ).textTheme.apply(bodyColor: label, displayColor: label),
    );
  }
}

class EditorCard extends StatelessWidget {
  const EditorCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 30,
    this.blur = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.65),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: Colors.black.withValues(alpha: 0.035),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (!blur) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: content,
      ),
    );
  }
}

class EditorPressable extends StatefulWidget {
  const EditorPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.disabled = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final bool disabled;

  @override
  State<EditorPressable> createState() => _EditorPressableState();
}

class _EditorPressableState extends State<EditorPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || widget.disabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: widget.disabled
            ? 0.35
            : _pressed
            ? 0.84
            : 1,
        duration: const Duration(milliseconds: 120),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.disabled ? null : (_) => _setPressed(true),
          onTapUp: widget.disabled ? null : (_) => _setPressed(false),
          onTapCancel: widget.disabled ? null : () => _setPressed(false),
          onTap: widget.disabled ? null : widget.onTap,
          child: widget.child,
        ),
      ),
    );
  }
}

class EditorCupertinoIcon extends StatelessWidget {
  const EditorCupertinoIcon(this.icon, {super.key, this.color, this.size = 24});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color ?? EditorTheme.label,
      opticalSize: size,
    );
  }
}
