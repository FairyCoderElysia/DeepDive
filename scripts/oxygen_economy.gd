class_name OxygenEconomy
extends RefCounted
## B4 · 氧气经济 —— **本作唯一的记账层**（**纯函数集：它不持有任何余额**）
##
## 【它的形状与前面六个系统都不同】A1–A6 给事实与表达；**B4 把事实记成一本以氧为单位的账**
## （`oxygen-economy.md` §Overview：它的定位不是"一个资源系统"，而是"**代价的记账单位**"）。
##
## ⚠️⚠️ **第一号不可违反的约束（Core Rule ②）：氧只有一个池。** ⚠️⚠️
##   它同时是**生命维持**与**助燃物**，而**这两件事是同一个数字**。
##   任何把它拆成两个数字的实现，**都会拆掉整个张力的支点** ——
##   而"两个数字"**不限于按角色分**：**"谁持有"分出两份也是两个数字。**
##
##   ★ 所以**本类【故意不持有余额】**（2026-10-03 用户拍板）：
##     那个【唯一的数字】由**化合物账**持有（A5/A2 的账里 `O2` 这一个化合物的存量），
##     而 B4 只提供**纯函数**：算收支 · 算状态 · 算分配 · 算积分。
##     ⇒ "只有一个池"这件事**在结构上成立**：**这里没有地方可以漂移出第二个数。**
##     （若本类自己也存一份，那就会有两个数字 —— 而它们是会飘的。）
##
## 【它不拥有什么】（§Tuning Knobs 的边界，必须写明）
##   参数旋钮属 **A1** · 档位属 **B3** · 罐容上限属 **B6** · 代价的呈现属 **A6**。
##
## 【"游离氧"怎么认】（④ 的实现边界）
##   **不需要改 A1 或 A3** —— 游离氧**就是 A2 化合物表里的 `O₂` 那个化合物**。
##   A1 的池记的是**元素原子数**（含水里那些氧），而 A2 的表区分了 O 是以 `H₂O` 还是 `O₂` 存在。
##   ⇒ 所以"水里有氧却不能呼吸"不是特例规则，**是化合物模型本来就支持的区分**。

const SCALE: int = ElementPool.SCALE

## ★ A2 化合物表里 `O₂` 的组成式 key —— **"可用氧"只认它**（水里的氧不算，用户拍板）。
const O2_KEY := "O2"

# ────────────────────────────────────────────────────────────────────────────
# ⚠️⚠️ 以下四个数在 B4 的 GDD 里**全部是 `[待定]`**（§Tuning Knobs）。
#     做成常量并**逐个标"暂定"**，是为了让账目层能被测试 ——
#     **但它们没有被定过**：它们是"先让它能跑"，不是"设计结论"。
#     其中第一个（生命维持率）GDD 原话是「**决定整个游戏的紧张度** —— 它是最重要的一个数」，
#     而它的手感取决于另一个数（C1 的表层通量天花板），那个还没实现。
# ────────────────────────────────────────────────────────────────────────────

## 生命维持基础耗氧率（氧 / 秒）—— **暂定 0.7**（2026-10-04 用户拍板）。
##
## ★ 为什么是 0.7：**它必须与"上限产能"成比例，张力才存在**。按 T1 与 C1 天花板算出来：
##     天花板 3.0 份/s ⇒ 水拿 2.135 份/s ⇒ 最多 1.067 批/s ⇒ **上限产能 ≈ 1.07 O₂/s**
##   而原值 0.05 只占 **4.7%** ⇒ 氧几乎免费 ⇒ **张力在算术上就不存在**（实测：收支一直 +0.5~1.0/s）。
##   0.7 占 **≈66%**：**活着是主要开销、工业是次要的** —— 玩家必须主动决定能负担多少产线，
##   那正是 B4 验收 1 要的"**为留氧而放弃产出**"的处境。
##
## ⚠️ 它仍然是**暂定值**：GDD 原话「决定整个游戏的紧张度 —— 它是最重要的一个数」，
##   而它的手感**只能靠玩家验收**（B4 的验收 1 是 ≥70% 的真人）。
const LIFE_SUPPORT_RATE := 0.7

## 存贮耗氧系数（氧 /（秒·存储量））—— **暂定**。推论 2：**它是速率，不是一次性扣费**。
const STORAGE_COEF := 0.001

## 销毁耗氧系数（氧 / 单位物质）—— **暂定**。推论 3：销毁**也**耗氧（把物质弄没不是免费的）。
const DESTROY_COEF := 0.5

## 三级分配的触发阈值（存量比例 0–1）—— **暂定**。存量比例低于它 ⇒ 从"正常"切到"分配"。
const TIGHT_THRESHOLD := 0.25

## 氧紧张时的三级优先（F-B4-1）。**顺序即语义**，而它**不是三个池**。
## 第二级（产氧链本身）存在的唯一理由：**避免死锁** ——
##   "工业全停"会让制氧设备也停 ⇒ 永远无法产氧 ⇒ 不可恢复，那违反全项目"所有状态可复原"的纪律。
enum Priority { LIFE_SUPPORT = 1, OXYGEN_CHAIN = 2, OTHER_INDUSTRY = 3 }

## 账目状态（§States）。`depleted` **必须是一个可离开的状态**（靠第 2 级产氧链恢复）。
const STATE_SURPLUS := "surplus"
const STATE_BALANCED := "balanced"
const STATE_DEFICIT := "deficit"
const STATE_DEPLETED := "depleted"


# ============================================================ ① 收支（纯函数）

## 本 tick 的收支**速率**。返回速率，**不改变任何东西** —— 本类没有任何东西可改。
##
## `produced`/`industrial`：来自 A3 的事实（本 tick 产氧 / 工业耗氧的速率）。
## `stored_amount`：当前存了多少（B6 提供），存贮耗氧 = 系数 × 存量 —— **是速率**。
## `destroyed_amount`：本 tick 销毁了多少物质。
static func net_rate(produced: float, industrial: float, stored_amount: float = 0.0,
		destroyed_amount: float = 0.0) -> float:
	return produced - (industrial + LIFE_SUPPORT_RATE
			+ STORAGE_COEF * stored_amount + DESTROY_COEF * destroyed_amount)


# ============================================================ ③ 三级优先（纯函数）

## **三级优先分配**（F-B4-1）：氧紧张时按 生命维持 > 产氧链 > 其他工业 的顺序分配。
##
## ⚠️ 这**不是"三个池"** —— 它只是**同一个数字不够分时的分配顺序**。
## **它不产生任何存量**：返回的只是"这一 tick 各自分到多少"，而**余额仍只有那一个**。
static func allocate(available: float, need_life: float, need_chain: float,
		need_industry: float) -> Dictionary:
	var left := maxf(available, 0.0)
	var out := {"life_support": 0.0, "oxygen_chain": 0.0, "other_industry": 0.0}
	for entry in [["life_support", need_life], ["oxygen_chain", need_chain],
			["other_industry", need_industry]]:
		var got := minf(maxf(float(entry[1]), 0.0), left)
		out[entry[0]] = got
		left -= got
	out["unfunded"] = left
	return out


## 存量比例（0–1），用于判断"该不该切到分配"。`capacity` 由 **B6** 给（B4 不拥有罐容）。
static func stock_ratio(stock: int, capacity: float) -> float:
	if capacity <= 0.0:
		return 0.0
	return clampf(float(stock) / capacity, 0.0, 1.0)


static func is_tight(stock: int, capacity: float) -> bool:
	if capacity <= 0.0:
		return false
	return stock_ratio(stock, capacity) < TIGHT_THRESHOLD


# ============================================================ §States（纯函数）

## 账目状态。`stock` 由**化合物账**给出（本类不持有），`rate` 是本 tick 的净收支速率。
static func state_of(stock: int, rate: float = 0.0) -> String:
	if stock <= 0 and rate < 0.0:
		return STATE_DEPLETED
	if absf(rate) < 0.000001:
		return STATE_BALANCED
	return STATE_SURPLUS if rate > 0.0 else STATE_DEFICIT


# ============================================================ 积分（纯函数）

## 把一个**速率**积分进存量：返回 `{stock, residual_scaled}`。
##
## ★ 纪律：**速率攒够一个才动账，余量留下**（与 A1 的余数累加器同）——
##   否则每 tick 丢掉小数，氧会**静默地**少下去。
## ★ 而"余量"**不归本类持有**：它由调用方（持有那个唯一池的人）连余额一起保存 ⇒
##   本类仍然是纯的，而"只有一个池 + 一个余量"这件事也仍然只有一个地方。
static func integrate(stock: int, rate: float, dt: float, residual_scaled: int = 0) -> Dictionary:
	var acc := residual_scaled + int(round(rate * dt * float(SCALE)))
	var whole := acc / SCALE                 # 向零取整（负数也朝零）
	var resid := acc - whole * SCALE         # **余量留下**，不丢
	return {"stock": maxi(stock + whole, 0), "residual_scaled": resid}
