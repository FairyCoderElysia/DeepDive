extends GdUnitTestSuite
## A6 · 参数与代价面 —— 逐条对应 A6 的 Acceptance Criteria
##
## ⚠️ 本文件的纪律（同 A4）：**"它该失败时真的失败"比"它通过了"更重要** ——
##   所以 §「代价不是标量」与 §「未知不是零」那两条是**配对的证据**，不是装饰。

const CS := preload("res://scripts/cost_surface.gd")
const CD := preload("res://scripts/compound_data.gd")
const PG := preload("res://scripts/process_graph.gd")
const RS := preload("res://scripts/reaction_solver.gd")

const KNOBS := SchemaContract.KNOBS


func _table() -> CompoundData:
	var d = CD.new()
	d.schema_version = SchemaContract.SCHEMA_VERSION
	d.schema_fingerprint = SchemaContract.SCHEMA_FINGERPRINT
	return d


## 一条**真反应**（`2H₂O -> 2H₂ + O₂`，两侧 H4O2 ✅ 配平）。
## ⚠️ 与本项目其它测试同一个坑：**测试数据也要受"它是不是真化学"的约束** ——
##   A2/A3 都不替我校验这件事，所以一条错的步骤会"跑过"却不代表任何事。
func _step() -> Dictionary:
	return {
		"id": "electrolysis",
		"inputs": {CD.composition_key({&"H": 2, &"O": 1}): 2},
		"outputs": {CD.composition_key({&"H": 2}): 2, CD.composition_key({&"O": 2}): 1},
		"conditions": [{
			"param": &"param_temperature",
			"opt_lo": 60.0, "opt_hi": 90.0, "brk_lo": 20.0, "brk_hi": 130.0,
			"coef_lo": 0.5, "coef_hi": 0.5,
			"alt": {CD.composition_key({&"H": 2, &"O": 1}): 2},
		}],
		"disaster": "boom",
	}


func _conds(t: float) -> Dictionary:
	return {&"param_temperature": t}


# ============================================================ 验收 1：无货币（核心）

## ★ Core Mechanics #6：「本作没有金币、没有市场、没有售价」——
##   而 **A6 是这条硬约束的第一道闸**，因为"代价"住在 A6。
func test_the_cost_triangle_carries_no_currency_whatsoever() -> void:
	var t := _table()
	var c := CS.cost_at(_step(), _conds(75.0), t)
	var names: Array = c.keys()
	for f: String in CS.COST_FIELDS:
		assert_bool(names.has(f)).is_true()
	for forbidden in ["price", "cost_money", "value", "gold", "sale", "market", "money"]:
		assert_bool(names.has(forbidden)).is_false()


# ============================================================ §Formulas ①：不是标量

## ★ 最要紧的一条：`代价(p)` 是**权衡三角**，**不得加权成一个总代价分数** ——
##   那会把权衡压平，玩家就看不到取舍了。
##   做法：三项必须是**三个各自可读的字段**，且**没有任何"总分"字段**。
##   （这条会在有人加 `total` / `score` / `weighted` 字段时变红 —— 那就是它存在的意义。）
func test_cost_is_a_triangle_not_a_scalar() -> void:
	var t := _table()
	var c := CS.cost_at(_step(), _conds(75.0), t)
	for f: String in CS.COST_FIELDS:
		assert_bool(c.has(f)).is_true()
	for scalar in ["total", "score", "cost", "weighted", "sum"]:
		assert_bool(c.has(scalar)).is_false()


## ★ **"未知"与"零代价"是两件事** —— 混起来会让玩家以为这一项不花钱。
##   `耗时` 此刻口径未定 ⇒ 必须是 `null`；而 `能耗` 在浅层**确实是 0**（光免费）。
func test_unknown_cost_item_is_null_not_zero() -> void:
	var t := _table()
	var c := CS.cost_at(_step(), _conds(75.0), t, 0.0)   # 速率非正 -> 耗时"不适用"
	assert_bool(c["time"] == null).is_true()
	assert_float(float(c["energy"])).is_equal_approx(0.0, 0.000001)


## ★ 口径 1（2026-10-03 用户拍板）：**耗时 = 单位产能时间 = 1 / 推进速率**。
func test_time_cost_is_one_over_the_injected_rate() -> void:
	var t := _table()
	var fast := CS.cost_at(_step(), _conds(75.0), t, 4.0)
	var slow := CS.cost_at(_step(), _conds(75.0), t, 0.5)
	assert_float(float(fast["time"])).is_equal_approx(0.25, 0.000001)
	assert_float(float(slow["time"])).is_equal_approx(2.0, 0.000001)
	assert_float(float(slow["time"])).is_greater(float(fast["time"]))     # 慢 = 更贵


## ★ 口径 2（2026-10-03 用户拍板）：**越界端除灾难标记外，三项都是"不适用"（null）** ——
##   越界出的是**灾难，不是产品** ⇒ 这里说"纯度 0"是**假话**（玩家会读成"零代价 / 产品为零"）。
##   与 `耗时 = null` 共用同一条纪律：**"未知 / 不适用"必须与"零"区分开**。
func test_disaster_band_reports_not_applicable_rather_than_zero() -> void:
	var t := _table()
	var c := CS.cost_at(_step(), _conds(200.0), t)
	assert_str(String(c["disaster"])).is_not_equal("")
	for f: String in CS.COST_FIELDS:
		assert_bool(c[f] == null).is_true()          # 不是 0，是"不适用"


# ============================================================ 验收 5：降维可用性（F-A6-1）

## ★ 「必须能对**任意一个**旋钮生成曲线；**若只能给全维数据即为失败**」
func test_every_one_of_the_five_knobs_can_be_sliced() -> void:
	var t := _table()
	var slices := CS.all_slices(_step(), _conds(75.0), t, 9)
	assert_int(slices.size()).is_equal(KNOBS.size())
	for k in KNOBS:
		assert_bool(slices.has(k)).is_true()
		assert_int((slices[k] as Array).size()).is_greater(1)      # 至少两点才叫"一片区域"


## 连续型旋钮：等距采样、**含两端**（范围端点必须在曲线上，否则玩家看不到边界代价）。
func test_continuous_knob_slice_spans_the_declared_range_inclusively() -> void:
	var t := _table()
	var pts := CS.slice(_step(), _conds(75.0), &"param_temperature", t, 11)
	assert_int(pts.size()).is_equal(11)
	var spec: Dictionary = KNOBS["param_temperature"]
	assert_float(float(pts[0]["knob_value"])).is_equal_approx(float(spec["min"]), 0.0001)
	assert_float(float(pts[10]["knob_value"])).is_equal_approx(float(spec["max"]), 0.0001)
	# 中点是范围的算术中点（11 个点 ⇒ 下标 5 就是中点）
	var mid: float = (float(spec["min"]) + float(spec["max"])) / 2.0
	assert_float(float(pts[5]["knob_value"])).is_equal_approx(mid, 0.0001)
	# 而且这个点**确实是在那个旋钮值上算的**（`conditions` 记着它）——
	# 否则"切片"可能只是把同一个点重复了 N 遍，而那种错误不会自己现形
	assert_float(float((pts[5]["conditions"] as Dictionary)[&"param_temperature"])).is_equal_approx(mid, 0.0001)


## 枚举型旋钮：**逐个选项各一点**（离散，没有"之间"）。
func test_enum_knob_slice_enumerates_options_instead_of_interpolating() -> void:
	var t := _table()
	var pts := CS.slice(_step(), _conds(75.0), &"param_catalyst", t, 11)
	var spec: Dictionary = KNOBS["param_catalyst"]
	assert_int(pts.size()).is_equal((spec["options"] as Array).size())


## ★ A6 的验收 4（不重定义）在**表达**这一侧的落点：
##   切片只能用**已声明**的旋钮 —— 不得另立定义（否则 A3↔A6 的环就回来了）。
func test_only_declared_knobs_exist() -> void:
	assert_bool(KNOBS.has("param_not_declared")).is_false()
	for k in KNOBS:
		assert_bool(String(k).begins_with("param_")).is_true()
		assert_bool((KNOBS[k] as Dictionary).has("unit")).is_true()


# ============================================================ 验收 2/3：三段的形状可区分

## ★ 验收 2「非线性」的直接落点：**纯度在最优带内是平的，进了偏移带就往下走** ——
##   所以"用一条直线近似"必然失败（一段平、一段斜）。
##   ★ 验收 3「三段区分」：越界段必须与偏移带可区分（这里表现为被标成灾难）。
func test_purity_is_flat_in_the_optimal_band_and_falls_in_the_offset_band() -> void:
	var t := _table()
	var s := _step()
	var a := CS.cost_at(s, _conds(60.0), t)
	var b := CS.cost_at(s, _conds(75.0), t)
	var c := CS.cost_at(s, _conds(89.9), t)
	assert_str(String(a["band"])).is_equal("optimal")
	assert_str(String(b["band"])).is_equal("optimal")
	assert_str(String(c["band"])).is_equal("optimal")
	assert_float(float(b["purity"])).is_equal_approx(float(a["purity"]), 0.0001)   # 平
	# 偏移带（上侧）：纯度应当掉下来
	var d := CS.cost_at(s, _conds(110.0), t)
	assert_str(String(d["band"])).is_not_equal("optimal")
	assert_float(float(d["purity"])).is_less(float(b["purity"]))                  # 斜
	# 越界段：A6 只**表达**它被标成灾难，后果与连锁归 B5
	var e := CS.cost_at(s, _conds(200.0), t)
	assert_str(String(e["disaster"])).is_not_equal("")


# ============================================================ 验收 2：偏移带内的【非线性】

## ★ 这是本轮新增的落点：§Formulas ③ 要求「偏移带内：**上升且非线性**」，
##   而 A2 的 δ 是线性的 ⇒ 只拿 δ 算，偏移带内会是一条直线，**验收 2 就不成立**。
##   所以加了第 4 个量 `penalty = (Σδ)^CURVATURE`（**A6 的表达，不是化学事实**）。
##
## 判别力从这里来：**取偏移带内的三个点，若 `penalty` 是线性的，
## 那么中点值必须等于两端均值** —— 而 `d²` 不满足它。
func test_offset_band_penalty_is_non_linear() -> void:
	var t := _table()
	var s := _step()
	# 下偏移带 [20, 40)，opt_lo = 40：三个等距点 ⇒ δ = 1.0 / 0.5 / 0.0
	var a := float((CS.cost_at(s, _conds(20.0), t))["penalty"])    # δ = 1.0
	var m := float((CS.cost_at(s, _conds(30.0), t))["penalty"])    # δ = 0.5
	var b := float((CS.cost_at(s, _conds(40.0), t))["penalty"])    # δ = 0.0（最优带边界）
	assert_float(a).is_greater(m)
	assert_float(m).is_greater(b)
	# ★ 非线性判据：**中点值 ≠ 两端均值**（直线会相等）
	var linear_mid: float = (a + b) / 2.0
	# ⚠️ 第一版我用了 `assert_float(...).is_not_equal_approx(...)` —— **gdUnit4 6.2.0 里没有这个方法**，
	#    它抛的是【Runtime Error】而不是断言失败 ⇒ 报表里记成 `errors=1` 而 **root 的 failures 仍是 0**
	#    ⇒ 我差点把这一次读成绿的。改用 Godot 自带的 `is_equal_approx` + `assert_bool`。
	assert_bool(is_equal_approx(m, linear_mid)).is_false()
	assert_float(m).is_less(linear_mid)          # d² 在中点比直线低 ⇒ "靠近最优带时不痛"


## ★ 最优带内 `penalty` 必须是 0（Σδ = 0）—— 否则"最优带"就没有意义了。
func test_penalty_is_zero_inside_the_optimal_band() -> void:
	var t := _table()
	for temp in [60.0, 75.0, 89.0]:
		var c := CS.cost_at(_step(), _conds(temp), t)
		assert_float(float(c["penalty"])).is_equal_approx(0.0, 0.000001)


## ★ 而它**不得吞并**另外三项：四项必须并存（§Formulas ① 禁的是"把权衡压平成总分"）。
##   同时钉住：**它只是 `Σδ` 的函数**，所以最优带内三项照旧可读。
func test_penalty_coexists_with_the_three_facts_instead_of_replacing_them() -> void:
	var t := _table()
	# ⚠️ 取值必须按**这条测试步骤自己的区间**算，不能照抄 T1 那份数据 ——
	#    本步骤 opt_lo=60 / brk_lo=20 ⇒ 下偏移带宽 40，T=20 处 δ=1.0（**我第一版抄错了，测试红了**）。
	var c := CS.cost_at(_step(), _conds(20.0), t)
	for f: String in CS.ALL_FIELDS:
		assert_bool(c.has(f)).is_true()
	for f: String in CS.COST_FIELDS:
		assert_bool(c.has(f)).is_true()
	# 纯度仍是 A2 的事实 —— ⚠️ 我第一版把 coef_lo 也算进去了，**那是错的**：
	#   A2 的式子是 `主产物占比 = max(0, 1 − Σδₖ)` —— **δ 不乘系数**（系数只进副产物的 share）。
	#   ⇒ δ=1.0 时纯度就是 0.0（T1 场景里 T=20 那点打印的 0.0000 正是它，实测一致）。
	assert_float(float(c["purity"])).is_equal_approx(0.0, 0.0001)
	assert_float(float(c["sum_delta"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(c["penalty"])).is_equal_approx(1.0, 0.0001)   # 1.0² = 1.0


## 越界端：`penalty` 也是"不适用"（与口径 2 的其它三项一致）。
func test_penalty_is_not_applicable_in_the_disaster_band() -> void:
	var t := _table()
	var c := CS.cost_at(_step(), _conds(200.0), t)
	assert_bool(c["penalty"] == null).is_true()


# ============================================================ 验收 7：不改模拟（⑤）

## ★ 「**关闭 / 不查看 A6 时，模拟结果必须完全不变** —— 证明它确实不参与判定」。
##
## 做法：**跑两遍同一个最小模拟**，一遍在每个 tick 之间把 A6 的每一件都调一遍
## （`cost_at` + `all_slices`），另一遍**一次都不碰 A6**；然后逐字比较两份快照。
## 只要 A6 有一丝副作用（改了输入 dict、改了表、碰了池），两份快照就会分叉。
##
## ⚠️ **而且必须证明这个模拟【真的动过】** —— 否则"两份都是空的"也会通过，
##    那就是本项目反复栽过的**空转测试**。（所以下面断言了水被消耗、H₂ 真的产出。）
func _simulate(ticks: int, touch_a6: bool) -> Dictionary:
	var t := _table()
	var s := _step()
	var water := CD.composition_key({&"H": 2, &"O": 1})
	var avail := {water: 20}
	var g = PG.new()
	g.add_node({"id": &"m", "priority": 0, "step": s,
				"conditions": {&"param_temperature": 75.0}})
	var solver = RS.new()
	for i in ticks:
		if touch_a6:
			# ★ 故意"查看"它：代价面被反复查询，而模拟不该因此改变一个原子
			CS.cost_at(s, {&"param_temperature": 75.0}, t)
			CS.all_slices(s, {&"param_temperature": 75.0}, t, 7)
		g.evaluate(avail, t, solver)          # evaluate 自己会把结果落进 avail
	return avail


## 把"账"折成一个**键有序**的字符串，便于逐字比较（Dictionary 的比较不该依赖插入顺序）。
func _snapshot(avail: Dictionary) -> String:
	var ks: Array = avail.keys()
	ks.sort()
	var parts := PackedStringArray()
	for k in ks:
		parts.append("%s=%d" % [k, int(avail[k])])
	return "|".join(parts)


func test_a6_never_changes_the_simulation() -> void:
	var a := _simulate(20, false)
	var b := _simulate(20, true)

	# ① 先证明这份模拟**不是空转**（否则"两份都空"也会通过 —— 那是本项目栽过的空转测试）。
	#    ⚠️ 第一版我用子串 `=20` 表示"水没被消耗"，**那个检查是脆的**：
	#    H₂ 恰好产了 20 个 ⇒ 快照里就有 `H2=20` ⇒ 它误报。
	#    **判据必须读键自己的值，不能靠子串碰撞。**
	var water := CD.composition_key({&"H": 2, &"O": 1})
	var h2 := CD.composition_key({&"H": 2})
	assert_int(int(a.get(water, 0))).is_less(20)                  # 水真的被消耗了
	assert_int(int(a.get(h2, 0))).is_greater(0)                   # H₂ 真的产出了

	# ② 而"看过 A6"与"没看过 A6"必须**逐字相同**
	assert_str(_snapshot(b)).is_equal(_snapshot(a))


## 另一半（更便宜、也更直接）：**A6 不得改动它读的那些东西** ——
## 它是"只表达"的系统，**输入 dict 在调用前后必须一模一样**。
func test_a6_does_not_mutate_its_inputs() -> void:
	var t := _table()
	var s := _step()
	var conds := {&"param_temperature": 75.0}
	var step_before := JSON.stringify(s)
	var conds_before := JSON.stringify(conds)
	CS.cost_at(s, conds, t)
	CS.slice(s, conds, &"param_temperature", t, 9)
	CS.all_slices(s, conds, t, 9)
	assert_str(JSON.stringify(s)).is_equal(step_before)
	assert_str(JSON.stringify(conds)).is_equal(conds_before)
