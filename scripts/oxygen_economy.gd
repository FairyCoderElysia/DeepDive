class_name OxygenEconomy
extends RefCounted
## B4 · 氧气经济 —— **本作唯一的记账层**
##
## 【它的形状与前面六个系统都不同】A1–A6 给事实与表达；**B4 把事实记成一本以氧为单位的账**
## （`oxygen-economy.md` §Overview：它的定位不是"一个资源系统"，而是"**代价的记账单位**"）。
##
## ⚠️ **本系统第一号不可违反的约束（Core Rule ②）**：
##   **氧只有一个池。** 它同时是**生命维持**与**助燃物**，而**这两件事是同一个数字**。
##   任何把它拆成"生命维持氧 / 工业氧"两个数字的实现，**都会拆掉整个张力的支点**。
##   ★ 而"三级优先分配"（③）是**在同一个数字上的分配顺序**，**不是三个池** ——
##     这两件事极容易被混为一谈（"分成三层"听起来像"分成三个池"），所以写在最前面。
##
## 【它不拥有什么】（§Tuning Knobs 的边界，必须写明）
##   参数旋钮属 **A1** · 档位属 **B3** · 罐容上限属 **B6** · 代价的呈现属 **A6**。
##   **B4 只定义"氧的收支如何计算、如何分配、如何成为唯一的记账单位"。**
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
#     我把它们做成常量并**逐个标"暂定"**，是为了让账目层能被测试 ——
#     **但它们没有被定过**：它们是"先让它能跑"，不是"设计结论"。
#     其中第一个（生命维持率）GDD 原话是「**决定整个游戏的紧张度** —— 它是最重要的一个数」，
#     而它的手感取决于另一个数（C1 的表层通量天花板），那个还没实现。
# ────────────────────────────────────────────────────────────────────────────

## 生命维持基础耗氧率（氧 / 秒）—— **暂定**。
const LIFE_SUPPORT_RATE := 0.05

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

## 存量（单位：化合物数 × SCALE）。**只有一个** —— 见文件头的 ②。
var stock_scaled: int = 0

## 净收支的分数余量（单位：× SCALE）。**速率攒够一个才动账**，余量留下 ——
## 与 A1 的余数累加器同一条纪律（**不得每 tick 丢弃小数**，否则会静默少氧）。
var _residual_scaled: int = 0


func _init(initial_stock: int = 0) -> void:
	stock_scaled = maxi(initial_stock, 0) * SCALE


## 当前游离氧存量（整数个 `O₂`）。**这是唯一的存量读数**。
func stock() -> int:
	return stock_scaled / SCALE


## 本 tick 的收支（四项相减）。返回**速率**，不改变任何状态。
##
## `produced`/`industrial`：来自 A3 的事实（本 tick 产氧 / 工业耗氧的速率）。
## `stored_amount`：当前存了多少（B6 提供），存贮耗氧 = 系数 × 存量 —— **是速率**。
## `destroyed_amount`：本 tick 销毁了多少物质。
static func net_rate(produced: float, industrial: float, stored_amount: float,
		destroyed_amount: float) -> float:
	return produced - (industrial + LIFE_SUPPORT_RATE
			+ STORAGE_COEF * stored_amount + DESTROY_COEF * destroyed_amount)


## **三级优先分配**（F-B4-1）：氧紧张时，按 生命维持 > 产氧链 > 其他工业 的顺序分配。
##
## ⚠️ 这不是"三个池" —— 它只是**同一池在不够分时的分配顺序**。
## 返回 `{life_support, oxygen_chain, other_industry, unfunded}`（各项都不超过各自的需求量）。
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


## 走一个 tick：把四项速率积分进存量。返回本 tick 的账目快照。
##
## ★ 纪律：**速率攒够一个才动账，余量留下**（与 A1 同）——
## 否则每 tick 丢掉小数，氧会**静默地**少下去。
func step(dt: float, produced: float, industrial: float,
		stored_amount: float = 0.0, destroyed_amount: float = 0.0) -> Dictionary:
	var net := net_rate(produced, industrial, stored_amount, destroyed_amount)
	# 先按分配顺序算"实际能拿到多少"（存量不够时，低优先级要被压缩）
	var tight := is_tight()
	if tight and net < 0.0:
		var alloc := allocate(float(stock()) / maxf(float(dt), 0.000001),
				LIFE_SUPPORT_RATE, industrial, 0.0)
		# 只允许"生命维持 + 产氧链"这两级吃氧，其他工业被压到 0
		net = produced - (alloc["life_support"] + alloc["oxygen_chain"]
				+ STORAGE_COEF * stored_amount + DESTROY_COEF * destroyed_amount)
	_residual_scaled += int(round(net * dt * float(SCALE)))
	var whole := _residual_scaled / SCALE            # 向零取整（C++ 语义：负数也朝零）
	_residual_scaled -= whole * SCALE                # **余量留下**，不丢
	stock_scaled = maxi(stock_scaled + whole * SCALE, 0)   # 不得为负：耗竭就是 0
	return {"stock": stock(), "rate": net, "state": state(net), "tight": tight}


## 账目状态（§States）。`delta` = 本 tick 的净收支速率。
func state(delta: float = 0.0) -> String:
	if stock() <= 0 and delta < 0.0:
		return STATE_DEPLETED
	if absf(delta) < 0.000001:
		return STATE_BALANCED
	return STATE_SURPLUS if delta > 0.0 else STATE_DEFICIT


## 存量比例（0–1），用于判断"该不该切到分配"。`capacity` 由 **B6** 给（B4 不拥有罐容）。
func stock_ratio(capacity: float) -> float:
	if capacity <= 0.0:
		return 0.0
	return clampf(float(stock()) / capacity, 0.0, 1.0)


func is_tight(capacity: float = 0.0) -> bool:
	if capacity <= 0.0:
		return false
	return stock_ratio(capacity) < TIGHT_THRESHOLD
