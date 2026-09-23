import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'editor_theme.dart';

class EditorHeader extends StatelessWidget {
  const EditorHeader({
    super.key,
    required this.onCancel,
    required this.onHelp,
    required this.onDone,
    this.title = 'Adjust',
    this.height = 52,
    this.buttonSize = 40,
    this.titleFontSize = 23,
    this.doneButtonWidth = 88,
    this.doneButtonHeight = 44,
  });

  final VoidCallback onCancel;
  final VoidCallback onHelp;
  final VoidCallback onDone;
  final String title;
  final double height;
  final double buttonSize;
  final double titleFontSize;
  final double doneButtonWidth;
  final double doneButtonHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Text(
            title,
            style: TextStyle(
              color: EditorTheme.label,
              fontSize: titleFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeaderCircleButton(
                  tooltip: 'Cancel',
                  icon: CupertinoIcons.back,
                  onTap: onCancel,
                  size: buttonSize,
                ),
                const SizedBox(width: 8),
                _HeaderCircleButton(
                  tooltip: 'Editing help',
                  icon: CupertinoIcons.question_circle,
                  onTap: onHelp,
                  size: buttonSize,
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: doneButtonWidth,
              height: doneButtonHeight,
              child: CupertinoButton.filled(
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(doneButtonHeight / 2),
                onPressed: onDone,
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.size,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: EditorPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                blurRadius: 16,
                offset: const Offset(0, 5),
                color: Colors.black.withValues(alpha: 0.05),
              ),
            ],
          ),
          child: EditorCupertinoIcon(icon, size: 18),
        ),
      ),
    );
  }
}
