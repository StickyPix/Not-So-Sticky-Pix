import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticky_pix/models/six_color_processing_settings.dart';
import 'package:sticky_pix/screens/editor/adjustment_panel.dart';
import 'package:sticky_pix/screens/editor/editor_header.dart';
import 'package:sticky_pix/screens/editor/editor_mode_tabs.dart';
import 'package:sticky_pix/screens/editor/editor_theme.dart';
import 'package:sticky_pix/screens/editor/filter_strip.dart';
import 'package:sticky_pix/screens/six_color_editor_screen.dart';

void main() {
  Uint8List testImage() {
    final image = img.Image(width: 20, height: 30);
    img.fill(image, color: img.ColorRgb8(100, 160, 220));
    return Uint8List.fromList(img.encodePng(image));
  }

  Future<void> pumpEditor(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final image = testImage();
    await tester.pumpWidget(
      MaterialApp(
        home: SixColorEditorScreen(
          imageBytes: image,
          initialPreviewPng: image,
          initialSettings: SixColorProcessingSettings.forPreset(
            ProcessingPreset.balanced,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder adjustmentPanel() =>
      find.byWidgetPredicate((widget) => widget is AdjustmentPanel);
  Finder filterStrip() =>
      find.byWidgetPredicate((widget) => widget is FilterStrip);

  testWidgets('compact editor starts in Adjust with no vertical scrolling', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
    expect(find.byTooltip('Switch display orientation'), findsOneWidget);
    expect(find.byType(EditorModeTabs), findsOneWidget);
    expect(adjustmentPanel(), findsOneWidget);
    expect(filterStrip(), findsNothing);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);

    for (final label in const [
      'Brightness',
      'Contrast',
      'Saturation',
      'Sharpness',
      'Highlights',
      'Shadows',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(tester.getBottomRight(adjustmentPanel()).dy, lessThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filter replaces Adjust and scrolls only horizontally', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(filterStrip(), findsNothing);
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    expect(filterStrip(), findsOneWidget);
    expect(adjustmentPanel(), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Warm'), findsOneWidget);

    final list = tester.widget<ListView>(
      find.descendant(of: filterStrip(), matching: find.byType(ListView)),
    );
    expect(list.scrollDirection, Axis.horizontal);

    await tester.drag(
      find.descendant(of: filterStrip(), matching: find.byType(Scrollable)),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mono'), findsOneWidget);

    await tester.tap(find.text('Adjust').last);
    await tester.pumpAndSettle();
    expect(filterStrip(), findsNothing);
    expect(adjustmentPanel(), findsOneWidget);
  });

  testWidgets('Ratio restores orientation and crop preset workflow', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Ratio'));
    await tester.pumpAndSettle();

    expect(adjustmentPanel(), findsNothing);
    expect(filterStrip(), findsNothing);
    expect(find.text('2:3 Portrait'), findsOneWidget);
    expect(find.text('3:2 Landscape'), findsOneWidget);
    expect(find.text('Crop'), findsOneWidget);
    expect(find.text('Fit'), findsOneWidget);
    expect(find.text('1.25×'), findsOneWidget);
    expect(find.text('1.5×'), findsOneWidget);

    await tester.tap(find.text('3:2 Landscape'));
    await tester.pump();
    expect(find.text('600 × 400 • 180 PPI'), findsOneWidget);
    await tester.tap(find.text('1.25×'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transform restores working rotate flip crop and perspective', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Transform'));
    await tester.pumpAndSettle();

    for (final label in const [
      'Left',
      'Right',
      'Flip',
      'Crop',
      'Perspective',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(adjustmentPanel(), findsNothing);
    expect(filterStrip(), findsNothing);

    await tester.tap(find.text('Right'));
    await tester.pump();
    await tester.tap(find.text('Flip'));
    await tester.pump();
    await tester.tap(find.text('Perspective'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Crop'));
    await tester.pumpAndSettle();
    expect(find.text('2:3 Portrait'), findsOneWidget);
  });

  testWidgets('Compare, orientation, 6 Color, undo and redo remain connected', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Compare'));
    await tester.pump();
    expect(find.text('Processed'), findsOneWidget);
    await tester.tap(find.text('Processed'));
    await tester.pump();
    expect(find.text('Compare'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch display orientation'));
    await tester.pump();
    expect(find.text('600 × 400 • 180 PPI'), findsOneWidget);

    await tester.tap(find.text('6 Color'));
    await tester.pumpAndSettle();
    expect(find.text('6 Color processing'), findsOneWidget);
    expect(find.text('RGB'), findsOneWidget);
    expect(find.text('LAB'), findsOneWidget);
    await tester.tap(find.text('LAB'));
    await tester.pump();
    Navigator.of(tester.element(find.text('LAB'))).pop();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Slider), const Offset(30, 0));
    await tester.pump();
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Done remains a fixed unclipped pill', (tester) async {
    await pumpEditor(tester);

    final done = find.widgetWithText(CupertinoButton, 'Done');
    expect(done, findsOneWidget);
    expect(tester.getSize(done), const Size(88, 44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('header and tab visuals use the compact target dimensions', (
    tester,
  ) async {
    await pumpEditor(tester);

    final headerIcons = tester.widgetList<EditorCupertinoIcon>(
      find.descendant(
        of: find.byType(EditorHeader),
        matching: find.byType(EditorCupertinoIcon),
      ),
    );
    expect(headerIcons.map((icon) => icon.size), everyElement(18));

    final tabs = find.byType(EditorModeTabs);
    expect(tester.getSize(tabs).height, 50);
    final pills = find.descendant(
      of: tabs,
      matching: find.byType(AnimatedContainer),
    );
    expect(pills, findsNWidgets(4));
    for (final pill in pills.evaluate()) {
      expect(tester.getSize(find.byWidget(pill.widget)).height, 40);
    }

    final materialIcons = tester.widgetList<Icon>(
      find.descendant(of: tabs, matching: find.byType(Icon)),
    );
    expect(materialIcons.map((icon) => icon.size), everyElement(16));
    final svgIcons = tester.widgetList<SvgPicture>(
      find.descendant(of: tabs, matching: find.byType(SvgPicture)),
    );
    expect(svgIcons.map((icon) => icon.width), everyElement(16));
    expect(svgIcons.map((icon) => icon.height), everyElement(16));
  });

  testWidgets('adjustment artwork and slider use lighter compact metrics', (
    tester,
  ) async {
    await pumpEditor(tester);

    final panel = adjustmentPanel();
    expect(tester.getSize(panel).height, 148);

    final circles = find.descendant(
      of: panel,
      matching: find.byType(AnimatedContainer),
    );
    expect(circles, findsNWidgets(6));
    final circleSizes = [
      for (final circle in circles.evaluate())
        tester.getSize(find.byWidget(circle.widget)),
    ];
    expect(
      circleSizes.where((size) => size == const Size(40, 40)),
      hasLength(1),
    );
    expect(
      circleSizes.where((size) => size == const Size(36, 36)),
      hasLength(5),
    );

    final adjustmentIcons = tester.widgetList<SvgPicture>(
      find.descendant(of: panel, matching: find.byType(SvgPicture)),
    );
    expect(adjustmentIcons.map((icon) => icon.width), everyElement(16));
    expect(adjustmentIcons.map((icon) => icon.height), everyElement(16));

    final sliderTheme = tester.widget<SliderTheme>(
      find.descendant(of: panel, matching: find.byType(SliderTheme)),
    );
    expect(sliderTheme.data.trackHeight, 2.5);
    final thumb = sliderTheme.data.thumbShape! as RoundSliderThumbShape;
    expect(thumb.enabledThumbRadius, 8);
    final sliderIcons = tester.widgetList<Icon>(
      find.descendant(of: panel, matching: find.byType(Icon)),
    );
    expect(sliderIcons.map((icon) => icon.size), everyElement(16));
  });

  testWidgets('short-phone active panels stay on screen', (tester) async {
    await pumpEditor(tester, size: const Size(320, 700));

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(adjustmentPanel(), findsOneWidget);
    expect(tester.getBottomRight(adjustmentPanel()).dy, lessThanOrEqualTo(700));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(filterStrip(), findsOneWidget);
    expect(tester.getBottomRight(filterStrip()).dy, lessThanOrEqualTo(700));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet layout remains centered at maximum content width', (
    tester,
  ) async {
    await pumpEditor(tester, size: const Size(1024, 1100));

    expect(
      tester.getSize(find.byType(EditorModeTabs)).width,
      lessThanOrEqualTo(520),
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
