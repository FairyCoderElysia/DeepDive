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
const OE := preload("res://scripts/oxygen_economy.gd")
const DL := preload("res://scripts/depth_layers.gd")
const TK := preload("res://scripts/tank.gd")

const WATER := {&"H": 2, &"O": 1}
const SALT := {&"Na": 1, &"Cl": 1}          # NaCl
const CALCIUM_CHLORIDE := {&"Ca": 1, &"Cl": 2}   # CaCl₂

## 进水 0.37 个水分子 / tick。⚠️ 速率一律以"每 tick 的放大整数"表达（A1 的 ②）
const WATER_PER_TICK_SCALED := 37 * ElementPool.SCALE / 100
## 反应 0.12 批 / tick
const BATCH_PER_TICK_SCALED := 12 * ElementPool.SCALE / 100
## ★ 2026-10-04 改：**前 HOLD_TICKS tick 守在最优带**（= 正常工况），**之后才扫温**（演示分支）。
##   为什么改：原版**全程扫温** ⇒ 大部分时间在带外、产氧为 0 ⇒
##   那会把"氧够不够"的测量**污染成演示场景的产物** —— 而"正常工况"与"扫温演示"两个参照系
##   会给出完全相反的答案（实测：全程扫温时生命维持 0.7 会把殖民地饿死）。
##   ⇒ 现在两者分开：先看正常工况能不能自持，最后再看分支切换。
const TEMP_PER_TICK := 1.2
const TEMP_MIN := 30.0
const TEMP_MAX := 145.0
## 前多少 tick 守在最优带；此后才扫温（见上）
const HOLD_TICKS := 70
const HOLD_TEMP := 75.0

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
## ★ B4：生命维持耗氧的**分数余量**（单位 ×SCALE）。
##   ⚠️ **氧余额【不】放在这里** —— 它由 `_compounds` 持有（那是唯一的数字，Core Rule ②）。
##   这里只是"攒够一个才动账"的那个余量（与 A1 的余数累加器同一条纪律）。
var _o2_residual_scaled := 0
## 本 tick 的三级分配结果（B4 的 ③）—— **只是"这次谁拿到了多少"，不是三个池**。
var _o2_alloc: Dictionary = {}
## 本 tick 的产氧量（氧/秒）—— 由 A3 的事实折算，B4 只消费它。
var _o2_produced_this_tick := 0.0
## 上一次打印时的 O₂ 存量 —— 用来算【区间均值】（单 tick 采样会采到空转 tick）。
var _o2_last_log_stock := 0
## ★ **直读的累计产氧量** —— 为什么必须有它：我先前用"消耗 ≈ 产氧"反推产氧速率，
##   而那是**无效的推断**：存量触底时（`integrate` 把存量夹在 0）**未被满足的呼吸量会被丢掉**，
##   于是"消耗"小于"名义呼吸"⇒ 反推出来的产氧偏低。**判据要直读，不要反推。**
var _o2_made_total := 0
## ★ B6：氧的仓库。**罐内是化合物表，不是元素池**（Core Rule ①）——
##   而它对 A1 的守恒是"池内部"的（F-B6-1）：存取只在化合物账之间移动，元素池一个原子都不动。
var _o2_tank = TK.new(TK.SIZE_MEDIUM)
## 本 tick 从罐里喝掉的氧 / 装不下而交回的氧（诊断用）
var _o2_drank_from_tank := 0
var _o2_tank_overflow := 0
## 本 tick 的表层提取：请求合计 / 授予合计（C1 的 T1 义务）—— 只用于日志与自检。
var _surface_requested := 0.0
var _surface_granted := 0.0
var _made_this_tick: Dictionary = {}
var _temp := 45.0


## ★ A6 的第一条消费者：把 `CostSurface` 的单旋钮切片真的算出来并打印。
##
## 为什么先做这个：代价面的三个 `[待定]` 里剩下那两个（偏移带曲率 / 权衡换算率）
## 本来就是"**得先看见形状才定得下来**"的东西 —— 所以先让它可看，再回头定。
##
## ⚠️ 它**不改变模拟**（A6 的 Core Rule ⑤）：这里只读 A2 的表、只调 A2 的求值，
##    一行都不写回池或图 —— 那是"关闭 A6 时模拟结果完全不变"（验收 7）的前提。
func _print_cost_slices() -> void:
	var K := CompoundData.composition_key
	var step: Dictionary = (TABLE.steps_for({K.call(WATER): 2}) as Array)[0]
	print("
===== A6 单旋钮切片 · 步骤=%s · 其余 4 个固定在默认值 =====" % step.get("id", "?"))
	# 基准点：每个旋钮取它的【默认值】（来自生成物 = 登记册，不是我手写的）
	var base := {}
	for k in CostSurface.KNOBS:
		var spec: Dictionary = CostSurface.KNOBS[k]
		if String(spec.get("kind", "")) == "enum":
			base[StringName(k)] = (spec["options"] as Array)[0]
		else:
			base[StringName(k)] = spec["default"]
	base[&"param_temperature"] = _temp
	var legend := {}
	for k in CostSurface.KNOBS:
		var pts := CostSurface.slice(step, base, StringName(k), TABLE, 21)
		# ⚠️ 第一版取 band 的**首字母** ⇒ `optimal` 与 `offset` **都是 'O'**，两条带分不开
		#    （我拿那行读数差点下了错结论）。现在改成：**先收集本切片上出现过的 band 种类，
		#    给每一【种】分配一个互不相同的字符** —— 这样无论将来多了哪种带，都不可能混。
		var bands := {}
		for pt2: Dictionary in pts:
			bands[String(pt2["band"])] = true
		var bks: Array = bands.keys()
		bks.sort()
		var palette := ["o", "-", "X", "?", "*", "#", "@", "%"]
		var cmap := {}
		for i2 in bks.size():
			cmap[bks[i2]] = palette[i2 % palette.size()]

		var line := ""
		var pmin := 2.0
		var pmax := -1.0
		for pt: Dictionary in pts:
			var b := String(pt["band"])
			legend[b] = cmap[b]
			line += String(cmap[b])
			# ⚠️ 越界端三项是 `null`（**"不适用"不是 0**，口径 2）——
			#    所以这里必须先判空：`float(null)` 会直接抛错（我第一次就踩了，
			#    而**测试没覆盖到它** —— 那条路径只有真的跑场景才会走到）。
			if pt["purity"] != null:
				pmin = minf(pmin, float(pt["purity"]))
				pmax = maxf(pmax, float(pt["purity"]))
		var spec2: Dictionary = CostSurface.KNOBS[k]
		var rng := "%s..%s" % [spec2.get("min", "?"), spec2.get("max", "?")]
		if String(spec2.get("kind", "")) == "enum":
			rng = "枚举 %d 项" % (spec2["options"] as Array).size()
		var pr := "纯度 %.3f→%.3f" % [pmin, pmax] if pmax >= 0.0 else "纯度 不适用（该段越界）"
		print("  %-22s [%s] %s  %s" % [k, rng, line, pr])
	var ks: Array = legend.keys()
	ks.sort()
	var lg := PackedStringArray()
	for b2: String in ks:
		lg.append("%s=%s" % [legend[b2], b2])
	print("  图例（每格 = 一个采样点）: %s" % "  ".join(lg))

	# ★ 直接把【温度】那条按点摊开 —— 因为上一版的歧义让我**无法回答
	#   "纯度 0.000 到底出在哪个点"**。这条读数就是为了不再靠猜。
	print("  ── param_temperature 逐点（前 8 点）──")
	var tp := CostSurface.slice(step, base, &"param_temperature", TABLE, 21)
	for i3 in mini(8, tp.size()):
		var q: Dictionary = tp[i3]
		var pv := "不适用" if q["purity"] == null else "%.4f" % float(q["purity"])
		var pn := "不适用" if q["penalty"] == null else "%.4f" % float(q["penalty"])
		print("     T=%7.2f  band=%-9s 纯度=%-8s 偏离代价=%s" % [float(q["knob_value"]), String(q["band"]), pv, pn])


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


## ★ **那个唯一的氧余额** —— 住在化合物账里（B4 的 Core Rule ②：氧只有一个池）。
##
## ★ 2026-10-04 用户拍板：**罐里的 O₂ 算"可用氧"**（罐子是"备用的肺"）——
##   否则玩家没有任何理由建氧罐，而"囤氧过冬"这个很自然的策略就不存在。
##   ⇒ 所以"可用氧" = **流动账 + 罐**，两者是**同一个池的两个部分**（F-B6-1：罐 = 池的有界子集）。
func _o2_stock() -> int:
	return int(_compounds.get(OE.O2_KEY, 0)) + int(_o2_tank.contents().get(OE.O2_KEY, 0))


## B4 的一行账：**存量 + 速率 + 状态**（§States 要求两者都要：速率回答"往里还是往外"，
## 存量回答"还能撑多久"）。
func _o2_banner() -> String:
	# ⚠️ 用【区间均值】而不是单 tick 采样：日志每 20 tick 打一次，
	#   而反应是攒够整数批才做 ⇒ 单 tick 采样会**系统性地采到空转 tick**
	#   （实测：单 tick 口径一直显示 −0.050/s，而存量明明在涨）。
	#   §States 要的往里还是往外是**趋势**，所以这里给区间均值。
	var dt := float(LOG_EVERY_TICKS) / float(TICK_HZ)
	var rate := float(_o2_stock() - _o2_last_log_stock) / dt
	var alloc := _o2_alloc
	return "O₂=%d 收支(近%d tick 均值)=%+.3f/s %s ｜ 生命维持分到 %.3f" % [
		_o2_stock(), LOG_EVERY_TICKS, rate, OE.state_of(_o2_stock(), rate),
		float(alloc.get("life_support", 0.0))]


func _step() -> void:
	_tick += 1
	# ★ **每个 tick 都要清零** —— 否则没跑反应的那一 tick 会拿着上一次的  去算速率，
	#   于是产量看起来恒定（我第一次就踩了：报 +9.950/s，而存量 20 tick 才涨 1）。
	#   **判据是速率要和存量的变化对得上** —— 对不上就说明其中一个是假的。
	_made_this_tick = {}
	# ★ 正常工况在前：守住最优带（75 落在 high_T 的 [60,110) 里）；之后才扫温演示分支
	if _tick <= HOLD_TICKS:
		_temp = HOLD_TEMP
	else:
		_temp = TEMP_MIN + float(_tick - HOLD_TICKS - 1) * TEMP_PER_TICK

	# ① 进水（多种原料，各走 A1 的余数累加器，全程无浮点）
	#   ★ C1 的 **T1 义务**：**总提取量要先过表层通量天花板**（海水无限，但**提取有上限**）。
	#     关键在于它压的是【总量】而不是每台泵各自封顶 —— 否则多接几台泵就能线性放大产能，
	#     天花板等于不存在，而"必须下潜"就退化成一句设定（Risk #8）。
	var req_units: Array = []
	for it0: Dictionary in _intakes:
		req_units.append(float(it0["rate"]) / float(ElementPool.SCALE))
	var granted := DL.clamp_surface_intake(req_units,
			DL.SURFACE_THROUGHPUT_CAP / float(TICK_HZ))     # 天花板是"份/秒" ⇒ 每 tick 要除
	_surface_requested = DL.total_of(req_units)
	_surface_granted = DL.total_of(granted)
	for i0 in _intakes.size():
		var it: Dictionary = _intakes[i0]
		var rate_scaled := int(round(float(granted[i0]) * float(ElementPool.SCALE)))
		var whole := _pool.accumulate(it["id"], it["key"], rate_scaled)
		if whole > 0 and _pool.add_formula(it["formula"], whole):
			_add_compound(it["formula"], whole)

	# ①.5 ★ B4：**生命维持真的在呼吸** —— 每 tick 从那个唯一的氧余额里扣。
	#   ⚠️ 余额就是 `_compounds[OE.O2_KEY]`（A5 的化合物账）—— **没有第二个数字**。
	#   扣不动时**不发明死亡机制**：按 B4 的三级优先如实算出"谁拿到了氧"，然后打印出来。
	var stored := int(_o2_tank.contents().get(OE.O2_KEY, 0))
	var o2_stock := _o2_stock()
	# ★ 两项连续支出都在这里：**生命维持**（B4 的常量）与**存贮耗氧**（推论 2，是速率）
	var life := OE.net_rate(0.0, 0.0, float(stored))
	var life_int := OE.integrate(o2_stock, life, 1.0 / float(TICK_HZ), _o2_residual_scaled)
	var o2_after := int(life_int["stock"])
	_o2_residual_scaled = int(life_int["residual_scaled"])
	var drawn := o2_stock - o2_after                        # 本 tick 要扣掉多少（正数 = 被消耗）
	if drawn > 0:
		# ★ 先喝流动账，不够再喝罐（罐子是"备用的肺"）
		var from_flow := mini(drawn, int(_compounds.get(OE.O2_KEY, 0)))
		if from_flow > 0:
			_add_compound_by_key(OE.O2_KEY, -from_flow)
		var still := drawn - from_flow
		if still > 0:
			# 罐里取出：纯 O₂ 的罐，取 2×still 个原子就得到 still 个 O₂
			var got := _o2_tank.take_atoms(still * 2)
			_o2_drank_from_tank += int(got.get(OE.O2_KEY, 0))
	# 三级优先：把"这一 tick 谁拿到了氧"如实算出来（存量不够时低优先级被压缩）
	_o2_alloc = OE.allocate(float(o2_stock) / (1.0 / float(TICK_HZ)),
			OE.LIFE_SUPPORT_RATE, 0.0, 0.0)

	# ② 反应（走 A2 的表）：攒够整数批才做
	var batches := _pool.accumulate(&"reactor", &"batch", BATCH_PER_TICK_SCALED)
	if batches > 0:
		_run_reaction(batches)

	# ②.5 记下本 tick 的**产氧量**（供 B4 算收支用；它是 A3 的事实，B4 只消费）
	_o2_produced_this_tick = float(_made_this_tick.get(OE.O2_KEY, 0)) / (1.0 / float(TICK_HZ))
	_o2_made_total += int(_made_this_tick.get(OE.O2_KEY, 0))          # 直读累计
	# ★ B6：把流动账里的 O₂ 存进罐（罐就是氧的仓库）——
	#   **`put()` 把装不下的原样交回**，而"装不下怎么办"属 A5 的阻塞语义（本切片只如实记下）
	var o2_flowing := int(_compounds.get(OE.O2_KEY, 0))
	if o2_flowing > 0:
		var left := _o2_tank.put({OE.O2_KEY: o2_flowing})
		var stored_now := o2_flowing - int(left.get(OE.O2_KEY, 0))
		if stored_now > 0:
			_add_compound_by_key(OE.O2_KEY, -stored_now)
		_o2_tank_overflow = int(left.get(OE.O2_KEY, 0))

	# ③ 对账：每一 tick 都要过，全程整数比较、无容差（A1 的 ⑤）
	if not _pool.conservation_ok():
		push_error("对账失败：%s" % _pool.conservation_report())

	_update_ui()
	if _tick % LOG_EVERY_TICKS == 0:
		print("[t=%3d T=%6.1f] %s ｜ 原子 H=%d O=%d 总=%d ｜ %s ｜ 对账=%s" % [
			_tick, _temp, _contract_banner(),
			_pool.count(&"H"), _pool.count(&"O"), _pool.total(),
			_compound_line(), "OK" if _pool.conservation_ok() else "FAIL"])
		print("        【B4】%s" % _o2_banner())
		_o2_last_log_stock = _o2_stock()
		print("        【B6】罐 %d/%d 原子（O₂×%d）｜ 本 tick 从罐喝 %d ｜ 装不下交回 %d%s" % [
			_o2_tank.occupied(), _o2_tank.capacity,
			int(_o2_tank.contents().get(OE.O2_KEY, 0)), _o2_drank_from_tank, _o2_tank_overflow,
			"  ← 罐满了，该由 A5 阻塞上游" if _o2_tank.is_full() else ""])
		_o2_drank_from_tank = 0
		_o2_tank_overflow = 0
		print("        【C1】表层提取 请求 %.3f/s → 授予 %.3f/s（上限 %.2f/s，%s）｜ 累计产氧 %d 个" % [
			_surface_requested * float(TICK_HZ), _surface_granted * float(TICK_HZ),
			DL.SURFACE_THROUGHPUT_CAP,
			"咬住" if _surface_requested > _surface_granted + 0.000001 else "未到顶",
			_o2_made_total])
		print("        【C1】表层提取 请求 %.3f/s → 授予 %.3f/s（上限 %.2f/s，%s）" % [
			_surface_requested * float(TICK_HZ), _surface_granted * float(TICK_HZ),
			DL.SURFACE_THROUGHPUT_CAP,
			"咬住" if _surface_requested > _surface_granted + 0.000001 else "未到顶"])
	if _tick >= RUN_TICKS:
		_print_cost_slices()
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
	for nid0: StringName in (g_r["results"] as Dictionary):
		for res0: Dictionary in g_r["results"][nid0]:
			for k0: String in (res0.get("made", {}) as Dictionary):
				_made_this_tick[k0] = int(_made_this_tick.get(k0, 0)) + int(res0["made"][k0])
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
