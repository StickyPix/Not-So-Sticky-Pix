import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Texture;
import 'package:thermion_flutter/thermion_flutter.dart';

import 'product_model_config.dart';
import 'product_orbit_input.dart';
import 'product_viewer_controller.dart';

class Product3dViewer extends StatefulWidget {
  const Product3dViewer({
    super.key,
    required this.controller,
    this.config = ProductModelConfig.spectra6FourInch,
    this.showGestureHint = true,
    this.borderRadius = 28,
    this.yawOnly = false,
    this.allowZoom = true,
    this.allowPan = true,
    this.frameRate = 60,
  });

  final ProductViewerController controller;
  final ProductModelConfig config;
  final bool showGestureHint;
  final double borderRadius;
  final bool yawOnly;
  final bool allowZoom;
  final bool allowPan;

  /// Lower thumbnail frame rates avoid spending product-page rendering budget
  /// on non-interactive device cards.
  final int frameRate;

  @override
  Product3dViewerState createState() => Product3dViewerState();
}

class Product3dViewerState extends State<Product3dViewer>
    with SingleTickerProviderStateMixin {
  ThermionViewer? _viewer;
  ThermionAsset? _asset;
  Camera? _camera;
  InputHandler? _inputHandler;
  ProductOrbitInputDelegate? _orbitDelegate;
  Widget? _viewport;

  final Map<ProductPart, List<UbershaderMaterialInstance>> _partMaterials = {};
  final Map<ProductPart, Color> _requestedPartColors = {};
  final List<MaterialInstance> _ownedMaterials = [];
  UbershaderMaterialInstance? _displayMaterial;
  TextureSampler? _displaySampler;
  Texture? _displayTexture;
  Uint8List? _queuedDisplayTexture;
  bool _isLandscape = false;

  late final AnimationController _cameraAnimation;
  Animation<Vector3>? _cameraPosition;
  Animation<Vector3>? _cameraFocus;
  bool _cameraWriteInFlight = false;
  bool _cameraWritePending = false;
  bool _isTransitioning = false;
  bool _isLoading = true;
  bool _isDisposed = false;
  Object? _loadError;
  final FocusNode _focusNode = FocusNode(debugLabel: 'Product 3D viewer');
  Future<void>? _initialization;

  ProductModelConfig get _config => widget.config;

  @override
  void initState() {
    super.initState();
    _cameraAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..addListener(_scheduleCameraWrite);
    widget.controller.attach(this);
    _initialization = _initialize();
  }

  @override
  void didUpdateWidget(Product3dViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detach(this);
      widget.controller.attach(this);
    }
    if (oldWidget.config.assetPath != widget.config.assetPath) {
      throw UnsupportedError(
        'Changing the product model requires a new Product3dViewer key.',
      );
    }
  }

  Future<void> _initialize() async {
    try {
      final viewer = await ThermionFlutterPlugin.createViewer();
      _viewer = viewer;
      await viewer.setFrameRate(widget.frameRate);
      await viewer.setPostProcessing(true);
      await viewer.setAntiAliasing(false, true, false);
      await viewer.setBackgroundColor(
        _config.backgroundColor.r,
        _config.backgroundColor.g,
        _config.backgroundColor.b,
        1,
      );
      if (_config.iblPath != null) {
        await viewer.loadIbl(_config.iblPath!, intensity: _config.iblIntensity);
      }
      if (_config.skyboxPath != null) {
        await viewer.loadSkybox(_config.skyboxPath!);
      }

      final asset = await viewer.loadGltf(_config.assetPath);
      _asset = asset;
      await asset.transformToUnitCube();
      await asset.setCastShadows(false);
      await asset.setReceiveShadows(false);
      await viewer.view.setShadowsEnabled(false);

      await _addStudioLighting(viewer);
      await _configureProductMaterials(asset);
      // Controllers can be attached before the GLB's material table is ready
      // (notably for the Devices-page thumbnails). Apply all requested colors
      // now that each named product part has a live material instance.
      for (final entry in _requestedPartColors.entries) {
        await setPartColor(entry.key, entry.value);
      }

      final camera = await viewer.getActiveCamera();
      _camera = camera;
      await _applyPose(_config.overviewPose);
      await camera.setExposure(5.6, 1 / 120, 100);

      final orbitDelegate = ProductOrbitInputDelegate(
        viewer.view,
        minimumDistance: 0.65,
        maximumDistance: 12,
        yawOnly: widget.yawOnly,
        allowZoom: widget.allowZoom,
        allowPan: widget.allowPan,
      )..up = _cameraUp;
      _orbitDelegate = orbitDelegate;
      final inputHandler = DelegateInputHandler(
        viewer: viewer,
        delegate: orbitDelegate,
      );
      _inputHandler = inputHandler;

      final renderWidget = ThermionWidget(viewer: viewer);
      _viewport = ThermionListenerWidget(
        focusNode: _focusNode,
        inputHandler: inputHandler,
        child: renderWidget,
      );
      if (!_isDisposed) {
        _focusNode.requestFocus();
      }

      final queuedTexture = _queuedDisplayTexture;
      if (queuedTexture != null) {
        await _uploadDisplayTexture(queuedTexture);
        _queuedDisplayTexture = null;
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addStudioLighting(ThermionViewer viewer) async {
    // A restrained three-point studio setup. The earlier all-direction,
    // high-intensity fill lights flattened the product and washed dark finish
    // colors into pale pastels. The key is intentionally angled from the
    // upper-left, with just enough fill and rim light to retain back detail.
    final lights = <(Vector3, double, bool)>[
      // Main softbox: angled rather than straight at the front surface.
      (Vector3(-0.85, -0.65, 1.0), 18000, false),
      // Gentle camera-side fill keeps the front readable without bleaching it.
      (Vector3(0.70, -0.20, 0.80), 4500, false),
      // Rear rim separates the back shell from the black background.
      (Vector3(0.45, 0.55, -1.0), 6500, false),
      // A very low lift preserves underside/kickstand detail.
      (Vector3(0, -1.0, -0.25), 1800, false),
    ];
    for (final (direction, intensity, castShadows) in lights) {
      await viewer.addDirectLight(
        DirectLight.sun(
          intensity: intensity,
          direction: direction,
          castShadows: castShadows,
          sunAngularRadius: 1.2,
        ),
      );
    }
  }

  Future<void> _configureProductMaterials(ThermionAsset asset) async {
    final materialMap = await asset.getMaterialInstancesAsMap();

    for (final entry in _config.partEntities.entries) {
      final originalMaterials = await _materialsForEntity(
        asset,
        materialMap,
        entry.value,
      );
      if (entry.key == ProductPart.enclosure ||
          entry.key == ProductPart.bezel) {
        _partMaterials[entry.key] = await _replaceWithIndependentPbrMaterials(
          asset,
          entry.value,
          originalMaterials.length,
          const Color(0xFFF5F5F5),
        );
      } else {
        _partMaterials[entry.key] = originalMaterials
            .map(UbershaderMaterialInstance.new)
            .toList(growable: false);
      }
    }

    await _materialsForEntity(asset, materialMap, _config.displayEntity);
    _displaySampler = await FilamentApp.instance!.createTextureSampler();
  }

  /// The Blender front parts contain multiple glTF material variants whose
  /// imported base-color parameters are not reliably mutable in Filament.
  /// Give each primitive its own runtime PBR material so cardstock and front
  /// shell colors are independent and deterministic.
  Future<List<UbershaderMaterialInstance>> _replaceWithIndependentPbrMaterials(
    ThermionAsset asset,
    String entityName,
    int primitiveCount,
    Color color,
  ) async {
    final entity = await asset.getChildEntity(entityName);
    if (entity == null) {
      throw StateError('GLB entity "$entityName" was not found.');
    }
    final replacements = <UbershaderMaterialInstance>[];
    for (
      var primitiveIndex = 0;
      primitiveIndex < primitiveCount;
      primitiveIndex++
    ) {
      final material = await FilamentApp.instance!.createUbershaderMaterial(
        doubleSided: true,
      );
      // These runtime materials intentionally have no base-color texture.
      // Explicitly disabling its UV slot keeps the constant PBR color from
      // being multiplied by an imported glTF texture/UV state.
      await material.setBaseColorUV(-1);
      await material.setBaseColorFactor(color.r, color.g, color.b, color.a);
      await material.setMetallicFactor(0);
      await material.setRoughnessFactor(0.12);
      await asset.setMaterialInstanceAt(
        material.materialInstance,
        entity: entity,
        primitiveIndex: primitiveIndex,
      );
      _ownedMaterials.add(material.materialInstance);
      replacements.add(material);
    }
    return replacements;
  }

  Future<List<MaterialInstance>> _materialsForEntity(
    ThermionAsset asset,
    Map<ThermionEntity, List<MaterialInstance>> materialMap,
    String entityName,
  ) async {
    final entity = await asset.getChildEntity(entityName);
    if (entity == null) {
      throw StateError('GLB entity "$entityName" was not found.');
    }
    final materials = materialMap[entity];
    if (materials == null || materials.isEmpty) {
      throw StateError('GLB entity "$entityName" has no renderable material.');
    }
    return materials;
  }

  Future<void> setDisplayTexture(Uint8List encodedImage) async {
    if (_asset == null || _displaySampler == null) {
      _queuedDisplayTexture = Uint8List.fromList(encodedImage);
      return;
    }
    await _uploadDisplayTexture(encodedImage);
  }

  Future<void> setLandscape(bool isLandscape) async {
    _isLandscape = isLandscape;
    await _applyOrientation();
  }

  Future<void> _applyOrientation() async {
    final camera = _camera;
    if (camera == null) return;

    // This GLB's renderable hierarchy is not rooted at the asset entity, so a
    // root transform does not rotate the visible enclosure. A camera roll does
    // and also keeps the selected composition upright: landscape panel bytes
    // are rotated clockwise for the portrait display, then the camera's up
    // axis presents the physical product in landscape on the home screen.
    _orbitDelegate?.up = _cameraUp;
    final position = await camera.getPosition();
    final focus = _orbitDelegate?.target ?? _vector(_config.overviewPose.focus);
    await camera.lookAt(position, focus: focus, up: _cameraUp);
  }

  Vector3 get _cameraUp => _isLandscape ? Vector3(1, 0, 0) : Vector3(0, 1, 0);

  Future<void> _uploadDisplayTexture(Uint8List encodedImage) async {
    final displayMaterial = await _ensureDisplayMaterial();
    final displayImage = await _addDisplaySheen(encodedImage);
    final decoded = await FilamentApp.instance!.decodeImage(
      displayImage,
      requireAlpha: true,
    );
    final width = await decoded.getWidth();
    final height = await decoded.getHeight();
    final channels = await decoded.getChannels();
    final texture = await FilamentApp.instance!.createTexture(
      width,
      height,
      textureFormat: channels == 4
          ? TextureFormat.RGBA32F
          : TextureFormat.RGB32F,
      levels: 1,
      flags: const {
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        TextureUsage.TEXTURE_USAGE_UPLOADABLE,
      },
    );
    await texture.setLinearImage(
      decoded,
      channels == 4 ? PixelDataFormat.RGBA : PixelDataFormat.RGB,
      PixelDataType.FLOAT,
    );
    await decoded.destroy();
    await displayMaterial.setBaseColorTexture(texture, _displaySampler!);

    final previous = _displayTexture;
    _displayTexture = texture;
    await previous?.destroy();
  }

  Future<UbershaderMaterialInstance> _ensureDisplayMaterial() async {
    final existing = _displayMaterial;
    if (existing != null) return existing;

    final material = await FilamentApp.instance!.createUbershaderMaterial(
      doubleSided: true,
      unlit: true,
      hasBaseColorTexture: true,
      baseColorUV: 0,
    );
    await material.setBaseColorUV(0);
    final asset = _asset!;
    final entity = await asset.getChildEntity(_config.displayEntity);
    if (entity == null) {
      await material.materialInstance.destroy();
      throw StateError('GLB entity "${_config.displayEntity}" was not found.');
    }
    final materials = (await asset.getMaterialInstancesAsMap())[entity];
    if (materials == null || materials.isEmpty) {
      await material.materialInstance.destroy();
      throw StateError(
        'GLB entity "${_config.displayEntity}" has no renderable material.',
      );
    }
    final primitiveIndex = _config.displayPrimitiveIndex;
    if (primitiveIndex < 0 || primitiveIndex >= materials.length) {
      await material.materialInstance.destroy();
      throw StateError(
        'GLB entity "${_config.displayEntity}" has ${materials.length} '
        'primitives, so display primitive $primitiveIndex is invalid.',
      );
    }
    await asset.setMaterialInstanceAt(
      material.materialInstance,
      entity: entity,
      primitiveIndex: primitiveIndex,
    );
    _displayMaterial = material;
    _ownedMaterials.add(material.materialInstance);
    return material;
  }

  Future<Uint8List> _addDisplaySheen(Uint8List encodedImage) async {
    final codec = await ui.instantiateImageCodec(encodedImage);
    final frame = await codec.getNextFrame();
    final source = frame.image;
    final width = source.width;
    final height = source.height;
    final bounds = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    canvas.drawRect(
      bounds,
      ui.Paint()
        ..blendMode = ui.BlendMode.screen
        ..shader = ui.Gradient.linear(
          ui.Offset(0, height * 0.92),
          ui.Offset(width.toDouble(), height * 0.08),
          const [
            Color(0x00FFFFFF),
            Color(0x0AFFFFFF),
            Color(0x26FFFFFF),
            Color(0x0FFFFFFF),
            Color(0x00FFFFFF),
          ],
          const [0, 0.32, 0.48, 0.64, 1],
        ),
    );
    final picture = recorder.endRecording();
    final composed = await picture.toImage(width, height);
    final png = await composed.toByteData(format: ui.ImageByteFormat.png);
    composed.dispose();
    picture.dispose();
    source.dispose();
    codec.dispose();
    if (png == null) {
      throw StateError('Unable to encode the glossy display texture.');
    }
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  }

  Future<void> setPartColor(ProductPart part, Color color) async {
    _requestedPartColors[part] = color;
    final materials = _partMaterials[part];
    if (materials == null) return;

    // Filament can retain the imported base-color state for the two
    // multi-primitive front meshes even after mutating their bound material
    // instance. Rebuild those small PBR instances with the requested color
    // already set, then bind them. The white startup replacements render
    // correctly through this same path, so recoloring is deterministic too.
    if (part == ProductPart.enclosure || part == ProductPart.bezel) {
      final asset = _asset;
      if (asset == null) return;
      final replacements = await _replaceWithIndependentPbrMaterials(
        asset,
        _config.partEntities[part]!,
        materials.length,
        color,
      );
      _partMaterials[part] = replacements;

      // Only dispose runtime materials owned by this viewer. Imported glTF
      // materials remain asset-owned and must never be destroyed here.
      for (final oldMaterial in materials) {
        final instance = oldMaterial.materialInstance;
        if (_ownedMaterials.remove(instance)) {
          await instance.destroy();
        }
      }
      return;
    }
    for (final material in materials) {
      await material.setBaseColorFactor(color.r, color.g, color.b, color.a);
    }
  }

  Future<void> animateToDisplay() => _animateTo(_config.displayPose);

  Future<void> animateToOverview() => _animateTo(_config.overviewPose);

  Future<void> animateToBack() => _animateTo(_config.backPose);

  Future<void> _animateTo(ProductCameraPose destination) async {
    final camera = _camera;
    if (camera == null) return;
    final start = await camera.getPosition();
    _cameraPosition =
        Tween<Vector3>(
          begin: start,
          end: _vector(destination.position),
        ).animate(
          CurvedAnimation(
            parent: _cameraAnimation,
            curve: Curves.easeInOutCubic,
          ),
        );
    _cameraFocus =
        Tween<Vector3>(
          begin: _orbitDelegate?.target ?? Vector3.zero(),
          end: _vector(destination.focus),
        ).animate(
          CurvedAnimation(
            parent: _cameraAnimation,
            curve: Curves.easeInOutCubic,
          ),
        );
    if (mounted) setState(() => _isTransitioning = true);
    await _cameraAnimation.forward(from: 0);
    await _applyPose(destination);
    _orbitDelegate?.resync(target: _vector(destination.focus), up: _cameraUp);
    if (mounted) setState(() => _isTransitioning = false);
  }

  void _scheduleCameraWrite() {
    if (_cameraWriteInFlight) {
      _cameraWritePending = true;
      return;
    }
    unawaited(_writeAnimatedCamera());
  }

  Future<void> _writeAnimatedCamera() async {
    final camera = _camera;
    final position = _cameraPosition?.value;
    final focus = _cameraFocus?.value;
    if (camera == null || position == null || focus == null) return;
    _cameraWriteInFlight = true;
    await camera.lookAt(position, focus: focus, up: _cameraUp);
    _cameraWriteInFlight = false;
    if (_cameraWritePending) {
      _cameraWritePending = false;
      _scheduleCameraWrite();
    }
  }

  Future<void> _applyPose(ProductCameraPose pose) async {
    await _camera?.lookAt(
      _vector(pose.position),
      focus: _vector(pose.focus),
      up: _cameraUp,
    );
  }

  Vector3 _vector(List<double> values) =>
      Vector3(values[0], values[1], values[2]);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: ColoredBox(
          color: _config.backgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_viewport != null)
                AbsorbPointer(absorbing: _isTransitioning, child: _viewport!),
              if (_isLoading)
                const Center(child: CircularProgressIndicator.adaptive()),
              if (_loadError != null)
                _ViewerError(
                  message: 'Unable to load the 3D product model.',
                  details: _loadError.toString(),
                ),
              if (widget.showGestureHint && !_isLoading && _loadError == null)
                const Positioned(left: 16, bottom: 14, child: _GestureHint()),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    widget.controller.detach(this);
    _cameraAnimation.dispose();
    _focusNode.dispose();
    unawaited(_tearDown());
    super.dispose();
  }

  Future<void> _tearDown() async {
    await _initialization;
    await _inputHandler?.dispose();
    await _viewer?.dispose();
    for (final material in _ownedMaterials) {
      await material.destroy();
    }
    await _displayTexture?.destroy();
    await _displaySampler?.dispose();
  }
}

class _GestureHint extends StatelessWidget {
  const _GestureHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          'Drag to rotate  •  Pinch to zoom  •  Two fingers to pan',
          style: TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError({required this.message, required this.details});

  final String message;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_in_ar_outlined, size: 38),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              details,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
