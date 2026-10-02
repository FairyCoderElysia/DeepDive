# Systems Index: 深海工艺（DeepDive: Process）

> **Status**: Draft
> **Created**: 2026-10-02
> **Last Updated**: 2026-10-02
> **Source Concept**: design/gdd/game-concept.md
> **生成方式**：`/map-systems`（`automation: guided` · `review_mode: lean`）
> **两个导演门按 `lean` 跳过并记录**：`TD-SYSTEM-BOUNDARY skipped — Lean mode.`（技能 201–203 行：`lean` 跳过且注明 not a PHASE-GATE）· `CD-SYSTEMS skipped — Lean mode.`（技能 328–331 行，同样注明 not a PHASE-GATE）

---

## Overview

本作是一个**无货币、无时限**的海洋星球工厂生存建造游戏。它的机械范围有个不寻常的形状：
**底座极窄、玩法极深**。底座是「元素池 + 化学计量 + 工艺图」三件套（Core 层 6 个系统里有一半是它们）；
而在此之上堆起来的，是**在同一套物料模型上反复做的判断**——每个旋钮有代价面、每个出口必须被接住、
每个污染物必须有去处、每次失败都必须可诊断。

所以本索引的重点**不是"系统多不多"，而是"谁是谁的基座"**：`A1 元素池与计量` 有 **9 个直接依赖者**，
它是全项目风险最高的地方（T0 已经踩过一次：`atomic_mass` 是后补的硬前置，补之前海水造不出水）。
核心动词是 **连**，而「连」的四种决策（纯化支线位置 / 出口选路 / 回流 / 分流比例）已由
`prototypes/t0b-connection-feel.html` 验证为**好玩**。

> **⚠️ 一处刻度反转，读之前必须先知道**：本索引使用**概念文档自己的** `T1 垂直切片 / T2 MVP / T3 完整愿景`。
> CCGS 的 `systems-index` 模板默认刻度是 `MVP → Vertical Slice → Alpha → Full Vision`，
> 即**默认把 MVP 排在切片之前**；而本项目概念文档定义的顺序**相反**（切片先于 MVP）。
> 我保留项目自己的刻度以免两份文档互相打脸，并在下面「Priority Tiers」里写明对应关系。

---

## Systems Enumeration

> `(inferred)` = 概念文档未直接提及、由枚举阶段推断出来的系统。

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | A1 元素池与计量系统 | Core | T1 | Not Started | — | — |
| 2 | A2 化合物与反应数据表 `(inferred)` | Core | T1 | Not Started | — | A1 |
| 3 | A3 反应求解器（限制试剂·化学计量） | Core | T1 | Not Started | — | A1, A2 |
| 4 | A4 Schema 双解释器与契约校验 | Core | T1 | Not Started | — | A1, A2 |
| 5 | A5 工艺图与连续流求解 | Core | T1 | Not Started | — | A3 |
| 6 | A6 参数与代价面 | Core | T1 | Not Started | — | A3 |
| 7 | B1 连线编辑与四种连线决策 | Gameplay | T1 | Not Started | — | A5, B2, B3, B4 |
| 8 | B2 污染物与失败通道（Cl / 结垢） | Gameplay | T1 | Not Started | — | A3, A6 |
| 9 | B3 纯度分级与分离提纯 | Gameplay | T1 | Not Started | — | B2, A1 |
| 10 | B4 氧气经济（无货币） | Economy | T1 | Not Started | — | A3 |
| 11 | B5 灾难与失控 | Gameplay | T1 | Not Started | — | A6, A3 |
| 12 | B6 储罐与容量 `(inferred)` | Gameplay | T1 | Not Started | — | A1 |
| 13 | B7 百科 | Gameplay | T1 | Not Started | — | A2, A3, A6, B3 |
| 14 | B8 渐进解锁 | Progression | T2 | Not Started | — | B1, A6, B7 |
| 15 | B9 工艺命名与工艺卡 | Progression | T2 | Not Started | — | A5, B7 |
| 16 | B10 诊断与反馈 | UI | T1 | Not Started | — | B2, B5, A3 |
| 17 | B11 HUD / UI `(inferred)` | UI | T1 | Not Started | — | B10, B3, B4, A6 |
| 18 | B12 热力图主图层 | UI | T2 | Not Started | — | A5, B4, B2 |
| 19 | B13 视觉身份·表层 | Visual | T2 | Not Started | — | A1 |
| 20 | B14 视觉身份·深度可读性 | Visual | T3 | Not Started | — | C1 |
| 21 | B15 音频 `(inferred)` | Audio | T2 | Not Started | — | B5, B1 |
| 22 | B16 存档 / 读档 `(inferred)` | Persistence | T2 | Not Started | — | A1, A5, B6, B8, C1, C3 |
| 23 | B17 新手引导 / 教程 | Meta | T2 | Not Started | — | A5, B1, B7, B8 |
| 24 | B18 设置与无障碍 `(inferred)` | Meta | T3 | Not Started | — | B11 |
| 25 | B19 性能预算与管网 tick | Technical | T1 | Not Started | — | A5 |
| 26 | C1 深度分层与通量阶梯 | World | T3 | Not Started | — | A5, B4 |
| 27 | C2 矿脉与开采 | World | T3 | Not Started | — | C1, A1 |
| 28 | C3 飞船与零件 | World | T3 | Not Started | — | A5, A3, C2 |
| 29 | C4 程序生成 | World | T3 | Not Started | — | C1, C2 |

> **编号说明**：A/B/C 前缀保留枚举阶段的模块分组，便于与评审对话对照；`B10`–`B19` 是原先的 D/E 组，
> 为满足本表的 Category 归类而重排了编号。**分类以 Category 列为准，前缀只作对照。**

---

## Categories

模板给的是通用分类；本作按需保留并新增了三个领域分类（`World` / `Visual` / `Technical`）。

| Category | Description | 本作对应 |
|----------|-------------|----------|
| **Core** | 所有系统都依赖的底座 | 元素池与计量 · 反应数据表 · 反应求解器 · Schema 校验 · 工艺图与连续流 · 参数代价面 |
| **Gameplay** | 让游戏好玩的那部分 | 连线编辑 · 污染物通道 · 纯度分级与分离 · 灾难 · 储罐容量 · 百科 |
| **Economy** | 资源的产生与消耗 | **氧气经济** —— ⚠️ 本作**没有货币**，唯一硬通货是氧气（Core Mechanics #6） |
| **Progression** | 玩家如何随时间成长 | 渐进解锁 · 工艺命名与卡 |
| **World** | 世界结构与内容生成（新增） | 深度分层与通量阶梯 · 矿脉开采 · 飞船与零件 · 程序生成 |
| **UI** | 面向玩家的信息呈现 | 诊断与反馈 · HUD · 热力图主图层 |
| **Visual** | 视觉身份与可读性（新增） | 表层视觉身份 · 深度可读性 |
| **Audio** | 声音与音乐 | ⚠️ **概念文档完全未提及**，本行是占位而非已定 |
| **Persistence** | 存档与连续性 | 存档 / 读档 |
| **Meta** | 核心循环之外 | 新手引导 · 设置与无障碍 |
| **Technical** | 性能与工程契约（新增） | 性能预算与管网 tick |

---

## Priority Tiers

**本表使用项目自己的刻度**（理由见文首的「刻度反转」说明）。

| Tier | Definition | 对应概念文档 | Design Urgency |
|------|------------|--------------|----------------|
| **T1 · 垂直切片** | 单条表层产线端到端跑通 + 氧气张力可感知 + 两条杂质通道 + 灾难可诊断 | 概念 T1（**先于** MVP） | **Design FIRST** |
| **T2 · MVP** | T1 全部 + 渐进解锁 + 工艺卡 + 热力图 + 表层视觉 + 教程 + 存档 | 概念 T2 | Design SECOND |
| **T3 · 完整愿景** | 下潜 → 深度与带宽 → 矿脉 → 飞船；含深度可读性与程序生成 | 概念 T3 | Design as needed |
| ~~Alpha~~ | 本项目不使用此刻度 —— 概念文档只定义了 T1/T2/T3 三档，不额外发明第四档 | — | — |

> **与模板默认刻度的对应关系**：模板 `MVP`≈本项目 `T2` · 模板 `Vertical Slice`≈本项目 `T1` ·
> 模板 `Full Vision`≈本项目 `T3` · 模板 `Alpha`≈**本项目不设**。
> **注意顺序相反**：模板默认"MVP 先、切片后"，本项目是"切片先、MVP 后"。

---

## Dependency Map

从下往上建：底层是基座，越往下越是包裹层。

### Foundation Layer（零依赖）

1. **A1 元素池与计量系统** —— 物料是 `{元素: 数量}` 的原子池；**全项目唯一的零依赖系统**，也是被依赖最多的（9 个直接依赖者）。它一旦改口径，上面全塌。

### Core Layer（只依赖 Foundation）

1. **A2 化合物与反应数据表** —— depends on: A1（化合物的标识符来自元素表）
2. **A3 反应求解器** —— depends on: A1, A2（按化学计量消耗生成，限制试剂决定谁先耗尽）
3. **A4 Schema 双解释器与契约校验** —— depends on: A1, A2（校验的正是这两张表）
4. **A5 工艺图与连续流求解** —— depends on: A3（图求值的语义来自求解器）
5. **A6 参数与代价面** —— depends on: A3
6. **B4 氧气经济** —— depends on: A3（氧的产出与消耗都来自反应结果）
7. **B6 储罐与容量** —— depends on: A1（存的是原子池）
8. **B2 污染物与失败通道** —— depends on: A3, A6（污染是"在此参数下"产生的）
9. **B3 纯度分级与分离提纯** —— depends on: B2, A1
10. **B5 灾难与失控** —— depends on: A6, A3

### Feature Layer（依赖 Core）

1. **B1 连线编辑与四种连线决策** —— depends on: A5, B2, B3, B4
2. **B7 百科** —— depends on: A2, A3, A6, B3
3. **B8 渐进解锁** —— depends on: B1, A6, B7
4. **C1 深度分层与通量阶梯** —— depends on: A5, B4
5. **C2 矿脉与开采** —— depends on: C1, A1
6. **C3 飞船与零件** —— depends on: A5, A3, C2
7. **C4 程序生成** —— depends on: C1, C2
8. **B19 性能预算与管网 tick** —— depends on: A5

### Presentation Layer（依赖 Feature）

1. **B10 诊断与反馈** —— depends on: B2, B5, A3
2. **B11 HUD / UI** —— depends on: B10, B3, B4, A6
3. **B12 热力图主图层** —— depends on: A5, B4, B2
4. **B13 视觉身份·表层** —— depends on: A1（色彩语义：青色只给氧、高饱和只给危险/异常）
5. **B14 视觉身份·深度可读性** —— depends on: C1
6. **B9 工艺命名与工艺卡** —— depends on: A5, B7
7. **B15 音频** —— depends on: B5, B1
8. **B17 新手引导 / 教程** —— depends on: A5, B1, B7, B8

### Polish Layer（依赖几乎全部）

1. **B16 存档 / 读档** —— depends on: A1, A5, B6, B8, C1, C3
2. **B18 设置与无障碍** —— depends on: B11

---

## Recommended Design Order

依赖顺序 + 优先级 + 瓶颈优先。每个 GDD 完成并评审后再开下一个；同层内相互独立的系统可以并行设计。

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | A1 元素池与计量系统 | T1 | Foundation | game-designer | M |
| 2 | A2 化合物与反应数据表 | T1 | Core | game-designer | M |
| 3 | A3 反应求解器（限制试剂·化学计量） | T1 | Core | game-designer | L |
| 4 | A4 Schema 双解释器与契约校验 | T1 | Core | game-designer + godot-gdscript-specialist | M |
| 5 | A6 参数与代价面 | T1 | Core | game-designer | M |
| 6 | A5 工艺图与连续流求解 | T1 | Core | game-designer | L |
| 7 | B4 氧气经济（无货币） | T1 | Core | game-designer | M |
| 8 | B6 储罐与容量 | T1 | Core | game-designer | S |
| 9 | B2 污染物与失败通道（Cl / 结垢） | T1 | Core | game-designer | M |
| 10 | B3 纯度分级与分离提纯 | T1 | Core | game-designer | M |
| 11 | B5 灾难与失控 | T1 | Core | game-designer | M |
| 12 | B1 连线编辑与四种连线决策 | T1 | Feature | game-designer | L |
| 13 | B7 百科 | T1 | Feature | game-designer | M |
| 14 | B10 诊断与反馈 | T1 | Presentation | game-designer | M |
| 15 | B11 HUD / UI | T1 | Presentation | godot-specialist | M |
| 16 | B19 性能预算与管网 tick | T1 | Feature | godot-gdscript-specialist | M |
| 17 | B8 渐进解锁 | T2 | Feature | game-designer | S |
| 18 | B9 工艺命名与工艺卡 | T2 | Presentation | game-designer | S |
| 19 | B12 热力图主图层 | T2 | Presentation | godot-specialist | M |
| 20 | B13 视觉身份·表层 | T2 | Presentation | godot-shader-specialist | M |
| 21 | B17 新手引导 / 教程 | T2 | Presentation | game-designer | M |
| 22 | B15 音频 | T2 | Presentation | game-designer | M |
| 23 | B16 存档 / 读档 | T2 | Polish | godot-gdscript-specialist | L |
| 24 | C1 深度分层与通量阶梯 | T3 | Feature | game-designer | L |
| 25 | C2 矿脉与开采 | T3 | Feature | game-designer | M |
| 26 | C3 飞船与零件 | T3 | Feature | game-designer | L |
| 27 | C4 程序生成 | T3 | Feature | godot-gdscript-specialist | L |
| 28 | B14 视觉身份·深度可读性 | T3 | Presentation | godot-shader-specialist | M |
| 29 | B18 设置与无障碍 | T3 | Polish | godot-specialist | S |

**Effort**：S = 1 个设计会话（产出完整 GDD）· M = 2–3 个会话 · L = 4+ 个会话。
**Agent 名**：按 `project.yaml` 的 `specialists` 块填的。⚠️ **本安装未核对 `.claude/agents/` 是否存在**
（与 `.claude/scripts/` 一样可能整块缺失）——`/design-system` 交接前必须先确认这两个名字真的可用，
否则把 `game-designer` 换成实际存在的 agent。

---

## Circular Dependencies

- **A3 反应求解器 ↔ A6 参数与代价面**（唯一一处，**已批准处置**）
  A6 要展示代价面就得调用 A3 求值；而 A3 用到的参数又由 A6 定义 —— 互为输入。
  **处置（契约拆分）**：把「有哪些旋钮、各自范围与单位」这份 **schema 下放到 A1/A2 的数据底座**，
  A6 只剩「表达代价面 + 让参数可见」。于是 **A6 → A3 变成单向**，循环解开。
  → 这意味着 **A1 的 GDD 必须包含"参数 schema"这一节**，不能只写元素表。

- **一处已消解的伪循环**：`B1 连线编辑 ↔ B3 纯度分级`。
  B1 的决策要用到 B3 的分离路线，而 B3 的机制不需要编辑器 → 单向，无环。

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| **A1 元素池与计量** | Design | **9 个直接依赖者**，是全项目基座。它改口径（加字段、改原子口径），上面全塌。T0 已踩过一次：`atomic_mass` 是后补的硬前置，补之前**海水连水都造不出来** | 按"以后一定会被改"来设计；GDD 里显式包含参数 schema（见循环依赖的处置） |
| **A5 工艺图与连续流** | Technical | Technical Risks #2：**数百管段下的 tick 开销**是首要性能风险；管网图与连续流是两个不同瓶颈 | 先做 `B19 性能预算` 的契约（求值循环怎么写），再放大规模；T1 就要有基准场景 |
| **C1 深度分层与通量阶梯** | Scope | **MVP 完全不测 P4**。不做"表层通量天花板"，"必须下潜"在体感上不存在，P4 会退化成一句设定 | 从 T1 起就必须把表层通量天花板做出来（已写入 Risks #8） |
| **B16 存档 / 读档** | Scope | 依赖 6+ 系统，却是**概念文档从未提及**的系统；一个"无时限 + 长线建造 + 工艺图"的游戏没有存档不成立 | 已改为「各系统自己交序列化契约」；每个 GDD 必须含一节"序列化契约" |
| **B5 灾难与失控** | Design | **无时限 ⇒ 灾难必须可复原**，否则"严谨的美感"会变成对第一个玩家的惩罚 | 灾难的 GDD 必须给出复原手段与代价（耗氧/停机） |
| **A4 Schema 双解释器** | Technical | Technical Risks #3：Python 与 GDScript 两侧各实现一遍校验，**契约必然漂移** | 契约必须显式维护；优先让一侧生成另一侧的期望值 |
| **B15 音频** | Design | **概念文档从头到尾没提过音频**，它不是"已定"，是空白 | 这是一次需要创意决定的设计，不是排期问题；见 Next Steps |
| **B3 纯度分级与分离** | Design | 用户修正过一次（提纯不是开关、是玩家搭的分离产线）；**大规模布线下会不会退化成琐碎管线活**仍未验证 | T1 的头号验证目标之一（本次只验到 5 节点、1 个关键决策） |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | **29** |
| Design docs started | 0 |
| Design docs reviewed | 0 |
| Design docs approved | 0 |
| **T1（垂直切片）系统已设计** | 0 / **16** |
| **T2（MVP）系统已设计** | 0 / **7** |
| **T3（完整愿景）系统已设计** | 0 / **6** |

---

## Next Steps

- [ ] 评审并批准本索引（`/design-review design/gdd/systems-index.md`）
- [ ] 按 Recommended Design Order 逐个设计：**从 A1 元素池与计量开始**（`/design-system a1-element-pool`）
- [ ] 每个 GDD 完成后跑 `/design-review`
- [ ] **首个系统 GDD 要顺手建 `design/registry/entities.yaml`**（评审 F5；第一批条目应是 `chem_elements` 与 `chem_compounds`）
- [ ] A1 的 GDD 必须含 **参数 schema**（解开 A3↔A6 循环）与 **序列化契约**（B16 的前置）
- [ ] **B15 音频需要一次创意决定**（概念文档从未涉及）——列进下一轮与用户讨论，不要默认成"以后再说"
- [ ] 相关交叉项：`/art-bible` 是 Concept 阶段的另一个必需交付物（`design/art/art-bible.md`），与 `B13/B14` 对应
- [ ] T1 系统设计完成后跑 `/gate-check technical-setup`
