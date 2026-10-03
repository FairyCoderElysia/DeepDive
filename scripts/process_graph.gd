class_name ProcessGraph
extends RefCounted
## A5：**工艺图** —— 节点 + 边的逻辑图，以及**对整张图的求值**。
##
## 它落地的八条规则（都来自已评审的 A5）：
##   ① **图模型 = 节点 + 边**（逻辑图）。**不得引入逐 tile / 逐格的概念。**
##   ② **求值语义来自 A3** —— A5 **只应用、不重定义**（**不得自定义求值顺序**）。
##   ③ **活跃集由 A5 决定**（A3 只求解该集合内的层内联立）。
##   ④ **连续流，不是批次**。
##   ⑤ **接不住 → 阻塞上游 + 告警**（**绝不丢弃**）。
##   ⑥ **环路 → 迭代到不动点**（带迭代上限 + 超限告警）。
##   ⑦ **A5 持有图**（存图 + 求值）；**B1 只是编辑器** —— 所以依赖方向是 B1 → A5。
##   ⑧ **性能形状随管段数增长**（与 A1 的原子数、A3 的机器数**正交**）。
##
## ⑤ 的落点（**已实现，且不越界**）：
##   "接不住"的对象是【下游的缓存/储罐】—— 而**容量是 B6 的概念**，不归 A5。
##   所以 A5 **不拥有容量**，只在**活跃集判定**里【尊重调用方提供的容量】：
##   某节点的产出物已达容量上限 -> **该节点停用（上游阻塞）+ 告警**，**绝不丢弃**。
##   `capacity` 是节点上的**可选**字段：`{"元素/组成式 key": 上限}`；不给 = 无上限。
##   ⚠️ 这块接口的形状是 A5 定的，而**容量的语义与数值仍属 B6** —— B6 落地时把它接进来即可。

## 环路迭代上限（A5 的 ⑥：带迭代上限 + 超限告警）
const MAX_RING_ITERATIONS := 8


## 节点：{ id: StringName, priority: int, branches: Array, conditions: Dictionary }
var _nodes: Dictionary = {}          # id -> 节点
## 边：[{ "from": StringName, "to": StringName }] —— **只表示物流方向**
var _edges: Array = []


func add_node(node: Dictionary) -> void:
	var id: StringName = node["id"]
	assert(not _nodes.has(id), "节点 id 重复：%s" % id)
	_nodes[id] = node


func add_edge(from_id: StringName, to_id: StringName) -> void:
	assert(_nodes.has(from_id), "边的起点不存在：%s" % from_id)
	assert(_nodes.has(to_id), "边的终点不存在：%s" % to_id)
	_edges.append({"from": from_id, "to": to_id})


func node_ids() -> Array:
	var out := _nodes.keys()
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func edges() -> Array:
	return _edges


func node(id: StringName) -> Dictionary:
	return _nodes[id]


# ---------------------------------------------------------------- 校验

## 返回错误列表（空 = 通过）。
func validate() -> Array:
	var errors: Array = []
	# 悬空边（add_edge 已断言，但图可能被外部直接构造过）
	for e: Dictionary in _edges:
		if not _nodes.has(e["from"]):
			errors.append("边 %s->%s 的起点不存在" % [e["from"], e["to"]])
		if not _nodes.has(e["to"]):
			errors.append("边 %s->%s 的终点不存在" % [e["from"], e["to"]])
	# 节点必须至少有一个 id，且 branches 或 step 至少给一个
	for id: StringName in _nodes:
		var n: Dictionary = _nodes[id]
		if not n.has("branches") and not n.has("step"):
			errors.append("节点 %s 既没有 branches 也没有 step" % id)
		# A3 的 ⑤：优先级是【玩家可配】的，所以它必须显式存在（不靠默认值糊过去）
		if not n.has("priority"):
			errors.append("节点 %s 缺 priority（A3 的 ⑤：优先级是玩家创作的一部分）" % id)
	return errors


# ---------------------------------------------------------------- 拓扑序（环检测）

## Kahn 拓扑排序。**有环时**：把环上的节点按 id 稳定排在末尾，并置 has_cycle = true。
## 为什么要稳定：A5 的 ⑥ 与 A3 的 ⑥ 都要求**同输入 → 逐位一致**。
func topological_order() -> Dictionary:
	var indeg := {}
	for id: StringName in _nodes:
		indeg[id] = 0
	for e: Dictionary in _edges:
		indeg[e["to"]] = int(indeg[e["to"]]) + 1

	# 初始队列按 id 排序 -> 确定性
	var ready: Array = []
	for id: StringName in indeg:
		if int(indeg[id]) == 0:
			ready.append(id)
	ready.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))

	var order: Array = []
	var seen := {}
	while not ready.is_empty():
		var id2: StringName = ready.pop_front()
		order.append(id2)
		seen[id2] = true
		var newly: Array = []
		for e2: Dictionary in _edges:
			if e2["from"] == id2:
				indeg[e2["to"]] = int(indeg[e2["to"]]) - 1
				if int(indeg[e2["to"]]) == 0 and not seen.has(e2["to"]):
					newly.append(e2["to"])
		newly.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for x: StringName in newly:
			ready.append(x)

	var has_cycle := order.size() != _nodes.size()
	if has_cycle:
		var rest: Array = []
		for id3: StringName in _nodes:
			if not seen.has(id3):
				rest.append(id3)
		rest.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		order.append_array(rest)
	return {"order": order, "has_cycle": has_cycle}


# ---------------------------------------------------------------- 求值（A5 的核心）

## 对整张图求值一次（= 一个 tick）。
##
## ★ **嵌套不动点**（A5 的 §Formulas ④）：
##   **外层是环、内层是 A3 的优先级层** —— 而内层完全由 A3 的 `solve()` 承担
##   （A5 的 ②：**求值语义来自 A3，A5 不得重定义**）。
##
## `available`：**会被就地修改**（这是调用方的账；A5 不自己造账）。
##   ⚠️⚠️ **调用方【不得】再对结果调一次 `ReactionSolver.apply()`** ——
##   `evaluate` 内部已经应用过了。**一个"唯一副作用点"如果被两层各调一次，
##   它就不再是唯一的那个了。**（我在把 T1 场景接到 A5 时踩过：双重应用让化合物账跑成负数。）
## 返回：{"results": {node_id: [...]}, "ring_iterations": n, "warned": bool, "has_cycle": bool}
func evaluate(available: Dictionary, table: CompoundData, solver: ReactionSolver) -> Dictionary:
	var topo := topological_order()
	var has_cycle := bool(topo["has_cycle"])
	var order: Array = topo["order"]

	# ③ 活跃集由 A5 决定：能拿到输入的节点。**空图 -> 空结果。**
	var ring_iters := 0
	var warned := false
	var blocked: Array = []          # ⑤ 被阻塞的节点（上游停产）
	var last: Dictionary = {}
	var all_results: Dictionary = {}

	for ri in MAX_RING_ITERATIONS:
		ring_iters = ri + 1
		# 本轮的活跃集（按拓扑序）
		var machines: Array = []
		for id: StringName in order:
			var n: Dictionary = _nodes[id]
			if not _has_any_input(n, available, table):
				continue
			# ⑤ 接不住 -> 阻塞上游 + 告警（**绝不丢弃**：不是"产出了再丢"，而是根本不产）
			if _output_is_full(n, available, table):
				if not blocked.has(id):
					blocked.append(id)
					push_warning("A5：节点 %s 的产出已满 -> 阻塞上游 + 告警（A5 的 ⑤，绝不丢弃）" % id)
				continue
			machines.append(n)
		if machines.is_empty():
			break
		# ★ 内层：**交给 A3**（它自己做优先级分层 + 层内联立 + 层内不动点）
		var r: Dictionary = solver.solve(machines, available, table)
		# 把结果应用到账上，并把每个节点的推进量收集起来（用于外层收敛判定）
		var snap: Dictionary = {}
		for res: Dictionary in r["results"]:
			ReactionSolver.apply(res, available)
			snap[res["id"]] = int(res["advanced_scaled"])
			if not all_results.has(res["id"]):
				all_results[res["id"]] = []
			(all_results[res["id"]] as Array).append(res)
		if r["warned"]:
			warned = true
		# 外层收敛判定：所有节点的推进量都不再变化
		if _snapshots_equal(last, snap):
			break
		last = snap
		# **无环的图：一轮就够**（拓扑序保证了流已经推进到底）
		if not has_cycle:
			break
	if ring_iters >= MAX_RING_ITERATIONS and has_cycle:
		warned = true      # A5 的 ⑥：超限必须告警，不得静默

	return {"results": all_results, "ring_iterations": ring_iters,
			"warned": warned, "has_cycle": has_cycle, "blocked": blocked}


# ---------------------------------------------------------------- 内部

func _snapshots_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: StringName in a:
		if not b.has(k) or int(b[k]) != int(a[k]):
			return false
	return true


## ③ 活跃集判据：这个节点能不能从账上拿到它要的输入。
## ⚠️ A3 会自己做"够不够"的判定，所以这里只做**粗判**（有没有任何输入键的存量 > 0）。
## ⑤ 的判据：这个节点的【产出物】是不是已经满了。
## **满了就不该再推进** —— 因为推进只会让产出溢出（而"绝不丢弃"意味着那部分本来就不该产出）。
func _output_is_full(n: Dictionary, available: Dictionary, table: CompoundData) -> bool:
	var cap: Dictionary = n.get("capacity", {})
	if cap.is_empty():
		return false
	for k: String in cap:
		if int(available.get(k, 0)) >= int(cap[k]):
			return true
	return false


func _has_any_input(n: Dictionary, available: Dictionary, table: CompoundData) -> bool:
	for b: Dictionary in _branches_of(n):
		for k: String in (b.get("inputs", {}) as Dictionary):
			if int(available.get(k, 0)) > 0:
				return true
	return false


## 取节点的候选分支（给 `branches` 或单条 `step`）
func _branches_of(n: Dictionary) -> Array:
	if n.has("branches"):
		return n["branches"]
	return [n["step"]]


# ---------------------------------------------------------------- ④ 连续流：累积量的积分

## 累积量(t) = 累积量(t-1) + 速率 × dt   —— **连续的，不是"按批累加"**。
## 结垢等累积量走此式；**清洗 = 一段停机时间**（期间速率为 0），
## **不是"算作一批"**（那是原型模型，概念文档明确禁止渗入）。
static func integrate(accumulated: float, rate_per_sec: float, dt: float) -> float:
	return accumulated + rate_per_sec * dt


## 清洗：**一段停机时间**。它把累积量拉回 0，而**期间速率必须为 0**。
## 注意签名：它收的是【秒数】而不是"批数" —— 这样写是为了让"它不是一批"在类型上都看得出来。
static func clean_during(downtime_sec: float, rate_during: float) -> float:
	assert(is_zero_approx(rate_during), "清洗期间速率必须为 0 —— 它不是一批，是一段停机时间")
	return maxf(0.0, downtime_sec)
