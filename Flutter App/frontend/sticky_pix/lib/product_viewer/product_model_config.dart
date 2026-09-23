import 'package:flutter/material.dart';

enum ProductPart { enclosure, bezel, backShell, kickstand }

@immutable
class ProductCameraPose {
  const ProductCameraPose({
    required this.position,
    this.focus = const [0, 0, 0],
  });

  final List<double> position;
  final List<double> focus;
}

@immutable
class ProductModelConfig {
  const ProductModelConfig({
    required this.assetPath,
    required this.displayEntity,
    required this.displayPrimitiveIndex,
    required this.partEntities,
    required this.overviewPose,
    required this.backPose,
    required this.displayPose,
    this.glassEntity,
    this.iblPath,
    this.iblIntensity = 30000,
    this.skyboxPath,
    this.backgroundColor = const Color(0xFF000000),
  });

  final String assetPath;
  final String displayEntity;
  final int displayPrimitiveIndex;
  final String? glassEntity;
  final Map<ProductPart, String> partEntities;
  final ProductCameraPose overviewPose;
  final ProductCameraPose backPose;
  final ProductCameraPose displayPose;
  final String? iblPath;
  final double iblIntensity;
  final String? skyboxPath;
  final Color backgroundColor;

  static const spectra6FourInch = ProductModelConfig(
    assetPath: 'assets/models/device.glb',
    displayEntity: 'DisplayPlane',
    displayPrimitiveIndex: 2,
    partEntities: {
      ProductPart.enclosure: 'Cardstock 4',
      ProductPart.bezel: 'FrontShell (1.5Fillet) with clips (1)',
      ProductPart.backShell: 'RearShell with Clips long',
      ProductPart.kickstand: 'Kickstand 1.5 (1) (1) (1)',
    },
    overviewPose: ProductCameraPose(
      position: [0.10, 0.04, -7.8],
      focus: [0, -0.18, 0],
    ),
    backPose: ProductCameraPose(
      position: [-0.10, 0.04, 7.8],
      focus: [0, -0.18, 0],
    ),
    displayPose: ProductCameraPose(position: [0, 0, -1.8]),
    iblPath: 'assets/environment/default_env_ibl.ktx',
    iblIntensity: 500,
  );
}
