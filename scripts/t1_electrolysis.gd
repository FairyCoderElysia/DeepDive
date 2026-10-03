extends Control
## T1 最小垂直切片：海水 → 电解 → H₂ + O₂
##
## 它要验证的是【A1 的整池模型在真引擎里成立】—— 而不是"做一个小游戏"。
## 所以它把两本账分开摆着：
##
##   ① 原子账（A1 的池）—— **守恒的**。对账每一 tick 都要过。
##   ② 化合物账（B6 的形状，此处只做最小版）—— **在变的**。
##
## ⚠️ 为什么必须两本账：**在原子层面 `2H₂O → 2H₂ + O₂` 是守恒的**，
## 所以只看原子账，这个反应"A 什么都没变"。变化的是化合物 ——
## 而"化合物 → 数量"正是 B6 定的罐子表示。本文件的化合物账是【最小版】，
## 真正的 B6 系统（罐容按原子总数、允许混装、取出按组成比例）在后续实现里替换它。
##
## 另一件它要验证的事：**分数速率靠余数累加器攒成整数原子**（A1 的 ②）——
## 所以速率故意取非整数，看它能不能既精确又守恒。
##
## ⚠️ 一处必须写清的纪律（本轮自己踩过）：
## **速率一律以「每 tick 的放大整数」表达，不得先写成"每秒"再除 tick 率** ——
## `int / int` 会在【进累加器之前】就截掉余数，那正是 ② 要防的浮点问题换了个马甲。
## A1 的累加器单位本来就是「原子 × SCALE / **tick**」，所以这样写才忠实。

const TABLE: ElementTable = preload("res://data/element_table.tres")

# ---- 化学式（A2：化合物 = 化学式）----
const WATER := {&"H": 2, &"O": 1}
const HYDROGEN := {&"H": 2}
const OXYGEN := {&"O": 2}

# ---- 工艺参数（A6 的旋钮）。单位：每 tick 的「分子 × SCALE」----
## 进水：**0.37 个水分子 / tick** 的意图 —— 但 ⚠️ 实际值是 387973/SCALE = 0.369999886，
## 因为 `37 * SCALE / 100` 会截断。**这不是漂移，是表示误差**（已在测试里钉住）。
## 规矩：**速率以 SCALE 为单位的整数直接给定**，十进制只是给人看的标签。
const WATER_PER_TICK_SCALED := 37 * ElementPool.SCALE / 100
## 电解：**0.12 次反应 / tick** 的意图（实际 0.119999886，同理）
const ELECTROLYSIS_PER_TICK_SCALED := 12 * ElementPool.SCALE / 100

const TICK_HZ := 10
## 可验证性：headless 下每 N tick 打一行；跑满 RUN_TICKS 就退出（供 smoke 用）
const LOG_EVERY_TICKS := 20
const RUN_TICKS := 100

var _pool := ElementPool.new()
## 化合物账（最小版）：化学式指纹 -> 数量
var _compounds: Dictionary = {}
var _widgets := {}
var _tick := 0


func _ready() -> void:
	_build_ui()
	# 定步长：P2 要求"同存档 + 同操作序列 → 结果必然复现"，所以绝不能跟随帧间隔
	var timer := Timer.new()
	timer.wait_time = 1.0 / TICK_HZ
	timer.timeout.connect(_step)
	add_child(timer)
	timer.start()
	# A1 的 ①：池饱和时**上游必须阻塞**（此处只告警；真正的上游阻塞在 A5 落地时接）
	_pool.pool_saturated.connect(func(e: StringName, req: int, acc: int) -> void:
		push_warning("池饱和：%s 请求 %d 只接受 %d —— 上游必须阻塞" % [e, req, acc]))
	_pool.pool_underflow.connect(func(e: StringName, req: int, avail: int) -> void:
		push_error("取料不足：%s 请求 %d 只有 %d —— 这是调用方的错" % [e, req, avail]))


## 一个 tick。所有速率都以「每 tick 的放大整数」进入累加器。
func _step() -> void:
	_tick += 1

	# ① 进水：分数分子数 → 整数分子（走余数累加器，全程无浮点）
	var water_whole := _pool.accumulate(&"intake", &"water_molecule", WATER_PER_TICK_SCALED)
	if water_whole > 0:
		# 一个水分子的原子 = WATER 的化学式
		if _pool.add_formula(WATER, water_whole):
			_add_compound(WATER, water_whole)
		else:
			# 池满了：这一批**不能悄悄丢掉**（丢 = 物质凭空消失，违反 P2）
			push_warning("进水被池饱和挡住（%d 个水分子）—— 上游必须阻塞" % water_whole)

	# ② 电解：攒够整数次反应才做
	var rx_whole := _pool.accumulate(&"electrolyzer", &"reaction", ELECTROLYSIS_PER_TICK_SCALED)
	if rx_whole > 0:
		_run_electrolysis(rx_whole)

	# ③ 对账：**每一 tick 都要过**，全程整数比较、无容差（A1 的 ⑤）
	if not _pool.conservation_ok():
		push_error("对账失败：%s" % _pool.conservation_report())

	_update_ui()

	# 每 N tick 打一行可被验证的状态（headless 下看不见 Label，而 smoke 需要能验证）
	if _tick % LOG_EVERY_TICKS == 0:
		print("[t=%d] 原子 H=%d O=%d 总=%d ｜ 化合物 水×%d H2×%d O2×%d ｜ 对账=%s" % [
			_tick, _pool.count(&"H"), _pool.count(&"O"), _pool.total(),
			_compound_count(WATER), _compound_count(HYDROGEN), _compound_count(OXYGEN),
			"OK" if _pool.conservation_ok() else "FAIL"])

	if _tick >= RUN_TICKS:
		print("—— 跑满 %d tick，退出（对账 %s）" % [RUN_TICKS, "通过" if _pool.conservation_ok() else "失败"])
		get_tree().quit(0 if _pool.conservation_ok() else 1)


## `2 H₂O → 2 H₂ + O₂`，做 `times` 次。
## 原子层面它是恒等的 —— 所以池的**总量不该变**；变的是化合物账。
func _run_electrolysis(times: int) -> void:
	# 能不能做，由【化合物账】决定（罐里有没有水）
	if _compound_count(WATER) < 2 * times:
		return
	# 原子账：取出 2×水 的原子，再放回 2×H₂ 与 1×O₂ 的原子 —— 净变化为 0
	var need := {&"H": 4 * times, &"O": 2 * times}
	var got: Array = _pool.take_formula(need)
	assert(got[0], "化合物账说有水，原子账就该拿得出 —— 两本账不允许不一致")
	var ok1 := _pool.add_formula(HYDROGEN, 2 * times)
	var ok2 := _pool.add_formula(OXYGEN, 1 * times)
	assert(ok1 and ok2, "刚取出来的原子必须放得回去（池的容量只会因为进水而变）")
	# 化合物账
	_add_compound(WATER, -2 * times)
	_add_compound(HYDROGEN, 2 * times)
	_add_compound(OXYGEN, 1 * times)


func _add_compound(formula: Dictionary, n: int) -> void:
	if n == 0:
		return
	var k := _formula_key(formula)
	var v := int(_compounds.get(k, 0)) + n
	assert(v >= 0, "化合物账不得为负（%s -> %d）" % [k, v])
	_compounds[k] = v


func _compound_count(formula: Dictionary) -> int:
	return int(_compounds.get(_formula_key(formula), 0))


func _formula_key(f: Dictionary) -> String:
	var parts := PackedStringArray()
	var keys := f.keys()
	keys.sort()
	for k: StringName in keys:
		parts.append("%s%d" % [k, f[k]])
	return "".join(parts)


# ---------------------------------------------------------------- UI（"能看见"）

func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	add_child(box)
	var title := Label.new()
	title.text = "T1 · 海水 → 电解 → H₂ + O₂　（验证 A1 的池是否守恒）"
	box.add_child(title)
	for name: String in ["tick", "原子账", "化合物账", "对账", "余数累加器"]:
		var l := Label.new()
		box.add_child(l)
		_widgets[name] = l


func _update_ui() -> void:
	_widgets["tick"].text = "tick = %d　（%d Hz 定步长）" % [_tick, TICK_HZ]

	var atoms := PackedStringArray()
	for e: StringName in [&"H", &"O"]:
		atoms.append("%s=%d" % [e, _pool.count(e)])
	atoms.append("总原子=%d" % _pool.total())
	_widgets["原子账"].text = "【原子账｜守恒】" + "　".join(atoms)

	var comp := PackedStringArray()
	for k: String in _compounds:
		if _compounds[k] != 0:
			comp.append("%s×%d" % [k, _compounds[k]])
	_widgets["化合物账"].text = "【化合物账｜在变】" + ("　".join(comp) if comp.size() > 0 else "（空）")

	_widgets["对账"].text = "【对账】%s　报告=%s" % [
		"✅ 通过" if _pool.conservation_ok() else "❌ 失败", _pool.conservation_report()]

	_widgets["余数累加器"].text = "【余数累加器】进水残留=%d　电解残留=%d　（上界 %d 原子）" % [
		_pool.residual(&"intake", &"water_molecule"),
		_pool.residual(&"electrolyzer", &"reaction"),
		_pool.residual_atom_upper_bound()]
