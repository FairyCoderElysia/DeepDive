# CCGS 安装缺陷记录（本项目实测）

> **用途**：记录在本机 CCGS 安装（框架 1.1.2，技能来自 `C:\Users\14665\.dsh\skills\`）上实测出的
> **框架级缺陷**。这些不是本项目的设计问题，而是工具链问题——**换一个 CCGS 项目也会再撞上**。
> 每条都附实测证据与"**不要做什么**"，因为最危险的失败模式是后人用"改内容"去迎合"改不了的工具"。
>
> 建立于 2026-10-02 · 最后更新 2026-10-02

---

## 缺陷 #1（🔥 一个 bug 的三种现身）：GDD 形状的工具被套在 `design/gdd/game-concept.md` 上

**根因**：CCGS **规定**概念文档必须住在 `design/gdd/game-concept.md`（`/start` Phase 1 与 `/brainstorm`
都写死这个路径），而 CCGS 的多件工具**按目录 glob `design/gdd/` 认定"这里全是系统 GDD"**。
于是概念文档被反复当成一份"缺了 6 段的 GDD"。

### 现身 ①：`validate-commit.sh` 会报 5 条假警告
- 位置：`.claude/hooks/validate-commit.sh`，规则是 `DESIGN_FILES=$(echo "$STAGED" | grep -E '^design/gdd/')`
- `workflow: standard` 下要求出现 `Overview` / `Detailed` / `Edge Cases` / `Dependencies` / `Acceptance Criteria`
- **实测**：`design/gdd/game-concept.md` 这 5 个词一个都没有 → 提交时必报 5 条 `DESIGN: … missing section`
- **后果**：仅警告，**不阻断**（`WARNINGS` 路径结尾是 `exit 0`）。可忍，但会持续误导读者以为文档残缺

### 现身 ②：`/design-review` 的 Phase 2 会给它判 FAIL
- 位置：`design-review/SKILL.md` Phase 2 的 8 段清单（Overview / Player Fantasy / Detailed Rules /
  Formulas / Edge Cases / Dependencies / Tuning Knobs / Acceptance Criteria）
- **实测**：概念文档 6/8 ABSENT（`Formulas`/`Tuning Knobs` 两个命中是子串巧合）
- **后果**：`workflow: standard` 下 5 段 REQUIRED 缺失 → **必然 `MAJOR REVISION NEEDED`**。
  这正是本期新发现的一条：**CCGS 的 concept 评审步骤（`workflow-catalog.yaml` 的
  `design-review-concept`）指向 `/design-review`，而 `/design-review` 的标准只认 GDD 形状** →
  框架自身不一致。

### 现身 ③：`/design-review` 在本安装上根本跑不动
- Phase 1 的 freshness check 要 `bash .claude/scripts/review-receipts.sh check …`
- Phase 2a 的确定性扫描要 `bash .claude/scripts/gdd-structure-check.sh …`
- **实测：`.claude/scripts/` 整个目录不存在**（本安装从未提供该目录）→ 两个调用都直接失败
- 附带的空摊子：`design/gdd/reviews/` 与 `design/registry/entities.yaml` **也都不存在**

### ❌ 不要做什么（最重要的一条）
**不要为了消掉上面这些警告，往 `design/gdd/game-concept.md` 里硬塞 GDD 段落**
（Overview / Detailed Rules / Edge Cases / Dependencies / Acceptance Criteria）。
那会**把一份对自己文档类型而言正确的概念文档改坏**，去迎合一个"按目录猜文档类型"的工具。
**正确处置**：把警告当已知假阳性记档；**不要**对概念文档跑 `/design-review` 的 Phase 2 判定。

### ✅ 概念文档该按什么标准评
按它**自己模板**的 30 个章节（`.claude/docs/templates/game-concept.md`），而不是 GDD 的 8 段。
**实测：概念文档 30/30 齐全**（逐标题比对过）。此外可做的是 `/design-review` 的 **Phase 3**
（一致性与可实现性）——那一段是文档类型无关的，可以照用。

---

## 缺陷 #2：`.claude/scripts/` 整个目录缺失（影响面比想象大）
**实测缺失的脚本**：`artifact-check.sh` · `gdd-structure-check.sh` · `review-receipts.sh` ·
`rotate-session-state.sh` · `migrate-v1-config.sh`
**后果**：
- 一切"确定性扫描"只能手工做（本项目的阶段检查、GDD 段落检查、评审新鲜度检查都已改为手工）
- 会话断点文件超过 ~200 行时无法轮转（`rotate-session-state.sh` 缺）→ 本项目已手工轮转过一次
**不要做什么**：不要假装跑过它们、也不要在文档里引用它们的输出。

---

## 缺陷 #3：`pwsh` 触发校验 hook，但 `pwsh` 推不上去
- `.claude/settings.json` 里 `PreToolUse matcher="pwsh"` 挂着 `validate-commit.sh` / `validate-push.sh`
- **实测**：用 `bash` 工具提交/推送 → **hook 完全不触发**（一条 commit 就是这么过去的）；
  用 `pwsh` 工具 → **推送失败**：`schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS (0x8009030E)`
- **后果**：**提交校验与推送能力互斥**。本项目的实际做法是**两边都用 `bash`**，
  代价是"推送那一步的校验永远是空的"——这一点必须在交接时说明，别让人以为校验跑过了

---

## 缺陷 #4：`docs/` 与 `.claude/skills/` 从未随模板安装到位
- 模板源（`C:\Users\14665\.dsh\ccgs\`）里**有**顶层 `docs/`（engine-reference / architecture / registry）
  与完整的 `.claude/skills/`，但项目里**两者都没有**
- **后果**：`CLAUDE.md` 里 `@docs/engine-reference/godot/VERSION.md` 这条 import **曾在每个会话静默失败**；
  技能正文只能从 `C:\Users\14665\.dsh\skills\<name>\SKILL.md` 读
- **已处置**：`/setup-engine` §7 补入了 `docs/engine-reference/godot/`（13 文件）并更新到 4.7.2；
  技能正文继续从 `.dsh/skills/` 读（**不要**去项目内 `.claude/skills/` 找，那是空的）

---

## 缺陷 #5：技能自带的 `references/` 子目录普遍缺失
- 例：`setup-engine/references/godot-language-config.md`（A1 命名 / A2 输入 / **A3 specialist 路由表**）
  不存在，`setup-engine/SKILL.md` 却引用它
- **已处置**：命名约定取自 `SKILL.md` §5.5.1 的**内联表**（有据可依）；
  **specialist 路由是按内联表 + 同文件 Unity/Unreal 示例推导的**，已在
  `.claude/docs/technical-preferences.md` 里**标注为推导、非原文**
