import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _jsonChunkType = 0x4E4F534A;
const _binaryChunkType = 0x004E4942;
const _displayNodeName = '4" Eink Display';
const _runtimeDisplayNodeName = 'DisplayPlane';
const _excludedNodeName = 'Cube';
const _portraitRootName = 'PortraitRoot';
const _displayMaterialName = 'Display';

const _productNodeNames = <String>[
  _displayNodeName,
  'Cardstock 4',
  'FrontShell (1.5Fillet) with clips (1)',
  'Kickstand 1.5 (1) (1) (1)',
  'RearShell with Clips long',
];

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/prepare_device_glb.dart input.glb output.glb',
    );
    exitCode = 64;
    return;
  }

  final input = File(arguments[0]).readAsBytesSync();
  final data = ByteData.sublistView(input);
  if (data.getUint32(0, Endian.little) != 0x46546C67 ||
      data.getUint32(4, Endian.little) != 2) {
    throw const FormatException('Expected a binary glTF 2.0 file.');
  }

  final chunks = <({int type, Uint8List bytes})>[];
  var offset = 12;
  while (offset < input.length) {
    final length = data.getUint32(offset, Endian.little);
    final type = data.getUint32(offset + 4, Endian.little);
    chunks.add((
      type: type,
      bytes: Uint8List.fromList(
        Uint8List.sublistView(input, offset + 8, offset + 8 + length),
      ),
    ));
    offset += 8 + length;
  }

  final jsonIndex = chunks.indexWhere((chunk) => chunk.type == _jsonChunkType);
  if (jsonIndex < 0) throw const FormatException('GLB has no JSON chunk.');
  final document =
      jsonDecode(
            utf8
                .decode(chunks[jsonIndex].bytes)
                .replaceAll(RegExp(r'[\u0000 ]+$'), ''),
          )
          as Map<String, dynamic>;

  _validateNodes(document);
  _applySafeProductMaterials(document);
  _stripExportOnlyGeometry(document);
  _splitActiveDisplaySurface(document, chunks);
  _buildActivePortraitScene(document);

  final encodedJson = utf8.encode(jsonEncode(document));
  final paddedJsonLength = (encodedJson.length + 3) & ~3;
  final paddedJson = Uint8List(paddedJsonLength)..setAll(0, encodedJson);
  for (var index = encodedJson.length; index < paddedJson.length; index++) {
    paddedJson[index] = 0x20;
  }
  chunks[jsonIndex] = (type: _jsonChunkType, bytes: paddedJson);

  final totalLength =
      12 + chunks.fold<int>(0, (sum, chunk) => sum + 8 + chunk.bytes.length);
  final output = BytesBuilder(copy: false);
  final header = ByteData(12)
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little);
  output.add(header.buffer.asUint8List());
  for (final chunk in chunks) {
    final chunkHeader = ByteData(8)
      ..setUint32(0, chunk.bytes.length, Endian.little)
      ..setUint32(4, chunk.type, Endian.little);
    output
      ..add(chunkHeader.buffer.asUint8List())
      ..add(chunk.bytes);
  }
  File(arguments[1]).writeAsBytesSync(output.takeBytes(), flush: true);
}

void _validateNodes(Map<String, dynamic> document) {
  final names = (document['nodes'] as List)
      .cast<Map<String, dynamic>>()
      .map((node) => node['name'])
      .toSet();
  for (final name in _productNodeNames) {
    if (!names.contains(name)) {
      throw StateError('Required product node "$name" was not found.');
    }
  }
  if (!names.contains(_excludedNodeName)) {
    throw StateError('Expected the export-only Cube node.');
  }
}

void _stripExportOnlyGeometry(Map<String, dynamic> document) {
  final nodes = (document['nodes'] as List).cast<Map<String, dynamic>>();
  final cube = nodes.singleWhere((node) => node['name'] == _excludedNodeName);
  // Thermion imports every renderable node in the GLB, including nodes omitted
  // from the active glTF scene. Removing the mesh is required; scene exclusion
  // alone leaves this large export helper directly in front of the product.
  cube
    ..remove('mesh')
    ..remove('skin')
    ..['name'] = 'ExcludedExportHelper';
}

void _applySafeProductMaterials(Map<String, dynamic> document) {
  final nodes = (document['nodes'] as List).cast<Map<String, dynamic>>();
  final meshes = (document['meshes'] as List).cast<Map<String, dynamic>>();
  final materials = (document['materials'] as List)
      .cast<Map<String, dynamic>>();

  document.remove('extensionsRequired');
  document.remove('extensionsUsed');

  const plasticNodes = <String>{
    'Cardstock 4',
    'FrontShell (1.5Fillet) with clips (1)',
    'Kickstand 1.5 (1) (1) (1)',
    'RearShell with Clips long',
  };
  final plasticMaterialIndices = <int>{};
  final rearShellMaterialIndices = <int>{};
  for (final node in nodes.where(
    (candidate) => plasticNodes.contains(candidate['name']),
  )) {
    final mesh = meshes[node['mesh'] as int];
    for (final primitive
        in (mesh['primitives'] as List).cast<Map<String, dynamic>>()) {
      final materialIndex = primitive['material'] as int;
      plasticMaterialIndices.add(materialIndex);
      if (node['name'] == 'RearShell with Clips long') {
        rearShellMaterialIndices.add(materialIndex);
      }
    }
  }

  for (final index in plasticMaterialIndices) {
    final material = materials[index];
    final isRearShell = rearShellMaterialIndices.contains(index);
    material
      ..['name'] = isRearShell ? 'PCABS_RearShell_$index' : 'PCABS_$index'
      ..['pbrMetallicRoughness'] = {
        'baseColorFactor': isRearShell
            ? [0.2502, 0.62396, 0.87137, 1]
            : [0.9608, 0.9608, 0.9608, 1],
        'metallicFactor': 0,
        'roughnessFactor': 0.12,
      }
      ..remove('extensions')
      ..remove('alphaMode')
      ..remove('alphaCutoff');
  }

  materials.add({
    'name': _displayMaterialName,
    'pbrMetallicRoughness': {
      'baseColorFactor': [0.01, 0.01, 0.012, 1],
      'metallicFactor': 0,
      'roughnessFactor': 0.9,
    },
    'doubleSided': true,
  });
}

void _splitActiveDisplaySurface(
  Map<String, dynamic> document,
  List<({int type, Uint8List bytes})> chunks,
) {
  final nodes = (document['nodes'] as List).cast<Map<String, dynamic>>();
  final meshes = (document['meshes'] as List).cast<Map<String, dynamic>>();
  final accessors = (document['accessors'] as List)
      .cast<Map<String, dynamic>>();
  final bufferViews = (document['bufferViews'] as List)
      .cast<Map<String, dynamic>>();
  final materials = (document['materials'] as List)
      .cast<Map<String, dynamic>>();
  final binary = chunks.singleWhere((chunk) => chunk.type == _binaryChunkType);
  final bytes = ByteData.sublistView(binary.bytes);

  final displayNode = nodes.singleWhere(
    (node) => node['name'] == _displayNodeName,
  );
  final mesh = meshes[displayNode['mesh'] as int];
  final primitives = (mesh['primitives'] as List).cast<Map<String, dynamic>>();
  if (primitives.length != 2) {
    throw StateError(
      '$_displayNodeName must contain its module and connector primitives.',
    );
  }
  final module = primitives.first;
  final attributes = module['attributes'] as Map<String, dynamic>;
  final positions = _readFloatVectors(
    bytes,
    accessors[attributes['POSITION'] as int],
    bufferViews,
    3,
  );
  final normals = _readFloatVectors(
    bytes,
    accessors[attributes['NORMAL'] as int],
    bufferViews,
    3,
  );
  final indexAccessor = accessors[module['indices'] as int];
  if (indexAccessor['componentType'] != 5123) {
    throw StateError('The display module must use unsigned-short indices.');
  }
  final indices = _readUnsignedShorts(bytes, indexAccessor, bufferViews);

  // The approved panel has a recessed 84.6 x 56.4 mm active surface. Find its
  // two +Y-facing triangles rather than texturing the module sides/connector.
  final screenTriangles = <List<int>>[];
  final bodyTriangles = <List<int>>[];
  for (var index = 0; index < indices.length; index += 3) {
    final triangle = indices.sublist(index, index + 3);
    final isFrontFacing = triangle.every(
      (vertex) =>
          normals[vertex][1] > 0.999 &&
          (positions[vertex][1] - 0.00046).abs() < 0.00001,
    );
    (isFrontFacing ? screenTriangles : bodyTriangles).add(triangle);
  }
  if (screenTriangles.length != 2) {
    throw StateError(
      'Expected exactly two triangles for the 4-inch active display surface.',
    );
  }

  final reordered = <int>[
    ...bodyTriangles.expand((triangle) => triangle),
    ...screenTriangles.expand((triangle) => triangle),
  ];
  _writeUnsignedShorts(bytes, indexAccessor, bufferViews, reordered);
  indexAccessor['count'] = bodyTriangles.length * 3;

  final screenAccessor = Map<String, dynamic>.from(indexAccessor)
    ..['byteOffset'] =
        (indexAccessor['byteOffset'] as int? ?? 0) +
        bodyTriangles.length * 3 * 2
    ..['count'] = screenTriangles.length * 3
    ..['min'] = [
      screenTriangles
          .expand((value) => value)
          .reduce((left, right) => left < right ? left : right),
    ]
    ..['max'] = [
      screenTriangles
          .expand((value) => value)
          .reduce((left, right) => left > right ? left : right),
    ];
  accessors.add(screenAccessor);

  final uvAccessor = accessors[attributes['TEXCOORD_0'] as int];
  final positionAccessor = accessors[attributes['POSITION'] as int];
  final screenVertices = screenTriangles.expand((value) => value).toSet();
  if (screenVertices.length != 4) {
    throw StateError('The active display must have four unique UV vertices.');
  }
  for (final vertex in screenVertices) {
    final position = positions[vertex];
    final isLeft = position[2] > 0;
    final isTop = position[0] > 0;
    // Keep the image surface just above the display module's top face. This is
    // still behind the front bezel, but prevents depth fighting or the image
    // being hidden by the display module itself.
    position[1] = 0.00125;
    _writeFloatVector(bytes, positionAccessor, bufferViews, vertex, position);
    _writeFloatVector(bytes, uvAccessor, bufferViews, vertex, [
      isLeft ? 0 : 1,
      isTop ? 0 : 1,
    ]);
  }
  uvAccessor
    ..['min'] = [0, 0]
    ..['max'] = [1, 1];
  final positionMax = List<num>.from(positionAccessor['max'] as List);
  positionMax[1] = 0.00125;
  positionAccessor['max'] = positionMax;

  primitives.add({
    'attributes': Map<String, dynamic>.from(attributes),
    'indices': accessors.length - 1,
    'material': materials.length - 1,
    'mode': module['mode'] as int? ?? 4,
  });
  // Filament/Thermion does not reliably preserve a double quote in an entity
  // lookup name. Keep the Blender source name as its import contract, but give
  // the packaged runtime entity a renderer-safe name.
  displayNode['name'] = _runtimeDisplayNodeName;
}

List<List<double>> _readFloatVectors(
  ByteData bytes,
  Map<String, dynamic> accessor,
  List<Map<String, dynamic>> bufferViews,
  int components,
) {
  if (accessor['componentType'] != 5126) {
    throw StateError('Expected a float accessor.');
  }
  final view = bufferViews[accessor['bufferView'] as int];
  final start =
      (view['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
  final stride = view['byteStride'] as int? ?? components * 4;
  return List.generate(accessor['count'] as int, (index) {
    return List.generate(
      components,
      (component) => bytes.getFloat32(
        start + index * stride + component * 4,
        Endian.little,
      ),
    );
  });
}

List<int> _readUnsignedShorts(
  ByteData bytes,
  Map<String, dynamic> accessor,
  List<Map<String, dynamic>> bufferViews,
) {
  final view = bufferViews[accessor['bufferView'] as int];
  final start =
      (view['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
  return List.generate(
    accessor['count'] as int,
    (index) => bytes.getUint16(start + index * 2, Endian.little),
  );
}

void _writeUnsignedShorts(
  ByteData bytes,
  Map<String, dynamic> accessor,
  List<Map<String, dynamic>> bufferViews,
  List<int> values,
) {
  final view = bufferViews[accessor['bufferView'] as int];
  final start =
      (view['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
  for (var index = 0; index < values.length; index++) {
    bytes.setUint16(start + index * 2, values[index], Endian.little);
  }
}

void _writeFloatVector(
  ByteData bytes,
  Map<String, dynamic> accessor,
  List<Map<String, dynamic>> bufferViews,
  int index,
  List<double> value,
) {
  final view = bufferViews[accessor['bufferView'] as int];
  final start =
      (view['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
  final stride = view['byteStride'] as int? ?? value.length * 4;
  for (var component = 0; component < value.length; component++) {
    bytes.setFloat32(
      start + index * stride + component * 4,
      value[component],
      Endian.little,
    );
  }
}

void _buildActivePortraitScene(Map<String, dynamic> document) {
  final nodes = (document['nodes'] as List).cast<Map<String, dynamic>>();
  final sceneIndex = document['scene'] as int? ?? 0;
  final scene =
      (document['scenes'] as List)[sceneIndex] as Map<String, dynamic>;
  final runtimeProductNodeNames = <String>[
    _runtimeDisplayNodeName,
    ..._productNodeNames.skip(1),
  ];
  final children = runtimeProductNodeNames
      .map((name) => nodes.indexWhere((node) => node['name'] == name))
      .toList(growable: false);
  final existingRoot = nodes.indexWhere(
    (node) => node['name'] == _portraitRootName,
  );
  final root = {
    'name': _portraitRootName,
    'children': children,
    'rotation': [0, 0, 0.7071068, 0.7071068],
  };
  final rootIndex = existingRoot < 0 ? nodes.length : existingRoot;
  if (existingRoot < 0) {
    nodes.add(root);
  } else {
    nodes[existingRoot] = root;
  }
  scene['nodes'] = [rootIndex];
}
