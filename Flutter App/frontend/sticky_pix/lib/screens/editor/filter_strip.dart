import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_theme.dart';

class FilterDescriptor<T> {
  const FilterDescriptor({
    required this.value,
    required this.label,
    required this.colorMatrix,
  });

  final T value;
  final String label;
  final List<double> colorMatrix;
}

class FilterStrip<T> extends StatelessWidget {
  const FilterStrip({
    super.key,
    required this.items,
    required this.sourceBytes,
    required this.selected,
    required this.onSelected,
    required this.height,
    this.compact = false,
  });

  final List<FilterDescriptor<T>> items;
  final Uint8List sourceBytes;
  final T selected;
  final ValueChanged<T> onSelected;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: EditorCard(
        radius: compact ? 24 : 26,
        padding: EdgeInsets.all(compact ? 9 : 10),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final isSelected = item.value == selected;
            return _FilterTile<T>(
              item: item,
              sourceBytes: sourceBytes,
              selected: isSelected,
              compact: compact,
              onTap: () {
                if (isSelected) return;
                HapticFeedback.selectionClick();
                onSelected(item.value);
              },
            );
          },
        ),
      ),
    );
  }
}

class _FilterTile<T> extends StatelessWidget {
  const _FilterTile({
    required this.item,
    required this.sourceBytes,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final FilterDescriptor<T> item;
  final Uint8List sourceBytes;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 56.0 : 62.0;
    final imageHeight = compact ? 54.0 : 64.0;
    return SizedBox(
      width: width,
      child: EditorPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: width,
              height: imageHeight,
              padding: EdgeInsets.all(selected ? 2 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: selected ? EditorTheme.purple : Colors.transparent,
                  width: selected ? 1.75 : 0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(item.colorMatrix),
                  child: Image.memory(
                    sourceBytes,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 3 : 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? EditorTheme.purple
                    : EditorTheme.secondaryLabel,
                fontSize: compact ? 10 : 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
