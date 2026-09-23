import 'package:flutter/material.dart';

import 'adjustment_button.dart';
import 'editor_slider.dart';
import 'editor_theme.dart';

class AdjustmentDescriptor<T> {
  const AdjustmentDescriptor({
    required this.value,
    required this.label,
    required this.valueLabel,
    required this.svg,
    required this.fallback,
  });

  final T value;
  final String label;
  final String valueLabel;
  final String svg;
  final IconData fallback;
}

class AdjustmentPanel<T> extends StatelessWidget {
  const AdjustmentPanel({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.sliderValue,
    required this.sliderMin,
    required this.sliderMax,
    required this.sliderStep,
    required this.onSliderStart,
    required this.onSliderChanged,
    required this.height,
    this.compact = false,
  });

  final List<AdjustmentDescriptor<T>> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final double sliderValue;
  final double sliderMin;
  final double sliderMax;
  final double sliderStep;
  final ValueChanged<double> onSliderStart;
  final ValueChanged<double> onSliderChanged;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const circleSize = 36.0;
    const selectedCircleSize = 40.0;
    final radius = compact ? 24.0 : 27.0;
    return SizedBox(
      height: height,
      child: EditorCard(
        radius: radius,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / items.length;
            return Column(
              children: [
                SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      for (final item in items)
                        AdjustmentButton<T>(
                          value: item.value,
                          label: item.label,
                          valueLabel: item.valueLabel,
                          svg: item.svg,
                          fallback: item.fallback,
                          selected: item.value == selected,
                          onSelected: onSelected,
                          circleSize: circleSize,
                          selectedCircleSize: selectedCircleSize,
                          itemWidth: itemWidth,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      height: 44,
                      child: EditorSlider(
                        value: sliderValue,
                        min: sliderMin,
                        max: sliderMax,
                        step: sliderStep,
                        onChangeStart: onSliderStart,
                        onChanged: onSliderChanged,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
