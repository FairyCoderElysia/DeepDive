# Technical Preferences

<!-- project.yaml at the repo root is the machine-readable source of truth for
     engine, specialists, naming, performance, platform, and testing.framework.
     This file is the human-readable LEGACY FALLBACK: agents and skills resolve
     each key from project.yaml first and fall back here only when the
     project.yaml key is absent. /setup-engine dual-writes both.
     Forbidden patterns and allowed libraries are NOT migrated — they live only
     in this file. Populated by /setup-engine; updated as decisions are made. -->

## Engine & Language

- **Engine**: Godot
- **Language**: GDScript
- **Version**: 4.7.2（= 官方最新 stable，且与本机安装版一致）
- **Rendering**: Forward+ — 2D · 非 web 行（`§5.5.1` 的 shape 表）
- **Physics**: Godot Physics 2D — **不是 Jolt**。Jolt 是 Godot 的 **3D** 默认引擎；2D 未变

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: PC (Steam / Epic)
- **Input Methods**: Keyboard/Mouse
- **Primary Input**: Keyboard/Mouse — 由 §5 映射表推导（策略 / 模拟 / 管理类 → 键鼠）
- **Gamepad Support**: Partial — PC-only 行
- **Touch Support**: None — PC-only 行
- **Platform Notes**: 手柄需能完成全部核心操作，但不做手柄专用机制；**禁止 hover-only 且无替代路径的交互**（键鼠优先）

## Naming Conventions

- **Classes**: PascalCase
- **Variables**: snake_case
- **Signals/Events**: past_tense
- **Files**: snake_case
- **Scenes/Prefabs**: snake_case
- **Constants**: SCREAMING_SNAKE

## Performance Budgets

- **Target Framerate**: [TO BE CONFIGURED] — 用户选择留待知道目标硬件后再定
- **Frame Budget**: [TO BE CONFIGURED]
- **Draw Calls**: [TO BE CONFIGURED]
- **Memory Ceiling**: [TO BE CONFIGURED]

## Testing

- **Framework**: gdUnit4 — 必须与 `commands.test` 的 runner（`res://addons/gdUnit4/bin/GdUnitCmdTool.gd`）一致
  > ⚠️ `addons/gdUnit4/` **尚未安装**，`tests/` 也还不存在 → 在 `/test-setup` scaffold 之前，`commands.test` 跑不了。
- **Minimum Coverage**: [TO BE CONFIGURED]
- **Required Tests**: Balance formulas, gameplay systems, networking (if applicable)

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here -->
- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist
- **Shader Specialist**: godot-shader-specialist
- **UI Specialist**: godot-specialist
- **Additional Specialists**: godot-gdextension-specialist
- **Routing Notes**: 架构与通用引擎决策走 primary；所有 `.gd` 代码走 GDScript specialist；着色器与材质走 shader specialist；`.tscn` / `.tres` 场景与 Control / theme 走 primary；GDExtension / native 插件走 gdextension specialist。

> **来源说明（诚实标注）**：技能 §5 引用的 `references/godot-language-config.md`（A1 命名 / A2 输入 / **A3 路由**）
> **在该技能目录下不存在**——只有 `SKILL.md`。命名约定取自 `SKILL.md` §5.5.1 的**内联表**（有据可依）；
> 上面的 **specialist 路由与文件类型路由是按内联 `specialists` 表 + 同文件 Unity/Unreal 示例的形状推导的**，
> 不是原文。要改随时改。

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (`.gd` files) | godot-gdscript-specialist |
| Shader / material files (`.gdshader`, `.gdshaderinc`, material `.tres`) | godot-shader-specialist |
| UI / screen files (`.tscn` with Control nodes, theme resources) | godot-specialist |
| Scene / prefab / level files (`.tscn`, `.tres`) | godot-gdscript-specialist |
| Native extension / plugin files (`.gdextension`, GDExtension C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
