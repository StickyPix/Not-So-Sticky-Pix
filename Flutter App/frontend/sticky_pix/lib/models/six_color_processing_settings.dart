enum SixColorMatching { rgb, lab }

enum ToneMappingMode { contrast, sCurve }

enum ProcessingPreset {
  balanced,
  warm,
  cool,
  dynamic,
  vivid,
  soft,
  grayscale,
  noir,
  custom,
}

enum SixColorOrientation { portrait, landscape }

extension SixColorOrientationDetails on SixColorOrientation {
  int get width => this == SixColorOrientation.portrait ? 400 : 600;

  int get height => this == SixColorOrientation.portrait ? 600 : 400;

  String get label =>
      this == SixColorOrientation.portrait ? 'Portrait' : 'Landscape';

  String get resolutionLabel => '$width × $height';

  SixColorOrientation get flipped => this == SixColorOrientation.portrait
      ? SixColorOrientation.landscape
      : SixColorOrientation.portrait;
}

class SixColorProcessingSettings {
  final ProcessingPreset preset;
  final SixColorMatching colorMatching;
  final ToneMappingMode toneMapping;
  final double exposure;
  final double saturation;
  final double contrast;
  final double warmth;
  final double sharpness;
  final double sCurveStrength;
  final double shadowBoost;
  final double highlightCompress;
  final double midpoint;
  final bool compressDynamicRange;
  final bool flipHorizontal;
  final double perspective;

  /// Zoom applied after the source has been aspect-filled into the display.
  ///
  /// A value of 1 is the minimum and means "fit the display frame".
  final double viewportScale;

  /// Horizontal/vertical image translation as a fraction of the display size.
  ///
  /// These values are intentionally resolution-independent so the editor and
  /// the final 400 × 600 / 600 × 400 render use the exact same crop.
  final double viewportOffsetX;
  final double viewportOffsetY;

  const SixColorProcessingSettings({
    required this.preset,
    required this.colorMatching,
    required this.toneMapping,
    required this.exposure,
    required this.saturation,
    required this.contrast,
    this.warmth = 0.0,
    this.sharpness = 0.12,
    required this.sCurveStrength,
    required this.shadowBoost,
    required this.highlightCompress,
    required this.midpoint,
    required this.compressDynamicRange,
    this.flipHorizontal = false,
    this.perspective = 0.0,
    this.viewportScale = 1.0,
    this.viewportOffsetX = 0.0,
    this.viewportOffsetY = 0.0,
  });

  factory SixColorProcessingSettings.forPreset(ProcessingPreset preset) {
    return switch (preset) {
      ProcessingPreset.balanced => const SixColorProcessingSettings(
        preset: ProcessingPreset.balanced,
        colorMatching: SixColorMatching.rgb,
        toneMapping: ToneMappingMode.contrast,
        exposure: 1.0,
        saturation: 1.0,
        contrast: 1.0,
        sCurveStrength: 0.9,
        shadowBoost: 0.0,
        highlightCompress: 1.5,
        midpoint: 0.5,
        compressDynamicRange: true,
      ),
      ProcessingPreset.dynamic => const SixColorProcessingSettings(
        preset: ProcessingPreset.dynamic,
        colorMatching: SixColorMatching.rgb,
        toneMapping: ToneMappingMode.sCurve,
        exposure: 1.0,
        saturation: 1.3,
        contrast: 1.0,
        sCurveStrength: 0.9,
        shadowBoost: 0.0,
        highlightCompress: 1.5,
        midpoint: 0.5,
        compressDynamicRange: false,
      ),
      ProcessingPreset.warm => const SixColorProcessingSettings(
        preset: ProcessingPreset.warm,
        colorMatching: SixColorMatching.rgb,
        toneMapping: ToneMappingMode.contrast,
        exposure: 1.03,
        saturation: 1.08,
        contrast: 1.02,
        warmth: 0.18,
        sCurveStrength: 0.9,
        shadowBoost: 0.0,
        highlightCompress: 1.5,
        midpoint: 0.5,
        compressDynamicRange: true,
      ),
      ProcessingPreset.cool => const SixColorProcessingSettings(
        preset: ProcessingPreset.cool,
        colorMatching: SixColorMatching.rgb,
        toneMapping: ToneMappingMode.contrast,
        exposure: 1.0,
        saturation: 1.08,
        contrast: 1.02,
        warmth: -0.18,
        sCurveStrength: 0.9,
        shadowBoost: 0.0,
        highlightCompress: 1.5,
        midpoint: 0.5,
        compressDynamicRange: true,
      ),
      ProcessingPreset.vivid => const SixColorProcessingSettings(
        preset: ProcessingPreset.vivid,
        colorMatching: SixColorMatching.rgb,
        toneMapping: ToneMappingMode.sCurve,
        exposure: 1.1,
        saturation: 1.6,
        contrast: 1.0,
        sCurveStrength: 0.7,
        shadowBoost: 0.1,
        highlightCompress: 1.3,
        midpoint: 0.5,
        compressDynamicRange: false,
      ),
      ProcessingPreset.soft => const SixColorProcessingSettings(
        preset: ProcessingPreset.soft,
        colorMatching: SixColorMatching.rgb,
        toneMapping: ToneMappingMode.contrast,
        exposure: 1.0,
        saturation: 1.1,
        contrast: 0.9,
        sCurveStrength: 0.9,
        shadowBoost: 0.0,
        highlightCompress: 1.5,
        midpoint: 0.5,
        compressDynamicRange: true,
      ),
      ProcessingPreset.grayscale => const SixColorProcessingSettings(
        preset: ProcessingPreset.grayscale,
        colorMatching: SixColorMatching.lab,
        toneMapping: ToneMappingMode.contrast,
        exposure: 1.0,
        saturation: 0.0,
        contrast: 1.1,
        sCurveStrength: 0.9,
        shadowBoost: 0.0,
        highlightCompress: 1.5,
        midpoint: 0.5,
        compressDynamicRange: true,
      ),
      ProcessingPreset.noir => const SixColorProcessingSettings(
        preset: ProcessingPreset.noir,
        colorMatching: SixColorMatching.lab,
        toneMapping: ToneMappingMode.contrast,
        exposure: 0.92,
        saturation: 0.0,
        contrast: 1.5,
        sCurveStrength: 0.9,
        shadowBoost: 0.0,
        highlightCompress: 1.25,
        midpoint: 0.5,
        compressDynamicRange: false,
      ),
      ProcessingPreset.custom => SixColorProcessingSettings.forPreset(
        ProcessingPreset.balanced,
      ).copyWith(preset: ProcessingPreset.custom),
    };
  }

  SixColorProcessingSettings copyWith({
    ProcessingPreset? preset,
    SixColorMatching? colorMatching,
    ToneMappingMode? toneMapping,
    double? exposure,
    double? saturation,
    double? contrast,
    double? warmth,
    double? sharpness,
    double? sCurveStrength,
    double? shadowBoost,
    double? highlightCompress,
    double? midpoint,
    bool? compressDynamicRange,
    bool? flipHorizontal,
    double? perspective,
    double? viewportScale,
    double? viewportOffsetX,
    double? viewportOffsetY,
  }) {
    return SixColorProcessingSettings(
      preset: preset ?? this.preset,
      colorMatching: colorMatching ?? this.colorMatching,
      toneMapping: toneMapping ?? this.toneMapping,
      exposure: exposure ?? this.exposure,
      saturation: saturation ?? this.saturation,
      contrast: contrast ?? this.contrast,
      warmth: warmth ?? this.warmth,
      sharpness: sharpness ?? this.sharpness,
      sCurveStrength: sCurveStrength ?? this.sCurveStrength,
      shadowBoost: shadowBoost ?? this.shadowBoost,
      highlightCompress: highlightCompress ?? this.highlightCompress,
      midpoint: midpoint ?? this.midpoint,
      compressDynamicRange: compressDynamicRange ?? this.compressDynamicRange,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      perspective: perspective ?? this.perspective,
      viewportScale: viewportScale ?? this.viewportScale,
      viewportOffsetX: viewportOffsetX ?? this.viewportOffsetX,
      viewportOffsetY: viewportOffsetY ?? this.viewportOffsetY,
    );
  }
}

extension ProcessingPresetLabel on ProcessingPreset {
  String get label => switch (this) {
    ProcessingPreset.balanced => 'Balanced',
    ProcessingPreset.warm => 'Warm',
    ProcessingPreset.cool => 'Cool',
    ProcessingPreset.dynamic => 'Dynamic',
    ProcessingPreset.vivid => 'Vivid',
    ProcessingPreset.soft => 'Soft',
    ProcessingPreset.grayscale => 'Grayscale',
    ProcessingPreset.noir => 'Noir',
    ProcessingPreset.custom => 'Custom',
  };
}
