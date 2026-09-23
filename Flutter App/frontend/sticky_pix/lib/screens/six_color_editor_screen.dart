import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../models/six_color_processing_settings.dart';
import '../services/image_processor.dart';
import 'editor/adjustment_panel.dart';
import 'editor/editor_header.dart';
import 'editor/editor_icon.dart';
import 'editor/editor_mode_tabs.dart';
import 'editor/editor_theme.dart';
import 'editor/filter_strip.dart';

double compactEditorScale({
  required double width,
  required double height,
  double referenceWidth = 390,
  double referenceHeight = 780,
}) {
  final widthScale = width / referenceWidth;
  final heightScale = height / referenceHeight;
  return math.min(widthScale, heightScale).clamp(0.82, 1.0);
}

class SixColorEditResult {
  final SixColorProcessingSettings settings;
  final int rotationQuarterTurns;
  final SixColorOrientation orientation;

  const SixColorEditResult({
    required this.settings,
    required this.rotationQuarterTurns,
    required this.orientation,
  });
}

class SixColorEditorScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final Uint8List? initialPreviewPng;
  final ImageProcessingMode processingMode;
  final SixColorProcessingSettings initialSettings;
  final int initialRotationQuarterTurns;
  final SixColorOrientation initialOrientation;

  const SixColorEditorScreen({
    super.key,
    required this.imageBytes,
    required this.initialSettings,
    this.processingMode = ImageProcessingMode.sixColor,
    this.initialPreviewPng,
    this.initialRotationQuarterTurns = 0,
    this.initialOrientation = SixColorOrientation.portrait,
  });

  @override
  State<SixColorEditorScreen> createState() => _SixColorEditorScreenState();
}

class _SixColorEditorScreenState extends State<SixColorEditorScreen> {
  late SixColorProcessingSettings _settings;
  late int _rotationQuarterTurns;
  late SixColorOrientation _orientation;
  late _Adjustment _adjustment;
  img.Image? _sourceImage;
  Uint8List? _previewPng;
  Timer? _previewTimer;
  int _previewGeneration = 0;
  bool _renderingPreview = false;
  bool _showOriginal = false;
  bool _isManipulatingViewport = false;
  double _gestureStartScale = 1;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;
  EditorMode _editorMode = EditorMode.adjust;
  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _rotationQuarterTurns = widget.initialRotationQuarterTurns;
    _orientation = widget.initialOrientation;
    _adjustment = _Adjustment.contrast;
    _previewPng = widget.initialPreviewPng;
    _sourceImage = img.decodeImage(widget.imageBytes);
    if (_previewPng == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _schedulePreview(immediate: true);
      });
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  List<_Adjustment> get _availableAdjustments {
    return const [
      _Adjustment.brightness,
      _Adjustment.contrast,
      _Adjustment.saturation,
      _Adjustment.sharpness,
      _Adjustment.highlights,
      _Adjustment.shadows,
    ];
  }

  bool get _isFourGray => widget.processingMode == ImageProcessingMode.fourGray;

  int get _canvasWidth => _isFourGray ? WIDTH : _orientation.width;

  int get _canvasHeight => _isFourGray ? HEIGHT : _orientation.height;

  String get _canvasResolutionLabel => '$_canvasWidth × $_canvasHeight';

  void _schedulePreview({bool immediate = false}) {
    final source = _sourceImage;
    if (source == null) return;

    _previewTimer?.cancel();
    final generation = ++_previewGeneration;
    if (!_renderingPreview && mounted) {
      setState(() => _renderingPreview = true);
    }

    _previewTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 140),
      () {
        final preview = _isFourGray
            ? generate4GrayPreviewPng(
                source,
                settings: _settings,
                rotationQuarterTurns: _rotationQuarterTurns,
              )
            : generateSixColorPreviewPng(
                source,
                settings: _settings,
                rotationQuarterTurns: _rotationQuarterTurns,
                orientation: _orientation,
              );
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _previewPng = preview;
          _renderingPreview = false;
          _isManipulatingViewport = false;
        });
      },
    );
  }

  void _selectPreset(ProcessingPreset preset) {
    if (preset == ProcessingPreset.custom) return;
    _rememberState();
    setState(() {
      _settings = SixColorProcessingSettings.forPreset(preset).copyWith(
        viewportScale: _settings.viewportScale,
        viewportOffsetX: _settings.viewportOffsetX,
        viewportOffsetY: _settings.viewportOffsetY,
        flipHorizontal: _settings.flipHorizontal,
        perspective: _settings.perspective,
      );
      if (!_availableAdjustments.contains(_adjustment)) {
        _adjustment = _Adjustment.contrast;
      }
    });
    _schedulePreview(immediate: true);
  }

  void _customize(SixColorProcessingSettings settings) {
    _rememberState();
    setState(() {
      _settings = settings.copyWith(preset: ProcessingPreset.custom);
    });
    _schedulePreview();
  }

  double _adjustmentValue(_Adjustment adjustment) {
    return switch (adjustment) {
      _Adjustment.brightness => _settings.exposure,
      _Adjustment.contrast => _settings.contrast,
      _Adjustment.saturation => _settings.saturation,
      _Adjustment.sharpness => _settings.sharpness,
      _Adjustment.highlights => _settings.highlightCompress,
      _Adjustment.shadows => _settings.shadowBoost,
    };
  }

  void _setAdjustmentValue(double value) {
    final updated = switch (_adjustment) {
      _Adjustment.brightness => _settings.copyWith(exposure: value),
      _Adjustment.contrast => _settings.copyWith(contrast: value),
      _Adjustment.saturation => _settings.copyWith(saturation: value),
      _Adjustment.sharpness => _settings.copyWith(sharpness: value),
      _Adjustment.highlights => _settings.copyWith(highlightCompress: value),
      _Adjustment.shadows => _settings.copyWith(shadowBoost: value),
    };
    setState(() {
      _settings = updated.copyWith(preset: ProcessingPreset.custom);
    });
    _schedulePreview();
  }

  void _setToneMapping(ToneMappingMode mode) {
    _rememberState();
    setState(() {
      _settings = _settings.copyWith(
        preset: ProcessingPreset.custom,
        toneMapping: mode,
      );
      _adjustment = _Adjustment.contrast;
    });
    _schedulePreview(immediate: true);
  }

  void _rotate(int delta) {
    _rememberState();
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + delta) % 4;
      _settings = _settings.copyWith(
        viewportScale: 1,
        viewportOffsetX: 0,
        viewportOffsetY: 0,
      );
    });
    _schedulePreview(immediate: true);
  }

  void _flipOrientation() {
    _rememberState();
    setState(() {
      _orientation = _orientation.flipped;
      _settings = _settings.copyWith(
        viewportScale: 1,
        viewportOffsetX: 0,
        viewportOffsetY: 0,
      );
    });
    _schedulePreview(immediate: true);
  }

  void _setOrientation(SixColorOrientation orientation) {
    if (_isFourGray) return;
    if (_orientation == orientation) return;
    HapticFeedback.selectionClick();
    _flipOrientation();
  }

  void _setCropScale(double scale) {
    if ((_settings.viewportScale - scale).abs() < 0.001 &&
        _settings.viewportOffsetX == 0 &&
        _settings.viewportOffsetY == 0) {
      return;
    }
    HapticFeedback.selectionClick();
    _rememberState();
    setState(() {
      _settings = _settings.copyWith(
        viewportScale: scale,
        viewportOffsetX: 0,
        viewportOffsetY: 0,
      );
      _isManipulatingViewport = true;
    });
    _schedulePreview(immediate: true);
  }

  void _flipImage() {
    HapticFeedback.selectionClick();
    _rememberState();
    setState(() {
      _settings = _settings.copyWith(flipHorizontal: !_settings.flipHorizontal);
    });
    _schedulePreview(immediate: true);
  }

  void _cyclePerspective() {
    HapticFeedback.selectionClick();
    _rememberState();
    final next = switch (_settings.perspective) {
      < -0.01 => 0.0,
      > 0.01 => -0.12,
      _ => 0.12,
    };
    setState(() {
      _settings = _settings.copyWith(perspective: next);
    });
    _schedulePreview(immediate: true);
  }

  void _rememberState() {
    _undoStack.add(
      _EditorSnapshot(
        settings: _settings,
        rotationQuarterTurns: _rotationQuarterTurns,
        orientation: _orientation,
      ),
    );
    if (_undoStack.length > 40) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(
      _EditorSnapshot(
        settings: _settings,
        rotationQuarterTurns: _rotationQuarterTurns,
        orientation: _orientation,
      ),
    );
    final snapshot = _undoStack.removeLast();
    _restore(snapshot);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(
      _EditorSnapshot(
        settings: _settings,
        rotationQuarterTurns: _rotationQuarterTurns,
        orientation: _orientation,
      ),
    );
    final snapshot = _redoStack.removeLast();
    _restore(snapshot);
  }

  void _restore(_EditorSnapshot snapshot) {
    setState(() {
      _settings = snapshot.settings;
      _rotationQuarterTurns = snapshot.rotationQuarterTurns;
      _orientation = snapshot.orientation;
      if (!_availableAdjustments.contains(_adjustment)) {
        _adjustment = _availableAdjustments.first;
      }
    });
    _schedulePreview(immediate: true);
  }

  void _startViewportGesture(ScaleStartDetails details, Size viewportSize) {
    _rememberState();
    _gestureStartScale = _settings.viewportScale;
    _gestureStartOffset = Offset(
      _settings.viewportOffsetX * viewportSize.width,
      _settings.viewportOffsetY * viewportSize.height,
    );
    _gestureStartFocalPoint = details.localFocalPoint;
    setState(() => _isManipulatingViewport = true);
  }

  void _updateViewportGesture(ScaleUpdateDetails details, Size viewportSize) {
    final nextScale = (_gestureStartScale * details.scale).clamp(1.0, 5.0);
    final center = viewportSize.center(Offset.zero);
    final ratio = nextScale / _gestureStartScale;
    var translation =
        details.localFocalPoint -
        center -
        (Offset(
              _gestureStartFocalPoint.dx - center.dx - _gestureStartOffset.dx,
              _gestureStartFocalPoint.dy - center.dy - _gestureStartOffset.dy,
            ) *
            ratio);

    final coverFactors = _coverFactors(viewportSize);
    final maxX = viewportSize.width * (coverFactors.dx * nextScale - 1) / 2;
    final maxY = viewportSize.height * (coverFactors.dy * nextScale - 1) / 2;
    translation = Offset(
      translation.dx.clamp(-maxX, maxX),
      translation.dy.clamp(-maxY, maxY),
    );

    setState(() {
      _settings = _settings.copyWith(
        viewportScale: nextScale,
        viewportOffsetX: translation.dx / viewportSize.width,
        viewportOffsetY: translation.dy / viewportSize.height,
      );
    });
  }

  void _endViewportGesture(ScaleEndDetails details) {
    _schedulePreview(immediate: true);
  }

  Offset _coverFactors(Size viewportSize) {
    final source = _sourceImage;
    if (source == null) return const Offset(1, 1);
    final rotated = _rotationQuarterTurns.isOdd;
    final sourceWidth = rotated ? source.height : source.width;
    final sourceHeight = rotated ? source.width : source.height;
    final sourceRatio = sourceWidth / sourceHeight;
    final viewportRatio = viewportSize.width / viewportSize.height;
    if (sourceRatio > viewportRatio) {
      return Offset(sourceRatio / viewportRatio, 1);
    }
    return Offset(1, viewportRatio / sourceRatio);
  }

  void _resetViewport() {
    if (_settings.viewportScale == 1 &&
        _settings.viewportOffsetX == 0 &&
        _settings.viewportOffsetY == 0) {
      return;
    }
    _rememberState();
    setState(() {
      _settings = _settings.copyWith(
        viewportScale: 1,
        viewportOffsetX: 0,
        viewportOffsetY: 0,
      );
      _isManipulatingViewport = true;
    });
    _schedulePreview(immediate: true);
  }

  void _finish() {
    Navigator.pop(
      context,
      SixColorEditResult(
        settings: _settings,
        rotationQuarterTurns: _rotationQuarterTurns,
        orientation: _orientation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: EditorTheme.materialTheme(context),
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [EditorTheme.backgroundWarm, EditorTheme.background],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final scale = compactEditorScale(width: width, height: height);
                final isShortScreen = height < 740;
                final horizontalPadding = (width * 0.05).clamp(14.0, 20.0);
                final contentWidth = math.min(
                  width - horizontalPadding * 2,
                  520.0,
                );

                final headerHeight = isShortScreen ? 48.0 : 52.0;
                const actionHeight = 44.0;
                const tabsHeight = 50.0;
                final panelHeight = isShortScreen ? 145.0 : 148.0;
                final filterHeight = isShortScreen ? 94.0 : 106.0;
                final sectionGap = math.max(
                  8.0,
                  (isShortScreen ? 8.0 : 9.0) * scale,
                );
                const bottomGap = 8.0;
                final reservedHeight =
                    headerHeight +
                    actionHeight +
                    tabsHeight +
                    panelHeight +
                    sectionGap * 4 +
                    bottomGap;
                final previewHeight = math.min(
                  390.0,
                  math.max(0.0, height - reservedHeight),
                );
                final usedHeight = reservedHeight + previewHeight;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Center(
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        children: [
                          SizedBox(
                            height: headerHeight,
                            child: EditorHeader(
                              height: headerHeight,
                              buttonSize: isShortScreen ? 38 : 40,
                              titleFontSize: isShortScreen ? 22 : 23,
                              doneButtonHeight: 44,
                              doneButtonWidth: 88,
                              onCancel: () => Navigator.pop(context),
                              onHelp: _showHelp,
                              onDone: _finish,
                            ),
                          ),
                          SizedBox(height: sectionGap),
                          SizedBox(
                            height: previewHeight,
                            child: _buildPreview(),
                          ),
                          SizedBox(height: sectionGap),
                          SizedBox(
                            height: actionHeight,
                            child: _buildQuickToolbar(),
                          ),
                          SizedBox(height: sectionGap),
                          EditorModeTabs(
                            selected: _editorMode,
                            compact: isShortScreen,
                            height: tabsHeight,
                            onChanged: (mode) {
                              setState(() => _editorMode = mode);
                            },
                          ),
                          SizedBox(height: sectionGap),
                          _buildActiveToolPanel(
                            compact: isShortScreen,
                            height: panelHeight,
                            filterHeight: filterHeight,
                          ),
                          const SizedBox(height: bottomGap),
                          if (height > usedHeight) Spacer(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHelp() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editing your E-Ink image'),
        content: const Text(
          'Pinch and drag directly on the image to frame it, compare it with '
          'the original, choose RGB or LAB matching, rotate it, and apply a '
          'processing preset. Zoom stops at fit-to-frame. You can switch '
          'between the exact 400 × 600 and 600 × 400 hardware canvases.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final aspectRatio = _canvasWidth / _canvasHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = math.min(
          constraints.maxWidth,
          constraints.maxHeight * aspectRatio,
        );
        final frameHeight = frameWidth / aspectRatio;
        return Center(
          child: SizedBox(
            width: frameWidth,
            height: frameHeight,
            child: EditorCard(
              padding: EdgeInsets.zero,
              radius: 22,
              child: LayoutBuilder(
                builder: (context, frameConstraints) {
                  final viewportSize = Size(
                    frameConstraints.maxWidth,
                    frameConstraints.maxHeight,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: (details) =>
                              _startViewportGesture(details, viewportSize),
                          onScaleUpdate: (details) =>
                              _updateViewportGesture(details, viewportSize),
                          onScaleEnd: _endViewportGesture,
                          onDoubleTap: _resetViewport,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: _buildViewportImage(viewportSize),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _PreviewBadge(
                          svg: EditorIconAssets.palette,
                          fallback: Icons.palette_outlined,
                          label: _showOriginal
                              ? 'Original'
                              : (_isFourGray ? '4 Gray' : '6 Color'),
                          onTap: _showProcessingOptions,
                        ),
                      ),
                      if (_renderingPreview)
                        const Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: _PreviewBadge(
                          svg: EditorIconAssets.compare,
                          fallback: Icons.compare_rounded,
                          label: _showOriginal ? 'Processed' : 'Compare',
                          onTap: () =>
                              setState(() => _showOriginal = !_showOriginal),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 10,
                        child: _PreviewBadge(
                          label: '$_canvasResolutionLabel • 180 PPI',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildViewportImage(Size viewportSize) {
    if (_showOriginal || _isManipulatingViewport) {
      final translation = Offset(
        _settings.viewportOffsetX * viewportSize.width,
        _settings.viewportOffsetY * viewportSize.height,
      );
      final coverFactors = _coverFactors(viewportSize);
      return Transform.translate(
        offset: translation,
        child: Transform.scale(
          scale: _settings.viewportScale,
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: viewportSize.width * coverFactors.dx,
              height: viewportSize.height * coverFactors.dy,
              child: RotatedBox(
                quarterTurns: _rotationQuarterTurns,
                child: Image.memory(
                  widget.imageBytes,
                  key: const ValueKey('interactive-original'),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_previewPng == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Image.memory(
      _previewPng!,
      key: ValueKey(_previewGeneration),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
  }

  Widget _buildQuickToolbar() {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          _SquareToolButton(
            tooltip: 'Undo',
            icon: Icons.undo_rounded,
            onPressed: _undoStack.isEmpty ? null : _undo,
          ),
          const SizedBox(width: 8),
          _SquareToolButton(
            tooltip: 'Redo',
            icon: Icons.redo_rounded,
            onPressed: _redoStack.isEmpty ? null : _redo,
          ),
          const Spacer(),
          if (_isFourGray)
            const _FixedOrientationPill()
          else
            Tooltip(
              message: 'Switch display orientation',
              child: _OrientationPill(
                orientation: _orientation,
                showLabel: constraints.maxWidth >= 330,
                onTap: _flipOrientation,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessingOptions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _OptionChip(
          label: 'RGB',
          selected: _settings.colorMatching == SixColorMatching.rgb,
          onPressed: () => _customize(
            _settings.copyWith(colorMatching: SixColorMatching.rgb),
          ),
        ),
        _OptionChip(
          label: 'LAB',
          selected: _settings.colorMatching == SixColorMatching.lab,
          onPressed: () => _customize(
            _settings.copyWith(colorMatching: SixColorMatching.lab),
          ),
        ),
        _OptionChip(
          label: _settings.toneMapping == ToneMappingMode.contrast
              ? 'Contrast tone'
              : 'S-curve',
          selected: true,
          onPressed: () => _setToneMapping(
            _settings.toneMapping == ToneMappingMode.contrast
                ? ToneMappingMode.sCurve
                : ToneMappingMode.contrast,
          ),
        ),
        _OptionChip(
          label: 'Dynamic range',
          selected: _settings.compressDynamicRange,
          onPressed: () => _customize(
            _settings.copyWith(
              compressDynamicRange: !_settings.compressDynamicRange,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showProcessingOptions() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: EditorCard(
          radius: 26,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isFourGray ? '4 Gray processing' : '6 Color processing',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _buildProcessingOptions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveToolPanel({
    required bool compact,
    required double height,
    required double filterHeight,
  }) {
    final panel = switch (_editorMode) {
      EditorMode.ratio => _buildRatioPanel(compact: compact, height: height),
      EditorMode.adjust => _buildAdjustmentPanel(
        compact: compact,
        height: height,
      ),
      EditorMode.filter => Align(
        alignment: Alignment.topCenter,
        child: _buildPresetGallery(compact: compact, height: filterHeight),
      ),
      EditorMode.transform => _buildTransformPanel(
        compact: compact,
        height: height,
      ),
    };
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_editorMode), child: panel),
      ),
    );
  }

  Widget _buildRatioPanel({required bool compact, required double height}) {
    final cropScale = _settings.viewportScale;
    return SizedBox(
      height: height,
      child: EditorCard(
        radius: compact ? 24 : 27,
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Column(
          children: [
            if (_isFourGray)
              const SizedBox(
                height: 42,
                child: Center(
                  child: Text(
                    'Fixed 5:3 landscape display',
                    style: TextStyle(
                      color: EditorTheme.secondaryLabel,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 42,
                child: Row(
                  children: [
                    Expanded(
                      child: _CompactChoice(
                        icon: Icons.crop_portrait_rounded,
                        label: '2:3 Portrait',
                        selected: _orientation == SixColorOrientation.portrait,
                        onTap: () =>
                            _setOrientation(SixColorOrientation.portrait),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CompactChoice(
                        icon: Icons.crop_landscape_rounded,
                        label: '3:2 Landscape',
                        selected: _orientation == SixColorOrientation.landscape,
                        onTap: () =>
                            _setOrientation(SixColorOrientation.landscape),
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Crop',
                      style: TextStyle(
                        color: EditorTheme.secondaryLabel,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final preset in const [
                    (1.0, 'Fit'),
                    (1.25, '1.25×'),
                    (1.5, '1.5×'),
                  ]) ...[
                    Expanded(
                      child: _CompactChoice(
                        label: preset.$2,
                        selected: (cropScale - preset.$1).abs() < 0.01,
                        onTap: () => _setCropScale(preset.$1),
                      ),
                    ),
                    if (preset.$1 != 1.5) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustmentPanel({
    required bool compact,
    required double height,
  }) {
    return AdjustmentPanel<_Adjustment>(
      items: [
        for (final adjustment in _availableAdjustments)
          AdjustmentDescriptor(
            value: adjustment,
            label: adjustment.label,
            valueLabel: _adjustmentValue(adjustment).toStringAsFixed(2),
            svg: adjustment.svg,
            fallback: adjustment.fallback,
          ),
      ],
      selected: _adjustment,
      onSelected: (adjustment) => setState(() => _adjustment = adjustment),
      sliderValue: _adjustmentValue(_adjustment),
      sliderMin: _adjustment.min,
      sliderMax: _adjustment.max,
      sliderStep: _adjustment.step,
      onSliderStart: (_) => _rememberState(),
      onSliderChanged: _setAdjustmentValue,
      height: height,
      compact: compact,
    );
  }

  Widget _buildTransformPanel({required bool compact, required double height}) {
    return SizedBox(
      height: height,
      child: EditorCard(
        radius: compact ? 24 : 27,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 10 : 12,
        ),
        child: Row(
          children: [
            _TransformTool(
              icon: Icons.rotate_left_rounded,
              label: 'Left',
              onTap: () => _rotate(-1),
            ),
            _TransformTool(
              icon: Icons.rotate_right_rounded,
              label: 'Right',
              onTap: () => _rotate(1),
            ),
            _TransformTool(
              icon: Icons.flip_rounded,
              label: 'Flip',
              selected: _settings.flipHorizontal,
              onTap: _flipImage,
            ),
            _TransformTool(
              icon: Icons.crop_rounded,
              label: 'Crop',
              onTap: () => setState(() => _editorMode = EditorMode.ratio),
            ),
            _TransformTool(
              icon: Icons.view_in_ar_outlined,
              label: 'Perspective',
              selected: _settings.perspective.abs() > 0.01,
              onTap: _cyclePerspective,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetGallery({required bool compact, required double height}) {
    final presets = [
      ...ProcessingPreset.values.where(
        (preset) => preset != ProcessingPreset.custom,
      ),
      if (_settings.preset == ProcessingPreset.custom) ProcessingPreset.custom,
    ];
    return FilterStrip<ProcessingPreset>(
      items: [
        for (final preset in presets)
          FilterDescriptor(
            value: preset,
            label: preset.filterLabel,
            colorMatrix: preset.previewColorMatrix,
          ),
      ],
      sourceBytes: widget.imageBytes,
      selected: _settings.preset,
      onSelected: _selectPreset,
      height: height,
      compact: compact,
    );
  }
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.settings,
    required this.rotationQuarterTurns,
    required this.orientation,
  });

  final SixColorProcessingSettings settings;
  final int rotationQuarterTurns;
  final SixColorOrientation orientation;
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({
    required this.label,
    this.svg,
    this.fallback,
    this.onTap,
  });

  final String label;
  final String? svg;
  final IconData? fallback;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (svg != null && fallback != null) ...[
            editorIcon(
              svg: svg!,
              fallback: fallback!,
              color: EditorTheme.label,
              size: 16,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return EditorCard(
      padding: EdgeInsets.zero,
      radius: 18,
      blur: true,
      child: onTap == null
          ? content
          : EditorPressable(
              onTap: onTap!,
              borderRadius: BorderRadius.circular(18),
              child: content,
            ),
    );
  }
}

class _SquareToolButton extends StatelessWidget {
  const _SquareToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: EditorPressable(
        onTap: onPressed ?? () {},
        disabled: onPressed == null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                blurRadius: 16,
                offset: const Offset(0, 6),
                color: Colors.black.withValues(alpha: 0.05),
              ),
            ],
          ),
          child: EditorCupertinoIcon(icon, color: EditorTheme.purple, size: 18),
        ),
      ),
    );
  }
}

class _OrientationPill extends StatelessWidget {
  const _OrientationPill({
    required this.orientation,
    required this.showLabel,
    required this.onTap,
  });

  final SixColorOrientation orientation;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EditorPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              blurRadius: 16,
              offset: const Offset(0, 6),
              color: Colors.black.withValues(alpha: 0.05),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              editorIcon(
                svg: EditorIconAssets.landscape,
                fallback: Icons.landscape_outlined,
                color: EditorTheme.label,
                size: 16,
              ),
              if (showLabel) ...[
                const SizedBox(width: 5),
                Text(
                  orientation.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
              ],
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: EditorTheme.label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four-gray hardware has a fixed 800 × 480 landscape panel. This mirrors
/// the orientation pill visually without offering an orientation that cannot
/// be sent to that display.
class _FixedOrientationPill extends StatelessWidget {
  const _FixedOrientationPill();

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 11),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(17),
      boxShadow: [
        BoxShadow(
          blurRadius: 16,
          offset: const Offset(0, 6),
          color: Colors.black.withValues(alpha: 0.05),
        ),
      ],
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.landscape_outlined, size: 16, color: EditorTheme.label),
        SizedBox(width: 5),
        Text(
          'Landscape',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

extension on ProcessingPreset {
  String get filterLabel => switch (this) {
    ProcessingPreset.balanced => 'Original',
    ProcessingPreset.grayscale => 'Mono',
    _ => label,
  };

  List<double> get previewColorMatrix => switch (this) {
    ProcessingPreset.warm => const [
      1.12,
      0,
      0,
      0,
      9,
      0,
      1.03,
      0,
      0,
      2,
      0,
      0,
      0.86,
      0,
      -4,
      0,
      0,
      0,
      1,
      0,
    ],
    ProcessingPreset.cool => const [
      0.88,
      0,
      0,
      0,
      -3,
      0,
      1.01,
      0,
      0,
      1,
      0,
      0,
      1.15,
      0,
      9,
      0,
      0,
      0,
      1,
      0,
    ],
    ProcessingPreset.dynamic => const [
      1.18,
      -0.09,
      -0.09,
      0,
      0,
      -0.09,
      1.18,
      -0.09,
      0,
      0,
      -0.09,
      -0.09,
      1.18,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
    ProcessingPreset.vivid => const [
      1.35,
      -0.18,
      -0.18,
      0,
      3,
      -0.18,
      1.35,
      -0.18,
      0,
      3,
      -0.18,
      -0.18,
      1.35,
      0,
      3,
      0,
      0,
      0,
      1,
      0,
    ],
    ProcessingPreset.soft => const [
      0.92,
      0.04,
      0.04,
      0,
      8,
      0.04,
      0.92,
      0.04,
      0,
      8,
      0.04,
      0.04,
      0.92,
      0,
      8,
      0,
      0,
      0,
      1,
      0,
    ],
    ProcessingPreset.grayscale => const [
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
    ProcessingPreset.noir => const [
      0.32,
      1.08,
      0.11,
      0,
      -42,
      0.32,
      1.08,
      0.11,
      0,
      -42,
      0.32,
      1.08,
      0.11,
      0,
      -42,
      0,
      0,
      0,
      1,
      0,
    ],
    ProcessingPreset.balanced || ProcessingPreset.custom => const [
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
  };
}

enum _Adjustment {
  brightness,
  contrast,
  saturation,
  sharpness,
  highlights,
  shadows,
}

extension on _Adjustment {
  String get label => switch (this) {
    _Adjustment.brightness => 'Brightness',
    _Adjustment.contrast => 'Contrast',
    _Adjustment.saturation => 'Saturation',
    _Adjustment.sharpness => 'Sharpness',
    _Adjustment.highlights => 'Highlights',
    _Adjustment.shadows => 'Shadows',
  };

  String get svg => switch (this) {
    _Adjustment.brightness => EditorIconAssets.brightness,
    _Adjustment.contrast => EditorIconAssets.contrast,
    _Adjustment.saturation => EditorIconAssets.saturation,
    _Adjustment.sharpness => EditorIconAssets.sharpness,
    _Adjustment.highlights => EditorIconAssets.highlights,
    _Adjustment.shadows => EditorIconAssets.shadows,
  };

  IconData get fallback => switch (this) {
    _Adjustment.brightness => Icons.brightness_6_rounded,
    _Adjustment.contrast => Icons.contrast_rounded,
    _Adjustment.saturation => Icons.water_drop_outlined,
    _Adjustment.sharpness => Icons.change_history_rounded,
    _Adjustment.highlights => Icons.light_mode_outlined,
    _Adjustment.shadows => Icons.dark_mode_outlined,
  };

  double get min => switch (this) {
    _Adjustment.brightness => 0.5,
    _Adjustment.contrast => 0.5,
    _Adjustment.saturation => 0.0,
    _Adjustment.sharpness => 0.0,
    _Adjustment.highlights => 0.5,
    _Adjustment.shadows => 0.0,
  };

  double get max => switch (this) {
    _Adjustment.brightness => 2.0,
    _Adjustment.contrast => 2.0,
    _Adjustment.saturation => 2.0,
    _Adjustment.sharpness => 1.5,
    _Adjustment.highlights => 5.0,
    _Adjustment.shadows => 1.0,
  };

  double get step => switch (this) {
    _Adjustment.highlights => 0.05,
    _Adjustment.brightness ||
    _Adjustment.contrast ||
    _Adjustment.saturation ||
    _Adjustment.sharpness ||
    _Adjustment.shadows => 0.01,
  };
}

class _CompactChoice extends StatelessWidget {
  const _CompactChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EditorTheme.purple : EditorTheme.secondaryLabel;
    return EditorPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? EditorTheme.lavender
              : Colors.white.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? EditorTheme.purple.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.8),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon case final icon?) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransformTool extends StatelessWidget {
  const _TransformTool({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EditorTheme.purple : EditorTheme.secondaryLabel;
    return Expanded(
      child: EditorPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? EditorTheme.lavender
                    : Colors.white.withValues(alpha: 0.68),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? EditorTheme.purple
                      : Colors.white.withValues(alpha: 0.82),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 13,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: EditorPressable(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? EditorTheme.lavender
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? EditorTheme.purple.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.85),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? EditorTheme.purple : EditorTheme.secondaryLabel,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
