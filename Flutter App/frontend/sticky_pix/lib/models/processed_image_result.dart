import 'dart:typed_data';

class ProcessedImageResult {
  final Uint8List previewPng;
  final Uint8List binaryPacked;

  /// The exact image orientation represented by [binaryPacked].
  ///
  /// Landscape editor previews are shown as 600 × 400, but the physical panel
  /// always receives a portrait 400 × 600 buffer. Keeping this separately lets
  /// the 3D product preview mirror what is actually sent to the device.
  final Uint8List displayTexturePng;

  ProcessedImageResult(
    this.previewPng,
    this.binaryPacked, {
    Uint8List? displayTexturePng,
  }) : displayTexturePng = displayTexturePng ?? previewPng;
}
