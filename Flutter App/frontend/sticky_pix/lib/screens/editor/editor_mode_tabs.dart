import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_icon.dart';
import 'editor_theme.dart';

enum EditorMode { ratio, adjust, filter, transform }

extension EditorModeDetails on EditorMode {
  String get label => switch (this) {
    EditorMode.ratio => 'Ratio',
    EditorMode.adjust => 'Adjust',
    EditorMode.filter => 'Filter',
    EditorMode.transform => 'Transform',
  };

  String? get svg => switch (this) {
    EditorMode.ratio => EditorIconAssets.ratio,
    EditorMode.adjust => null,
    EditorMode.filter => EditorIconAssets.filter,
    EditorMode.transform => EditorIconAssets.transform,
  };

  IconData get fallback => switch (this) {
    EditorMode.ratio => Icons.crop_rounded,
    EditorMode.adjust => CupertinoIcons.slider_horizontal_3,
    EditorMode.filter => Icons.filter_alt_outlined,
    EditorMode.transform => Icons.transform_rounded,
  };
}

class EditorModeTabs extends StatelessWidget {
  const EditorModeTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    this.compact = false,
    this.height = 50,
  });

  final EditorMode selected;
  final ValueChanged<EditorMode> onChanged;
  final bool compact;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 24.0 : 27.0;
    return SizedBox(
      height: height,
      child: EditorCard(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        radius: radius,
        child: Row(
          children: [
            for (final mode in EditorMode.values)
              Expanded(
                child: _ModeTab(
                  mode: mode,
                  selected: mode == selected,
                  onTap: () {
                    if (mode == selected) return;
                    HapticFeedback.selectionClick();
                    onChanged(mode);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final EditorMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EditorTheme.purple : EditorTheme.secondaryLabel;
    return EditorPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(23),
      child: Center(
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: selected ? EditorTheme.lavender : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (mode.svg case final svg?)
                  editorIcon(
                    svg: svg,
                    fallback: mode.fallback,
                    color: color,
                    size: 16,
                  )
                else
                  Icon(mode.fallback, color: color, size: 16),
                const SizedBox(width: 3),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      mode.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
