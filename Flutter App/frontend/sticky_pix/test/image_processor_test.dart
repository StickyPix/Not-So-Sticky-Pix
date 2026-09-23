import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticky_pix/models/six_color_processing_settings.dart';
import 'package:sticky_pix/services/image_processor.dart';

void main() {
  group('six-color dithering', () {
    test('preserves exact panel palette colors', () {
      final source = img.Image(width: 6, height: 1);
      const colors = [
        (0, 0, 0, 0x0),
        (255, 255, 255, 0x1),
        (255, 255, 0, 0x2),
        (255, 0, 0, 0x3),
        (0, 0, 255, 0x5),
        (0, 255, 0, 0x6),
      ];

      for (var x = 0; x < colors.length; x++) {
        final color = colors[x];
        source.setPixelRgb(x, 0, color.$1, color.$2, color.$3);
      }

      final codes = applyFloydSteinbergDither6Color(source);
      expect(codes, Uint8List.fromList([for (final color in colors) color.$4]));
    });

    test(
      'dynamic-range compression maps white to the measured white point',
      () {
        final source = img.Image(width: 1, height: 1);
        img.fill(source, color: img.ColorRgb8(255, 255, 255));
        final balanced = SixColorProcessingSettings.forPreset(
          ProcessingPreset.balanced,
        );
        final uncompressedSettings = balanced.copyWith(
          compressDynamicRange: false,
          preset: ProcessingPreset.custom,
        );

        final compressed = apply6ColorEnhancements(
          source,
          settings: balanced,
        ).getPixel(0, 0);
        final uncompressed = apply6ColorEnhancements(
          source,
          settings: uncompressedSettings,
        ).getPixel(0, 0);

        expect(compressed.r, lessThan(uncompressed.r));
        expect(compressed.g, lessThan(uncompressed.g));
        expect(compressed.b, lessThan(uncompressed.b));
      },
    );

    test('represents a clear sky mostly with blue and white', () {
      final source = img.Image(width: 128, height: 128);
      img.fill(source, color: img.ColorRgb8(92, 165, 229));

      final codes = applyFloydSteinbergDither6Color(source);
      final offHueCount = codes
          .where((code) => code == 0x2 || code == 0x3 || code == 0x6)
          .length;

      expect(offHueCount / codes.length, lessThan(0.05));
      expect(codes.contains(0x5), isTrue);
      expect(codes.contains(0x1), isTrue);
    });

    test('supports both RGB and LAB palette matching', () {
      final source = img.Image(width: 64, height: 64);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(
            x,
            y,
            x * 255 ~/ (source.width - 1),
            y * 255 ~/ (source.height - 1),
            (x * 3 + y * 5) % 256,
          );
        }
      }

      final rgbCodes = applyFloydSteinbergDither6Color(
        source,
        matching: SixColorMatching.rgb,
      );
      final labCodes = applyFloydSteinbergDither6Color(
        source,
        matching: SixColorMatching.lab,
      );

      expect(rgbCodes, isNot(equals(labCodes)));
    });

    test('only emits valid panel codes and packs to 120000 bytes', () {
      final source = img.Image(width: sixColorWidth, height: sixColorHeight);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(
            x,
            y,
            (x * 255 ~/ (source.width - 1)),
            (y * 255 ~/ (source.height - 1)),
            ((x + y) * 255 ~/ (source.width + source.height - 2)),
          );
        }
      }

      final codes = applyFloydSteinbergDither6Color(source);
      const validCodes = {0x0, 0x1, 0x2, 0x3, 0x5, 0x6};
      expect(codes.every(validCodes.contains), isTrue);

      final packed = packHorizontal4Bpp(codes, sixColorWidth, sixColorHeight);
      expect(packed.length, 120000);
    });
  });

  group('processing presets', () {
    test('balanced is measured-palette RGB with dynamic-range compression', () {
      final settings = SixColorProcessingSettings.forPreset(
        ProcessingPreset.balanced,
      );

      expect(settings.colorMatching, SixColorMatching.rgb);
      expect(settings.toneMapping, ToneMappingMode.contrast);
      expect(settings.compressDynamicRange, isTrue);
      expect(settings.exposure, 1.0);
      expect(settings.saturation, 1.0);
    });

    test('grayscale uses zero saturation and LAB matching', () {
      final settings = SixColorProcessingSettings.forPreset(
        ProcessingPreset.grayscale,
      );

      expect(settings.saturation, 0.0);
      expect(settings.colorMatching, SixColorMatching.lab);
      expect(settings.contrast, 1.1);
    });

    test('manual changes can be marked custom', () {
      final settings = SixColorProcessingSettings.forPreset(
        ProcessingPreset.balanced,
      ).copyWith(exposure: 1.25, preset: ProcessingPreset.custom);

      expect(settings.preset, ProcessingPreset.custom);
      expect(settings.exposure, 1.25);
    });

    test('warm and cool filters shift opposite color channels', () {
      final source = img.Image(width: 1, height: 1);
      img.fill(source, color: img.ColorRgb8(120, 120, 120));

      final warm = apply6ColorEnhancements(
        source,
        settings: SixColorProcessingSettings.forPreset(ProcessingPreset.warm),
      ).getPixel(0, 0);
      final cool = apply6ColorEnhancements(
        source,
        settings: SixColorProcessingSettings.forPreset(ProcessingPreset.cool),
      ).getPixel(0, 0);

      expect(warm.r - warm.b, greaterThan(0));
      expect(cool.b - cool.r, greaterThan(0));
    });

    test('noir filter is monochrome with stronger contrast', () {
      final settings = SixColorProcessingSettings.forPreset(
        ProcessingPreset.noir,
      );

      expect(settings.saturation, 0);
      expect(settings.contrast, greaterThan(1.4));
      expect(settings.colorMatching, SixColorMatching.lab);
    });

    test('sharpness increases local edge contrast', () {
      final source = img.Image(width: 5, height: 5);
      img.fill(source, color: img.ColorRgb8(90, 90, 90));
      source.setPixelRgb(2, 2, 170, 170, 170);
      final balanced = SixColorProcessingSettings.forPreset(
        ProcessingPreset.balanced,
      ).copyWith(compressDynamicRange: false);

      final plain = apply6ColorEnhancements(
        source,
        settings: balanced.copyWith(sharpness: 0),
      ).getPixel(2, 2);
      final sharpened = apply6ColorEnhancements(
        source,
        settings: balanced.copyWith(sharpness: 1),
      ).getPixel(2, 2);

      expect(sharpened.r, greaterThan(plain.r));
    });
  });

  group('image rotation', () {
    test('landscape panel codes rotate clockwise into portrait transport', () {
      //  1 2 3        7 4 1
      //  4 5 6  -->   8 5 2
      //  7 8 9        9 6 3
      final rotated = rotateSixColorCodesClockwise(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]),
        3,
        3,
      );

      expect(rotated, Uint8List.fromList([7, 4, 1, 8, 5, 2, 9, 6, 3]));
    });

    test('quarter-turn rotation swaps image dimensions', () {
      final source = img.Image(width: 40, height: 60);

      final rotated = rotateByQuarterTurns(source, 1);
      final restored = rotateByQuarterTurns(source, 4);

      expect(rotated.width, 60);
      expect(rotated.height, 40);
      expect(restored.width, 40);
      expect(restored.height, 60);
    });

    test('portrait and landscape keep the same packed payload size', () {
      final source = img.Image(width: 30, height: 20);
      img.fill(source, color: img.ColorRgb8(90, 140, 200));
      final settings = SixColorProcessingSettings.forPreset(
        ProcessingPreset.balanced,
      );

      final portrait = process6ColorImage(
        Uint8List(0),
        source,
        settings: settings,
        orientation: SixColorOrientation.portrait,
      );
      final landscape = process6ColorImage(
        Uint8List(0),
        source,
        settings: settings,
        orientation: SixColorOrientation.landscape,
      );
      final portraitPreview = img.decodePng(portrait.previewPng)!;
      final landscapePreview = img.decodePng(landscape.previewPng)!;

      expect((portraitPreview.width, portraitPreview.height), (400, 600));
      expect((landscapePreview.width, landscapePreview.height), (600, 400));
      expect(portrait.binaryPacked.length, 120000);
      expect(landscape.binaryPacked.length, 120000);
      final landscapeDevicePreview = img.decodePng(
        landscape.displayTexturePng,
      )!;
      expect(
        (landscapeDevicePreview.width, landscapeDevicePreview.height),
        (400, 600),
      );
    });

    test('live editor preview retains the full selected resolution', () {
      final source = img.Image(width: 30, height: 20);
      img.fill(source, color: img.ColorRgb8(90, 140, 200));
      final settings = SixColorProcessingSettings.forPreset(
        ProcessingPreset.balanced,
      );

      final portrait = img.decodePng(
        generateSixColorPreviewPng(
          source,
          settings: settings,
          orientation: SixColorOrientation.portrait,
        ),
      )!;
      final landscape = img.decodePng(
        generateSixColorPreviewPng(
          source,
          settings: settings,
          orientation: SixColorOrientation.landscape,
        ),
      )!;

      expect((portrait.width, portrait.height), (400, 600));
      expect((landscape.width, landscape.height), (600, 400));
    });
  });

  group('transform controls', () {
    test('horizontal flip changes the actual processing source', () {
      final source = img.Image(width: 3, height: 1);
      source.setPixelRgb(0, 0, 255, 0, 0);
      source.setPixelRgb(1, 0, 0, 255, 0);
      source.setPixelRgb(2, 0, 0, 0, 255);
      final settings = SixColorProcessingSettings.forPreset(
        ProcessingPreset.balanced,
      ).copyWith(flipHorizontal: true);

      final transformed = prepareSixColorSource(source, settings: settings);

      expect(transformed.getPixel(0, 0).b, 255);
      expect(transformed.getPixel(2, 0).r, 255);
    });

    test('perspective correction changes the sampled source geometry', () {
      final source = img.Image(width: 40, height: 40);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, x * 6, y * 6, (x + y) * 3);
        }
      }
      final balanced = SixColorProcessingSettings.forPreset(
        ProcessingPreset.balanced,
      );

      final plain = prepareSixColorSource(source, settings: balanced);
      final rectified = prepareSixColorSource(
        source,
        settings: balanced.copyWith(perspective: 0.12),
      );

      expect(img.encodePng(rectified), isNot(equals(img.encodePng(plain))));
    });
  });

  group('display viewport crop', () {
    test('zoom and pan use the same edge-clamped crop as the editor', () {
      final source = img.Image(width: 300, height: 100);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(
            x,
            y,
            x < 100 ? 255 : 0,
            x >= 100 && x < 200 ? 255 : 0,
            x >= 200 ? 255 : 0,
          );
        }
      }

      final left = resizeAndCrop(
        source,
        100,
        100,
        scale: 3,
        offsetX: 4,
      ).getPixel(50, 50);
      final right = resizeAndCrop(
        source,
        100,
        100,
        scale: 3,
        offsetX: -4,
      ).getPixel(50, 50);

      expect(left.r, greaterThan(240));
      expect(left.g, lessThan(15));
      expect(right.b, greaterThan(240));
      expect(right.g, lessThan(15));
    });

    test('zoom cannot go below fit-frame scale', () {
      final source = img.Image(width: 200, height: 300);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
        }
      }

      final fit = resizeAndCrop(source, 40, 60);
      final belowFit = resizeAndCrop(source, 40, 60, scale: 0.2);

      expect(img.encodePng(belowFit), img.encodePng(fit));
    });
  });
}
