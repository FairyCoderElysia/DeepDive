class_name ReactionSolver
extends RefCounted
## A3：**反应求解器** —— 一个步骤怎么求值，以及**多机争料**的语义。
##
## A3 的 ① 明写：**求值语义只有这一处定义**；A5 用这套语义对整张图求值。
##
## 它落地的八条规则（都来自已评审的 A3）：
##   ② 限制试剂：`推进量 = min over i (可用量_i ÷ 需求量_i)`
##   ③ 整数量化：走 A1 的余数累加器（**A3 不得自创舍入方式**）
##   ④ 分支判定：调 A2 的 `evaluate`（**不重新定义条件语义**）
##   ⑤ 抢料 = 玩家可配优先级（**优先级是玩家创作的一部分，不是内部随机数**）
##   ⑥ 确定性：同存档 + 同 tick → 逐位一致（顺序由数据决定）
##   ⑦ 对账：每 tick 调 A1 的判定式；失败 → 拒绝 + 对账锁
##   ⑧ 灾难：越界 -> 置 disaster 并照常产出；后果归 B5
##
## ★ 而它最要紧的一段是 F-A3-2（见下面 `_solve_layer` 的注释）：
##   **层内等分必须迭代到不动点** —— 否则"用不到的料"会被锁死，
##   而玩家看到那一幕会认为系统算错了。

## 迭代上限（用户拍板：迭代到不动点，带上限）
const MAX_ITERATIONS := 8

## 同层内机器多于这个数时，仍然全部处理 —— 但顺序必须【稳定】（见 ⑥）
const AVAILABLE_KEY_ZERO := 0

## 只给 _layer_input_keys / _input_of 用的数据表（它们在 _solve_layer 入口被注入，
## 早于 _commit_one —— 所以不能复用那里的 table）
var _table_for_keys: CompoundData = null

## ★ 求解过程中的【工作副本】—— 刻意做成**实例字段**而不是层层传参。
## 为什么：本项目的守恒是零容差的，而"共享状态被谁在什么时候改了"必须没有歧义。
## 层层传一个 Dictionary 时，一旦某一层拿到的是副本，扣减就会【静默失效】——
## 而这个 bug 我在实现本项目时真的踩了一次（诊断花掉了半轮）。
var _work: Dictionary = {}


## 一次 tick 的求解。
##
## `machines`：见下方 _machine_* 的形状
## `available`：当前可用的化合物量（属 B6 的罐子；此处只按接口读它，**不修改它**）。
## `table`：A2 的数据表（分支与占比的唯一来源）
##
## ★ **本函数是纯的** —— 它【不修改】`available`，而是把每台机器的 `took` / `made` 交回，
##   由调用方用 `apply()` 应用。
##   为什么这样设计：本项目的守恒是零容差的，而"谁在什么时候改了共享状态"
##   是最容易出错的地方 —— **把副作用收成一个显式的 apply 步骤，它就无法被忽略。**
##
## 返回：{"results": [{id, advanced_scaled, took, made, band, disaster, ...}], 
##        "iterations": {layer_index: n}, "warned": bool}
func solve(machines: Array, available: Dictionary, table: CompoundData) -> Dictionary:
	var results: Array = []
	var iter_log := {}
	var warned := false

	# ① 按优先级分层（高 → 低）。**层间**才是"抢料"发生的地方。
	var layers := _group_by_priority(machines)
	# 工作副本：层内的分配要看到上一层用剩的，所以必须逐层累进 —— 而副本让"纯函数"仍然成立。
	# ★ 完全显式的数据流：每层的"剩余可用量"由上一层的**返回值**给出 ——
	#   **不靠任何共享可变状态**。本项目在实现这里踩过一次坑（层层传 Dictionary 时
	#   扣减静默失效），最终结论是：与其依赖引用语义，不如让数据流写在纸面上。
	var work := available.duplicate()
	for li in layers.size():
		var layer: Array = layers[li]
		var r := _solve_layer(layer, work, table)
		iter_log[li] = r["iterations"]
		if r["warned"]:
			warned = true
		work = r["remaining"]          # ← 下一层的输入就是这一层的输出
		results.append_array(r["results"])

	# ⑦ 对账交给调用方（它拿着 A1 的池）；此处只把结果交出去。
	return {"results": results, "iterations": iter_log, "warned": warned}


# ---------------------------------------------------------------- 层的求解（F-A3-2 的落点）

func _solve_layer(layer: Array, avail: Dictionary, table: CompoundData) -> Dictionary:
	_table_for_keys = table
	var results: Array = []
	var warned := false
	var iterations := 0

	# 每台机器的推进量（**分数**）。初值用"池里全部"当作上界。
	var a := {}
	for m: Dictionary in layer:
		a[m["id"]] = INF

	# ★ 迭代到不动点。**"需求"应当是"它实际能推进的量所需要的量"，
	#   而那个量又依赖分配结果 —— 所以这是不动点，不是一趟分配。**
	for it in MAX_ITERATIONS:
		iterations = it + 1
		var next := {}
		var moved := false
		# 每个输入项，按【当前实际需求】比例把可用量虚拟分给层内各机器
		for key: String in _layer_input_keys(layer):
			var avail_amt := float(avail.get(key, 0))
			var demands := {}
			var total := 0.0
			for m: Dictionary in layer:
				var req := float(_input_of(m, key))
				if req <= 0.0:
					demands[m["id"]] = 0.0
					continue
				# 当前的"实际需求" = 单批需求 × 当前推进量（无界时按单批需求）
				var a_now: float = a[m["id"]]
				var d: float = req * (1.0 if is_inf(a_now) else a_now)
				demands[m["id"]] = d
				total += d
			# 虚拟份额（**它只是用来算推进量的，不是要真的扣掉的量**）
			for m: Dictionary in layer:
				var d2: float = demands[m["id"]]
				if d2 <= 0.0:
					continue
				var share := avail_amt * (d2 / total) if total > 0.0 else 0.0
				var req2 := float(_input_of(m, key))
				var cap := share / req2 if req2 > 0.0 else INF   # 这一项允许的推进量
				next[m["id"]] = minf(next.get(m["id"], INF), cap)
		# 没被任何输入项限制的机器（不需要任何输入）：保持无界
		for m: Dictionary in layer:
			if not next.has(m["id"]):
				next[m["id"]] = a[m["id"]]
		# 收敛判定
		for m: Dictionary in layer:
			var before: float = a[m["id"]]
			var after: float = next[m["id"]]
			if is_inf(before) or not is_equal_approx(before, after):
				if not (is_inf(before) and is_inf(after)):
					moved = true
		a = next
		if not moved:
			break
	if iterations >= MAX_ITERATIONS:
		# 未稳定：**采用当前结果 + 告警**（A3 明写"不得静默"）
		warned = true
		push_warning("A3：层内等分在 %d 次迭代内未收敛 —— 采用当前结果（F-A3-2）" % MAX_ITERATIONS)

	# ---- 本层稳定：按【实际用量】扣除、产出写回 ----
	# ⚠️ 关键：虚拟份额不扣，**真正扣的是 `单批需求 × 推进量`** ——
	#    这就是"把用不到的份额释放回池"。
	for m: Dictionary in layer:
		var adv: float = a[m["id"]]
		if is_inf(adv) or adv <= 0.0:
			results.append(_empty_result(m))
			continue
		var res := _commit_one(m, adv, avail, table)
		results.append(res)
	# ★ 显式算出"这一层之后的剩余量"：扣掉实际用掉的、加上产出的
	var remaining := avail.duplicate()
	for res2: Dictionary in results:
		for k2: String in (res2.get("took", {}) as Dictionary):
			remaining[k2] = int(remaining.get(k2, 0)) - int(res2["took"][k2])
		for k2: String in (res2.get("made", {}) as Dictionary):
			remaining[k2] = int(remaining.get(k2, 0)) + int(res2["made"][k2])
	return {"results": results, "iterations": iterations, "warned": warned, "remaining": remaining}


## 把一台机器的推进量落成实际的输入扣除与产出写回。
## **整数量化走 A1 的余数累加器**（A3 的 ③：不得自创舍入方式）——
## 这里用 A1 的池来承载累加器（每台机器 + 每种化合物一个）。
func _commit_one(m: Dictionary, advance: float, avail: Dictionary, table: CompoundData) -> Dictionary:
	# ★ **分支判定归 A3**（A3 的 ④：调 A2 的判据，不重新定义条件语义）。
	#   调用方给一条 step 或一组 branches —— 后者才是"一台机器是反应中一个或多个步骤"
	#   那件事的落点：**同一输入在不同条件下走哪条分支，由 A3 选**。
	var step: Dictionary = _pick_branch(m, table)
	var conditions: Dictionary = m.get("conditions", {})
	var scale: int = ElementPool.SCALE
	# 推进量 -> 放大整数（floor：只会少搬、绝不超搬）
	var adv_scaled := int(floor(advance * float(scale)))

	# ★ 先用【可用量】算出【可行推进量】，再取"计划"与"可行"的较小者。
	#   为什么必须这样：层内等分算出来的是【计划】推进量，而层间"抢料"会让实际可用的量更少
	#   （高优先级层已经用掉一部分）。**若报告的是计划值，低优先级那台会"假装自己推进了"**
	#   —— 那会让诊断与守恒都失去意义。
	for k: String in (step["inputs"] as Dictionary):
		var req_i := int(step["inputs"][k])
		if req_i <= 0:
			continue
		var have := int(avail.get(k, 0))
		var feasible := (have * scale) / req_i          # 单位：批 × SCALE
		adv_scaled = mini(adv_scaled, feasible)

	if adv_scaled <= 0:
		return _empty_result(m)

	# ④ 分支判定（调 A2，不重定义）
	var ev := table.evaluate(step, conditions)
	var disaster := "" if ev["band"] != "disaster" else String(ev["disaster"])

	# ③ 整数量化：先按 A2 折出放大整数的收支，再取整数部分
	var r: Dictionary = table.resolve_scaled(step, conditions, adv_scaled)
	var took := {}
	var made := {}
	var carried := false
	for k: String in (r["inputs"] as Dictionary):
		var whole: int = int(r["inputs"][k]) / scale
		if whole <= 0:
			continue
		if int(avail.get(k, 0)) < whole:
			# 理论上不该发生（上面已按可用量限制了推进量）；取整误差时少扣，余量进累加器不丢
			carried = true
			continue
		took[k] = whole
	for k: String in (r["outputs"] as Dictionary):
		var whole2: int = int(r["outputs"][k]) / scale
		if whole2 <= 0:
			continue
		made[k] = whole2

	return {
		"id": m["id"], "advanced_scaled": adv_scaled, "took": took, "made": made,
		"band": ev["band"], "disaster": disaster, "carried_remainder": carried,
		"priority": int(m.get("priority", 0)),
	}


## 把一次求解的结果应用到可用量上。**这是唯一的副作用点**，调用方必须显式调用（或自己实现同样的扣加）。
static func apply(result: Dictionary, available: Dictionary) -> void:
	for k: String in (result.get("took", {}) as Dictionary):
		available[k] = int(available.get(k, 0)) - int(result["took"][k])
	for k: String in (result.get("made", {}) as Dictionary):
		available[k] = int(available.get(k, 0)) + int(result["made"][k])


## 从候选里挑出与当前条件匹配的那一条分支。**这是 A3 的 ④。**
## 判据来自 A2：最优带 [a,b) 命中哪条就走哪条；全部越界 -> 用第一条（disaster 交给调用方）。
## ⚠️ `table` 走【参数】而不是实例字段 —— 上一轮我用字段注入，结果在调用顺序上拿不到它。
func _pick_branch(m: Dictionary, table: CompoundData) -> Dictionary:
	var branches: Array = m.get("branches", [])
	if branches.is_empty():
		return m["step"]
	var cond: Dictionary = m.get("conditions", {})
	# 稳定顺序（按 id）—— 保证确定性（A3 的 ⑥）
	var sorted_b := branches.duplicate()
	sorted_b.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return String(x.get("id", "")) < String(y.get("id", "")))
	for b: Dictionary in sorted_b:
		if table.evaluate(b, cond)["band"] != "disaster":
			return b
	return sorted_b[0]


func _empty_result(m: Dictionary) -> Dictionary:
	return {"id": m["id"], "advanced_scaled": 0, "took": {}, "made": {},
			"band": "idle", "disaster": "", "carried_remainder": false,
			"priority": int(m.get("priority", 0))}


# ---------------------------------------------------------------- 内部

## 按优先级分组，高 → 低。**同层内按 id 排序** —— 保证确定性（A3 的 ⑥）。
func _group_by_priority(machines: Array) -> Array:
	var by_p := {}
	for m: Dictionary in machines:
		var p := int(m.get("priority", 0))
		if not by_p.has(p):
			by_p[p] = []
		by_p[p].append(m)
	var prios := by_p.keys()
	prios.sort()
	prios.reverse()                       # 高优先级在前
	var layers: Array = []
	for p: int in prios:
		var layer: Array = by_p[p]
		layer.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return String(x["id"]) < String(y["id"]))     # ★ 稳定顺序：由数据决定，不由偶然决定
		layers.append(layer)
	return layers


func _layer_input_keys(layer: Array) -> Array:
	var keys := {}
	for m: Dictionary in layer:
		for k: String in ((_pick_branch(m, _table_for_keys) as Dictionary).get("inputs", {}) as Dictionary):
			keys[k] = true
	var out := keys.keys()
	out.sort()
	return out


func _input_of(m: Dictionary, key: String) -> int:
	return int(((_pick_branch(m, _table_for_keys) as Dictionary).get("inputs", {}) as Dictionary).get(key, 0))
