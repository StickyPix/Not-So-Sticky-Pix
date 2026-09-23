import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('studio IBL is a bundled KTX 1 environment', () async {
    final asset = await rootBundle.load(
      'assets/environment/default_env_ibl.ktx',
    );
    final bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    expect(bytes.length, greaterThan(100000));
    expect(
      bytes.sublist(0, 12),
      Uint8List.fromList([
        0xAB,
        0x4B,
        0x54,
        0x58,
        0x20,
        0x31,
        0x31,
        0xBB,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]),
    );
  });
}
