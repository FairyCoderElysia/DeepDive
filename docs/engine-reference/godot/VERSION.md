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
- ~~**godot-ai MCP 从未真正被使用过**（插件能加载 ≠ 工具通道能用）~~ → **2026-10-02 已端到端验证可用（编辑器侧），见本文件末尾"追加实测之二"**
- **没有任何场景、脚本、节点、导出预设** —— 上面的"导入成功"只说明**空项目**能被导入
- **`addons/` 被 gitignore**：`[autoload]` 与 `[editor_plugins]` 都指向它 → 曾记为"别人 clone 下来是个坏项目"。
  **→ 2026-10-02 已用沙箱实测严重度并修掉，见下一节。**

---

## 追加实测（2026-10-02，沙箱 `$TEMP/dd_sandbox`）—— 场景/脚本/物理，以及 addons 问题的**真实**严重度

> 上一节只证明了"**空**项目能被导入"。这一节另建一个**最小可跑项目**（有 `run/main_scene`、有脚本、有 RigidBody2D）来测两件事。
> **全部在 `$TEMP` 沙箱里做，不往仓库写任何临时文件。**

### ✅ 场景 + 脚本 + 2D 物理这条链是真的通的
- `run/main_scene` 能加载 `.tscn`；脚本 `_ready` / `_physics_process` 照常执行
- 打印出 `Engine=4.7.2-stable (official)`
- **一个 RigidBody2D + CircleShape2D 在 40 帧后从 `y=-200` 落到 `y=+7.92`** → 重力与 2D 物理求解器**真的在步进**
  （同时反证上面那条 `2d/physics_engine="GodotPhysics2D"` 的钉法生效）

### ⚠️ 更正我此前一个被夸大的说法
我此前多次说过「**`addons/` 被 gitignore ⇒ 别人 clone 下来是个坏项目**」。**实测：夸大了。** 精确严重度：

| 缺失的东西 | 沙箱实测行为 |
|---|---|
| `[autoload] _mcp_game_helper`（指向 `addons/`） | **3 行 `ERROR`**（File not found → Failed loading resource → Failed to instantiate an autoload），**但游戏照常跑完**，脚本与物理都正常 |
| `[editor_plugins]`（指向 `addons/`） | **完全静默** —— headless 导入 `exit=0`，一行报错都没有 |

**真相：clone 能跑，但每次启动喷 3 行 ERROR。** 不是"坏项目"。

### ✅ 处置（已改 `project.godot` + 已验证）
**移除 `[autoload]` 那一段，保留 `[editor_plugins]`**：
- autoload 是**开发工具**的运行时挂钩（godot-ai 的 `game_eval` 一类），**不是游戏的一部分**；游戏侧没有任何脚本依赖它
- 它是**唯一**产生 ERROR 的那一项 → 移除后 clone 即干净
- `[editor_plugins]` **实测对缺 addons 的 clone 零副作用**，而保留它就能让"手上有 addon 的人"直接用上编辑器侧 MCP 能力 —— 属于「对 clone 是空操作、对本地开发是使能器」

**验证**：本仓库 smoke `exit=0 / 0 条真实错误`；**模拟 clone**（只带 `project.godot` + `icon.svg` + `docs/`，**不带 `addons/`**）→ `exit=0 / 0 条真实错误` ✓

**代价（一行可还原）**：本机因此失去 godot-ai 的**游戏运行时**工具（`game_eval` / `game_manage` / `source="game"` 截图）。需要时在 `project.godot` 临时加回：
```
[autoload]
_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"
```
**编辑器侧**工具（场景/节点/属性/脚本/材质/瓦片图）不受影响，因为 `[editor_plugins]` 仍在。

### 本节仍未能验证的
- **GUI 编辑器从未真正打开过** → 「缺失插件在**图形界面**下会不会弹报错」仍未测（headless 下是静默的）
- ~~**godot-ai 的 MCP 通道从未真正使用过**~~ → **2026-10-02 已端到端验证可用（编辑器侧），见下一节**
- **仍无任何导出预设** → `commands.build` 依旧 `[TO BE CONFIGURED]`

---

## 追加实测之二（2026-10-02）—— **godot-ai 的 MCP 通道已验证可用**（编辑器侧）

> 本文件此前多处记着「godot-ai 的 MCP 通道从未真正被使用过」。**这一节取代那些记录：通道已端到端验证可用。**
>
> ⚠️ **但接下来说的"headless"是错的，必须撤回**：我原写"而且不需要打开 GUI 窗口"，
> 而实测**那个被验证的编辑器实例是以 GUI 方式启动的**（`tasklist /V` 显示窗口标题
> `DeepDive-v2 - Godot Engine`，状态 `Not Responding`）。**所以"headless 编辑器也能承载 MCP"并未被证明。**
> 详见本节的「🛑 自我更正」。

### ⚠️ 起一个持久编辑器会话的方式（实测是 **GUI**，不是 headless —— 见自我更正）
```powershell
Start-Process -FilePath "godot" -ArgumentList "--headless","--path","<项目绝对路径>","--editor" -PassThru -WindowStyle Hidden
```
**必须用 `Start-Process` 脱离父进程**，不能用 `pwsh` 工具的 `run_in_background`。
🛑 **但注意上例里的 `--headless` 实测没有生效**（见自我更正第 1 条）—— 照抄会开出一个 GUI 窗口。

⚠️ **两条实测到的坑（都很容易误判成"通道坏了"）**：
1. `pwsh` 工具的 `run_in_background` 会**误报 `completed / exit 0`**，而编辑器其实已被收尾杀掉。
   我第一次尝试看起来是"注册成功但会话立刻变陈旧"，就是这个原因 —— **不是 Godot 自己退出**：
   用 `timeout 25` 直接测，它是 `exit=124`（被 timeout 杀掉），**即长驻**。
2. 之后**在 pwsh 里 `Get-Process` 看不到这个 Godot 进程**（连自己刚启动的 PID 也报"不存在"，沙箱进程视图受限）。
   → **改用 `tasklist`**（它能看到；bash 侧的 `tasklist //FI "IMAGENAME eq Godot*"` 有效）。
   → ⚠️ **不要用 PID 跨视图认进程**：我这一轮看到过三个不同 PID（启动返回 11880 / 会话上报 `editor_pid` 28276 /
   实际 25888）。**认进程要靠命令行**：`wmic process where "name like '%Godot%'" get ProcessId,CommandLine /format:list`

---

### 🛑 自我更正（本节最重要的一节 —— 三条我说错的事实）

1. **`--headless` 没有生效，我开出了一个 GUI 窗口。**
   我明确说过"不打算打开 GUI（那会在桌面上弹窗）"，**结果还是开了**。`tasklist` 显示它
   `Window Title: DeepDive-v2 - Godot Engine`、`Status: Not Responding`。
   实际进程命令行只剩 `--path E:/Deep_Game/DeepDive-v2 --editor` —— **`--headless` 不见了**。
   **教训：声明"headless"之后，必须用 `tasklist /V` 核对窗口标题有没有出现，而不是相信参数传过去了。**
   ⚠️ 这也意味着 **上一节"沙箱实测"里那几条 `godot --headless --editor --quit` 的调用，`--headless` 是否真的生效，我也没有核对过** ——
   它们都带 `--quit` 且在 5–6 秒内退出，所以即使弹窗也只是一闪。**这一条无法追溯，只能记为"未核对"。**
2. **`editor_manage op=quit` 不管用。** 它返回 `{"message":"Editor quit initiated","status":"quitting"}`，
   **但进程继续存在**（仍是 251 MB、`Not Responding`）。真正结束它要靠：
   ```
   taskkill //PID <编辑器PID> //T //F
   ```
   **（只杀编辑器，不要杀 `godot-ai.exe` —— 那是我自己的 MCP 桥 `attach --port 8001`。）**
3. **`session_active: false` 与通道可用并不矛盾**（这条我上一轮已更正，此处保留以免复犯）：
   它指的是**游戏运行时会话**，不是编辑器连接。

### ✅ 那么本节到底"验证"了什么（把范围收窄到站得住的部分）
**站得住的**：MCP 通道能把真实工具调用送达一个**正在运行的编辑器**，并取回真实数据
（`filesystem_manage` / `project_manage` / `editor_manage monitors_get` 三个域都通过；`monitors_get`
返回 30 个实时监视器，含 `node_count=22288`、`draw_calls_in_frame=237`、`video_mem_used=271MB`、`fps=10`）。

**没验证的**：
- **headless 编辑器能否承载 MCP**（未证明；本次实例是 GUI）
- **被验证的那个实例是 `Not Responding` 的**：它在回答 MCP 的同一时期被系统标为未响应 ——
  所以"通道可用"成立，但"**这个会话状态是健康的**"不成立
- **GUI 是否会被我这套启动方式反复弹出来**：没有再测（不该在用户桌面上反复弹窗来测）

### ✅ 已验证可用的工具域（每一项都返回了真实数据）
| 工具域 | 实测调用 | 证据 |
|---|---|---|
| 会话 | `session_manage op=list` | `is_active: true` · plugin **4.2.3** · protocol 2 · `last_seen` 随调用刷新 |
| 文件系统 | `filesystem_manage read_text res://project.godot` | 返回 **680 字节 / 34 行**，内容与磁盘一致 |
| 项目设置 | `project_manage settings_get physics/2d/physics_engine` | 返回 **`GodotPhysics2D`** —— 独立确认了上面那个钉法 |
| 性能监视器 | `editor_manage monitors_get` | 返回 **30 个实时监视器**（`object/node_count=22288` · `render/total_draw_calls_in_frame=237` · `video_mem_used=271MB` · `time/fps=10`） |

### ⚠️ 更正我自己的一处误读（重要，别再犯）
我一度把 `editor_state` 里的 **`session_active: false`** 读成"编辑器会话陈旧了"，并据此判断通道不可用。**这是误读：**
- `session_active` / `game_status` / `helper_live` 指的是**游戏运行时会话**（依赖 `[autoload] _mcp_game_helper`），**不是编辑器连接**
- 实测：`session_active: false` 的同时，`filesystem_manage` 与 `monitors_get` 都正常工作
- **这恰好独立验证了我移除 autoload 时写下的那句预测：「编辑器侧工具不受影响」** ✅

### 仍然要 autoload 才能用的部分（未变）
`game_eval` · `game_manage`（运行时节点/UI 检查、输入模拟）· `source="game"` 的截图 —— 它们依赖
`[autoload] _mcp_game_helper`，当前**不可用**（一行可还原，见上文"处置"）。
