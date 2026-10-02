# Godot — Breaking Changes

Last verified: 2026-10-02

Changes between Godot versions, focused on post-LLM-cutoff changes (4.4+).

## 4.6 → 4.7 (Jun 2026 — POST-CUTOFF, HIGH RISK)

Source: raw `.rst` of the official migration guide, **fetched 2026-10-02** —
https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/migrating/upgrading_to_godot_4.7.rst
The official page states: *"For most games and apps made with 4.6 it should be
relatively safe to migrate to 4.7."* Everything below is what that page lists;
the GH numbers are its own. Nothing here is from memory.

| Subsystem | Change | Details |
|-----------|--------|---------|
| Core | `Object.is_class` param type `String` → `StringName` | GDScript-compatible. GH-118582 |
| Core | `ZIPPacker.start_file` adds `permissions`, `modified_time` optional params | GH-115946 |
| Core | `OptimizedTranslation.generate` return `void` → `bool` | GDScript-compatible; C# **not** binary-compatible. GH-119563 |
| 2D / 3D | `CPUParticles2D/3D`, `GPUParticles2D/3D`: `request_particles_process` adds `process_time_residual` | GH-109142 |
| GUI | `Control.accessibility_live` type `DisplayServer.AccessibilityLiveMode` → `AccessibilityServer.AccessibilityLiveMode` | C# breaks both ways. GH-116839 |
| GUI | `RichTextLabel`: `ImageUpdateMask.UPDATE_WIDTH_IN_PERCENT` **renamed** → `UPDATE_WIDTH_UNIT` | **GDScript INCOMPATIBLE (❌)**. GH-112617 |
| GUI | `RichTextLabel.add_image` / `update_image`: `width` / `height` `int` → `float`; `width_in_percent` / `height_in_percent` **renamed** → `width_unit` / `height_unit`, type `bool` → `RichTextLabel.ImageUnit` | GH-112617 |
| Text | `Font.find_variation` adds `palette_index`, `custom_colors` | GH-117149 |
| Text | `TreeItem.select` adds `set_as_cursor` | GH-119367 |
| Rendering | `Image.save_exr` / `save_exr_to_buffer` add `color_image`, `max_linear_value` | GH-117800 |
| Rendering | `ImageTexture.get_format` and `PortableCompressedTexture2D.get_format` **moved to base class `Texture2D`** | GH-109004 |
| Rendering | `RenderingServer.particles_request_process_time` renames `time` → `process_time`, adds `process_time_residual` | GH-109142 |
| Rendering | `RenderingServer.viewport_set_size` adds `view_count` | GH-115799 |
| Animation | `Animation.length` type metadata `float` → `double` | C# breaks both ways. GH-116394 |
| Animation | `AnimationNodeBlendSpace1D/2D.add_blend_point` adds `name` | GH-110369 |
| Physics | `PhysicsServer2D.body_set_shape_as_one_way_collision` adds `direction` optional param | GDScript-compatible. GH-104736 — **relevant: this project uses Godot Physics 2D** |
| Physics | `PhysicsServer2DExtension._body_set_shape_as_one_way_collision` adds `direction` param | **GDScript INCOMPATIBLE (❌)**. GH-104736 |
| Audio | `AudioEffectSpectrumAnalyzer.tap_back_pos` **REMOVED** | **GDScript INCOMPATIBLE (❌)**. GH-114355 |
| XR | `OpenXRExtensionWrapper._on_register_metadata` adds `interaction_profile_metadata` | GDScript INCOMPATIBLE. GH-117399 |
| XR | `OpenXRSpatialAnchorCapability.create_new_anchor` adds `next` | GH-118128 |
| Editor | `EditorSceneFormatImporter` constants (`IMPORT_ANIMATION`, `IMPORT_SCENE`, …) **moved into enum `ImportFlags`** | GH-115788 |
| Editor | `EditorVCSInterface._commit` adds `amend` | GDScript INCOMPATIBLE. GH-117968 |

### Behavior changes — 4.6 → 4.7

| Subsystem | Change | Details |
|-----------|--------|---------|
| Animation | `AnimationNodeBlendSpace1D` / `2D`: a new **`SyncMode` enum replaces the boolean `sync` property** | If you use an `AnimationTree` and transitions misbehave after upgrading, set `sync_mode` on each blend space. **Present in the `.rst`, absent from the rendered HTML** when both were checked this run |
| Rendering | `LinearToSRGB` visual shader **no longer clamps to `[0.0, 1.0]`** on Mobile / Forward+ | GH-113956 — **relevant: this project uses Forward+** |
| Rendering | `CanvasItem` **no longer adds the antialiasing feather when drawing lines** | GH-105122 — lines render **thinner** at the same `width`. **Directly relevant: this project is line-heavy (pipes / network graphs)** |
| Physics | `AudioStreamPlayer` default `area_mask` changed `1` → `0` (disabled) | GH-107679 — with `audio_bus_override` on `Area2D`/`Area3D` **and** the default mask, reset the mask to layer 1 or bus overrides stop working |
| Physics (Jolt **3D**) | `WorldBoundaryShape3D.plane.d` sign convention now matches Godot Physics | GH-118948 — flip the sign to keep 4.6 behaviour. **3D only; this project is 2D** |
| Physics (Jolt **3D**) | `SoftBody3D` no longer defaults mass to `0` (now 1 kg total, not 1 kg/point) | GH-116041 — **3D only** |
| Physics (Jolt **3D**) | `SoftBody3D.linear_stiffness` applied differently | GH-116041 — re-tune stiffness / damping. **3D only** |
| Physics (Jolt **3D**) | `Area3D` now reports overlaps with `SoftBody3D` | GH-114198 — **3D only** |
| Input | **Mouse / keyboard device IDs changed from `0` to `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD`** | GH-116274 — some joypads use `0`. Compare against those constants instead. **Directly relevant: PC keyboard/mouse-primary** |
| GDScript | Setting an element of **packed arrays no longer calls the setter** for the whole packed-array property | GH-113228 |
| GDScript | **Methods inheriting a typed return now inherit the return type**, requiring an explicit `return` in the override | GH-115763 — add `return null` to fix. **This is a parse error, not a warning** |
| Platforms | **Minimum macOS raised from 10.13 (High Sierra) to 11 (Big Sur)** | In the `.rst`, absent from the rendered HTML when checked |

### Changed defaults — 4.6 → 4.7

| Property / Parameter | Old default | New default |
|---|---|---|
| **Newly created projects** — stretch mode / aspect | `disabled` / `keep` | **`canvas_items` / `expand`** |
| `LookAtModifier3D.relative` | `true` | `false` |
| `ProjectSettings` → `rendering/reflections/sky_reflections/roughness_layers` | `7` | `8` |
| `RichTextLabel.add_image` / `update_image` — `width_in_percent` / `height_in_percent` | `false` | `0` |
| `ResourceImporterDynamicFont.hinting` | `1` | `3` |

> **Note for this project:** `project.godot` already carries
> `window/stretch/mode="canvas_items"` and `window/stretch/aspect="expand"`,
> which **matches the new 4.7 default** — so this project is unaffected by that
> particular change either way.

## 4.5 → 4.6 (Jan 2026 — POST-CUTOFF, HIGH RISK)

| Subsystem | Change | Details |
|-----------|--------|---------|
| Physics | Jolt is now the DEFAULT 3D physics engine | New projects use Jolt automatically. Existing projects keep their setting. Some HingeJoint3D properties (like `damp`) only work with GodotPhysics. |
| Rendering | Glow processes BEFORE tonemapping | Was after tonemapping. Scenes with glow will look different. Adjust intensity/blend in WorldEnvironment. |
| Rendering | D3D12 default on Windows | Was Vulkan. For better driver compatibility. |
| Rendering | AgX tonemapper new controls | White point and contrast parameters added. |
| Core | Quaternion initializes to identity | Was zero. Unlikely to affect most code but technically breaking. |
| UI | Dual-focus system | Mouse/touch focus now separate from keyboard/gamepad focus. Visual feedback differs by input method. |
| Animation | IK system fully restored | CCDIK, FABRIK, Jacobian IK, Spline IK, TwoBoneIK via SkeletonModifier3D nodes. |
| Editor | New "Modern" theme default | Grayscale replaces blue-tint. Restore: Editor Settings → Interface → Theme → Style: Classic |
| Editor | "Select Mode" keybind changed | New "Select Mode" (v key) prevents accidental transforms. Old mode renamed "Transform Mode" (q key). |
| 2D | TileMapLayer scene tile rotation | Scene tiles can now be rotated like atlas tiles. |
| Localization | CSV plural form support | No longer requires Gettext for plurals. Context columns added. |
| C# | Automatic string extraction | Translation strings auto-extracted from C# code. |
| Plugins | New EditorDock class | Specialized container for plugin docks with layout control. |

## 4.4 → 4.5 (Late 2025 — POST-CUTOFF, HIGH RISK)

| Subsystem | Change | Details |
|-----------|--------|---------|
| GDScript | Variadic arguments added | Functions can accept `...` arbitrary params — new language feature |
| GDScript | `@abstract` decorator | Abstract classes and methods now enforceable |
| GDScript | Script backtracing | Detailed call stacks available even in Release builds |
| Rendering | Stencil buffer support | New capability for advanced visual effects |
| Rendering | SMAA 1x antialiasing | New post-processing AA option |
| Rendering | Shader Baker | Pre-compiles shaders — reportedly 20x faster startup on some demos |
| Rendering | Bent normal maps, specular occlusion | New material features |
| Accessibility | Screen reader support | Control nodes work with accessibility tools via AccessKit |
| Editor | Live translation preview | Test GUI layouts in different languages in-editor |
| Physics | 3D interpolation rearchitected | Moved from RenderingServer to SceneTree. API unchanged but internals differ. |
| Animation | BoneConstraint3D | New: AimModifier3D, CopyTransformModifier3D, ConvertTransformModifier3D |
| Resources | `duplicate_deep()` added | New explicit method for deep duplication of nested resources |
| Navigation | Dedicated 2D navigation server | No longer a proxy to 3D navigation; smaller export for 2D games |
| UI | FoldableContainer node | New accordion-style container for collapsible UI sections |
| UI | Recursive Control behavior | Disable mouse/focus interactions across entire node hierarchies |
| Platform | visionOS export support | New platform target |
| Platform | SDL3 gamepad driver | Delegated gamepad handling to SDL library |
| Platform | Android 16KB page support | Required for Google Play targeting Android 15+ |

## 4.3 → 4.4 (Mid 2025 — NEAR CUTOFF, VERIFY)

| Subsystem | Change | Details |
|-----------|--------|---------|
| Core | `FileAccess.store_*` return `bool` | Was `void`. Methods: `store_8`, `store_16`, `store_32`, `store_64`, `store_buffer`, `store_csv_line`, `store_double`, `store_float`, `store_half`, `store_line`, `store_pascal_string`, `store_real`, `store_string`, `store_var` |
| Core | `OS.execute_with_pipe` | Added optional `blocking` parameter |
| Core | `RegEx.compile/create_from_string` | Added optional `show_error` parameter |
| Rendering | `RenderingDevice.draw_list_begin` | Many parameters removed; `breadcrumb` parameter added |
| Rendering | `Shader.set_default_texture_parameter()` / `get_default_texture_parameter()` | Parameter/return type changed from `Texture2D` to `Texture`; the shading language did not change |
| Particles | `.restart()` method | Added optional `keep_seed` parameter (CPU/GPU 2D/3D) |
| GUI | `RichTextLabel.push_meta` | Added optional `tooltip` parameter |
| GUI | `GraphEdit.connect_node` | Added optional `keep_alive` parameter |

## 4.2 → 4.3 (In Training Data — LOW RISK)

| Subsystem | Change | Details |
|-----------|--------|---------|
| Animation | `Skeleton3D.add_bone` returns `int32` | Was `void` |
| Animation | `bone_pose_updated` signal | Replaced by `skeleton_updated` |
| TileMap | `TileMapLayer` replaces `TileMap` | One node per layer instead of multi-layer single node |
| Navigation | `NavigationRegion2D` | Removed `avoidance_layers`, `constrain_avoidance` properties |
| Editor | `EditorSceneFormatImporterFBX` | Renamed to `EditorSceneFormatImporterFBX2GLTF` |
| Animation | AnimationMixer base class | AnimationPlayer and AnimationTree now extend AnimationMixer |
