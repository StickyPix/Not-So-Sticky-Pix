import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef NativeHomeOverlayAction =
    Future<void> Function(String action, Map<String, Object?> arguments);

/// Live state rendered by the native iOS home overlay.
class NativeHomeOverlayState {
  const NativeHomeOverlayState({
    required this.preset,
    required this.fileSize,
    required this.deviceName,
    required this.status,
    required this.isReady,
    required this.batteryLevel,
    required this.lastUpdated,
    required this.canSend,
    required this.progress,
    required this.selectedDestination,
    required this.mode,
    required this.canEdit,
    required this.canPick,
    required this.imageLabel,
    required this.compact,
    this.previewPng,
  });

  final String preset;
  final String fileSize;
  final String deviceName;
  final String status;
  final bool isReady;
  final int? batteryLevel;
  final String lastUpdated;
  final bool canSend;
  final int progress;
  final String selectedDestination;
  final String mode;
  final bool canEdit;
  final bool canPick;
  final String imageLabel;
  final bool compact;
  final Uint8List? previewPng;

  Map<String, Object?> toMap() => <String, Object?>{
    'preset': preset,
    'fileSize': fileSize,
    'deviceName': deviceName,
    'status': status,
    'isReady': isReady,
    'batteryLevel': batteryLevel,
    'lastUpdated': lastUpdated,
    'canSend': canSend,
    'progress': progress,
    'selectedDestination': selectedDestination,
    'mode': mode,
    'canEdit': canEdit,
    'canPick': canPick,
    'imageLabel': imageLabel,
    'compact': compact,
    'previewPng': previewPng,
  };
}

/// Controls the root-level SwiftUI Liquid Glass overlay on iOS.
///
/// The native overlay is a sibling above Flutter's view rather than an
/// embedded platform view. That gives Liquid Glass access to the rendered
/// Flutter/3D scene behind it. Android keeps rendering the existing Flutter UI.
class NativeHomeOverlayController {
  NativeHomeOverlayController({required NativeHomeOverlayAction onAction})
    : _onAction = onAction {
    if (isSupported) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  static const _channel = MethodChannel(
    'stickypix/native_liquid_glass_overlay',
  );

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  NativeHomeOverlayAction? _onAction;
  bool _visible = false;

  Future<void> show(NativeHomeOverlayState state) async {
    if (!isSupported) return;
    _visible = true;
    await _channel.invokeMethod<void>('show', state.toMap());
  }

  Future<void> hide() async {
    if (!isSupported || !_visible) return;
    _visible = false;
    await _channel.invokeMethod<void>('hide');
  }

  Future<void> dispose() async {
    await hide();
    _onAction = null;
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'action') return null;
    final raw = call.arguments;
    final arguments = raw is Map
        ? raw.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, Object?>{};
    final action = arguments['action'] as String?;
    if (action != null) {
      await _onAction?.call(action, arguments);
    }
    return null;
  }
}
