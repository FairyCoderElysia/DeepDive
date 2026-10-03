extends Control
## T1 最小垂直切片：海水 → 电解 → (H₂ + H₂O₂) 或 (2H₂ + O₂)
##
## **本版由 A2 的数据表驱动**（代码里没有一条反应式）—— 所以它验证的是【整条数据链在真引擎里成立】：
##
##   进水 ──A1 的余数累加器──▶ 整数水分子
##        │
##        ▼
##   A2：steps_for(输入) 找到【分支】── 按当前温度选一条
##        │
##        ▼
##   A2：resolve_scaled() 把占比折成【放大整数的原子收支】
##        │
##        ▼
##   A1 的池：取输入原子 / 放回输出原子 ── 而【每一 tick 零容差对账】
##
## ⚠️ 为什么必须两本账：**在原子层面两个分支都是恒等的**
##   （2H₂O→2H₂+O₂ 与 2H₂O→H₂+H₂O₂ 的原子数都是 H4O2），
##   所以只看原子账，"反应"什么都没变。变化的是【化合物】——
##   而"化合物 → 数量"正是 B6 定的罐子表示。
##
## ★ 它能演示【分支】：温度缓慢扫过两条最优带，产物真的从 (H₂+H₂O₂) 换成 (2H₂+O₂)。

const TABLE: CompoundData = preload("res://data/reactions.tres")
const SOLVER := preload("res://scripts/reaction_solver.gd")
const GRAPH := preload("res://scripts/process_graph.gd")

const WATER := {&"H": 2, &"O": 1}
const SALT := {&"Na": 1, &"Cl": 1}          # NaCl
const CALCIUM_CHLORIDE := {&"Ca": 1, &"Cl": 2}   # CaCl₂

## 进水 0.37 个水分子 / tick。⚠️ 速率一律以"每 tick 的放大整数"表达（A1 的 ②）
const WATER_PER_TICK_SCALED := 37 * ElementPool.SCALE / 100
## 反应 0.12 批 / tick
const BATCH_PER_TICK_SCALED := 12 * ElementPool.SCALE / 100
## 温度扫过 [30, 145)，好让两条分支都被看到
const TEMP_PER_TICK := 1.2
const TEMP_MIN := 30.0
const TEMP_MAX := 145.0

## NaCl 0.10 /tick · CaCl₂ 0.05 /tick（都给得比反应需要少 —— 让"抢料"真的发生）
const SALT_PER_TICK_SCALED := 10 * ElementPool.SCALE / 100
const CACL2_PER_TICK_SCALED := 5 * ElementPool.SCALE / 100

const TICK_HZ := 10
const LOG_EVERY_TICKS := 20
const RUN_TICKS := 100

var _pool := ElementPool.new()
var _solver = SOLVER.new()
var _graph = GRAPH.new()
var _compounds: Dictionary = {}
var _widgets := {}
var _intakes: Array = []
var _tick := 0
var _temp := 45.0


## ★ A4 的**运行时唯一把关的地方**（Core Rule ②）：一份数据自称按哪一版写的，
## 与本内核认的那一版是否**同时**在「版本号」与「内容指纹」上一致。
##
## ⚠️ 为什么这一段在**组装点**（本文件）而不是写进 `CompoundData.validate()`：
##   A4 依赖 A2（A4 校验的正是 A2 的表），所以 **A2 不该反过来引用 A4 的契约头** —— 那会成环。
##   机制归 A4、**调用归组装点** —— 与索引里那条「机制归 A4、执行归 B16」是同一条切法。
func _require_contract() -> void:
	var errs := SchemaContract.check_head(TABLE.schema_version, TABLE.schema_fingerprint)
	if errs.is_empty():
		return
	for e: String in errs:
		push_error("[A4 契约] %s" % e)
	# 拒绝载入（A4 §Edge Cases：版本缺失/不符都不得"猜一版"继续跑）
	assert(false, "reactions.tres 与 schema 契约不符 —— 拒绝载入，见上面的 [A4 契约] 行")


## 把 A4 那条检查的**结果**打进日志 —— 让"契约被真的检查过"是可见的，
## 而不是"没报错，所以大概过了"。
func _contract_banner() -> String:
	var errs := SchemaContract.check_head(TABLE.schema_version, TABLE.schema_fingerprint)
	if errs.is_empty():
		return "契约=v%d/%s ✅" % [TABLE.schema_version, TABLE.schema_fingerprint]
	return "契约=❌ %s" % " | ".join(errs)


func _ready() -> void:
	_require_contract()
	_build_ui()
	# ★ T1 的图：**三台机器 + 一条流**（这才是"垂直切片"该有的样子）
	#   电解（水 → H₂+O₂）· 氯碱（NaCl+水 → NaOH+Cl₂+H₂）· 除硬（CaCl₂+NaOH → Ca(OH)₂+NaCl）
	#   而 **NaOH 从氯碱流到除硬** —— 那是 A5 的【边】第一次被真的用上。
	var K := CompoundData.composition_key
	_graph.add_node({"id": &"electrolyzer", "priority": 0,
		"branches": TABLE.steps_for({K.call(WATER): 2}),
		"conditions": {&"param_temperature": _temp}})
	_graph.add_node({"id": &"chlor_alkali", "priority": 0,
		"branches": TABLE.steps_for({K.call(SALT): 2, K.call(WATER): 2}),
		"conditions": {&"param_temperature": _temp}})
	_graph.add_node({"id": &"hardness_removal", "priority": 0,
		"branches": TABLE.steps_for({K.call(CALCIUM_CHLORIDE): 1, K.call({&"Na": 1, &"O": 1, &"H": 1}): 2}),
		"conditions": {&"param_temperature": _temp}})
	_graph.add_edge(&"chlor_alkali", &"hardness_removal")      # NaOH 那条流
	# 原料（每种各走 A1 的余数累加器）
	_intakes = [
		{"id": &"intake_water", "key": &"water", "rate": WATER_PER_TICK_SCALED, "formula": WATER},
		{"id": &"intake_salt", "key": &"salt", "rate": SALT_PER_TICK_SCALED, "formula": SALT},
		{"id": &"intake_cacl2", "key": &"cacl2", "rate": CACL2_PER_TICK_SCALED, "formula": CALCIUM_CHLORIDE},
	]
	# 定步长：P2 要求"同存档 + 同操作序列 → 结果必然复现"，所以绝不跟随帧间隔
	var timer := Timer.new()
	timer.wait_time = 1.0 / TICK_HZ
	timer.timeout.connect(_step)
	add_child(timer)
	timer.start()
	_pool.pool_saturated.connect(func(e: StringName, req: int, acc: int) -> void:
		push_warning("池饱和：%s 请求 %d 只接受 %d —— 上游必须阻塞" % [e, req, acc]))
	_pool.pool_underflow.connect(func(e: StringName, req: int, avail: int) -> void:
		push_error("取料不足：%s 请求 %d 只有 %d —— 调用方的错" % [e, req, avail]))


func _step() -> void:
	_tick += 1
	_temp += TEMP_PER_TICK
	if _temp >= TEMP_MAX:
		_temp = TEMP_MIN

	# ① 进水（多种原料，各走 A1 的余数累加器，全程无浮点）
	for it: Dictionary in _intakes:
		var whole := _pool.accumulate(it["id"], it["key"], it["rate"])
		if whole > 0 and _pool.add_formula(it["formula"], whole):
			_add_compound(it["formula"], whole)

	# ② 反应（走 A2 的表）：攒够整数批才做
	var batches := _pool.accumulate(&"reactor", &"batch", BATCH_PER_TICK_SCALED)
	if batches > 0:
		_run_reaction(batches)

	# ③ 对账：每一 tick 都要过，全程整数比较、无容差（A1 的 ⑤）
	if not _pool.conservation_ok():
		push_error("对账失败：%s" % _pool.conservation_report())

	_update_ui()
	if _tick % LOG_EVERY_TICKS == 0:
		print("[t=%3d T=%6.1f] %s ｜ 原子 H=%d O=%d 总=%d ｜ %s ｜ 对账=%s" % [
			_tick, _temp, _contract_banner(),
			_pool.count(&"H"), _pool.count(&"O"), _pool.total(),
			_compound_line(), "OK" if _pool.conservation_ok() else "FAIL"])
	if _tick >= RUN_TICKS:
		print("—— 跑满 %d tick，退出（对账 %s）" % [RUN_TICKS, "通过" if _pool.conservation_ok() else "失败"])
		get_tree().quit(0 if _pool.conservation_ok() else 1)


## ★ 本版的核心：反应完全由 A2 的数据决定
func _run_reaction(batches: int) -> void:
	# ★ 走 A5：把本切片当作一张【图的求值】 —— 现在图里有【三台机器 + 一条流】。
	#   NaOH 从氯碱流到除硬，那是 A5 的【边】第一次被真的用上。
	#   将来加机器只需在 _ready 里 add_node + add_edge，本函数不用改。
	for nid2: StringName in _graph.node_ids():
		_graph.node(nid2)["conditions"] = {&"param_temperature": _temp}
	var g_r: Dictionary = _graph.evaluate(_compounds, TABLE, _solver)
	# ★ 遍历【所有】节点 —— 一台机器一个结果；而不是只看某台
	var by_node: Array = []
	for nid: StringName in (g_r["results"] as Dictionary):
		by_node.append_array(g_r["results"][nid])

	for res: Dictionary in by_node:
		var took: Dictionary = res.get("took", {})
		var made: Dictionary = res.get("made", {})
		if took.is_empty() and made.is_empty():
			continue

		# ① 原子账：取输入的原子、放回输出的原子（两本账必须逐元素吻合）
		var in_atoms := {}
		var out_atoms := {}
		for k: String in took:
			var lit := CompoundData.atoms_of({k: int(took[k])})
			for e: StringName in lit:
				in_atoms[e] = int(in_atoms.get(e, 0)) + int(lit[e])
		for k: String in made:
			var lit2 := CompoundData.atoms_of({k: int(made[k])})
			for e: StringName in lit2:
				out_atoms[e] = int(out_atoms.get(e, 0)) + int(lit2[e])

		assert(_pool.take_formula(in_atoms)[0], "化合物账说够，原子账就该拿得出")
		assert(_pool.add_formula(out_atoms), "刚取出来的原子必须放得回去")

		# ② 化合物账：应用 A3 的结果（**唯一的副作用点是显式的 apply**）
	# ⚠️ 这里【不】再 apply —— A5 的 evaluate() 内部已经应用过了（上一版双重应用 -> 账跑成负数）

		# ③ 灾难：A3 只标记，后果与连锁归 B5（本切片只告警）
		if String(res.get("disaster", "")) != "":
			push_warning("越界 -> 灾难 %s（后果与连锁归 B5）" % res["disaster"])
# ---------------------------------------------------------------- 化合物账（最小版，B6 的形状）

func _add_compound(f: Dictionary, n: int) -> void:
	_add_compound_by_key(CompoundData.composition_key(f), n)


func _add_compound_by_key(k: String, n: int) -> void:
	if n == 0 or k == "":
		return
	var v := int(_compounds.get(k, 0)) + n
	assert(v >= 0, "化合物账不得为负（%s -> %d）" % [k, v])
	_compounds[k] = v


func _compound_count_by_key(k: String) -> int:
	return int(_compounds.get(k, 0))


func _compound_line() -> String:
	var parts := PackedStringArray()
	var keys := _compounds.keys()
	keys.sort()
	for k: String in keys:
		if _compounds[k] != 0:
			parts.append("%s×%d" % [k, _compounds[k]])
	return " ".join(parts) if parts.size() > 0 else "（空）"


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	add_child(box)
	var title := Label.new()
	title.text = "T1 · 由 A2 的数据表驱动（温度缓慢扫过两条分支）"
	box.add_child(title)
	for name: String in ["tick", "原子账", "化合物账", "对账", "分支"]:
		var l := Label.new()
		box.add_child(l)
		_widgets[name] = l


func _update_ui() -> void:
	_widgets["tick"].text = "tick=%d　T=%.1f°C　（%d Hz 定步长）" % [_tick, _temp, TICK_HZ]
	_widgets["原子账"].text = "【原子账｜守恒】H=%d O=%d 总=%d" % [
		_pool.count(&"H"), _pool.count(&"O"), _pool.total()]
	_widgets["化合物账"].text = "【化合物账｜在变】" + _compound_line()
	_widgets["对账"].text = "【对账】%s" % ("✅ 通过" if _pool.conservation_ok() else "❌ 失败")
	var branches := TABLE.steps_for({CompoundData.composition_key(WATER): 2})
	var hit := "（越界！）"
	for s: Dictionary in branches:
		if TABLE.evaluate(s, {&"param_temperature": _temp})["band"] != "disaster":
			hit = String(s["id"])
	_widgets["分支"].text = "【当前分支】%s" % hit
