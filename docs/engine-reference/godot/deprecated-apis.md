# Godot — Deprecated APIs

Last verified: 2026-10-02 | Engine: Godot 4.7.2

If an agent suggests any API in the "Deprecated" column, it MUST be replaced
with the "Use Instead" column.

## Nodes & Classes

| Deprecated | Use Instead | Since | Notes |
|------------|-------------|-------|-------|
| `TileMap` | `TileMapLayer` | 4.3 | One node per layer instead of multi-layer node |
| `VisibilityNotifier2D` | `VisibleOnScreenNotifier2D` | 4.0 | Renamed for clarity |
| `VisibilityNotifier3D` | `VisibleOnScreenNotifier3D` | 4.0 | Renamed for clarity |
| `YSort` | `Node2D.y_sort_enabled` | 4.0 | Property on Node2D, not a separate node |
| `Navigation2D` / `Navigation3D` | `NavigationServer2D` / `NavigationServer3D` | 4.0 | Server-based API |
| `EditorSceneFormatImporterFBX` | `EditorSceneFormatImporterFBX2GLTF` | 4.3 | Renamed |

## Methods & Properties

| Deprecated | Use Instead | Since | Notes |
|------------|-------------|-------|-------|
| `yield()` | `await signal` | 4.0 | GDScript 2.0 coroutine syntax |
| `connect("signal", obj, "method")` | `signal.connect(callable)` | 4.0 | Callable-based connections |
| `instance()` | `instantiate()` | 4.0 | Renamed |
| `PackedScene.instance()` | `PackedScene.instantiate()` | 4.0 | Renamed |
| `get_world()` | `get_world_3d()` | 4.0 | Explicit 2D/3D split |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` | 4.0 | Time singleton preferred |
| `duplicate()` for nested resources | `duplicate_deep()` | 4.5 | Explicit deep copy control |
| `Skeleton3D` signal `bone_pose_updated` | `skeleton_updated` | 4.3 | Renamed |
| `AnimationPlayer.method_call_mode` | `AnimationMixer.callback_mode_method` | 4.3 | Moved to base class |
| `AnimationPlayer.playback_active` | `AnimationMixer.active` | 4.3 | Moved to base class |

## Patterns (Not Just APIs)

| Deprecated Pattern | Use Instead | Why |
|--------------------|-------------|-----|
| String-based `connect()` | Typed signal connections | Type-safe, refactor-friendly |
| `$NodePath` in `_process()` | `@onready var` cached reference | Performance: path lookup every frame |
| Untyped `Array` / `Dictionary` | `Array[Type]`, typed variables | GDScript compiler optimizations |
| `Texture2D` in `Shader.set_default_texture_parameter()` / `get_default_texture_parameter()` | `Texture` base type | Changed in 4.4; the shading language's `sampler2D` / `texture()` did not change |
| Manual post-process viewport chains | `Compositor` + `CompositorEffect` | Structured post-processing (4.3+) |
| GodotPhysics3D for new projects | Jolt Physics 3D | Default since 4.6; better stability |

## 4.6 → 4.7 (Jun 2026 — POST-CUTOFF, HIGH RISK)

Source: raw `.rst` of the official migration guide, **fetched 2026-10-02** —
https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/migrating/upgrading_to_godot_4.7.rst
The migration page calls these **breaking changes**; they are listed here because
each one means *code that used the old name or type stops working*.

| Deprecated / Removed | Use Instead | Since | Notes |
|----------------------|-------------|-------|-------|
| `AudioEffectSpectrumAnalyzer.tap_back_pos` | **no replacement listed in the guide** | 4.7 | **Property REMOVED.** GDScript-INCOMPATIBLE (❌). GH-114355 |
| `RichTextLabel.add_image` / `update_image` — params `width_in_percent` / `height_in_percent` (`bool`) | `width_unit` / `height_unit` (`RichTextLabel.ImageUnit`) | 4.7 | Renamed + retyped. GH-112617 |
| `ImageUpdateMask.UPDATE_WIDTH_IN_PERCENT` | `ImageUpdateMask.UPDATE_WIDTH_UNIT` | 4.7 | Enum field renamed. **GDScript INCOMPATIBLE (❌)**. GH-112617 |
| `RenderingServer.particles_request_process_time(time = …)` | `…(process_time = …)` | 4.7 | Parameter renamed; `process_time_residual` added. GH-109142 |
| `ImageTexture.get_format()` / `PortableCompressedTexture2D.get_format()` | `Texture2D.get_format()` | 4.7 | Moved to the base class. GH-109004 |
| `EditorSceneFormatImporter.IMPORT_*` constants | enum `ImportFlags` | 4.7 | `IMPORT_ANIMATION`, `IMPORT_SCENE`, `IMPORT_GENERATE_TANGENT_ARRAYS`, … GH-115788 |
| `OpenXRExtensionWrapper._on_register_metadata` | — | 4.7 | Signature gained `interaction_profile_metadata`. GDScript INCOMPATIBLE. GH-117399 |
| `EditorVCSInterface._commit` | — | 4.7 | Signature gained `amend`. GDScript INCOMPATIBLE. GH-117968 |

**Behavior-level changes — these still compile, but no longer behave the same:**

| Old behavior | New behavior | Notes |
|---|---|---|
| Boolean `sync` on `AnimationNodeBlendSpace1D` / `2D` | `SyncMode` enum (`sync_mode`) | Set `sync_mode` on each blend space if an `AnimationTree` misbehaves. In the `.rst`, **absent from the rendered HTML** when checked |
| `CanvasItem` line drawing added an antialiasing feather | No feather — **lines are thinner** | GH-105122. Draw a larger `width` if you relied on it |
| `InputEvent.device == 0` meant mouse/keyboard | `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD` | GH-116274. Compare against the constants, or branch on the event type |
| Setting an element of a packed array called the whole property's setter | It no longer does | GH-113228 |
| Overriding a typed-return method needed no explicit `return` | **It does** — add `return null` | GH-115763. A **parse error**, not a warning |
| `AudioStreamPlayer` default `area_mask` = layer 1 | `0` (disabled) | GH-107679. Only matters with `audio_bus_override` on `Area2D`/`Area3D` |
| `WorldBoundaryShape3D.plane.d` sign meant the opposite under Jolt (3D) | Now matches Godot Physics | GH-118948. **3D only; this project is 2D** |
