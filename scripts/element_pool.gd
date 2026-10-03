class_name ElementPool
extends RefCounted
## A1 的 ①②⑤：**原子池**（池只存非负整数原子）+ **余数累加器**（放大整数，全程无浮点）+ **对账**。
##
## 三条不可动摇的（都来自已评审的 A1）：
##   ① 池本体永远是 **int64 整数**；分数速率由**每台机器自己的余数累加器**累积，攒够 1 个原子才搬运。
##      **溢出饱和 + 告警**，且**饱和时上游阻塞** —— **绝不丢弃**
##      （丢弃 = 物质凭空消失 = 直接违反 P2「严谨是美感」）。
##   ⑤ 对账：池的变化**必须逐元素等于净导入**，**全程整数比较、无容差**。
##
## 2026-10-03 在 Godot 4.7.2 实测确认（这两条撑起了上面两行）：
##   · int64 `max + 1` 会【静默回绕成负数】（引擎不报错）⇒ 所以必须显式做饱和判断，
##     否则池会静默变成「负物质」。
##   · 二进制序列化（`var_to_bytes`）逐位精确；而 JSON 会把 int64 变成 float 且 `==` 仍返回 true
##     ⇒ 所以池的存档必须走二进制 + 断言 `typeof()`（那一步在 B16 落地时做）。

## 池被加到饱和（上游必须据此阻塞）
signal pool_saturated(element_id: StringName, requested: int, accepted: int)

## 池的下限违规（取到不足）—— 这是**调用方的错**，不是玩家的错
signal pool_underflow(element_id: StringName, requested: int, available: int)

## int64 上限。**用它做饱和判断，而不是等它溢出** —— 溢出是静默的。
const MAX_ATOMS := 9223372036854775807

## SCALE = 2^20：累加器的放大倍数（A1 的 ②）
const SCALE := 1048576

## element_id -> 原子数（永远是 int，永远 ≥ 0）
var _atoms: Dictionary = {}

## 余数累加器：machine_id -> { element_id -> 单位是「原子 × SCALE」的整数 }
## ⚠️ 是**每 `(机器, 元素)` 一个**（`r[m][e]`）—— 这决定了 A1 的误差上界是「机器数 × 元素种数」
var _residual: Dictionary = {}

## 对账基线：element_id -> 原子数。每次 add/take 都会同步维护「净导入」账
var _net_imported: Dictionary = {}


# ---------------------------------------------------------------- 池本体

## 加原子。返回**实际接受**的个数（饱和时 < 请求量）。饱和时**必须**由上游阻塞。
func add(element_id: StringName, amount: int) -> int:
	assert(amount >= 0, "add 的 amount 不得为负（取料请用 take）")
	if amount == 0:
		return 0
	var current := count(element_id)
	# ⚠️ 必须这样判断：写成 `current + amount > MAX_ATOMS` 会先溢出再比较（实测会静默回绕）
	var accepted := amount
	if amount > MAX_ATOMS - current:
		accepted = MAX_ATOMS - current
	_atoms[element_id] = current + accepted
	_bump_net(element_id, accepted)
	if accepted < amount:
		pool_saturated.emit(element_id, amount, accepted)
	return accepted


## 取原子。返回**实际取出**的个数（不足时 < 请求量，并 emit 下溢）。
func take(element_id: StringName, amount: int) -> int:
	assert(amount >= 0, "take 的 amount 不得为负")
	if amount == 0:
		return 0
	var available := count(element_id)
	var taken := mini(amount, available)
	if taken > 0:
		_atoms[element_id] = available - taken
		_bump_net(element_id, -taken)
	if taken < amount:
		pool_underflow.emit(element_id, amount, available)
	return taken


func count(element_id: StringName) -> int:
	return int(_atoms.get(element_id, 0))


## 池里的原子总数（用于对账）。
func total() -> int:
	var t := 0
	for e: StringName in _atoms:
		t += int(_atoms[e])
	return t


## 按化学式取料。`formula` = {element_id: 系数}（A2：化合物 = 化学式）。
## 返回 (是否全部取到, 每元素实际取到量)。
## ⚠️ **要么全取、要么全不取**（原子一旦取走就得还回去，否则对账会看到假变化）。
func take_formula(formula: Dictionary, times: int = 1) -> Array:
	assert(times >= 0)
	for e: StringName in formula:
		if count(e) < int(formula[e]) * times:
			return [false, {}]
	var got := {}
	for e: StringName in formula:
		var n := int(formula[e]) * times
		take(e, n)
		got[e] = n
	return [true, got]


## 按化学式放料。返回是否**全部**放进去了（饱和时 false —— 上游必须阻塞）。
func add_formula(formula: Dictionary, times: int = 1) -> bool:
	assert(times >= 0)
	# 先探一遍容量：只要有一个元素放不下，就整批不放（避免半批状态）
	for e: StringName in formula:
		var n := int(formula[e]) * times
		if n > MAX_ATOMS - count(e):
			return false
	for e: StringName in formula:
		add(e, int(formula[e]) * times)
	return true


# ---------------------------------------------------------------- 余数累加器（A1 的 ②）

## 让某台机器对某元素累计一次需求。
## `scaled_rate` 的单位是「**原子 × SCALE / tick**」—— **它本身就是整数**，
## 所以这里**全程没有浮点乘法**（A1 明确：绝不用 `float 速率 × SCALE`，那会把浮点请回来）。
## 返回本次攒够的**整数原子数**（floor），调用方据此搬运。
func accumulate(machine_id: StringName, element_id: StringName, scaled_rate: int) -> int:
	assert(scaled_rate >= 0, "需求不得为负（要取料请用 take）")
	if not _residual.has(machine_id):
		_residual[machine_id] = {}
	var m: Dictionary = _residual[machine_id]
	var r := int(m.get(element_id, 0)) + scaled_rate
	# 整数除法 = floor（GDScript 的 int / int 就是向下取整——舍入方向必须是 floor：
	# floor 只会少搬、绝不超搬 ⇒ 池永远不会凭空多出原子）
	var n := r / SCALE
	m[element_id] = r - n * SCALE
	return n


## 某台机器对某元素的当前残留（单位：原子 × SCALE）。**它不计入原子总量**（A1 明写）。
func residual(machine_id: StringName, element_id: StringName) -> int:
	return int((_residual.get(machine_id, {}) as Dictionary).get(element_id, 0))


## 全部残留折算成原子的**上界**（用于对账时解释"为什么池比理想连续模型少"）。
## A1 的上界：< 机器数 × 元素种数 个原子。
func residual_atom_upper_bound() -> int:
	var pairs := 0
	for m: StringName in _residual:
		pairs += (_residual[m] as Dictionary).size()
	return pairs


# ---------------------------------------------------------------- 对账（A1 的 ⑤）

## 净导入账（每元素）。add 加、take 减。
func net_imported(element_id: StringName) -> int:
	return int(_net_imported.get(element_id, 0))


## 对账判据：**池的当前量必须逐元素等于净导入**（若调用方从零开始）。
## ⚠️ 全程整数比较、无容差 —— 有任何浮点参与都会让它变成"差不多"。
func conservation_ok() -> bool:
	for e: StringName in _net_imported:
		if count(e) != net_imported(e):
			return false
	# 也要检查那些"净导入为 0 但池非空"的元素（防漏记）
	for e: StringName in _atoms:
		if count(e) != net_imported(e):
			return false
	return true


## 给测试与诊断用：逐元素列出对账差
func conservation_report() -> Dictionary:
	var out := {}
	var keys := {}
	for e: StringName in _net_imported:
		keys[e] = true
	for e: StringName in _atoms:
		keys[e] = true
	for e: StringName in keys:
		var d := count(e) - net_imported(e)
		if d != 0:
			out[e] = d
	return out


func _bump_net(element_id: StringName, delta: int) -> void:
	_net_imported[element_id] = int(_net_imported.get(element_id, 0)) + delta
