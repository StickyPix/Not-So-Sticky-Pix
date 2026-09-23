import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_pix/product_viewer/product_model_config.dart';

void main() {
  test('four-inch model exposes independently configurable product parts', () {
    const config = ProductModelConfig.spectra6FourInch;

    expect(config.assetPath, 'assets/models/device.glb');
    expect(config.displayEntity, 'DisplayPlane');
    expect(config.displayPrimitiveIndex, 2);
    expect(config.glassEntity, isNull);
    expect(config.partEntities.keys.toSet(), ProductPart.values.toSet());
    expect(config.overviewPose.position, [0.10, 0.04, -7.8]);
    expect(config.overviewPose.focus, [0, -0.18, 0]);
    expect(config.backPose.position, [-0.10, 0.04, 7.8]);
    expect(config.backPose.focus, [0, -0.18, 0]);
    expect(config.displayPose.position, hasLength(3));
    expect(config.iblPath, 'assets/environment/default_env_ibl.ktx');
    expect(config.iblIntensity, 500);
  });
}
