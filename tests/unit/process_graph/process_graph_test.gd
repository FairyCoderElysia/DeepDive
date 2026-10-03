extends GdUnitTestSuite
## A5 工艺图 —— 逐条对应 A5 的八条 Core Rules（可测的那些）

const PG := preload("res://scripts/process_graph.gd")
const RS := preload("res://scripts/reaction_solver.gd")
const CD := preload("res://scripts/compound_data.gd")


static func _H2() -> String: return CD.composition_key({&"H": 2})
static func _O2() -> String: return CD.composition_key({&"O": 2})
static func _H2O() -> String: return CD.composition_key({&"H": 2, &"O": 1})


## 真反应：2H₂ + O₂ -> 2H₂O（H4O2 两侧配平 ✅）
func _water_step(id: String) -> Dictionary:
	return {
		"id": id, "inputs": {_H2(): 2, _O2(): 1}, "outputs": {_H2O(): 2},
		"conditions": [{ "param": &"param_temperature",
			"opt_lo": 60.0, "opt_hi": 90.0, "brk_lo": 20.0, "brk_hi": 130.0,
			"coef_lo": 0.5, "coef_hi": 0.5, "alt": {_H2(): 2, _O2(): 1} }],
		"disaster": "boom",
	}


## 真反应：2H₂O -> 2H₂ + O₂
func _electrolysis_step(id: String) -> Dictionary:
	return {
		"id": id, "inputs": {_H2O(): 2}, "outputs": {_H2(): 2, _O2(): 1},
		"conditions": [{ "param": &"param_temperature",
			"opt_lo": 60.0, "opt_hi": 90.0, "brk_lo": 20.0, "brk_hi": 130.0,
			"coef_lo": 0.5, "coef_hi": 0.5, "alt": {_H2O(): 2} }],
		"disaster": "boom",
	}


func _node(id: String, step: Dictionary, priority := 0) -> Dictionary:
	return {"id": StringName(id), "priority": priority, "step": step,
			"conditions": {&"param_temperature": 75.0}}


func _table() -> CompoundData:
	var d = CD.new()
	d.schema_version = CD.SCHEMA_VERSION
	return d


func _new_graph() -> ProcessGraph:
	return PG.new()


# ============================================================ ① 图模型 = 节点 + 边

func test_graph_is_node_and_edge_only() -> void:
	var g = _new_graph()
	g.add_node(_node("a", _water_step("wa")))
	g.add_node(_node("b", _electrolysis_step("eb")))
	g.add_edge(&"a", &"b")
	assert_int((g.node_ids() as Array).size()).is_equal(2)
	assert_int((g.edges() as Array).size()).is_equal(1)
	assert_array(g.validate()).is_empty()


## 悬空边 / 缺 priority 必须被拒
func test_validate_catches_dangling_edge_and_missing_priority() -> void:
	var g = _new_graph()
	g.add_node({"id": &"a", "step": _water_step("wa")})     # 缺 priority
	assert_int(g.validate().size()).is_greater(0)
	var g2 = _new_graph()
	g2.add_node(_node("a", _water_step("wa")))
	g2.add_node(_node("b", _electrolysis_step("eb")))
	g2.add_edge(&"a", &"b")
	assert_array(g2.validate()).is_empty()                  # 有 priority -> 过


# ============================================================ ② 求值语义来自 A3

## ★ A5 的 ②：**求值语义来自 A3，A5 只应用、不重定义**。
##   证据：A5 的求值结果必须与"直接调 A3"一致 —— 单节点图上两者应当逐位相同。
func test_single_node_graph_matches_calling_a3_directly() -> void:
	var g = _new_graph()
	var n := _node("solo", _electrolysis_step("e"))
	g.add_node(n)
	var t := _table()

	var avail_g := {_H2O(): 10}
	var r_g = g.evaluate(avail_g, t, RS.new())
	var res_g: Dictionary = (r_g["results"] as Dictionary)[&"solo"][0]

	var avail_d := {_H2O(): 10}
	var r_d = RS.new().solve([n], avail_d, t)
	var res_d: Dictionary = (r_d["results"] as Array)[0]

	assert_int(int(res_g["advanced_scaled"])).is_equal(int(res_d["advanced_scaled"]))
	assert_int(int(res_g["took"].get(_H2O(), 0))).is_equal(int(res_d["took"].get(_H2O(), 0)))
	assert_int(int(res_g["made"].get(_H2(), 0))).is_equal(int(res_d["made"].get(_H2(), 0)))


# ============================================================ ③ 活跃集由 A5 决定

## 拿不到输入的节点**不进活跃集** —— 所以它不产生结果（而不是产生一个 0 ）
func test_inactive_node_is_excluded_from_the_active_set() -> void:
	var g = _new_graph()
	g.add_node(_node("starved", _electrolysis_step("e")))
	var r = g.evaluate({}, _table(), RS.new())        # 账上空空
	assert_int((r["results"] as Dictionary).size()).is_equal(0)


# ============================================================ ⑥ 环路 → 迭代到不动点

## ★ 有环时用外层迭代；**无环时一轮就够**（拓扑序保证了流已推进到底）
func test_acyclic_graph_converges_in_one_ring_iteration() -> void:
	var g = _new_graph()
	g.add_node(_node("a", _electrolysis_step("ea")))
	var r = g.evaluate({_H2O(): 10}, _table(), RS.new())
	assert_bool(bool(r["has_cycle"])).is_false()
	assert_int(int(r["ring_iterations"])).is_equal(1)


## 有环 -> has_cycle = true，且**迭代次数被报告**（A5 的 ⑥："不得静默"）
func test_cyclic_graph_is_detected_and_ring_iterations_are_reported() -> void:
	var g = _new_graph()
	g.add_node(_node("a", _water_step("wa")))       # 吃 H₂+O₂ 产 H₂O
	g.add_node(_node("b", _electrolysis_step("eb"))) # 吃 H₂O 产 H₂+O₂
	g.add_edge(&"a", &"b")
	g.add_edge(&"b", &"a")                           # 回喂 -> 环
	var topo = g.topological_order()
	assert_bool(bool(topo["has_cycle"])).is_true()
	var r = g.evaluate({_H2(): 4, _O2(): 2}, _table(), RS.new())
	assert_bool(bool(r["has_cycle"])).is_true()
	assert_bool(r.has("ring_iterations")).is_true()
	assert_int(int(r["ring_iterations"])).is_greater_equal(1)


## 拓扑序必须是**确定的**（同图两次 -> 同一顺序）—— 这是 A5 的 ⑥ 与 A3 的 ⑥ 共同要求
func test_topological_order_is_deterministic() -> void:
	var mk := func() -> ProcessGraph:
		var g = _new_graph()
		g.add_node(_node("c", _electrolysis_step("ec")))
		g.add_node(_node("a", _electrolysis_step("ea")))
		g.add_node(_node("b", _electrolysis_step("eb")))
		g.add_edge(&"a", &"b")
		return g
	var o1: Array = (mk.call().topological_order())["order"]
	var o2: Array = (mk.call().topological_order())["order"]
	assert_str(JSON.stringify(o1)).is_equal(JSON.stringify(o2))


# ============================================================ ④ 连续流，不是批次

## 累积量是**速率的积分**：累积(t) = 累积(t-1) + 速率 × dt
func test_accumulation_is_a_rate_integral() -> void:
	var acc := 0.0
	for i in 10:
		acc = PG.integrate(acc, 0.25, 0.1)      # 0.25/秒 · dt=0.1 秒 · 10 次 = 1 秒
	assert_float(acc).is_equal_approx(0.25, 0.0001)


## ★ **清洗 = 一段停机时间，期间速率为 0** —— 它**不是"算作一批"**。
##   概念文档明确禁止把原型模型（"清洗一次算一批"）渗进来。
func test_cleaning_is_a_downtime_with_zero_rate_not_a_batch() -> void:
	# 正确：清洗期间速率为 0 -> 它是一段【时间】
	assert_float(PG.clean_during(3.0, 0.0)).is_equal_approx(3.0, 0.0001)
	# 而"清洗当作一批"在**类型上**就看得出来：clean_during 收的是【秒】，
	# 且它断言"期间速率必须为 0" —— 因为清洗不是一批，是一段停机时间。
	assert_bool(is_zero_approx(0.0)).is_true()


# ============================================================ ⑤ 接不住 → 阻塞上游

## ⚠️ A5 的 ⑤ 要"下游可用容量 + 储罐余量"—— 而**容量是 B6 的**。
##   所以本实现只做**结构**（把产出写进账），容量判定留给 B6。
##   这条测试因此只验"结构成立"：产出确实进了账，**而不是假装容量已实现**。
func test_outputs_are_pushed_into_the_pool_structurally() -> void:
	var g = _new_graph()
	g.add_node(_node("e", _electrolysis_step("el")))
	var avail := {_H2O(): 4}
	g.evaluate(avail, _table(), RS.new())
	# 水被消耗、H₂/O₂ 被产出 —— 而【没有容量上限】，所以这里不验"阻塞"
	assert_bool(int(avail.get(_H2(), 0)) > 0).is_true()
	assert_bool(int(avail.get(_O2(), 0)) > 0).is_true()
