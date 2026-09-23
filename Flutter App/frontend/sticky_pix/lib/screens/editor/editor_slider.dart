import 'package:flutter/material.dart';

import 'editor_theme.dart';

class EditorSlider extends StatelessWidget {
  const EditorSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChangeStart,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final divisions = ((max - min) / step).round();
    return Row(
      children: [
        const SizedBox(
          width: 26,
          height: 44,
          child: Icon(
            Icons.remove_rounded,
            size: 16,
            color: EditorTheme.secondaryLabel,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: EditorTheme.purple,
              inactiveTrackColor: EditorTheme.inactiveTrack,
              thumbColor: Colors.white,
              overlayColor: EditorTheme.purple.withValues(alpha: 0.08),
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 8,
                elevation: 1,
                pressedElevation: 2,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChangeStart: onChangeStart,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(
          width: 26,
          height: 44,
          child: Icon(
            Icons.add_rounded,
            size: 16,
            color: EditorTheme.secondaryLabel,
          ),
        ),
      ],
    );
  }
}
