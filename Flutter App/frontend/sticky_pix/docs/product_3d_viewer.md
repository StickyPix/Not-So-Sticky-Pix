# Reusable 3D product viewer

`Product3dViewer` is the Flutter presentation layer. It owns one Thermion
viewer, one loaded glTF asset, the camera input delegate, and GPU resources.
`ProductViewerController` is the application-facing API. The image processor
never talks directly to Filament.

## Runtime flow

1. The bundled 1.5 MB GLB is loaded once and normalized to a unit cube.
2. Named glTF entities receive independent Filament PBR material instances.
3. Primitive `2` of runtime entity `DisplayPlane` (the Blender node named
   `4" Eink Display`) receives an unlit texture material using UV0. The display
   module body and connector retain their own materials.
4. Processed PNG bytes are decoded and uploaded as a GPU texture.
5. The new texture replaces the old texture on the material; the model and UV
   mapping remain loaded and unchanged.
6. Edit and Save animate the existing camera between configurable poses.

## Public control surface

```dart
final controller = ProductViewerController();

Product3dViewer(controller: controller);

await controller.setDisplayTexture(processedPng);
await controller.focusDisplay();
await controller.showOverview();
await controller.setPartColor(ProductPart.kickstand, const Color(0xFF222222));
```

Each device model supplies a `ProductModelConfig`, so new hardware variants do
not require changes to rendering code. Put their node names, asset path, camera
poses, and optional IBL/skybox paths in a new config.

## Performance budget

- The render loop is capped at 60 FPS.
- The GLB is loaded once; image changes do not reload it.
- Display textures use mipmaps to avoid shimmer when the device rotates.
- GPU textures and custom material instances are explicitly released.
- The viewport is isolated behind a `RepaintBoundary`.
- Keep mobile GLBs below roughly 100k triangles, use one UV set for the
  display, prefer 1K–2K textures, and use KTX2/Basis textures for larger
  production assets.

## Blender/export contract

See `assets/models/README.md`. In particular, keep the part node names stable,
keep the `4" Eink Display` active surface dimensions unchanged, and position
the kickstand origin at its hinge. Export a `KickstandOpen` glTF animation
before adding the controller action for it.

For a more reflective studio look, add mobile-sized Filament IBL and skybox KTX
assets and set `iblPath`/`skyboxPath` on the model config. Direct three-point
lighting is the current fallback.
