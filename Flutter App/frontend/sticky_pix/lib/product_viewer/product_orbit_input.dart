import 'dart:math' as math;

import 'package:thermion_flutter/thermion_flutter.dart';

/// Product-page camera controls with optional vertical-axis-only rotation.
class ProductOrbitInputDelegate extends InputHandlerDelegate {
  ProductOrbitInputDelegate(
    this.view, {
    this.minimumDistance = 0.65,
    this.maximumDistance = 12,
    this.rotationSensitivity = 0.0045,
    this.panSensitivity = 0.0018,
    this.yawOnly = false,
    this.allowZoom = true,
    this.allowPan = true,
  });

  final View view;
  final double minimumDistance;
  final double maximumDistance;
  final double rotationSensitivity;
  final double panSensitivity;
  final bool yawOnly;
  final bool allowZoom;
  final bool allowPan;

  Vector3 target = Vector3.zero();
  Vector3 up = Vector3(0, 1, 0);
  double _radius = 4;
  double _gestureScale = 1;
  double _azimuth = 0;
  double _elevation = 0;
  bool _initialized = false;

  void resync({required Vector3 target, Vector3? up}) {
    this.target = target.clone();
    if (up != null) this.up = up.clone();
    _initialized = false;
    _gestureScale = 1;
  }

  Future<void> _initialize(Camera camera) async {
    final position = await camera.getPosition();
    final offset = position - target;
    _radius = offset.length.clamp(minimumDistance, maximumDistance);
    if (_radius <= 0.001) {
      _radius = minimumDistance;
      _azimuth = 0;
      _elevation = 0;
    } else {
      final normalized = offset.normalized();
      _elevation = math
          .asin(normalized.y)
          .clamp(-math.pi / 2 + 0.03, math.pi / 2 - 0.03);
      _azimuth = math.atan2(normalized.x, normalized.z);
    }
    _initialized = true;
  }

  @override
  Future<void> handle(List<InputEvent> events) async {
    final camera = await view.getCamera();
    if (!_initialized) await _initialize(camera);

    var changed = false;
    for (final event in events) {
      switch (event) {
        case ScaleUpdateEvent(
          numPointers: final pointerCount,
          scale: final scale,
          localFocalPointDelta: final focalDelta,
        ):
          if (pointerCount == 1 && focalDelta != null) {
            _azimuth -= focalDelta.$1 * rotationSensitivity;
            if (!yawOnly) {
              _elevation -= focalDelta.$2 * rotationSensitivity;
            }
            changed = focalDelta.$1 != 0 || (!yawOnly && focalDelta.$2 != 0);
          } else if (pointerCount >= 2) {
            if (allowZoom) {
              _gestureScale = 1 / scale;
              changed = true;
            }
            if (allowPan && focalDelta != null) {
              await _pan(camera, focalDelta.$1, focalDelta.$2);
              changed = true;
            }
          }
        case ScaleEndEvent():
          if (allowZoom) {
            _radius = (_radius * _gestureScale).clamp(
              minimumDistance,
              maximumDistance,
            );
            changed = true;
          }
          _gestureScale = 1;
        case ScrollEvent(delta: final delta):
          if (allowZoom) {
            _radius = (_radius + delta * 0.01).clamp(
              minimumDistance,
              maximumDistance,
            );
            changed = true;
          }
        default:
          break;
      }
    }

    if (!changed) return;
    _elevation = _elevation.clamp(-math.pi / 2 + 0.03, math.pi / 2 - 0.03);
    _azimuth %= 2 * math.pi;
    final radius = (_radius * _gestureScale).clamp(
      minimumDistance,
      maximumDistance,
    );
    final position =
        target +
        Vector3(
          radius * math.cos(_elevation) * math.sin(_azimuth),
          radius * math.sin(_elevation),
          radius * math.cos(_elevation) * math.cos(_azimuth),
        );
    await camera.lookAt(position, focus: target, up: up);
  }

  Future<void> _pan(Camera camera, double dx, double dy) async {
    final model = await camera.getModelMatrix();
    final right = Vector3(
      model.entry(0, 0),
      model.entry(1, 0),
      model.entry(2, 0),
    );
    final up = Vector3(model.entry(0, 1), model.entry(1, 1), model.entry(2, 1));
    final scale = _radius * panSensitivity;
    target -= right * (dx * scale);
    target += up * (dy * scale);
  }
}
