extends GdUnitTestSuite
## A3 反应求解器 —— 逐条对应 A3 的 Core Rules 与 F-A3-2

const RS := preload("res://scripts/reaction_solver.gd")
const CD := preload("res://scripts/compound_data.gd")


func _step(id: String, inputs: Dictionary, outputs: Dictionary, opt_lo := 60.0, opt_hi := 90.0) -> Dictionary:
	return {
		"id": id,
		"inputs": inputs,
		"outputs": outputs,
		"conditions": [{
			"param": &"param_temperature",
			"opt_lo": opt_lo, "opt_hi": opt_hi, "brk_lo": 20.0, "brk_hi": 130.0,
			"coef_lo": 0.5, "coef_hi": 0.5, "alt": inputs,
		}],
		"disaster": "boom",
	}


func _machine(id: String, step: Dictionary, priority := 0) -> Dictionary:
	return {"id": StringName(id), "priority": priority, "step": step,
			"conditions": {&"param_temperature": 75.0}}


func _table() -> CompoundData:
	var d = CD.new()
	d.schema_version = CD.SCHEMA_VERSION
	return d


## ★ A3 的 solve 是【纯】的：它不修改 available，而是交回 took/made。
##   所以测试统一走这个助手：solve 之后显式 apply —— **副作用只有一个显式入口**。
func _solve_and_apply(machines: Array, avail: Dictionary, t: CompoundData) -> Dictionary:
	var solver = RS.new()
	var r = solver.solve(machines, avail, t)
	for res: Dictionary in r["results"]:
		RS.apply(res, avail)
	return r


# ============================================================ ② 限制试剂

## ② `推进量 = min over 输入项 (可用量 ÷ 需求量)` —— "谁先耗尽"
func test_limit_reagent_is_the_min_ratio() -> void:
	var t := _table()
	var H := CD.composition_key({&"H": 2})     # 用 H₂ 当"两种输入"的载体
	var O := CD.composition_key({&"O": 2})
	# 一台机器要 {A: 2, B: 1}；池里 A 只有 2、B 有 100 -> A 是瓶颈 -> 推进 1 批
	var s := _step("m", {H: 2, O: 1}, {CD.composition_key({&"H": 2, &"O": 1}): 1})
	var avail := {H: 2, O: 100}
	var r = _solve_and_apply([_machine("m", s)], avail, t)
	var res: Dictionary = r["results"][0]
	# 推进量 = min(2/2, 100/1) = 1 批 -> 放大整数 = 1 × SCALE
	var S0: int = preload("res://scripts/element_pool.gd").SCALE
	assert_float(float(res["advanced_scaled"]) / float(S0)).is_equal_approx(1.0, 0.0001)
	# 而实际扣的是 A 全用掉、B 只用 1 —— **不是把 100 个 B 都扣掉**
	assert_int(int(res["took"][H])).is_equal(2)
	assert_int(int(res["took"][O])).is_equal(1)
	assert_int(int(avail[O])).is_equal(99)          # 剩下的 B 还在池里


# ============================================================ ★ F-A3-2：层内等分迭代到不动点

## ★ 规格里自己举的那条反例：**同优先级两台各要 2H+1O，池里只有 2H、100O**
##   -> H 是瓶颈，两台各只能推进 0.5 份。
##   **若按"初始需求"分一趟**，它们会各分到 50 个 O，**99 个 O 被锁死** ——
##   而那时 **第三台只要 O 的机器会被饿死**。玩家看到会认为系统算错了。
func test_fair_share_iterates_so_unused_share_is_not_locked() -> void:
	var t := _table()
	var H := CD.composition_key({&"H": 2})
	var O := CD.composition_key({&"O": 2})
	var product := CD.composition_key({&"H": 2, &"O": 1})
	var s := _step("needs_both", {H: 2, O: 1}, {product: 3})
	var avail := {H: 2, O: 100}

	var r = _solve_and_apply([_machine("a", s), _machine("b", s)], avail, t)
	# 两台各推进 0.5 份（H 各用 1、O 各用 0.5）—— 而**不是**各锁 50 个 O
	var S: int = preload("res://scripts/element_pool.gd").SCALE
	for res: Dictionary in r["results"]:
		assert_float(float(res["advanced_scaled"]) / float(S)).is_equal_approx(0.5, 0.01)
	# O 只被用掉 1 个（两个 0.5），所以还剩 99 —— 第三台不会被饿死
	assert_bool(int(avail[O]) >= 99).is_true()
	# 而 H 应该被用光（它是瓶颈）
	assert_int(int(avail[H])).is_equal(0)


## 第三台只要 O 的机器**不能**被饿死（上一版"一趟分完"会让它饿死）
func test_a_third_machine_that_only_needs_the_abundant_input_is_not_starved() -> void:
	var t := _table()
	var H := CD.composition_key({&"H": 2})
	var O := CD.composition_key({&"O": 2})
	var s_both := _step("both", {H: 2, O: 1}, {CD.composition_key({&"H": 2, &"O": 1}): 3})
	var s_o_only := _step("o_only", {O: 2}, {O: 2})

	var avail := {H: 2, O: 100}
	var r = _solve_and_apply([_machine("a", s_both), _machine("b", s_both), _machine("c", s_o_only)], avail, t)
	var c_res: Dictionary = {}
	for res: Dictionary in r["results"]:
		if String(res["id"]) == "c":
			c_res = res
	assert_bool(c_res.is_empty()).is_false()
	# 它应该拿到 O（而不是被别人锁死）
	assert_bool(int(c_res["advanced_scaled"]) > 0).is_true()


# ============================================================ ⑤ 优先级 = 抢料

## ⑤ 高优先级先取料 —— **而它是玩家可配的（P3），不是内部随机数**
##
## ⚠️⚠️ **【未解问题 · OPEN】** ⚠️⚠️
## 这条测试**当前失败**，而根因**尚未定位**。已排除的：
##   · 不是 Dictionary 的引用语义（形状一致的独立实验是通过的）
##   · 不是"层间扣减没执行"（改成实例字段、再改成显式返回值，都一样）
##   · 不是"报告的推进量用了计划值"（已改成"计划 ∩ 可行"）
## 现象：**低优先级那台也报告 advanced=1×SCALE 且 took 与高优先级那台相同** ——
##       即**层间"用剩的才轮到下一层"没有生效**。
## **保留它为失败**，而不是跳过 —— 因为"让一个未解的缺陷显示为绿色"比它本身更危险。
## 下一步该做的：在 `_solve_layer` 入口打印 `avail`（而不是继续推理）。
## 上一条推论为什么没查出它：我用的是"独立复现"而不是"在真实调用链里打印"。
func test_higher_priority_takes_first() -> void:
	var t := _table()
	var H := CD.composition_key({&"H": 2})
	var s := _step("m", {H: 2}, {CD.composition_key({&"H": 2}): 2})
	var avail := {H: 2}                     # 只够一台
	var r = RS.new().solve([
		_machine("low", s, 0), _machine("high", s, 10),
	], avail, t)
	var by := {}
	for res: Dictionary in r["results"]:
		by[String(res["id"])] = res
	# 高优先级拿到全部，低优先级拿 0
	assert_bool(int(by["high"]["advanced_scaled"]) > 0).is_true()
	assert_int(int(by["low"]["advanced_scaled"])).is_equal(0)


# ============================================================ ⑥ 确定性

## ⑥ 同输入 → **逐位一致**（顺序由数据决定，不由偶然决定）
func test_determinism_same_input_gives_bit_identical_output() -> void:
	var t := _table()
	var H := CD.composition_key({&"H": 2})
	var O := CD.composition_key({&"O": 2})
	var s := _step("m", {H: 2, O: 1}, {CD.composition_key({&"H": 2, &"O": 1}): 3})
	var runs: Array = []
	for k in 3:
		var avail := {H: 7, O: 11}
		var r = RS.new().solve([_machine("b", s), _machine("a", s), _machine("c", s)], avail, t)
		runs.append(JSON.stringify(r["results"]))
	assert_str(String(runs[0])).is_equal(String(runs[1]))
	assert_str(String(runs[1])).is_equal(String(runs[2]))


## 而**机器的输入顺序不应该影响结果**（顺序由数据决定）—— 这是 ⑥ 的另一半
func test_machine_order_does_not_change_the_outcome() -> void:
	var t := _table()
	var H := CD.composition_key({&"H": 2})
	var s := _step("m", {H: 2}, {CD.composition_key({&"H": 2}): 2})
	var a := [_machine("a", s, 0), _machine("b", s, 0), _machine("c", s, 0)]
	var b := [_machine("c", s, 0), _machine("a", s, 0), _machine("b", s, 0)]
	var r1 = RS.new().solve(a, {H: 5}, t)
	var r2 = RS.new().solve(b, {H: 5}, t)
	# 按 id 排好再比
	var norm := func(rs: Array) -> String:
		var m := {}
		for x: Dictionary in rs: m[String(x["id"])] = int(x["advanced_scaled"])
		var ks := m.keys(); ks.sort()
		var out := PackedStringArray()
		for k2: String in ks: out.append("%s=%d" % [k2, m[k2]])
		return " ".join(out)
	assert_str(String(norm.call(r1["results"]))).is_equal(String(norm.call(r2["results"])))


# ============================================================ ④ 分支（调 A2，不重定义）

func test_branch_and_disaster_come_from_a2_not_from_a3() -> void:
	var t := _table()
	var H := CD.composition_key({&"H": 2})
	var s := _step("m", {H: 2}, {H: 2})
	var solver = RS.new()
	# 在最优带内 -> optimal
	var m_ok := _machine("m", s)
	var avail := {H: 10}
	var r1 = solver.solve([m_ok], avail, t)
	assert_str(String((r1["results"][0] as Dictionary)["band"])).is_equal("optimal")
	# 越界 -> disaster 被标出来，**但产出照旧**（A3 的 ⑧：后果与连锁归 B5）
	var m_bad := _machine("m", s)
	m_bad["conditions"] = {&"param_temperature": 200.0}
	var avail2 := {H: 10}
	var r2 = solver.solve([m_bad], avail2, t)
	assert_str(String((r2["results"][0] as Dictionary)["disaster"])).is_equal("boom")


# ============================================================ ③ 整数量化（不超发）

## ③ 量化不得"超搬" —— 余量进累加器，**不丢**
func test_quantization_never_over_delivers() -> void:
	var t := _table()
	var H := CD.composition_key({&"H": 2})
	var s := _step("m", {H: 3}, {CD.composition_key({&"H": 2}): 3})   # 每批要 3 个 H₂
	var avail := {H: 2}                       # 只够 2/3 批
	var r = _solve_and_apply([_machine("m", s)], avail, t)
	var res: Dictionary = r["results"][0]
	# 推进量是 2/3 批，但**实际只扣整数个** -> 2 个（不会扣 3 个，也不会扣小数）
	assert_int(int(res["took"].get(H, 0))).is_less_equal(2)
	assert_bool(int(avail[H]) >= 0).is_true()      # 绝不出现负库存
