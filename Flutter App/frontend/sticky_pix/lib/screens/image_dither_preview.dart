import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../models/processed_image_result.dart';
import '../models/six_color_processing_settings.dart';
import '../product_viewer/product_3d_viewer.dart';
import '../product_viewer/product_model_config.dart';
import '../product_viewer/product_viewer_controller.dart';
import '../services/ble_image_client.dart';
import '../services/image_processor.dart';
import '../widgets/native_liquid_glass.dart';
import 'devices_screen.dart';
import 'editor/editor_screen.dart';

abstract final class _HomeTokens {
  static const canvas = Color(0xFF000000);
  static const surface = Color(0xF2FFFFFF);
  static const glassSurface = Color(0xD9FFFFFF);
  static const primaryText = Color(0xFF252429);
  static const secondaryText = Color(0xFF625D68);
  static const primaryViolet = Color(0xFF6040AC);
  static const pressedViolet = Color(0xFF4E2CA9);
  static const selectedViolet = Color(0xFFE9DEFA);
  static const violetBorder = Color(0xFFB5A2E4);
  static const divider = Color(0x1A231E2A);
  static const success = Color(0xFF2E8B57);
  static const disconnected = Color(0xFF8A8790);
  static const error = Color(0xFFB42335);
}

enum _PrimaryDestination { me, library, home, messages, devices }

class ImageDitherPreview extends StatefulWidget {
  const ImageDitherPreview({super.key, this.viewer});

  final Widget? viewer;

  @override
  State<ImageDitherPreview> createState() => _ImageDitherPreviewState();
}

class _ImageDitherPreviewState extends State<ImageDitherPreview> {
  final ProductViewerController _productViewerController =
      ProductViewerController();
  File? _original;
  Uint8List? _previewPng;
  Uint8List? _binary;
  ImageProcessingMode _mode = ImageProcessingMode.fourGray;
  SixColorProcessingSettings _sixColorSettings =
      SixColorProcessingSettings.forPreset(ProcessingPreset.balanced);
  int _sixColorRotationQuarterTurns = 0;
  SixColorOrientation _sixColorOrientation = SixColorOrientation.portrait;
  // 4 Gray has its own editable treatment so switching display modes never
  // overwrites a user's six-color composition.
  SixColorProcessingSettings _fourGraySettings =
      SixColorProcessingSettings.forPreset(ProcessingPreset.grayscale);
  int _fourGrayRotationQuarterTurns = 0;
  bool _busy = false;
  bool _showingBack = false;
  int _progress = 0;
  _PrimaryDestination _selectedDestination = _PrimaryDestination.home;
  int? _batteryLevel;
  String? _lastDeviceName;
  // The product currently shown on Home. This is intentionally separate from
  // the live BLE peripheral name: choosing a home device does not imply it is
  // connected over Bluetooth.
  String _homeDeviceName = 'Bedroom';
  DateTime? _lastUpdated;
  bool _showRotateHint = true;
  bool _devicesRouteOpen = false;
  Timer? _rotateHintTimer;
  late final NativeHomeOverlayController _nativeHomeOverlay;

  @override
  void initState() {
    super.initState();
    _nativeHomeOverlay = NativeHomeOverlayController(
      onAction: _handleNativeOverlayAction,
    );
    _rotateHintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showRotateHint = false);
    });
  }

  @override
  void dispose() {
    _rotateHintTimer?.cancel();
    unawaited(_nativeHomeOverlay.dispose());
    super.dispose();
  }

  Future<void> _handleNativeOverlayAction(
    String action,
    Map<String, Object?> arguments,
  ) async {
    if (!mounted) return;
    if (action == 'send') {
      await _nativeHomeOverlay.hide();
      try {
        await _selectAndSend();
      } finally {
        if (mounted) setState(() {});
      }
      return;
    }
    if (action == 'destination') {
      final name = arguments['destination'] as String?;
      final destination = _PrimaryDestination.values
          .where((value) => value.name == name)
          .firstOrNull;
      if (destination != null) {
        _onPrimaryDestinationSelected(destination);
      }
      return;
    }
    if (action == 'mode') {
      final mode = arguments['mode'] as String?;
      if (mode == 'fourGray') {
        await _setMode(ImageProcessingMode.fourGray);
      } else if (mode == 'sixColor') {
        await _setMode(ImageProcessingMode.sixColor);
      }
      return;
    }
    if (action == 'edit') {
      await _editSixColorSettings();
      return;
    }
    if (action == 'pick') {
      await _pickImage();
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;

    _sixColorSettings = _sixColorSettings.copyWith(
      viewportScale: 1,
      viewportOffsetX: 0,
      viewportOffsetY: 0,
    );
    _sixColorRotationQuarterTurns = 0;
    _fourGraySettings = _fourGraySettings.copyWith(
      viewportScale: 1,
      viewportOffsetX: 0,
      viewportOffsetY: 0,
    );
    _fourGrayRotationQuarterTurns = 0;
    await _processImage(File(x.path));
  }

  Future<void> _processImage(File file) async {
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final ProcessedImageResult r = await processImageAndGeneratePreview(
        bytes,
        mode: _mode,
        sixColorSettings: _mode == ImageProcessingMode.sixColor
            ? _sixColorSettings
            : _fourGraySettings,
        sixColorRotationQuarterTurns: _mode == ImageProcessingMode.sixColor
            ? _sixColorRotationQuarterTurns
            : _fourGrayRotationQuarterTurns,
        sixColorOrientation: _sixColorOrientation,
      );
      setState(() {
        _original = file;
        _previewPng = r.previewPng;
        _binary = r.binaryPacked;
      });
      await _productViewerController.setLandscape(
        _mode == ImageProcessingMode.sixColor &&
            _sixColorOrientation == SixColorOrientation.landscape,
      );
      await _productViewerController.setDisplayTexture(r.displayTexturePng);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image processing failed: $e'),
            backgroundColor: _HomeTokens.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSixColorSettings() async {
    if (_original == null || _busy) return;

    await _nativeHomeOverlay.hide();
    if (_showingBack) setState(() => _showingBack = false);
    await _productViewerController.focusDisplay();
    final imageBytes = await _original!.readAsBytes();
    if (!mounted) return;
    try {
      final updated = await Navigator.push<SixColorEditResult>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => EInkEditorScreen(
            imageBytes: imageBytes,
            initialPreviewPng: _previewPng,
            processingMode: _mode,
            initialSettings: _mode == ImageProcessingMode.sixColor
                ? _sixColorSettings
                : _fourGraySettings,
            initialRotationQuarterTurns: _mode == ImageProcessingMode.sixColor
                ? _sixColorRotationQuarterTurns
                : _fourGrayRotationQuarterTurns,
            initialOrientation: _mode == ImageProcessingMode.sixColor
                ? _sixColorOrientation
                : SixColorOrientation.landscape,
          ),
        ),
      );
      if (updated == null || !mounted) return;

      setState(() {
        if (_mode == ImageProcessingMode.sixColor) {
          _sixColorSettings = updated.settings;
          _sixColorRotationQuarterTurns = updated.rotationQuarterTurns;
          _sixColorOrientation = updated.orientation;
        } else {
          _fourGraySettings = updated.settings;
          _fourGrayRotationQuarterTurns = updated.rotationQuarterTurns;
        }
      });
      await _processImage(_original!);
    } finally {
      await _productViewerController.showOverview();
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleProductSide() async {
    if (_busy) return;
    final showBack = !_showingBack;
    setState(() => _showingBack = showBack);
    if (showBack) {
      await _productViewerController.showBack();
    } else {
      await _productViewerController.showOverview();
    }
  }

  Future<void> _setMode(ImageProcessingMode mode) async {
    if (_mode == mode || _busy) return;

    HapticFeedback.selectionClick();
    setState(() {
      _mode = mode;
      _progress = 0;
      _batteryLevel = null;
    });

    final original = _original;
    if (original != null) {
      await _processImage(original);
    }
  }

  Future<void> _selectAndSend() async {
    if (_binary == null) return;

    setState(() {
      _progress = 0;
      _batteryLevel = null;
    });

    final devices = await BleImageClient.scanOpen(
      timeout: const Duration(seconds: 2),
    );

    if (!mounted) return;
    final chosen = await showDialog<ScanResult>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select Device'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: ListView(
            children: devices.map((r) {
              final name = r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : (r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : '(Unnamed)');
              return ListTile(
                title: Text(name),
                subtitle: Text(r.device.remoteId.str),
                trailing: Text('${r.rssi} dBm'),
                onTap: () => Navigator.pop(context, r),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (chosen == null) return;

    try {
      if (!mounted) return;
      setState(() {
        _busy = true;
        _lastDeviceName = _deviceName(chosen);
      });

      // Send the full image (size + data)
      await BleImageClient.sendImage(
        device: chosen.device,
        image: _binary!,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onBatteryLevel: (l) {
          if (mounted) setState(() => _batteryLevel = l);
        },
      );

      if (mounted) {
        setState(() => _lastUpdated = DateTime.now());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Image sent successfully: ${_binary!.length} bytes',
            ),
            backgroundColor: Colors.green,
          ),
        );
        await SemanticsService.sendAnnouncement(
          View.of(context),
          'Image sent successfully',
          TextDirection.ltr,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ BLE error: $e'),
            backgroundColor: _HomeTokens.error,
          ),
        );
        await SemanticsService.sendAnnouncement(
          View.of(context),
          'Image transfer failed',
          TextDirection.ltr,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectAndReadBattery() async {
    setState(() => _batteryLevel = null);

    final devices = await BleImageClient.scanOpen(
      timeout: const Duration(seconds: 2),
    );

    if (!mounted) return;
    final chosen = await showDialog<ScanResult>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select Device'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: ListView(
            children: devices.map((r) {
              final name = r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : (r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : '(Unnamed)');
              return ListTile(
                title: Text(name),
                subtitle: Text(r.device.remoteId.str),
                trailing: Text('${r.rssi} dBm'),
                onTap: () => Navigator.pop(context, r),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (chosen == null) return;

    try {
      if (!mounted) return;
      setState(() {
        _busy = true;
        _lastDeviceName = _deviceName(chosen);
      });

      final level = await BleImageClient.readBatteryLevel(chosen.device);

      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _lastUpdated = DateTime.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Battery: $level%'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Battery read failed: $e'),
            backgroundColor: _HomeTokens.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unpairDevice() async {
    setState(() => _busy = true);
    try {
      final devices = await BleImageClient.scanOpen(
        timeout: const Duration(seconds: 2),
      );

      if (!mounted) return;
      final chosen = await showDialog<ScanResult>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Select Device to Unpair'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView(
              children: devices.map((r) {
                final name = r.advertisementData.advName.isNotEmpty
                    ? r.advertisementData.advName
                    : (r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : '(Unnamed)');
                return ListTile(
                  title: Text(name),
                  subtitle: Text(r.device.remoteId.str),
                  trailing: Text('${r.rssi} dBm'),
                  onTap: () => Navigator.pop(context, r),
                );
              }).toList(),
            ),
          ),
        ),
      );

      if (chosen == null) return;

      await BleImageClient.unpairDevice(chosen.device);

      if (mounted) {
        setState(() {
          _lastDeviceName = null;
          _lastUpdated = null;
          _batteryLevel = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Unpair command sent'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Unpair failed: $e'),
            backgroundColor: _HomeTokens.error,
          ),
        );
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  String _deviceName(ScanResult result) {
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    }
    return 'StickyPix';
  }

  String get _lastUpdatedText {
    final updated = _lastUpdated;
    if (updated == null) return 'Not synced yet';
    final minutes = DateTime.now().difference(updated).inMinutes;
    if (minutes < 1) return 'Updated just now';
    return 'Last updated $minutes min ago';
  }

  Future<void> _showDeviceActions() async {
    await _nativeHomeOverlay.hide();
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.battery_5_bar),
              title: const Text('Get battery level'),
              onTap: () => Navigator.pop(context, 'battery'),
            ),
            ListTile(
              leading: const Icon(Icons.flip_camera_android),
              title: Text(_showingBack ? 'Show front' : 'Show back'),
              onTap: () => Navigator.pop(context, 'side'),
            ),
            ListTile(
              leading: Icon(Icons.link_off, color: Colors.red.shade700),
              title: Text(
                'Unpair device',
                style: TextStyle(color: Colors.red.shade700),
              ),
              onTap: () => Navigator.pop(context, 'unpair'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (action == 'battery') {
      await _selectAndReadBattery();
    } else if (action == 'side') {
      await _toggleProductSide();
    } else if (action == 'unpair') {
      await _unpairDevice();
    }
  }

  void _onPrimaryDestinationSelected(_PrimaryDestination destination) {
    setState(() => _selectedDestination = destination);
    if (destination == _PrimaryDestination.home) return;
    if (destination == _PrimaryDestination.devices) {
      unawaited(_openDevices());
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${destination.name} is coming soon.')),
    );
  }

  Future<void> _openDevices() async {
    // The Liquid Glass overlay is a native sibling above Flutter. Mark this
    // route inactive before hiding it so no pending home-frame callback can
    // re-show the overlay over the Devices page.
    if (mounted) setState(() => _devicesRouteOpen = true);
    await _nativeHomeOverlay.hide();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DevicesScreen(
          latestPreviewPng: _previewPng,
          homeDeviceName: _homeDeviceName,
          onHomeDeviceCustomized: _applyHomeDeviceCustomization,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _devicesRouteOpen = false;
        _selectedDestination = _PrimaryDestination.home;
      });
    }
  }

  void _applyHomeDeviceCustomization(StickyPixDevice device) {
    setState(() => _homeDeviceName = device.name);
    unawaited(
      Future.wait([
        _productViewerController.setPartColor(
          ProductPart.backShell,
          device.rearShellColor,
        ),
        _productViewerController.setPartColor(
          ProductPart.enclosure,
          device.cardstockColor,
        ),
        _productViewerController.setPartColor(
          ProductPart.bezel,
          device.bezelColor,
        ),
        _productViewerController.setPartColor(
          ProductPart.kickstand,
          device.kickstandColor,
        ),
      ]),
    );
  }

  void _scheduleNativeHomeOverlay({
    required bool compact,
    required bool canSend,
    required String preset,
    required String fileSize,
    required String status,
    required bool canEdit,
    required String imageLabel,
  }) {
    if (!NativeHomeOverlayController.isSupported || _devicesRouteOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _devicesRouteOpen) return;
      unawaited(
        _nativeHomeOverlay.show(
          NativeHomeOverlayState(
            preset: preset,
            fileSize: fileSize,
            deviceName: _homeDeviceName,
            status: status,
            isReady: _lastDeviceName != null,
            batteryLevel: _batteryLevel,
            lastUpdated: _lastUpdatedText,
            canSend: canSend,
            progress: _progress,
            selectedDestination: _selectedDestination.name,
            mode: _mode == ImageProcessingMode.fourGray
                ? 'fourGray'
                : 'sixColor',
            canEdit: canEdit,
            canPick: !_busy,
            imageLabel: imageLabel,
            compact: compact,
            previewPng: _previewPng,
          ),
        ),
      );
    });
  }

  Widget _hideBehindNativeOverlay(Widget child) {
    if (!NativeHomeOverlayController.isSupported) return child;
    return IgnorePointer(
      ignoring: true,
      child: Opacity(opacity: 0, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _binary != null && !_busy;
    final fileSizeKb = _binary == null
        ? '—'
        : '${(_binary!.length / 1024).round()} KB';
    final presetName = _mode == ImageProcessingMode.sixColor
        ? _sixColorSettings.preset.label
        : '4 Gray';
    final deviceStatus = _busy
        ? 'Connecting'
        : _lastDeviceName == null
        ? 'Not connected'
        : 'Ready';
    final canEdit = !_busy && _original != null;
    final imageLabel = _original == null ? 'Pick Image' : 'Replace';
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: _HomeTokens.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _HomeTokens.canvas),
          widget.viewer ??
              Product3dViewer(
                controller: _productViewerController,
                showGestureHint: false,
                borderRadius: 0,
                yawOnly: true,
                allowZoom: false,
                allowPan: false,
              ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xE6000000),
                    Color(0x80000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xB8000000),
                    Color(0xF2000000),
                  ],
                  stops: [0, 0.18, 0.32, 0.58, 0.74, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeight = MediaQuery.sizeOf(context).height < 760;
                _scheduleNativeHomeOverlay(
                  compact: compactHeight,
                  canSend: canSend,
                  preset: presetName,
                  fileSize: fileSizeKb,
                  status: deviceStatus,
                  canEdit: canEdit,
                  imageLabel: imageLabel,
                );
                final horizontalMargin = constraints.maxWidth < 360
                    ? 12.0
                    : 16.0;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalMargin,
                    compactHeight ? 0 : 4,
                    horizontalMargin,
                    compactHeight ? 2 : 4,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: compactHeight ? 36 : 40,
                        child: const Center(
                          child: Text(
                            'E-Ink Preview Processor',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.25,
                            ),
                          ),
                        ),
                      ),
                      _hideBehindNativeOverlay(
                        _ProcessingModeSelector(
                          mode: _mode,
                          enabled: !_busy,
                          onChanged: _setMode,
                        ),
                      ),
                      SizedBox(height: compactHeight ? 6 : 8),
                      _hideBehindNativeOverlay(
                        _JoinedImageActions(
                          canEdit: canEdit,
                          canPick: !_busy,
                          imageLabel: imageLabel,
                          onEdit: _editSixColorSettings,
                          onPick: _pickImage,
                        ),
                      ),
                      SizedBox(
                        height: compactHeight ? 18 : 20,
                        child: _busy ? const _ImageProcessingProgress() : null,
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _showRotateHint ? 1 : 0,
                              duration: disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 280),
                              child: const _RotateHint(),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: math.min(
                            353.0,
                            constraints.maxWidth - horizontalMargin * 2 - 8,
                          ),
                          height: compactHeight ? 59 : 61,
                          child: _hideBehindNativeOverlay(
                            _OverlayPanel(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 5,
                              ),
                              borderRadius: 13,
                              child: _ProcessingSummary(
                                preset: presetName,
                                fileSize: fileSizeKb,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compactHeight ? 8 : 10),
                      SizedBox(
                        height: 98,
                        child: _hideBehindNativeOverlay(
                          _UnifiedDeviceDock(
                            previewPng: _previewPng,
                            deviceName: _homeDeviceName,
                            status: deviceStatus,
                            isReady: _lastDeviceName != null,
                            batteryLevel: _batteryLevel,
                            lastUpdated: _lastUpdatedText,
                            canSend: canSend,
                            progress: _progress,
                            onSend: _selectAndSend,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 72,
                        child: _hideBehindNativeOverlay(
                          _FloatingPrimaryNavigationBar(
                            selectedDestination: _selectedDestination,
                            onDestinationSelected:
                                _onPrimaryDestinationSelected,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessingModeSelector extends StatelessWidget {
  const _ProcessingModeSelector({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final ImageProcessingMode mode;
  final bool enabled;
  final ValueChanged<ImageProcessingMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Image processing mode',
      child: SizedBox(
        width: math.min(239.0, MediaQuery.sizeOf(context).width - 32),
        height: 44,
        child: Center(
          child: Container(
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _HomeTokens.glassSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
            ),
            child: Row(
              children: [
                _ModeSegment(
                  icon: Icons.contrast_rounded,
                  label: '4 Gray',
                  selected: mode == ImageProcessingMode.fourGray,
                  enabled: enabled,
                  onTap: () => onChanged(ImageProcessingMode.fourGray),
                ),
                _ModeSegment(
                  icon: Icons.palette_outlined,
                  label: '6 Color',
                  selected: mode == ImageProcessingMode.sixColor,
                  enabled: enabled,
                  onTap: () => onChanged(ImageProcessingMode.sixColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: label,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: enabled ? onTap : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: selected
                      ? _HomeTokens.selectedViolet
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 17, color: _HomeTokens.primaryViolet),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            color: _HomeTokens.primaryText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinedImageActions extends StatelessWidget {
  const _JoinedImageActions({
    required this.canEdit,
    required this.canPick,
    required this.imageLabel,
    required this.onEdit,
    required this.onPick,
  });

  final bool canEdit;
  final bool canPick;
  final String imageLabel;
  final VoidCallback onEdit;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 211,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            top: 2.5,
            bottom: 2.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _HomeTokens.glassSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F201730),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _JoinedAction(
                  icon: Icons.tune_rounded,
                  label: 'Edit',
                  enabled: canEdit,
                  onTap: onEdit,
                ),
              ),
              const SizedBox(
                height: 25,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: _HomeTokens.divider,
                ),
              ),
              Expanded(
                child: _JoinedAction(
                  icon: Icons.photo_library_outlined,
                  label: imageLabel,
                  enabled: canPick,
                  onTap: onPick,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JoinedAction extends StatelessWidget {
  const _JoinedAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _HomeTokens.primaryViolet, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _HomeTokens.primaryViolet,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageProcessingProgress extends StatelessWidget {
  const _ImageProcessingProgress();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Processing image…',
          style: TextStyle(color: _HomeTokens.secondaryText, fontSize: 11),
        ),
        SizedBox(height: 2),
        SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            color: _HomeTokens.primaryViolet,
            backgroundColor: _HomeTokens.selectedViolet,
          ),
        ),
      ],
    );
  }
}

class _RotateHint extends StatelessWidget {
  const _RotateHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _HomeTokens.canvas.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.arrow_back_rounded,
            size: 18,
            color: _HomeTokens.secondaryText,
          ),
          SizedBox(width: 8),
          Text(
            'Drag to rotate',
            style: TextStyle(
              color: _HomeTokens.secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 8),
          Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: _HomeTokens.secondaryText,
          ),
        ],
      ),
    );
  }
}

class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.borderRadius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _HomeTokens.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.88),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F201730),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _ProcessingSummary extends StatelessWidget {
  const _ProcessingSummary({required this.preset, required this.fileSize});

  final String preset;
  final String fileSize;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _SummaryItem(
              icon: Icons.show_chart,
              value: preset,
              label: 'Dithering',
            ),
          ),
          const VerticalDivider(width: 1),
          const Expanded(
            child: _SummaryItem(
              icon: Icons.crop,
              value: '400 × 600',
              label: 'Resolution',
            ),
          ),
          const VerticalDivider(width: 1),
          const Expanded(
            child: _SummaryItem(
              icon: Icons.apps,
              value: '180 PPI',
              label: 'Display',
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _SummaryItem(
              icon: Icons.insert_drive_file_outlined,
              value: fileSize,
              label: 'File Size',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _HomeTokens.primaryViolet, size: 17),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: _HomeTokens.primaryText,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: _HomeTokens.secondaryText,
                fontSize: 10.5,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedDeviceDock extends StatelessWidget {
  const _UnifiedDeviceDock({
    required this.previewPng,
    required this.deviceName,
    required this.status,
    required this.isReady,
    required this.batteryLevel,
    required this.lastUpdated,
    required this.canSend,
    required this.progress,
    required this.onSend,
  });

  final Uint8List? previewPng;
  final String deviceName;
  final String status;
  final bool isReady;
  final int? batteryLevel;
  final String lastUpdated;
  final bool canSend;
  final int progress;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final showProgress = progress > 0 && progress < 100;
    return _OverlayPanel(
      padding: EdgeInsets.zero,
      borderRadius: 20,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: _DeviceTransferCard(
                previewPng: previewPng,
                deviceName: deviceName,
                status: status,
                isReady: isReady,
                batteryLevel: batteryLevel,
                lastUpdated: lastUpdated,
                canSend: canSend,
                progress: progress,
                onSend: onSend,
              ),
            ),
          ),
          SizedBox(
            height: 6,
            child: showProgress
                ? Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      widthFactor: 0.82,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value: progress / 100,
                          color: _HomeTokens.primaryViolet,
                          backgroundColor: _HomeTokens.violetBorder,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _DeviceTransferCard extends StatelessWidget {
  const _DeviceTransferCard({
    required this.previewPng,
    required this.deviceName,
    required this.status,
    required this.isReady,
    required this.batteryLevel,
    required this.lastUpdated,
    required this.canSend,
    required this.progress,
    required this.onSend,
  });

  final Uint8List? previewPng;
  final String deviceName;
  final String status;
  final bool isReady;
  final int? batteryLevel;
  final String lastUpdated;
  final bool canSend;
  final int progress;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 310;
        final thumbnailSize = compact ? 62.0 : 71.0;
        final sendSize = compact ? 64.0 : 72.0;
        final itemGap = compact ? 7.0 : 12.0;
        final statusColor = status == 'Connecting'
            ? _HomeTokens.primaryViolet
            : isReady
            ? _HomeTokens.success
            : _HomeTokens.disconnected;
        return Row(
          children: [
            Container(
              width: thumbnailSize,
              height: thumbnailSize,
              padding: EdgeInsets.all(compact ? 6 : 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white),
              ),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9E9E9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFD0D0D0),
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: previewPng == null
                          ? const Center(
                              child: Text(
                                'sticky pix',
                                style: TextStyle(
                                  color: Color(0x806E4FC4),
                                  fontSize: 6.5,
                                ),
                              ),
                            )
                          : Image.memory(previewPng!, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: itemGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _HomeTokens.primaryText,
                            fontSize: compact ? 17 : 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _HomeTokens.selectedViolet,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _HomeTokens.primaryViolet,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.bluetooth,
                        color: _HomeTokens.primaryViolet,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.battery_5_bar,
                        color: _HomeTokens.primaryText,
                        size: 18,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        batteryLevel == null ? '—' : '$batteryLevel%',
                        style: const TextStyle(
                          color: _HomeTokens.primaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    lastUpdated,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _HomeTokens.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 4 : 8),
            _SendButton(
              enabled: canSend,
              progress: progress,
              size: sendSize,
              onTap: onSend,
            ),
          ],
        );
      },
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.progress,
    required this.size,
    required this.onTap,
  });

  final bool enabled;
  final int progress;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final transferring = progress > 0 && progress < 100;
    return Semantics(
      button: true,
      enabled: enabled,
      label: transferring ? 'Sending image, $progress percent' : 'Send image',
      child: Opacity(
        opacity: enabled || transferring ? 1 : 0.38,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: Ink(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_HomeTokens.primaryViolet, _HomeTokens.pressedViolet],
              ),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (transferring)
                    SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        value: progress / 100,
                        strokeWidth: 2.5,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    )
                  else
                    const Icon(
                      Icons.send_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  const SizedBox(height: 1),
                  Text(
                    transferring ? '$progress%' : 'Send',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingPrimaryNavigationBar extends StatelessWidget {
  const _FloatingPrimaryNavigationBar({
    required this.selectedDestination,
    required this.onDestinationSelected,
  });

  final _PrimaryDestination selectedDestination;
  final ValueChanged<_PrimaryDestination> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xEB1C1C1E) : const Color(0xF5FFFFFF);
    final border = isDark ? const Color(0x14FFFFFF) : const Color(0x99FFFFFF);
    final shadow = isDark ? const Color(0x73000000) : const Color(0x1A000000);
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: shadow,
                blurRadius: isDark ? 24 : 30,
                offset: Offset(0, isDark ? 8 : 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _PrimaryNavigationItem(
                destination: _PrimaryDestination.me,
                icon: Icons.person_outline_rounded,
                label: 'Me',
                selected: selectedDestination == _PrimaryDestination.me,
                onTap: onDestinationSelected,
              ),
              _PrimaryNavigationItem(
                destination: _PrimaryDestination.library,
                icon: Icons.photo_library_outlined,
                label: 'Library',
                selected: selectedDestination == _PrimaryDestination.library,
                onTap: onDestinationSelected,
              ),
              _PrimaryNavigationItem(
                destination: _PrimaryDestination.home,
                icon: Icons.home_rounded,
                label: 'Home',
                selected: selectedDestination == _PrimaryDestination.home,
                isHome: true,
                onTap: onDestinationSelected,
              ),
              _PrimaryNavigationItem(
                destination: _PrimaryDestination.messages,
                icon: Icons.forum_outlined,
                label: 'Messages',
                selected: selectedDestination == _PrimaryDestination.messages,
                onTap: onDestinationSelected,
              ),
              _PrimaryNavigationItem(
                destination: _PrimaryDestination.devices,
                icon: Icons.settings_input_antenna_rounded,
                label: 'Devices',
                selected: selectedDestination == _PrimaryDestination.devices,
                onTap: onDestinationSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryNavigationItem extends StatelessWidget {
  const _PrimaryNavigationItem({
    required this.destination,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.isHome = false,
  });

  final _PrimaryDestination destination;
  final IconData icon;
  final String label;
  final bool selected;
  final bool isHome;
  final ValueChanged<_PrimaryDestination> onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = isDark ? Colors.white : Colors.black;
    final inactiveColor = isDark
        ? const Color(0xFF9B9BA2)
        : _HomeTokens.secondaryText;
    final color = selected ? selectedColor : inactiveColor;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => onTap(destination),
          child: SizedBox(
            height: 72,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: selected ? const Offset(0, -0.035) : Offset.zero,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                scale: selected ? 1.08 : 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: selected && isHome ? 28 : 24,
                      height: selected && isHome ? 28 : 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected && isHome
                            ? _HomeTokens.selectedViolet.withValues(alpha: 0.42)
                            : Colors.transparent,
                      ),
                      child: Icon(
                        icon,
                        color: color,
                        size: selected ? (isHome ? 22 : 21) : 20,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, maxLines: 1),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.only(top: 2),
                      width: selected ? 14 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        color: selected
                            ? _HomeTokens.primaryViolet
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
