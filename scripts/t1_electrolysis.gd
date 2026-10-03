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

const WATER := {&"H": 2, &"O": 1}

## 进水 0.37 个水分子 / tick。⚠️ 速率一律以"每 tick 的放大整数"表达（A1 的 ②）
const WATER_PER_TICK_SCALED := 37 * ElementPool.SCALE / 100
## 反应 0.12 批 / tick
const BATCH_PER_TICK_SCALED := 12 * ElementPool.SCALE / 100
## 温度扫过 [30, 145)，好让两条分支都被看到
const TEMP_PER_TICK := 1.2
const TEMP_MIN := 30.0
const TEMP_MAX := 145.0

const TICK_HZ := 10
const LOG_EVERY_TICKS := 20
const RUN_TICKS := 100

var _pool := ElementPool.new()
var _solver = SOLVER.new()
var _compounds: Dictionary = {}
var _widgets := {}
var _tick := 0
var _temp := 45.0


func _ready() -> void:
	_build_ui()
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

	# ① 进水（走 A1 的余数累加器，全程无浮点）
	var water_whole := _pool.accumulate(&"intake", &"water", WATER_PER_TICK_SCALED)
	if water_whole > 0 and _pool.add_formula(WATER, water_whole):
		_add_compound(WATER, water_whole)

	# ② 反应（走 A2 的表）：攒够整数批才做
	var batches := _pool.accumulate(&"reactor", &"batch", BATCH_PER_TICK_SCALED)
	if batches > 0:
		_run_reaction(batches)

	# ③ 对账：每一 tick 都要过，全程整数比较、无容差（A1 的 ⑤）
	if not _pool.conservation_ok():
		push_error("对账失败：%s" % _pool.conservation_report())

	_update_ui()
	if _tick % LOG_EVERY_TICKS == 0:
		print("[t=%3d T=%6.1f] 原子 H=%d O=%d 总=%d ｜ %s ｜ 对账=%s" % [
			_tick, _temp, _pool.count(&"H"), _pool.count(&"O"), _pool.total(),
			_compound_line(), "OK" if _pool.conservation_ok() else "FAIL"])
	if _tick >= RUN_TICKS:
		print("—— 跑满 %d tick，退出（对账 %s）" % [RUN_TICKS, "通过" if _pool.conservation_ok() else "失败"])
		get_tree().quit(0 if _pool.conservation_ok() else 1)


## ★ 本版的核心：反应完全由 A2 的数据决定
func _run_reaction(batches: int) -> void:
	var water_key := CompoundData.composition_key(WATER)

	# ⚠️ **已知缺口（本轮接线时暴露）**：A3 的 ④ 明写"分支判定归 A3"，
	#   而我的 ReactionSolver 目前要求调用方先把【分支 step】挑好再交给它。
	#   -> 这里由场景代挑（与 A5 将来要做的同一件事）；**这条缺口已记进断点**。
	var branches := TABLE.steps_for({water_key: 2})
	var chosen: Dictionary = {}
	for s: Dictionary in branches:
		if TABLE.evaluate(s, {&"param_temperature": _temp})["band"] != "disaster":
			chosen = s
	if chosen.is_empty():
		push_warning("温度 %.1f 落在所有分支的越界区 —— 那是灾难；本切片只告警" % _temp)
		return

	# ★ 交给 A3：一台机器、一个 step、当前条件
	var machine := {
		"id": &"electrolyzer",
		"priority": 0,
		"step": chosen,
		"conditions": {&"param_temperature": _temp},
	}
	# A3 的 solve 是【纯】的；化合物账就是它读的 available
	var r: Dictionary = _solver.solve([machine], _compounds, TABLE)

	for res: Dictionary in r["results"]:
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
		SOLVER.apply(res, _compounds)

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
