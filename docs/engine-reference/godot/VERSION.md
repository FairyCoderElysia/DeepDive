# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.7.2 |
| **Installed at pin time** | `4.7.2.stable.official.ed1daf0bf` — probe **ran**: bare `godot --version` (bare `godot` resolves via a hardlink shim in `~/.local/bin`, so `commands.*` use bare `godot` and carry no local path) |
| **Release Date** | 18 August 2026 (4.7.2 stable) |
| **Project Pinned** | 2026-10-02 |
| **Last Docs Verified** | 2026-10-02 |
| **LLM Knowledge Cutoff** | May 2025 |

## Knowledge Gap Warning

The LLM's training data likely covers Godot up to ~4.3. Versions 4.4, 4.5, 4.6,
**4.7** and **4.7.2** introduced changes the model does NOT know about. Always
cross-reference this directory before suggesting Godot API calls.

## Installed-Version Gap Warning

**Pinned == installed on this project (4.7.2), so there is NO installed-version gap.**
The reference set is *not* ahead of the editor, so a version-qualified claim taken
from these files should compile locally.

> Keep this paragraph honest if the pin ever moves. The section exists because the
> reverse gap is real: `/setup-engine` §3 can deliberately pin a version *newer*
> than the installed editor, and an agent citing the reference correctly would then
> emit APIs that do not compile locally. `NOT DETERMINED` means the gap is unknown,
> not absent.

## Post-Cutoff Version Timeline

| Version | Release | Risk Level | Key Theme |
|---------|---------|------------|-----------|
| 4.4 | ~Mid 2025 | MEDIUM | Jolt physics option, FileAccess return types, shader texture type changes |
| 4.5 | ~Late 2025 | HIGH | Accessibility (AccessKit), variadic args, @abstract, shader baker, SMAA |
| 4.6 | Jan 2026 | HIGH | Jolt default, glow rework, D3D12 default on Windows, IK restored |
| **4.7** | **18 Jun 2026** | **HIGH** | **`AnimationNodeBlendSpace*.sync_mode` enum replaces the `sync` bool; `CanvasItem` line AA feather removed; mouse/keyboard device-ID constants; GDScript typed-return inheritance now requires an explicit `return`; macOS 11 minimum; new-project stretch defaults changed** |
| **4.7.2** | **18 Aug 2026** | **HIGH** | **Maintenance release (stable). Specific fixes: `NOT SOURCEABLE` — see the note below.** |

> **4.7 / 4.7.1 / 4.7.2 maintenance specifics are `NOT SOURCEABLE` in this run.**
> Only the version's **existence and date** were verified
> (`https://godotengine.org/versions.json`). The maintenance release notes page
> (`https://godotengine.org/article/maintenance-release-godot-4-7-2/`) was **not
> fetched**, so **no claim about what 4.7.1 or 4.7.2 changed is recorded here**.
> Treat 4.7.2 as *"4.7 plus unlisted maintenance fixes."* Run
> `/setup-engine refresh` to source it properly.

## Scope Note — where the 4.7 delta lives

The `modules/` files in this directory describe subsystems **up to 4.6** (they
arrive from the CCGS template's curated set, which v2 had never received until
this run). The **4.7 delta is recorded in the three top-level files**:
`breaking-changes.md § 4.6 → 4.7` · `deprecated-apis.md § 4.6 → 4.7` ·
`current-best-practices.md § 4.7`. It was deliberately **not** duplicated into
`modules/` — one source of truth beats four paraphrases.

**Before trusting a `modules/` claim on an affected subsystem** (input, physics,
rendering, ui, animation, audio, core), cross-check it against
`breaking-changes.md § 4.6 → 4.7` first.

## Verified Sources

Everything below was **fetched in this run (2026-10-02)** unless explicitly marked
as a *template baseline* (i.e. carried over from the CCGS template and NOT
re-verified this run — do not treat those as freshly confirmed).

- **Godot docs source repo (authoritative source pointed at by the user):**
  https://github.com/godotengine/godot-docs
- **4.6 → 4.7 migration guide — raw `.rst`, fetched this run:**
  https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/migrating/upgrading_to_godot_4.7.rst
  (rendered equivalent: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.7.html)
  > The `.rst` is the **more complete** source: the `AnimationNodeBlendSpace*.sync_mode`
  > behavior change and the macOS 11 minimum both appear here but were **absent from
  > the rendered HTML** when checked in the same run.
- **Version list & release dates — fetched this run:** https://godotengine.org/versions.json
- *Template baseline, NOT re-fetched this run:*
  - Official docs: https://docs.godotengine.org/en/stable/
  - 4.5→4.6 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.6.html
  - 4.4→4.5 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.5.html
  - Changelog: https://github.com/godotengine/godot/blob/master/CHANGELOG.md
  - Release notes 4.6: https://godotengine.org/releases/4.6/

---

## 本机实测（2026-10-02）—— 引擎侧不再是"完全未验证"

> 起因：Technical Risks #1 记的是「**Godot 编辑器至今从未启动过，引擎侧一切未验证**」。
> 这一节把该风险降到"已冒烟"，并把实测数据留档，供以后比对。
> **环境**：本机 `godot` 经 shim 指向真实的 4.7.2 可执行文件（`--headless --version` 已确认）。

| 检查 | 命令 | 结果 |
|---|---|---|
| 二进制与版本 | `godot --headless --version` | `4.7.2.stable.official.ed1daf0bf` · exit=0 |
| **GDScript 能执行** | `godot --headless --path . -s <script.gd>` | ✅ 打印出 `2+2=4`、`Engine=4.7.2-stable (official)` |
| **项目能被导入** | `godot --headless --editor --quit` | ✅ **exit=0 / 约 5–6 秒 / 0 条真实错误**，并生成 `.godot/` 导入缓存 |
| 编辑器插件能加载 | 同上（`[editor_plugins]` 指向 `addons/godot_ai/plugin.cfg`） | ✅ 导入过程走完 `loading_editor_layout → DONE` |

### ✅ 一条可用的 smoke 命令（已写回 `project.yaml`）

```
godot --headless --editor --quit
```
**它不需要 `run/main_scene`**，且真的跑了一遍资源导入与脚本类扫描。

### ⚠️ 更正一条旧记录
本项目断点里曾写：`--quit-after 5` 会打印 `Can't run project: no main scene defined` **且不退出、必须套 timeout**。
**实测：它 2 秒内就退出，exit=1。** 旧记录是错的。真实情况是——
**这条命令因为缺 `run/main_scene` 而完全无效**（永远报错、从不做任何检查），所以必须换掉，而不是"加个 timeout 硬扛"。

### ⚠️ 两条配置事实（本次新查，避免以后猜）

1. **2D 物理引擎原先没有被钉住**：`project.godot` 只有 `3d/physics_engine="Jolt Physics"`，
   而 `physics/2d/physics_engine` 读到的是 `DEFAULT`。已按 `project.yaml` 的既定决策补上
   **`2d/physics_engine="GodotPhysics2D"`**（补后引擎读到 `GodotPhysics2D` ✓）。
   > **合法取值来自引擎本身**（`ProjectSettings.get_property_list()` 的 `hint_string`）：
   > - 2D：`DEFAULT,GodotPhysics2D,Dummy`
   > - 3D：`DEFAULT,Jolt Physics,GodotPhysics3D,Dummy`
   >
   > **注意 2D 的值没有空格（`GodotPhysics2D`），而 3D 有（`Jolt Physics`）。**
   > 照 3D 的样子猜成 `"Godot Physics 2D"` 就会写错 —— 所以这类值只能问引擎，不能猜。
2. **Windows 渲染驱动被设为 `d3d12`**（`rendering_device/driver.windows="d3d12"`）。
   与 `project.yaml` 的 `Forward+` **不冲突**（Forward+ 可用 Vulkan 或 D3D12），但它是
   **Windows 专属**、且 D3D12 后端与 Vulkan 在着色器兼容性上历来有差异。
   **本回合未改动**（合法选择，不是缺陷），仅记一笔：将来若出现"某着色器在别人机器上不对"，先看这里。

### ❌ 仍未被验证的部分（不要把上面这节读成"引擎侧都验过了"）
- **编辑器 GUI 从未真正打开过**（全是 `--headless`）
- **godot-ai MCP 从未真正被使用过**（插件能加载 ≠ 工具通道能用）
- **没有任何场景、脚本、节点、导出预设** —— 上面的"导入成功"只说明**空项目**能被导入
- **`addons/` 被 gitignore**：`[autoload]` 与 `[editor_plugins]` 都指向它 → **别人 clone 下来会是一个报错的 Godot 项目**（未决）
