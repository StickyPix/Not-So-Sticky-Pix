# Product model contract

The viewer loads `device.glb` once and addresses model parts by glTF node name.
Keep these names stable in Blender:

- `4" Eink Display` — the complete display module in Blender. The preparation
  tool renames it `DisplayPlane` for reliable Thermion lookup and splits its
  recessed 84.6 × 56.4 mm active face into display primitive `2`.
- `Cube` — an export-only helper whose mesh is stripped from the packaged GLB.
  Thermion imports renderable nodes outside the active glTF scene, so scene
  exclusion alone is insufficient.
- `FrontShell (1.5Fillet) with clips (1)` — front bezel.
- `RearShell with Clips long` — rear enclosure.
- `Kickstand 1.5 (1) (1) (1)` — kickstand pivot object.
- `Cardstock 4` — inner enclosure.

The packaged model is generated from `Blender Models/NewPieces.glb` with
`tool/prepare_device_glb.dart`. It creates the dedicated `Display` primitive,
keeps the five named product pieces, excludes the unrelated `Cube`, applies the
safe mobile plastic material, and locks the product in portrait orientation.

Keep the display UV aspect ratio at 3:2 and orient UV0 so the upper-left of the
image appears at the upper-left of the physical display. Apply object scale and
rotation before export. Put the kickstand origin at its physical hinge and
export an animation named `KickstandOpen` when that animation is ready.

Recommended Blender materials:

- Front shell, cardstock, and kickstand PC/ABS: `#F5F5F5`.
- Rear shell PC/ABS: baby blue `#89CFF0`.
- All PC/ABS: metallic `0`, roughness `0.12` for a high-gloss finish.
  Thermion 0.4.1's default
  mobile ubershader cannot safely load the glTF clearcoat/IOR combination, so
  the glossy injection-molded finish is represented by low roughness instead.
- The export-only `Cube` is excluded because it is not one of the five named
  NewPieces product components.
- Display: matte black placeholder, with UV0 retained in the GLB.
