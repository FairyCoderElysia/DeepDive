# Test Infrastructure — 深海工艺（DeepDive: Process）

**Engine**: Godot 4.7.2 · **Language**: GDScript
**Test Framework**: GdUnit4 **6.2.0**（已装在 `addons/gdUnit4/`）
**CI**: `.github/workflows/tests.yml`
**Setup date**: 2026-10-02（`/test-setup`）

---

## 目录布局

```
tests/
  unit/           # 隔离的单元测试（公式 / 状态机 / 逻辑）—— 每个系统一个子目录
  integration/    # 跨系统测试与存档往返
  smoke/          # critical-paths.md —— 15 分钟人工门（/smoke-check 读它）

production/qa/
  evidence/       # 截图日志与人工签收记录
```

> **人工证据放在 `production/qa/evidence/`，不在 `tests/`** ——
> `/smoke-check` · `/test-evidence-review` · `/story-done` 读的都是那一个位置。

---

## 跑测试

**⚠️ 必须先 import，再跑测试** —— 顺序反了会 exit 1：

```bash
godot --headless --path . --import
godot --headless -s -d --remote-debug tcp://127.0.0.1:0 \
      res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
```

**为什么那样拼**（全部由 `/test-setup` 的技能给定，且**已在本机实测**）：

| 参数 | 为什么必须有 |
|---|---|
| `--import`（先跑） | 新克隆没有 `.godot/` 类缓存 → 不 import 会 **exit 1**（`GdUnitCmdTool.gd` 加载失败，一个测试都没跑） |
| `-a res://tests` | 跑 `tests/` 下所有套件 |
| `--ignoreHeadlessMode` | 不加它 gdUnit4 **会拒绝 headless 运行** |
| `--remote-debug tcp://127.0.0.1:0` | **不加它会卡在 `debug>` 提示符上不退出**（脚本错误会打开交互式调试器） |
| `--path .` | 项目根 |

**退出码**（技能给定，Godot 4.6.1 + gdUnit4 6.1.3 实测；本机 4.7.2 + 6.2.0 已复验链路）：

| 码 | 含义 |
|---|---|
| **0** | **全部通过** |
| **100** | **有测试失败** |
| **101** | 全部通过，但有测试泄漏了节点（警告，不是失败） |
| 103 / 104 | gdUnit4 跑不起来（headless 被拒 / Godot 太旧） |
| 105 | **某个测试脚本解析不过** |

> **⚠️ 两条容易误判的**：
> 1. 每次运行都会打印两行关于 `127.0.0.1:0` 的 `ERROR:` —— **那是预期的，不是失败**。
> 2. **`No test cases found` + exit 0【不是通过】** —— 那是"一个测试都没找到"。

### ⚠️ 一条 CI 陷阱（**本项目实测发现，2026-10-02**）

**一个【解析不过】的测试文件会被扫描器【静默跳过】—— 于是报告是 `No test cases found` + exit 0，
而不是它本该报的 105。**

**→ 后果很严重：一个坏掉的测试文件会让 CI 通过。**

本项目就踩了一次：第一版示例测试里 `assert_float(...).is_equal_approx(1.0)` 少传了一个参数
（gdUnit4 6.2.0 的签名是 `is_equal_approx(expected, approx)`），于是扫描器在
`GdUnitTestSuiteScanner.gd:225` 抛 Parse Error 并**跳过了整个文件**，
而外层看到的是"No test cases found"→ exit 0。

**→ 而更可靠的通道是【结构化报告】，不是人读的输出流**（2026-10-03 实测教训）：

gdUnit4 每次都写 `reports/report_<N>/results.xml`。**读它**：

```python
import xml.etree.ElementTree as ET
r = ET.parse("reports/report_N/results.xml").getroot()
print(r.get("tests"), r.get("failures"))            # 权威计数
for tc in r.iter("testcase"):
    f = tc.find("failure")
    if f is not None: print(tc.get("name"), f.get("message"))
```

**为什么**：我曾连续 8 次用正则去解析那次运行的**终端输出**（带 ANSI 色码、换行时机不确定），
**8 次全部误判** —— 其中一次让我以为"有 3 个测试没被发现"，还花了一整轮去查一个不存在的 bug；
而 XML 里写着 `tests=41`，**41 个一个不少**。
**→ 人读的输出是给人看的；判据要取结构化的那份。**

**→ 防御办法（写测试时照做）**：**新增/修改测试文件后，必须看到它出现在 `Executed test suites: (N/M)` 里**
—— 只要 `N` 对得上你期望的套件数，就说明没有文件被静默跳过。
**只看到 exit 0 是不够的。**

---

## 命名规范（`.claude/rules/test-standards.md`）

- **文件**：`[system]_[feature]_test.gd` —— 例如 `element_pool_seawater_test.gd`
- **函数**：`test_[scenario]_[expected]()` —— 例如 `test_mass_fraction_to_atoms_preserves_h_o_ratio()`
- **一个子目录一个系统**：`tests/unit/element_pool/` · `tests/unit/reaction_solver/` …

---

## 安装 GdUnit4（**已经装好了 —— 这里是给新机器 / 重装时用的**）

1. Godot → **AssetLib** → 搜 `GdUnit4` → Download & Install
2. **启用插件**：Project → Project Settings → Plugins → **GdUnit4 ✓**
3. 重启编辑器
4. 验证：`res://addons/gdUnit4/bin/GdUnitCmdTool.gd` **存在（注意大写 U）**

> **⚠️ 大小写很重要**：目录必须是 `addons/gdUnit4/`（**大写 U**）。
> Windows 的文件系统不区分大小写，**所以本地永远看不出问题** ——
> **而 CI 跑在 Linux 上，那里 `gdunit4` 与 `gdUnit4` 是两个不同的路径。**
> （本项目 `commands.test` 与 CI 都写的是大写 U，已对齐。）

---

## Story Type → 测试证据

| Story 类型 | 需要的证据 | 位置 |
|---|---|---|
| **Logic**（公式 / 状态 / 逻辑） | 自动化单元测试 —— **必须通过** | `tests/unit/[system]/` |
| **Integration**（跨系统 / 存档） | 集成测试**或** playtest 文档 | `tests/integration/[system]/` |
| **Visual/Feel** | 截图 + 负责人签收 | `production/qa/evidence/` |
| **UI** | 每个改动过的界面的留存截图 | `production/qa/evidence/` |
| **Config/Data** | smoke 通过 | `production/qa/smoke-*.md` |

> **本项目的一条附加约定**：**每一份 GDD 的 §Acceptance Criteria 都是测试用例的来源。**
> 写测试时不要自己另想"该测什么" —— **去那份 GDD 的验收表里逐条对应**。
> （26 份 GDD 的验收条目总数已远超一个 T1 能覆盖的量，所以按 T1 优先级取。）

---

## CI

`.github/workflows/tests.yml` —— 每次 push 到 `main` 与每个 PR 都跑。
**测试失败会挡住合并。**

> **⚠️ 一个 CI 上的坑（技能已给定）**：新仓库的 token 是只读的，
> **没有 `checks: write` 权限时，即使全部测试通过 job 也会失败。**
> 另外：**若给 `main` 设了保护规则，要勾的 check 是 `Run GdUnit4 Tests`，不是 `test-results`** ——
> 后者即使有测试失败也会报 success。
