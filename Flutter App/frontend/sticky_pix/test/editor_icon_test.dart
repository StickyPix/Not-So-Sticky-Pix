import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_pix/screens/editor/editor_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all editor SVG assets are bundled and valid SVG documents', () async {
    for (final asset in EditorIconAssets.all) {
      final contents = await rootBundle.loadString(asset);
      expect(contents, contains('<svg'), reason: asset);
      expect(contents, contains('</svg>'), reason: asset);
    }
  });

  testWidgets('all editor SVG icons render without framework errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: [
            for (final asset in EditorIconAssets.all)
              editorIcon(
                svg: asset,
                fallback: Icons.image_outlined,
                color: Colors.purple,
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNWidgets(EditorIconAssets.all.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed SVG asset renders its built-in icon fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: editorIcon(
            svg: 'assets/icons/not-present.svg',
            fallback: Icons.broken_image_outlined,
            color: Colors.red,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-icon-fallback')), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
