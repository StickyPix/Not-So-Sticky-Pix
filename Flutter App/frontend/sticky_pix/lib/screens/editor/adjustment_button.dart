import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_icon.dart';
import 'editor_theme.dart';

class AdjustmentButton<T> extends StatelessWidget {
  const AdjustmentButton({
    super.key,
    required this.value,
    required this.label,
    required this.valueLabel,
    required this.svg,
    required this.fallback,
    required this.selected,
    required this.onSelected,
    required this.circleSize,
    required this.selectedCircleSize,
    required this.itemWidth,
  });

  final T value;
  final String label;
  final String valueLabel;
  final String svg;
  final IconData fallback;
  final bool selected;
  final ValueChanged<T> onSelected;
  final double circleSize;
  final double selectedCircleSize;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EditorTheme.purple : EditorTheme.secondaryLabel;
    return SizedBox(
      width: itemWidth,
      child: EditorPressable(
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          onSelected(value);
        },
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: selected ? selectedCircleSize : circleSize,
              height: selected ? selectedCircleSize : circleSize,
              decoration: BoxDecoration(
                color: selected
                    ? EditorTheme.lavender
                    : Colors.white.withValues(alpha: 0.72),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? EditorTheme.purple
                      : Colors.white.withValues(alpha: 0.85),
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: selected ? 13 : 9,
                    offset: const Offset(0, 4),
                    color: Colors.black.withValues(
                      alpha: selected ? 0.07 : 0.035,
                    ),
                  ),
                ],
              ),
              child: editorIcon(
                svg: svg,
                fallback: fallback,
                color: color,
                size: 16,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: itemWidth,
              height: 12,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1),
            SizedBox(
              height: 12,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  valueLabel,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected
                        ? EditorTheme.purple
                        : EditorTheme.secondaryLabel,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
