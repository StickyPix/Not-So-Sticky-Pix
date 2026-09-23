import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'packaged NewPieces GLB preserves the display texture contract',
    () async {
      final asset = await rootBundle.load('assets/models/device.glb');
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(0, Endian.little), 0x46546C67);
      expect(data.getUint32(4, Endian.little), 2);

      final jsonLength = data.getUint32(12, Endian.little);
      final document =
          jsonDecode(
                utf8
                    .decode(bytes.sublist(20, 20 + jsonLength))
                    .replaceAll(RegExp(r'[\u0000 ]+$'), ''),
              )
              as Map<String, dynamic>;
      final nodes = (document['nodes'] as List).cast<Map<String, dynamic>>();
      final meshes = (document['meshes'] as List).cast<Map<String, dynamic>>();
      final materials = (document['materials'] as List)
          .cast<Map<String, dynamic>>();
      final accessors = (document['accessors'] as List)
          .cast<Map<String, dynamic>>();
      final bufferViews = (document['bufferViews'] as List)
          .cast<Map<String, dynamic>>();
      final binaryDataStart = 20 + jsonLength + 8;

      const activeNames = <String>[
        'DisplayPlane',
        'Cardstock 4',
        'FrontShell (1.5Fillet) with clips (1)',
        'Kickstand 1.5 (1) (1) (1)',
        'RearShell with Clips long',
      ];
      final activeScene =
          (document['scenes'] as List)[document['scene'] as int]
              as Map<String, dynamic>;
      final portraitRoot = nodes.singleWhere(
        (node) => node['name'] == 'PortraitRoot',
      );
      expect(activeScene['nodes'], [nodes.indexOf(portraitRoot)]);
      expect(portraitRoot['rotation'], [0, 0, 0.7071068, 0.7071068]);
      expect(
        (portraitRoot['children'] as List)
            .map((index) => nodes[index as int]['name'])
            .toList(),
        activeNames,
      );
      expect(
        (portraitRoot['children'] as List).map(
          (index) => nodes[index as int]['name'],
        ),
        isNot(contains('Cube')),
      );
      final excludedHelper = nodes.singleWhere(
        (node) => node['name'] == 'ExcludedExportHelper',
      );
      expect(excludedHelper, isNot(contains('mesh')));

      final displayNode = nodes.singleWhere(
        (node) => node['name'] == 'DisplayPlane',
      );
      final displayMesh = meshes[displayNode['mesh'] as int];
      final primitives = (displayMesh['primitives'] as List)
          .cast<Map<String, dynamic>>();
      expect(primitives, hasLength(3));

      final displayPrimitive = primitives[2];
      expect(materials[displayPrimitive['material'] as int]['name'], 'Display');
      final displayIndices = accessors[displayPrimitive['indices'] as int];
      expect(displayIndices['count'], 6);
      expect(accessors[primitives[0]['indices'] as int]['count'], 120);

      final screenVertexIndices = _readUnsignedShorts(
        data,
        displayIndices,
        bufferViews,
        binaryDataStart,
      ).toSet();
      expect(screenVertexIndices, hasLength(4));
      final attributes = displayPrimitive['attributes'] as Map<String, dynamic>;
      final uvAccessor = accessors[attributes['TEXCOORD_0'] as int];
      expect(uvAccessor['min'], [0, 0]);
      expect(uvAccessor['max'], [1, 1]);
      final screenUvs = screenVertexIndices
          .map(
            (index) => _readFloatVector(
              data,
              uvAccessor,
              bufferViews,
              binaryDataStart,
              index,
              2,
            ),
          )
          .map((uv) => '${uv[0].round()},${uv[1].round()}')
          .toSet();
      expect(screenUvs, {'0,0', '1,0', '0,1', '1,1'});
      final positionAccessor = accessors[attributes['POSITION'] as int];
      final screenDepths = screenVertexIndices
          .map(
            (index) => _readFloatVector(
              data,
              positionAccessor,
              bufferViews,
              binaryDataStart,
              index,
              3,
            )[1],
          )
          .toList();
      expect(screenDepths, everyElement(closeTo(0.00125, 0.000001)));

      expect(document['extensionsUsed'] as List<dynamic>? ?? const [], isEmpty);
      for (final material in materials.where(
        (material) => (material['name'] as String).startsWith('PCABS_'),
      )) {
        final pbr = material['pbrMetallicRoughness'] as Map<String, dynamic>;
        if ((material['name'] as String).startsWith('PCABS_RearShell_')) {
          expect(pbr['baseColorFactor'], [0.2502, 0.62396, 0.87137, 1]);
        } else {
          expect(pbr['baseColorFactor'], [0.9608, 0.9608, 0.9608, 1]);
        }
        expect(pbr['metallicFactor'], 0);
        expect(pbr['roughnessFactor'], 0.12);
        expect(material, isNot(contains('extensions')));
      }
    },
  );
}

List<int> _readUnsignedShorts(
  ByteData data,
  Map<String, dynamic> accessor,
  List<Map<String, dynamic>> bufferViews,
  int binaryDataStart,
) {
  final view = bufferViews[accessor['bufferView'] as int];
  final start =
      binaryDataStart +
      (view['byteOffset'] as int? ?? 0) +
      (accessor['byteOffset'] as int? ?? 0);
  return List.generate(
    accessor['count'] as int,
    (index) => data.getUint16(start + index * 2, Endian.little),
  );
}

List<double> _readFloatVector(
  ByteData data,
  Map<String, dynamic> accessor,
  List<Map<String, dynamic>> bufferViews,
  int binaryDataStart,
  int index,
  int componentCount,
) {
  final view = bufferViews[accessor['bufferView'] as int];
  final start =
      binaryDataStart +
      (view['byteOffset'] as int? ?? 0) +
      (accessor['byteOffset'] as int? ?? 0);
  final stride = view['byteStride'] as int? ?? componentCount * 4;
  return List.generate(
    componentCount,
    (component) =>
        data.getFloat32(start + index * stride + component * 4, Endian.little),
  );
}
