import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_pix/screens/image_dither_preview.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, {required Size size}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6040AC)),
        ),
        home: const ImageDitherPreview(
          viewer: ColoredBox(color: Color(0xFFE4E0DA)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('home matches the empty-state hierarchy at 393 × 852', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(393, 852));

    expect(find.text('E-Ink Preview Processor'), findsOneWidget);
    expect(find.text('4 Gray'), findsAtLeastNWidgets(2));
    expect(find.text('6 Color'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Pick Image'), findsOneWidget);
    expect(find.text('Drag to rotate'), findsOneWidget);

    expect(find.text('Dithering'), findsOneWidget);
    expect(find.text('400 × 600'), findsOneWidget);
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('180 PPI'), findsOneWidget);
    expect(find.text('Display'), findsOneWidget);
    expect(find.text('File Size'), findsOneWidget);

    expect(find.text('StickyPix'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Not synced yet'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('home does not overflow on a compact 320 × 667 screen', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 667));

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Pick Image'), findsOneWidget);
    expect(find.text('File Size'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);

    final devicesBottom = tester.getBottomRight(find.text('Devices')).dy;
    expect(devicesBottom, lessThanOrEqualTo(667));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 4));
  });
}
