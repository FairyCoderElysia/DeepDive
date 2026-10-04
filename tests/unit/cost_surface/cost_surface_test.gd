extends GdUnitTestSuite
## A6 · 参数与代价面 —— 逐条对应 A6 的 Acceptance Criteria
##
## ⚠️ 本文件的纪律（同 A4）：**"它该失败时真的失败"比"它通过了"更重要** ——
##   所以 §「代价不是标量」与 §「未知不是零」那两条是**配对的证据**，不是装饰。

const CS := preload("res://scripts/cost_surface.gd")
const CD := preload("res://scripts/compound_data.gd")

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
	var c := CS.cost_at(_step(), _conds(75.0), t)
	assert_bool(c["time"] == null).is_true()
	assert_float(float(c["energy"])).is_equal_approx(0.0, 0.000001)


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
