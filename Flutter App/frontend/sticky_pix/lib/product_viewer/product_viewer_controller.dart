import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'product_3d_viewer.dart';
import 'product_model_config.dart';

class ProductViewerController {
  Product3dViewerState? _state;
  Uint8List? _pendingDisplayTexture;
  final Map<ProductPart, Color> _pendingPartColors = {};
  bool _isLandscape = false;

  bool get isAttached => _state != null;

  void attach(Product3dViewerState state) {
    _state = state;
    state.setLandscape(_isLandscape);
    final pending = _pendingDisplayTexture;
    if (pending != null) {
      state.setDisplayTexture(pending);
    }
    for (final entry in _pendingPartColors.entries) {
      state.setPartColor(entry.key, entry.value);
    }
  }

  void detach(Product3dViewerState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  Future<void> setDisplayTexture(Uint8List encodedImage) async {
    _pendingDisplayTexture = Uint8List.fromList(encodedImage);
    await _state?.setDisplayTexture(_pendingDisplayTexture!);
  }

  /// Turns the physical product to match the editor orientation. The model is
  /// rotated counter-clockwise so the clockwise-rotated portrait panel buffer
  /// remains visually upright when viewed as a landscape device.
  Future<void> setLandscape(bool isLandscape) async {
    _isLandscape = isLandscape;
    await _state?.setLandscape(isLandscape);
  }

  Future<void> focusDisplay() async {
    await _state?.animateToDisplay();
  }

  Future<void> showOverview() async {
    await _state?.animateToOverview();
  }

  Future<void> showBack() async {
    await _state?.animateToBack();
  }

  Future<void> setPartColor(ProductPart part, Color color) async {
    _pendingPartColors[part] = color;
    await _state?.setPartColor(part, color);
  }
}
