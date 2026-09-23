import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/processed_image_result.dart';
import '../models/six_color_processing_settings.dart';

const int WIDTH = 800;
const int HEIGHT = 480;
const int sixColorWidth = 400;
const int sixColorHeight = 600;

const List<int> _grayPalette = [0x00, 0x55, 0xAA, 0xFF];
const List<int> _sixColorCodes = [0x0, 0x1, 0x2, 0x3, 0x5, 0x6];
const List<(int, int, int)> _sixColorOutputPalette = [
  (0, 0, 0),
  (255, 255, 255),
  (255, 255, 0),
  (255, 0, 0),
  (0, 0, 255),
  (0, 255, 0),
];

// Approximate measured Spectra 6 colors from the esp32-photoframe project.
// These values drive matching and error diffusion; the panel nibble codes and
// theoretical output palette above remain unchanged.
const List<(int, int, int)> _sixColorMeasuredPalette = [
  (2, 2, 2),
  (190, 200, 200),
  (205, 202, 0),
  (135, 19, 0),
  (5, 64, 158),
  (39, 102, 60),
];

enum ImageProcessingMode { fourGray, sixColor }

Future<ProcessedImageResult> processImageAndGeneratePreview(
  Uint8List inputBytes, {
  ImageProcessingMode mode = ImageProcessingMode.fourGray,
  SixColorProcessingSettings? sixColorSettings,
  int sixColorRotationQuarterTurns = 0,
  SixColorOrientation sixColorOrientation = SixColorOrientation.portrait,
}) async {
  final original = img.decodeImage(inputBytes);
  if (original == null) throw Exception("Failed to decode image");

  return switch (mode) {
    ImageProcessingMode.fourGray => process4GrayImage(
      inputBytes,
      original,
      settings: sixColorSettings,
      rotationQuarterTurns: sixColorRotationQuarterTurns,
    ),
    ImageProcessingMode.sixColor => process6ColorImage(
      inputBytes,
      original,
      settings:
          sixColorSettings ??
          SixColorProcessingSettings.forPreset(ProcessingPreset.balanced),
      rotationQuarterTurns: sixColorRotationQuarterTurns,
      orientation: sixColorOrientation,
    ),
  };
}

ProcessedImageResult process4GrayImage(
  Uint8List inputBytes,
  img.Image original, {
  SixColorProcessingSettings? settings,
  int rotationQuarterTurns = 0,
}) {
  // Keep the legacy rendering bit-for-bit intact when no editor settings are
  // provided. When editing, the grayscale panel uses the same crop, rotation,
  // tonal, and detail controls as 6 Color before Atkinson quantization.
  final resized = settings == null
      ? resizeAndCenterCrop(original, WIDTH, HEIGHT)
      : apply6ColorEnhancements(
          resizeAndCrop(
            prepareSixColorSource(
              original,
              settings: settings,
              rotationQuarterTurns: rotationQuarterTurns,
            ),
            WIDTH,
            HEIGHT,
            scale: settings.viewportScale,
            offsetX: settings.viewportOffsetX,
            offsetY: settings.viewportOffsetY,
          ),
          settings: settings,
        );
  final grayCodes = applyAtkinsonDither4Gray(resized);
  final preview = build4GrayPreview(grayCodes, WIDTH, HEIGHT);
  final packed = packHorizontal2Bpp(
    grayCodes,
    WIDTH,
    HEIGHT,
    flipX: true,
    flipY: false,
  );

  print("Image processing complete:");
  print("  Mode: 4-gray");
  print("  Original size: ${inputBytes.length} bytes");
  print("  Processed size: ${packed.length} bytes");
  print(
    "  First 8 packed bytes: ${packed.take(8).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}",
  );

  return ProcessedImageResult(
    Uint8List.fromList(img.encodePng(preview)),
    packed,
  );
}

ProcessedImageResult process6ColorImage(
  Uint8List inputBytes,
  img.Image original, {
  required SixColorProcessingSettings settings,
  int rotationQuarterTurns = 0,
  SixColorOrientation orientation = SixColorOrientation.portrait,
}) {
  final rotated = prepareSixColorSource(
    original,
    settings: settings,
    rotationQuarterTurns: rotationQuarterTurns,
  );
  final targetWidth = orientation.width;
  final targetHeight = orientation.height;
  final resized = resizeAndCrop(
    rotated,
    targetWidth,
    targetHeight,
    scale: settings.viewportScale,
    offsetX: settings.viewportOffsetX,
    offsetY: settings.viewportOffsetY,
  );
  final enhanced = apply6ColorEnhancements(resized, settings: settings);
  final colorCodes = applyFloydSteinbergDither6Color(
    enhanced,
    matching: settings.colorMatching,
  );
  final preview = build6ColorPreview(
    colorCodes,
    targetWidth,
    targetHeight,
    useMeasuredColors: true,
  );
  // The panel's transport geometry is always portrait (400 × 600). When the
  // editor is in landscape, rotate the finished, dithered palette indices—not
  // the RGB image—clockwise into that portrait buffer. This preserves every
  // chosen e-ink color and makes the sent bytes match the product preview.
  final deviceCodes = orientation == SixColorOrientation.landscape
      ? rotateSixColorCodesClockwise(colorCodes, targetWidth, targetHeight)
      : colorCodes;
  final deviceWidth = orientation == SixColorOrientation.landscape
      ? targetHeight
      : targetWidth;
  final deviceHeight = orientation == SixColorOrientation.landscape
      ? targetWidth
      : targetHeight;
  final devicePreview = orientation == SixColorOrientation.landscape
      ? build6ColorPreview(
          deviceCodes,
          deviceWidth,
          deviceHeight,
          useMeasuredColors: true,
        )
      : preview;
  final packed = packHorizontal4Bpp(
    deviceCodes,
    deviceWidth,
    deviceHeight,
    flipX: false,
    flipY: false,
  );

  print("Image processing complete:");
  print("  Mode: 6-color");
  print("  Original size: ${inputBytes.length} bytes");
  print("  Processed size: ${packed.length} bytes");
  print(
    "  First 8 packed bytes: ${packed.take(8).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}",
  );

  return ProcessedImageResult(
    Uint8List.fromList(img.encodePng(preview)),
    packed,
    displayTexturePng: Uint8List.fromList(img.encodePng(devicePreview)),
  );
}

/// Rotates a row-major e-ink palette-index image 90° clockwise.
///
/// A [width] × [height] source becomes [height] × [width]. This is performed
/// after dithering so palette codes survive unchanged for BLE packing.
Uint8List rotateSixColorCodesClockwise(
  Uint8List source,
  int width,
  int height,
) {
  if (source.length != width * height) {
    throw ArgumentError.value(
      source.length,
      'source.length',
      'must equal width × height',
    );
  }
  final rotated = Uint8List(source.length);
  final rotatedWidth = height;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final rotatedX = height - 1 - y;
      final rotatedY = x;
      rotated[rotatedY * rotatedWidth + rotatedX] = source[y * width + x];
    }
  }
  return rotated;
}

Uint8List generateSixColorPreviewPng(
  img.Image original, {
  required SixColorProcessingSettings settings,
  int rotationQuarterTurns = 0,
  SixColorOrientation orientation = SixColorOrientation.portrait,
  int? previewWidth,
  int? previewHeight,
}) {
  final width = previewWidth ?? orientation.width;
  final height = previewHeight ?? orientation.height;
  final rotated = prepareSixColorSource(
    original,
    settings: settings,
    rotationQuarterTurns: rotationQuarterTurns,
  );
  final resized = resizeAndCrop(
    rotated,
    width,
    height,
    scale: settings.viewportScale,
    offsetX: settings.viewportOffsetX,
    offsetY: settings.viewportOffsetY,
  );
  final enhanced = apply6ColorEnhancements(resized, settings: settings);
  final colorCodes = applyFloydSteinbergDither6Color(
    enhanced,
    matching: settings.colorMatching,
  );
  final preview = build6ColorPreview(
    colorCodes,
    width,
    height,
    useMeasuredColors: true,
  );
  return Uint8List.fromList(img.encodePng(preview));
}

/// Live editor preview for the physical 800 × 480 four-gray panel.
Uint8List generate4GrayPreviewPng(
  img.Image original, {
  required SixColorProcessingSettings settings,
  int rotationQuarterTurns = 0,
}) {
  final prepared = prepareSixColorSource(
    original,
    settings: settings,
    rotationQuarterTurns: rotationQuarterTurns,
  );
  final resized = resizeAndCrop(
    prepared,
    WIDTH,
    HEIGHT,
    scale: settings.viewportScale,
    offsetX: settings.viewportOffsetX,
    offsetY: settings.viewportOffsetY,
  );
  final enhanced = apply6ColorEnhancements(resized, settings: settings);
  final grayCodes = applyAtkinsonDither4Gray(enhanced);
  return Uint8List.fromList(
    img.encodePng(build4GrayPreview(grayCodes, WIDTH, HEIGHT)),
  );
}

img.Image rotateByQuarterTurns(img.Image source, int quarterTurns) {
  final normalized = quarterTurns % 4;
  if (normalized == 0) return img.Image.from(source);
  return img.copyRotate(source, angle: normalized * 90);
}

img.Image prepareSixColorSource(
  img.Image source, {
  required SixColorProcessingSettings settings,
  int rotationQuarterTurns = 0,
}) {
  var transformed = rotateByQuarterTurns(source, rotationQuarterTurns);
  if (settings.flipHorizontal) {
    transformed = img.flipHorizontal(transformed);
  }

  final perspective = settings.perspective.clamp(-0.2, 0.2);
  if (perspective.abs() < 0.001) return transformed;

  final maxX = transformed.width - 1.0;
  final maxY = transformed.height - 1.0;
  final inset = maxX * perspective.abs();
  final taperTop = perspective > 0;
  return img.copyRectify(
    transformed,
    topLeft: img.Point(taperTop ? inset : 0, 0),
    topRight: img.Point(taperTop ? maxX - inset : maxX, 0),
    bottomLeft: img.Point(taperTop ? 0 : inset, maxY),
    bottomRight: img.Point(taperTop ? maxX : maxX - inset, maxY),
    interpolation: img.Interpolation.cubic,
  );
}

img.Image resizeAndCenterCrop(img.Image source, int width, int height) {
  return resizeAndCrop(source, width, height);
}

/// Aspect-fills [source] into the target and then applies the editor's
/// resolution-independent zoom/pan crop.
img.Image resizeAndCrop(
  img.Image source,
  int width,
  int height, {
  double scale = 1.0,
  double offsetX = 0.0,
  double offsetY = 0.0,
}) {
  final srcRatio = source.width / source.height;
  final dstRatio = width / height;

  late final double baseCropWidth;
  late final double baseCropHeight;

  if (srcRatio > dstRatio) {
    baseCropHeight = source.height.toDouble();
    baseCropWidth = baseCropHeight * dstRatio;
  } else {
    baseCropWidth = source.width.toDouble();
    baseCropHeight = baseCropWidth / dstRatio;
  }

  final safeScale = scale.clamp(1.0, 5.0);
  final cropWidth = (baseCropWidth / safeScale).round().clamp(1, source.width);
  final cropHeight = (baseCropHeight / safeScale).round().clamp(
    1,
    source.height,
  );

  final coverWidthFactor = source.width / baseCropWidth;
  final coverHeightFactor = source.height / baseCropHeight;
  final maxOffsetX = (coverWidthFactor * safeScale - 1.0) / 2.0;
  final maxOffsetY = (coverHeightFactor * safeScale - 1.0) / 2.0;
  final safeOffsetX = offsetX.clamp(-maxOffsetX, maxOffsetX);
  final safeOffsetY = offsetY.clamp(-maxOffsetY, maxOffsetY);

  // Positive UI translation moves the image right/down, so the sampled source
  // window moves left/up by the corresponding amount.
  final centerX = source.width / 2.0 - safeOffsetX * baseCropWidth / safeScale;
  final centerY =
      source.height / 2.0 - safeOffsetY * baseCropHeight / safeScale;
  final cropX = (centerX - cropWidth / 2.0).round().clamp(
    0,
    source.width - cropWidth,
  );
  final cropY = (centerY - cropHeight / 2.0).round().clamp(
    0,
    source.height - cropHeight,
  );

  final cropped = img.copyCrop(
    source,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );
  return img.copyResize(
    cropped,
    width: width,
    height: height,
    interpolation: img.Interpolation.cubic,
  );
}

img.Image apply6ColorEnhancements(
  img.Image source, {
  SixColorProcessingSettings? settings,
}) {
  final active =
      settings ??
      SixColorProcessingSettings.forPreset(ProcessingPreset.balanced);
  final output = img.Image.from(source);
  final measuredBlack = _sixColorMeasuredPalette[0];
  final measuredWhite = _sixColorMeasuredPalette[1];
  final blackLab = _rgbToLab(
    measuredBlack.$1.toDouble(),
    measuredBlack.$2.toDouble(),
    measuredBlack.$3.toDouble(),
  );
  final whiteLab = _rgbToLab(
    measuredWhite.$1.toDouble(),
    measuredWhite.$2.toDouble(),
    measuredWhite.$3.toDouble(),
  );

  for (final pixel in output) {
    var r = (pixel.r * active.exposure).clamp(0.0, 255.0);
    var g = (pixel.g * active.exposure).clamp(0.0, 255.0);
    var b = (pixel.b * active.exposure).clamp(0.0, 255.0);

    if (active.warmth != 0.0) {
      final shift = active.warmth * 38.0;
      r = (r + shift).clamp(0.0, 255.0);
      g = (g + shift * 0.08).clamp(0.0, 255.0);
      b = (b - shift).clamp(0.0, 255.0);
    }

    if (active.saturation != 1.0) {
      final luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      r = (luminance + (r - luminance) * active.saturation).clamp(0.0, 255.0);
      g = (luminance + (g - luminance) * active.saturation).clamp(0.0, 255.0);
      b = (luminance + (b - luminance) * active.saturation).clamp(0.0, 255.0);
    }

    if (active.toneMapping == ToneMappingMode.contrast) {
      r = _applyContrast(r, active.contrast);
      g = _applyContrast(g, active.contrast);
      b = _applyContrast(b, active.contrast);
    } else {
      r = _applySCurve(r, active);
      g = _applySCurve(g, active);
      b = _applySCurve(b, active);
    }

    if (active.compressDynamicRange) {
      final lab = _rgbToLab(r, g, b);
      final compressedLightness =
          blackLab.$1 + (lab.$1 / 100.0) * (whiteLab.$1 - blackLab.$1);
      final compressed = _labToRgb(compressedLightness, lab.$2, lab.$3);
      r = compressed.$1;
      g = compressed.$2;
      b = compressed.$3;
    }

    pixel
      ..r = r.round().clamp(0, 255)
      ..g = g.round().clamp(0, 255)
      ..b = b.round().clamp(0, 255);
  }

  return active.sharpness <= 0
      ? output
      : _applyUnsharpMask(output, active.sharpness);
}

img.Image _applyUnsharpMask(img.Image source, double strength) {
  final output = img.Image.from(source);
  final amount = strength.clamp(0.0, 1.5) * 0.42;

  for (var y = 1; y < source.height - 1; y++) {
    for (var x = 1; x < source.width - 1; x++) {
      final center = source.getPixel(x, y);
      final left = source.getPixel(x - 1, y);
      final right = source.getPixel(x + 1, y);
      final top = source.getPixel(x, y - 1);
      final bottom = source.getPixel(x, y + 1);

      double sharpen(num centerChannel, num neighborSum) {
        final blurred = neighborSum / 4.0;
        return (centerChannel + (centerChannel - blurred) * amount).clamp(
          0.0,
          255.0,
        );
      }

      output.setPixelRgb(
        x,
        y,
        sharpen(center.r, left.r + right.r + top.r + bottom.r).round(),
        sharpen(center.g, left.g + right.g + top.g + bottom.g).round(),
        sharpen(center.b, left.b + right.b + top.b + bottom.b).round(),
      );
    }
  }
  return output;
}

Uint8List applyAtkinsonDither4Gray(img.Image source) {
  final width = source.width;
  final height = source.height;
  final length = width * height;
  final pixels = Float32List(length);
  final codes = Uint8List(length);
  final gray = img.grayscale(source);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = y * width + x;
      pixels[idx] = gray.getPixel(x, y).luminance.toDouble();
    }
  }

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = y * width + x;
      final code = nearest4GrayCode(pixels[idx]);
      final newValue = _grayPalette[code].toDouble();
      final error = (pixels[idx] - newValue) / 8.0;

      pixels[idx] = newValue;
      codes[idx] = code;

      void spread(int dx, int dy) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) return;

        pixels[ny * width + nx] += error;
      }

      spread(1, 0);
      spread(2, 0);
      spread(-1, 1);
      spread(0, 1);
      spread(1, 1);
      spread(0, 2);
    }
  }

  return codes;
}

Uint8List applyFloydSteinbergDither6Color(
  img.Image source, {
  SixColorMatching matching = SixColorMatching.rgb,
}) {
  final width = source.width;
  final height = source.height;
  final length = width * height;
  final r = Float32List(length);
  final g = Float32List(length);
  final b = Float32List(length);
  final codes = Uint8List(length);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = y * width + x;
      final pixel = source.getPixel(x, y);
      r[idx] = pixel.r.toDouble();
      g[idx] = pixel.g.toDouble();
      b[idx] = pixel.b.toDouble();
    }
  }

  final paletteLab = [
    for (final color in _sixColorMeasuredPalette)
      _rgbToLab(color.$1.toDouble(), color.$2.toDouble(), color.$3.toDouble()),
  ];

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = y * width + x;
      final oldR = r[idx].clamp(0.0, 255.0);
      final oldG = g[idx].clamp(0.0, 255.0);
      final oldB = b[idx].clamp(0.0, 255.0);
      final paletteIndex = _nearestMeasuredPaletteIndex(
        oldR,
        oldG,
        oldB,
        matching,
        paletteLab,
      );
      final measuredColor = _sixColorMeasuredPalette[paletteIndex];
      final newR = measuredColor.$1.toDouble();
      final newG = measuredColor.$2.toDouble();
      final newB = measuredColor.$3.toDouble();

      final errR = oldR - newR;
      final errG = oldG - newG;
      final errB = oldB - newB;

      r[idx] = newR;
      g[idx] = newG;
      b[idx] = newB;
      codes[idx] = _sixColorCodes[paletteIndex];

      void spread(int dx, int dy, double factor) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) return;

        final nIdx = ny * width + nx;
        r[nIdx] += errR * factor;
        g[nIdx] += errG * factor;
        b[nIdx] += errB * factor;
      }

      spread(1, 0, 7 / 16);
      spread(-1, 1, 3 / 16);
      spread(0, 1, 5 / 16);
      spread(1, 1, 1 / 16);
    }
  }

  return codes;
}

int nearest4GrayCode(double value) {
  var bestCode = 0;
  var bestDistance = double.infinity;

  for (int code = 0; code < _grayPalette.length; code++) {
    final distance = (value - _grayPalette[code]).abs();

    if (distance < bestDistance) {
      bestDistance = distance;
      bestCode = code;
    }
  }

  return bestCode;
}

double _srgbToLinear(double channel) {
  if (channel <= 0.04045) return channel / 12.92;
  return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

double _linearToSrgb(double channel) {
  if (channel <= 0.0031308) return 12.92 * channel;
  return 1.055 * math.pow(channel, 1 / 2.4).toDouble() - 0.055;
}

double _applyContrast(double channel, double contrast) {
  return ((channel - 128.0) * contrast + 128.0).clamp(0.0, 255.0);
}

double _applySCurve(double channel, SixColorProcessingSettings settings) {
  final normalized = channel / 255.0;
  final midpoint = settings.midpoint;
  late final double result;

  if (normalized <= midpoint) {
    final shadowValue = normalized / midpoint;
    result =
        math
            .pow(
              shadowValue,
              1.0 - settings.sCurveStrength * settings.shadowBoost,
            )
            .toDouble() *
        midpoint;
  } else {
    final highlightValue = (normalized - midpoint) / (1.0 - midpoint);
    result =
        midpoint +
        math
                .pow(
                  highlightValue,
                  1.0 + settings.sCurveStrength * settings.highlightCompress,
                )
                .toDouble() *
            (1.0 - midpoint);
  }

  return (result * 255.0).clamp(0.0, 255.0);
}

double _labPivot(double value) {
  return value > 0.008856
      ? math.pow(value, 1 / 3).toDouble()
      : 7.787 * value + 16 / 116;
}

(double, double, double) _rgbToLab(double r, double g, double b) {
  final linearR = _srgbToLinear((r / 255.0).clamp(0.0, 1.0));
  final linearG = _srgbToLinear((g / 255.0).clamp(0.0, 1.0));
  final linearB = _srgbToLinear((b / 255.0).clamp(0.0, 1.0));

  final x =
      (linearR * 0.4124564 + linearG * 0.3575761 + linearB * 0.1804375) /
      0.95047;
  final y = linearR * 0.2126729 + linearG * 0.7151522 + linearB * 0.0721750;
  final z =
      (linearR * 0.0193339 + linearG * 0.1191920 + linearB * 0.9503041) /
      1.08883;

  final fx = _labPivot(x);
  final fy = _labPivot(y);
  final fz = _labPivot(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

double _inverseLabPivot(double value) {
  return value > 0.206897 ? value * value * value : (value - 16 / 116) / 7.787;
}

(double, double, double) _labToRgb(double l, double a, double b) {
  final fy = (l + 16) / 116;
  final fx = a / 500 + fy;
  final fz = fy - b / 200;
  final x = 0.95047 * _inverseLabPivot(fx);
  final y = _inverseLabPivot(fy);
  final z = 1.08883 * _inverseLabPivot(fz);

  final linearR = x * 3.2404542 + y * -1.5371385 + z * -0.4985314;
  final linearG = x * -0.9692660 + y * 1.8760108 + z * 0.0415560;
  final linearB = x * 0.0556434 + y * -0.2040259 + z * 1.0572252;

  return (
    (_linearToSrgb(linearR) * 255).clamp(0.0, 255.0),
    (_linearToSrgb(linearG) * 255).clamp(0.0, 255.0),
    (_linearToSrgb(linearB) * 255).clamp(0.0, 255.0),
  );
}

int _nearestMeasuredPaletteIndex(
  double r,
  double g,
  double b,
  SixColorMatching matching,
  List<(double, double, double)> paletteLab,
) {
  var bestIndex = 0;
  var bestDistance = double.infinity;
  final inputLab = matching == SixColorMatching.lab ? _rgbToLab(r, g, b) : null;

  for (int i = 0; i < _sixColorMeasuredPalette.length; i++) {
    late final double distance;
    if (matching == SixColorMatching.lab) {
      final dL = inputLab!.$1 - paletteLab[i].$1;
      final dA = inputLab.$2 - paletteLab[i].$2;
      final dB = inputLab.$3 - paletteLab[i].$3;
      distance = dL * dL + dA * dA + dB * dB;
    } else {
      final paletteColor = _sixColorMeasuredPalette[i];
      final dR = r - paletteColor.$1;
      final dG = g - paletteColor.$2;
      final dB = b - paletteColor.$3;
      distance = dR * dR + dG * dG + dB * dB;
    }

    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = i;
    }
  }

  return bestIndex;
}

img.Image build4GrayPreview(Uint8List grayCodes, int width, int height) {
  final preview = img.Image(width: width, height: height);

  for (int i = 0; i < grayCodes.length; i++) {
    final value = _grayPalette[grayCodes[i]];
    preview.setPixelRgb(i % width, i ~/ width, value, value, value);
  }

  return preview;
}

img.Image build6ColorPreview(
  Uint8List colorCodes,
  int width,
  int height, {
  bool useMeasuredColors = true,
}) {
  final preview = img.Image(width: width, height: height);
  final previewPalette = useMeasuredColors
      ? _sixColorMeasuredPalette
      : _sixColorOutputPalette;

  for (int i = 0; i < colorCodes.length; i++) {
    final paletteIndex = _sixColorCodes.indexOf(colorCodes[i]);
    final safeIndex = paletteIndex < 0 ? 0 : paletteIndex;
    final color = previewPalette[safeIndex];
    preview.setPixelRgb(i % width, i ~/ width, color.$1, color.$2, color.$3);
  }

  return preview;
}

Uint8List packHorizontal2Bpp(
  Uint8List grayCodes,
  int width,
  int height, {
  bool flipX = false,
  bool flipY = false,
}) {
  if (width % 4 != 0) {
    throw ArgumentError("Width must be divisible by 4.");
  }

  final output = Uint8List((width ~/ 4) * height);
  var outIdx = 0;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x += 4) {
      var byte = 0;

      for (int i = 0; i < 4; i++) {
        final srcX = flipX ? width - 1 - (x + i) : x + i;
        final srcY = flipY ? height - 1 - y : y;
        final code = grayCodes[srcY * width + srcX] & 0x03;
        byte |= code << (6 - 2 * i);
      }

      output[outIdx++] = byte;
    }
  }

  return output;
}

Uint8List packVertical2Bpp(
  Uint8List grayCodes,
  int width,
  int height, {
  bool flipX = false,
  bool flipY = false,
}) {
  if (height % 4 != 0) {
    throw ArgumentError("Height must be divisible by 4.");
  }

  final output = Uint8List(width * (height ~/ 4));
  var outIdx = 0;

  for (int x = 0; x < width; x++) {
    for (int y = 0; y < height; y += 4) {
      var byte = 0;

      for (int i = 0; i < 4; i++) {
        final srcX = flipX ? width - 1 - x : x;
        final srcY = flipY ? height - 1 - (y + i) : y + i;
        final code = grayCodes[srcY * width + srcX] & 0x03;
        byte |= code << (6 - 2 * i);
      }

      output[outIdx++] = byte;
    }
  }

  return output;
}

Uint8List packVertical4Bpp(
  Uint8List colorCodes,
  int width,
  int height, {
  bool flipX = false,
  bool flipY = false,
}) {
  if (height % 2 != 0) {
    throw ArgumentError("Height must be divisible by 2.");
  }

  final output = Uint8List(width * (height ~/ 2));
  var outIdx = 0;

  for (int x = 0; x < width; x++) {
    for (int y = 0; y < height; y += 2) {
      final srcX = flipX ? width - 1 - x : x;
      final srcY0 = flipY ? height - 1 - y : y;
      final srcY1 = flipY ? height - 1 - (y + 1) : y + 1;
      final code0 = colorCodes[srcY0 * width + srcX] & 0x0F;
      final code1 = colorCodes[srcY1 * width + srcX] & 0x0F;
      output[outIdx++] = (code0 << 4) | code1;
    }
  }

  return output;
}

Uint8List packHorizontal4Bpp(
  Uint8List colorCodes,
  int width,
  int height, {
  bool flipX = false,
  bool flipY = false,
}) {
  if (width % 2 != 0) {
    throw ArgumentError("Width must be divisible by 2.");
  }

  final output = Uint8List((width ~/ 2) * height);
  var outIdx = 0;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x += 2) {
      final srcY = flipY ? height - 1 - y : y;
      final srcX0 = flipX ? width - 1 - x : x;
      final srcX1 = flipX ? width - 1 - (x + 1) : x + 1;
      final code0 = colorCodes[srcY * width + srcX0] & 0x0F;
      final code1 = colorCodes[srcY * width + srcX1] & 0x0F;
      output[outIdx++] = (code0 << 4) | code1;
    }
  }

  return output;
}
