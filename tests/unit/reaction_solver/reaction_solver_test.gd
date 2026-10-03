extends GdUnitTestSuite
## A3 反应求解器 —— 逐条对应 A3 的 Core Rules 与 F-A3-2
##
## ⚠️ 本文件里的每一条步骤都必须是【配平的真反应】。
##    我第一版用了 `{H:2} -> {H:2}` 这种【恒等反应】当测试数据 ——
##    结果池里的量本来就不该变，而我看不出这点、误以为求解器坏了，追了半轮。
##    那次的教训：**测试数据也要受"它是不是真化学"的约束** —— A3 不校验配平（那是 A2 的活），
##    所以一条错的步骤会"跑过"却不代表任何事。

const RS := preload("res://scripts/reaction_solver.gd")
const CD := preload("res://scripts/compound_data.gd")

# 常用组成式（由 composition_key 现算，不手写）
static func _H2() -> String: return CD.composition_key({&"H": 2})
static func _O2() -> String: return CD.composition_key({&"O": 2})
static func _H2O() -> String: return CD.composition_key({&"H": 2, &"O": 1})


func _step(id: String, inputs: Dictionary, outputs: Dictionary) -> Dictionary:
	return {
		"id": id, "inputs": inputs, "outputs": outputs,
		"conditions": [{
			"param": &"param_temperature",
			"opt_lo": 60.0, "opt_hi": 90.0, "brk_lo": 20.0, "brk_hi": 130.0,
			"coef_lo": 0.5, "coef_hi": 0.5, "alt": inputs,
		}],
		"disaster": "boom",
	}


## **真反应**：`2H₂ + O₂ -> 2H₂O`（两侧 H4O2 ✅ 配平）
func _water_step(id: String) -> Dictionary:
	return _step(id, {_H2(): 2, _O2(): 1}, {_H2O(): 2})


## **真反应**：`2H₂O -> 2H₂ + O₂`（两侧 H4O2 ✅ 配平）
func _electrolysis_step(id: String) -> Dictionary:
	return _step(id, {_H2O(): 2}, {_H2(): 2, _O2(): 1})


func _machine(id: String, step: Dictionary, priority := 0) -> Dictionary:
	return {"id": StringName(id), "priority": priority, "step": step,
			"conditions": {&"param_temperature": 75.0}}


func _table() -> CompoundData:
	var d = CD.new()
	d.schema_version = CD.SCHEMA_VERSION
	return d


## A3 的 solve 是【纯】的：它不修改 available，而是交回 took/made。
## 所以测试统一走这个助手 —— **副作用只有一个显式入口**。
func _solve_and_apply(machines: Array, avail: Dictionary, t: CompoundData) -> Dictionary:
	var r = RS.new().solve(machines, avail, t)
	for res: Dictionary in r["results"]:
		RS.apply(res, avail)
	return r


# ============================================================ ② 限制试剂

## ② `推进量 = min over 输入项 (可用量 ÷ 需求量)` —— "谁先耗尽"
func test_limit_reagent_is_the_min_ratio() -> void:
	var t := _table()
	var H := _H2()
	var O := _O2()
	# 2H₂ + O₂ -> 2H₂O：池里 H₂ 只有 2、O₂ 有 100 -> H₂ 是瓶颈 -> 推进 1 批
	var s := _water_step("m")
	var avail := {H: 2, O: 100}
	var r = _solve_and_apply([_machine("m", s)], avail, t)
	var res: Dictionary = r["results"][0]
	# 推进量 = min(2/2, 100/1) = 1 批 -> 放大整数 = 1 × SCALE
	var S: int = preload("res://scripts/element_pool.gd").SCALE
	assert_float(float(res["advanced_scaled"]) / float(S)).is_equal_approx(1.0, 0.0001)
	# 实际扣的是 H₂ 全用掉、O₂ 只用 1 —— **不是把 100 个 O₂ 都扣掉**
	assert_int(int(res["took"][H])).is_equal(2)
	assert_int(int(res["took"][O])).is_equal(1)
	assert_int(int(avail[O])).is_equal(99)


# ============================================================ ★ F-A3-2：迭代到不动点

## ★ 规格自己举的反例：同优先级两台各要 2H₂+1O₂、池里只有 2H₂、100O₂
##   -> H₂ 是瓶颈，两台各只能推进 0.5 份。
##   **若按"初始需求"分一趟**，它们会各分到 50 个 O₂，99 个被锁死 ——
##   而那时**第三台只要 O₂ 的机器会被饿死**。玩家看到会认为系统算错了。
func test_fair_share_iterates_so_unused_share_is_not_locked() -> void:
	var t := _table()
	var H := _H2()
	var O := _O2()
	var s := _water_step("needs_both")
	var avail := {H: 2, O: 100}
	var r = _solve_and_apply([_machine("a", s), _machine("b", s)], avail, t)
	var S: int = preload("res://scripts/element_pool.gd").SCALE
	for res: Dictionary in r["results"]:
		assert_float(float(res["advanced_scaled"]) / float(S)).is_equal_approx(0.5, 0.01)
	# O₂ 只被用掉 1 个（两个 0.5×… 合计 1）—— 所以还剩 99，第三台不会被饿死
	assert_bool(int(avail[O]) >= 99).is_true()


# ============================================================ ⑤ 优先级 = 抢料

## ⑤ 高优先级先取料 —— **而它是玩家可配的（P3），不是内部随机数**
func test_higher_priority_takes_first() -> void:
	var t := _table()
	var W := _H2O()
	# 真反应：2H₂O -> 2H₂ + O₂（吃水，所以池会真的减少）
	var s := _electrolysis_step("m")
	var avail := {W: 2}                      # 只够一台（每台要 2 个水）
	var r = RS.new().solve([_machine("low", s, 0), _machine("high", s, 10)], avail, t)
	var by := {}
	for res: Dictionary in r["results"]:
		by[String(res["id"])] = res
	# 高优先级拿到全部
	assert_bool(int(by["high"]["advanced_scaled"]) > 0).is_true()
	# 而低优先级必须拿到 0 —— "用剩的才轮到下一层"
	assert_int(int(by["low"]["advanced_scaled"])).is_equal(0)


# ============================================================ ⑥ 确定性

func test_determinism_same_input_gives_bit_identical_output() -> void:
	var t := _table()
	var s := _water_step("m")
	var runs: Array = []
	for k in 3:
		var avail := {_H2(): 7, _O2(): 11}
		var r = RS.new().solve([_machine("b", s), _machine("a", s), _machine("c", s)], avail, t)
		runs.append(JSON.stringify(r["results"]))
	assert_str(String(runs[0])).is_equal(String(runs[1]))
	assert_str(String(runs[1])).is_equal(String(runs[2]))


## **机器的输入顺序不应该影响结果**（顺序由数据决定）
func test_machine_order_does_not_change_the_outcome() -> void:
	var t := _table()
	var s := _water_step("m")
	var a := [_machine("a", s, 0), _machine("b", s, 0), _machine("c", s, 0)]
	var b := [_machine("c", s, 0), _machine("a", s, 0), _machine("b", s, 0)]
	var r1 = RS.new().solve(a, {_H2(): 5, _O2(): 5}, t)
	var r2 = RS.new().solve(b, {_H2(): 5, _O2(): 5}, t)
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
	var s := _electrolysis_step("m")
	var solver = RS.new()
	var r1 = solver.solve([_machine("m", s)], {_H2O(): 10}, t)
	assert_str(String((r1["results"][0] as Dictionary)["band"])).is_equal("optimal")
	# 越界 -> disaster 被标出来，**但产出照旧**（A3 的 ⑧：后果与连锁归 B5）
	var m_bad := _machine("m", s)
	m_bad["conditions"] = {&"param_temperature": 200.0}
	var r2 = solver.solve([m_bad], {_H2O(): 10}, t)
	assert_str(String((r2["results"][0] as Dictionary)["disaster"])).is_equal("boom")


# ============================================================ ③ 整数量化（不超发）

func test_quantization_never_over_delivers() -> void:
	var t := _table()
	var H := _H2()
	# 2H₂ + O₂ -> 2H₂O；H₂ 只够半批
	var s := _water_step("m")
	var avail := {H: 1, _O2(): 100}
	var r = _solve_and_apply([_machine("m", s)], avail, t)
	var res: Dictionary = r["results"][0]
	# 推进 0.5 批，但实际只扣【整数个】：≤ 1 个 H₂（不会超发，也不会扣小数）
	assert_int(int(res["took"].get(H, 0))).is_less_equal(1)
	assert_bool(int(avail[H]) >= 0).is_true()      # 绝不出现负库存


# ============================================================ A3 的其余边界

## ★ A2 明写：「循环步骤（A→B→A）**A2 允许**（可逆与循环在真实化学里存在）；
##   **终止性由 A3 负责**」—— 而 A3 的终止性是【结构性】的：
##   **每个 tick 每台机器只求值一次**，所以自环/回喂不会让它转圈。
func test_self_loop_terminates_a_single_evaluation() -> void:
	var t := _table()
	var W := _H2O()
	var H := _H2()
	# 一台机器吃水、产氢；而它产的氢又被自己当成输入（自环）
	var s := _step("loop", {W: 2, H: 1}, {H: 3})
	# 注意：这条不是真化学（只用于测终止性），所以**显式标注**它不参与守恒断言
	var avail := {W: 4, H: 2}
	var r = RS.new().solve([_machine("loop", s)], avail, t)
	# 关键：**它返回了**（没有转圈），且每台机器只有一个结果
	assert_int((r["results"] as Array).size()).is_equal(1)


## ★ F-A3-2 的"不得静默"：迭代次数必须被报告出来，收敛时 warned = false
func test_iteration_count_is_reported_and_normal_case_does_not_warn() -> void:
	var t := _table()
	var s := _water_step("m")
	var r = RS.new().solve([_machine("a", s), _machine("b", s)], {_H2(): 4, _O2(): 4}, t)
	assert_bool(r.has("iterations")).is_true()
	assert_bool(r.has("warned")).is_true()
	# 正常的等分应当很快收敛
	var first: int = int((r["iterations"] as Dictionary).values()[0])
	assert_int(first).is_less_equal(preload("res://scripts/reaction_solver.gd").MAX_ITERATIONS)
	assert_bool(bool(r["warned"])).is_false()


## 迭代上限是 A3 的硬常量（用户拍板"迭代到不动点，带上限"）
func test_max_iterations_is_eight() -> void:
	assert_int(preload("res://scripts/reaction_solver.gd").MAX_ITERATIONS).is_equal(8)
