class_name CompoundData
extends Resource
## A2：**化合物与反应数据表** —— 只读数据。**运行时状态一律归 A3。**
##
## 三条在本文件里被强制执行的硬约束（都来自已评审的 A2）：
##   ① **化合物 = 组成式唯一标识**。组成（元素 → 原子数）**就是主键**，名字只是显示标签 ——
##      "同一组成两个名字"在结构上不可能。
##   ② **一记录一步骤**：输入 → 条件区间 → 输出。**分支 = 同一输入的多条记录**，
##      各自带**不重叠**的条件区间 —— 分支不是特例，而是区间划分推出来的。
##   ④ **强制配平**：每条记录输入输出**元素原子数必须整数配平**，否则**拒绝导入整张表**并指出是哪一条。
##      ⚠️ 校验对象是「**记录的输出集合**」，不是单个产物。
##   补充（F-A2-1）：**每条记录 Σ副产物系数 ≤ 1**。
##
## 关于浮点：本表里的数字是【设计期常量】，允许是浮点。
## 而**运行时**的条件求值结果一旦要变成原子数，必须走 A1 的放大整数路径（那是 A3 的事）。
##
## 关于旋钮：**旋钮的权威定义在 A1**（③ 参数 schema）。本表只**引用** `param_*` 名字，
## 不另立定义 —— 否则又是"同一事实两处定义"。

const SCHEMA_VERSION := 1

## schema 版本。**必须存在** —— 与 A1 同口径（否则后期改表要改所有下游）。
@export var schema_version: int = SCHEMA_VERSION

## 步骤记录表。每条的字段见下（`scripts/` 里以本文件为唯一权威）：
##   id            : String        —— 人类可读的标识（日志/百科用）
##   inputs        : Dictionary    —— 组成式 key -> 数量
##   outputs       : Dictionary    —— 组成式 key -> 数量
##   conditions    : Array         —— 每个受控旋钮一段（见下）
##   ★ 条件偏移时出的是【另一组同样配平的输出】（**不是"附加产物"**）——
##     因为 A2 的 ④ 是硬约束：配平必须成立。若副产物是"附加"上去的，原子就不守恒了。
##   disaster      : String        —— 越界时的灾难 id（对应 B5 的灾难类型）
##   conditions 里每一项：
##     param              : StringName  —— **引用** A1 的 param_* 名（不得另立）
##     opt_lo / opt_hi    : float      —— 最优带 [opt_lo, opt_hi)（**左闭右开**）
##     brk_lo / brk_hi    : float      —— 越界点：<= brk_lo 或 >= brk_hi 就是灾难
##     coef_lo / coef_hi  : float      —— 该侧偏移带的副产物系数
##     alt                : Dictionary —— 该旋钮偏移时的【另一组配平输出】（组成式 key -> 数量）
@export var steps: Array = []


# ---------------------------------------------------------------- 化合物 = 组成式

## **组成式唯一标识**（A2 的 ①）。元素按符号排序拼成 —— 所以"同一组成两个名字"结构上不可能。
## 例：{O:1, H:2} 与 {H:2, O:1} 与 {H:1, O:0.5 化成整数后} 都归一到同一个 key。
static func composition_key(composition: Dictionary) -> String:
	# ⚠️ 必须【显式按字符串形式】排序。实测（Godot 4.7.2）：
	#   Array[StringName].sort() -> [&"Na", &"H", &"Cl"]（**不是字母序**，按 StringName 的内部次序）
	#   Array[String].sort()     -> ["Cl", "H", "Na"]（才是字母序）
	# 那个内部次序【当前是稳定的，但它由引擎实现决定】—— 一旦随版本变动，
	# 已经烤进 .tres 的键就会与运行时算出的键对不上，**而且不会报错**。
	# 所以这里把它钉成【字典序、与版本无关】。
	var keys := _sorted_strings(composition.keys())
	var parts := PackedStringArray()
	for e: StringName in keys:
		var n := int(composition[e])
		if n != 0:
			parts.append("%s%d" % [e, n])
	return "|".join(parts) if parts.size() > 0 else "∅"


## **公开**：把 `{组成式 key -> 数量}` 折成 `{元素 -> 原子数}`。
## 数量可以是任意整数（包括"数量 × SCALE"的放大值）—— 它只做乘法与加法，不关心单位。
## **测试与 A3 都该用这个，而不是够私有函数。**
static func atoms_of(counts: Dictionary) -> Dictionary:
	var out := {}
	for k: String in counts:
		out = _merge(out, atom_totals_by_key(k, int(counts[k])))
	return out


## 上式的便捷形式：只取总原子数（守恒比较用）。
static func total_atoms_of(counts: Dictionary) -> int:
	var n := 0
	for e: StringName in atoms_of(counts):
		n += int(atoms_of(counts)[e])
	return n


## 一个组成式与另一化合物反应时，用它算总原子数（配平校验用）。
static func atom_totals(composition: Dictionary) -> Dictionary:
	var out := {}
	for e: StringName in composition:
		out[e] = int(out.get(e, 0)) + int(composition[e])
	return out


# ---------------------------------------------------------------- 导入期校验（A2 的 ④）

## 校验整张表。返回**错误列表**（空 = 通过）。
## **校验不过就【拒绝导入整张表】** —— 不是跳过那一条（A2 的 ④ 明写）。
## `known_elements`：A1 已登记的元素集合（StringName -> true）。传空 = 跳过这项校验。
func validate(known_elements: Dictionary = {}) -> Array:
	var errors: Array = []
	if schema_version != SCHEMA_VERSION:
		errors.append("schema_version = %d，本内核只认 %d" % [schema_version, SCHEMA_VERSION])

	var seen_ids := {}
	var by_input := {}      # 输入 key -> 该输入的记录列表（用于查区间重叠）

	for i in steps.size():
		var s: Dictionary = steps[i]
		var wid := "步骤[%d] id=%s" % [i, s.get("id", "?")]

		# --- id 不得重复 ---
		var sid := String(s.get("id", ""))
		if sid == "":
			errors.append("%s：缺 id" % wid)
		elif seen_ids.has(sid):
			errors.append("%s：id 重复" % wid)
		else:
			seen_ids[sid] = true

		# --- ★ 强制配平：**校验对象是「记录的输出集合」**（不是单个产物）---
		var lhs := {}
		for k: String in (s.get("inputs", {}) as Dictionary):
			lhs = _merge(lhs, atom_totals_by_key(k, int(s["inputs"][k])))
		var rhs := _merge({}, {})
		for k: String in (s.get("outputs", {}) as Dictionary):
			rhs = _merge(rhs, atom_totals_by_key(k, int(s["outputs"][k])))
		if lhs.is_empty():
			errors.append("%s：没有 inputs" % wid)
		if lhs != rhs:
			errors.append("%s：**未配平** 输入=%s 最优输出=%s" % [wid, lhs, rhs])
		# ★ 每一组 alt（条件偏移时的另一组输出）必须【独立配平同一份输入】——
		#   否则偏移时会凭空多出/少掉元素，守恒直接破。
		for c: Dictionary in (s.get("conditions", []) as Array):
			var alt: Dictionary = c.get("alt", {})
			if alt.is_empty():
				continue
			var arhs := _merge({}, {})
			for k: String in alt:
				arhs = _merge(arhs, atom_totals_by_key(k, int(alt[k])))
			if arhs != lhs:
				errors.append("%s：旋钮 %s 的 alt 未配平（输入=%s alt=%s）—— 偏移时守恒会破" % [
					wid, c.get("param", "?"), lhs, arhs])

		# --- 缺元素校验（验收 5）：引用了 A1 未登记的元素，必须报出是哪一个 ---
		if not known_elements.is_empty():
			var keys: Array = []
			keys.append_array((s.get("inputs", {}) as Dictionary).keys())
			keys.append_array((s.get("outputs", {}) as Dictionary).keys())
			for c2: Dictionary in (s.get("conditions", []) as Array):
				keys.append_array((c2.get("alt", {}) as Dictionary).keys())
			for k2: String in keys:
				for seg: String in String(k2).split("|"):
					if seg == "":
						continue
					var sym: StringName = _parse_segment(seg)[0]
					if not known_elements.has(sym):
						errors.append("%s：引用了未登记的元素「%s」（组成式 %s）" % [wid, sym, k2])

		# --- 编号：每条记录必须有 outputs ---
		if (s.get("outputs", {}) as Dictionary).is_empty():
			errors.append("%s：没有 outputs" % wid)

		# --- 空组成式 / 原子数为 0（§Edge Cases）：**拒绝** ---
		#     ① 组成式必须非空 ② 只记实际存在的元素（不得出现 `H0` 这种条目）
		var allkeys: Array = []
		allkeys.append_array((s.get("inputs", {}) as Dictionary).keys())
		allkeys.append_array((s.get("outputs", {}) as Dictionary).keys())
		for c3: Dictionary in (s.get("conditions", []) as Array):
			allkeys.append_array((c3.get("alt", {}) as Dictionary).keys())
		for k3: String in allkeys:
			if String(k3) == "" or String(k3) == "∅":
				errors.append("%s：出现了空组成式 —— 组成式必须非空" % wid)
				continue
			for seg2: String in String(k3).split("|"):
				var mm := _parse_segment(seg2)
				if int(mm[1]) <= 0:
					errors.append("%s：组成式 %s 里「%s」的个数是 %d —— 只记实际存在的元素（不得写 0 或负数）" % [
						wid, k3, seg2, int(mm[1])])

		# --- ★ F-A2-1：Σ副产物系数 ≤ 1 ---
		var coef_sum := 0.0
		for c: Dictionary in (s.get("conditions", []) as Array):
			coef_sum += float(c.get("coef_lo", 0.0)) + float(c.get("coef_hi", 0.0))
			# 数序：**最优带必须非空**（opt_lo < opt_hi），
			# 而两侧偏移带**允许零宽**（brk_lo == opt_lo 表示"最优带以下立刻是灾难"）。
			# ⚠️ 零宽是安全的：那时 v <= brk_lo 已经走灾难分支，
			#    所以 δ 式里的 (opt_lo - brk_lo) 作为分母永不为 0。
			if not (float(c["brk_lo"]) <= float(c["opt_lo"])
					and float(c["opt_lo"]) < float(c["opt_hi"])
					and float(c["opt_hi"]) <= float(c["brk_hi"])):
				errors.append("%s：旋钮 %s 的区间数序不对（要求 brk_lo <= opt_lo < opt_hi <= brk_hi；最优带必须非空，偏移带可零宽）" % [wid, c.get("param", "?")])
		if coef_sum > 1.0:
			errors.append("%s：**Σ副产物系数 = %.3f > 1**（F-A2-1）—— 会让副产物占比超过 100%%" % [wid, coef_sum])

		# --- 分支：同一输入的记录，条件区间【不得重叠】 ---
		var ik := _inputs_key(s.get("inputs", {}))
		if not by_input.has(ik):
			by_input[ik] = []
		by_input[ik].append(s)

	for ik: String in by_input:
		var group: Array = by_input[ik]
		for a in group.size():
			for b in range(a + 1, group.size()):
				for ca: Dictionary in (group[a].get("conditions", []) as Array):
					for cb: Dictionary in (group[b].get("conditions", []) as Array):
						if ca.get("param") != cb.get("param"):
							continue
						# 两条不同记录对同一旋钮的最优带不得重叠（[a,b) 语义）
						var a_lo := float(ca["opt_lo"]); var a_hi := float(ca["opt_hi"])
						var b_lo := float(cb["opt_lo"]); var b_hi := float(cb["opt_hi"])
						if maxf(a_lo, b_lo) < minf(a_hi, b_hi):
							errors.append("输入 %s 的两条记录（%s / %s）在旋钮 %s 上的最优带重叠了 —— 分支必须是不重叠的区间划分" % [
								ik, group[a].get("id", "?"), group[b].get("id", "?"), ca.get("param", "?")])
						# ★ 验收 4 的另一半：**不留缝**。
						# 只在"同一输入、同一旋钮、且两条记录都覆盖这一点附近"时要求相邻；
						# 靠"把两个带的端点对齐"来实现分段。留缝 = 那个温度区间没有任何分支 -> 无人区。
						elif not (is_equal_approx(a_hi, b_lo) or is_equal_approx(b_hi, a_lo)):
							# 两者不重叠但也不相邻 —— 只有在"它们本该连续"时才报。
							# 判据：若一个带的端点落在另一个带的【越界范围之内】，说明作者本意是连续分段。
							var lo1 := minf(a_lo, b_lo); var hi1 := maxf(a_hi, b_hi)
							var span := hi1 - lo1
							if span > 0.0:
								errors.append("输入 %s 的两条记录（%s / %s）在旋钮 %s 上的最优带既不重叠也不相邻（%s 与 %s）—— 会留下无人区（验收 4）" % [
									ik, group[a].get("id", "?"), group[b].get("id", "?"), ca.get("param", "?"),
									"[%s,%s)" % [a_lo, a_hi], "[%s,%s)" % [b_lo, b_hi]])
	return errors


# ---------------------------------------------------------------- 序列化（验收 7）

## **二进制**通道。与 A1 同口径（`var_to_bytes`），供 B16 存档 / 工艺卡之外的持久化使用。
## 注意：`.tres` 本身就是一种序列化（给编辑器用）；本函数是给【运行时存档】用的。
func to_bytes() -> PackedByteArray:
	return var_to_bytes({"v": schema_version, "steps": steps})


static func from_bytes(data: PackedByteArray) -> CompoundData:
	var d = bytes_to_var(data)
	assert(d is Dictionary and int(d.get("v", -1)) == SCHEMA_VERSION,
		"schema 版本不匹配 —— 必须走迁移（A4），不得静默继续")
	assert(typeof(d["v"]) == TYPE_INT, "版本字段回来时不是 int —— 说明有人把它过了一遍 JSON")
	var out = CompoundData.new()
	out.schema_version = int(d["v"])
	out.steps = (d["steps"] as Array).duplicate(true)
	return out


# ---------------------------------------------------------------- 查询（A3 用）

## 按输入查记录。**返回数组** —— A2 的契约明写「**不得假设一个产物只有一条路径**」。
func steps_for(inputs: Dictionary) -> Array:
	var ik := _inputs_key(inputs)
	var out: Array = []
	for s: Dictionary in steps:
		if _inputs_key(s.get("inputs", {})) == ik:
			out.append(s)
	return out


# ---------------------------------------------------------------- 条件求值（A2 的 ②③④）

## 求值。返回：
##   {"band": "optimal"|"offset"|"disaster", "deltas": {param: δ}, "main_share": float,
##    "byproducts": {key: share}, "disaster": String}
##
## δ_k 的定义（A2 的 §Formulas ③）：
##   δ_k = 0                                   若在最优带内
##   δ_k = 离最优带最近边界的距离 ÷ 该侧偏移带的宽度   若在偏移带内 → (0,1]
##   越界 → 走灾难分支，**不走比例式**
func evaluate(step: Dictionary, conditions: Dictionary) -> Dictionary:
	var deltas := {}
	var byproducts := {}
	var disaster := ""
	var in_upper_offset := false

	for c: Dictionary in (step.get("conditions", []) as Array):
		var p: StringName = c.get("param")
		if not conditions.has(p):
			continue
		var v := float(conditions[p])
		var opt_lo := float(c["opt_lo"]); var opt_hi := float(c["opt_hi"])
		var brk_lo := float(c["brk_lo"]); var brk_hi := float(c["brk_hi"])

		var d := 0.0
		# ★ 边界必须与 A2 的 [a, b) 语义一致：面向最优带的那一侧【开】。
		#   若写 v <= brk_lo，则 brk_lo == opt_lo 时 v == opt_lo 会同时属于"最优"与"灾难" ——
		#   而 A2 明写 [a,b) 就是为了"避免同一点属于两段"。
		if v < brk_lo or v >= brk_hi:
			disaster = String(step.get("disaster", "unknown_disaster"))
			deltas[p] = 1.0
			continue
		elif v < opt_lo:
			# 下侧偏移带：宽度 = opt_lo - brk_lo（可能为 0 —— 但那时 v <= brk_lo 已在上面走灾难分支）
			assert(opt_lo - brk_lo > 0.0, "零宽偏移带不该走到这里 —— 区间判定有漏")
			d = (opt_lo - v) / (opt_lo - brk_lo)
		elif v >= opt_hi:
			# 上侧偏移带：宽度 = brk_hi - opt_hi
			d = (v - opt_hi) / (brk_hi - opt_hi)
			in_upper_offset = true
		else:
			d = 0.0

		deltas[p] = d
		if d > 0.0:
			var coef := float(c["coef_hi"]) if in_upper_offset else float(c["coef_lo"])
			var share: float = d * coef
			# 这个旋钮偏移时，分给它的那一份走【它自己的那组配平输出】
			byproducts[p] = {"alt": (c.get("alt", {}) as Dictionary), "share": share}

	if disaster != "":
		return {"band": "disaster", "deltas": deltas, "main_share": 0.0,
				"alts": {}, "disaster": disaster}

	var sum_delta := 0.0
	for k: StringName in deltas:
		sum_delta += float(deltas[k])
	var main_share: float = maxf(0.0, 1.0 - sum_delta)
	var band := "offset" if sum_delta > 0.0 else "optimal"
	return {"band": band, "deltas": deltas, "main_share": main_share,
			"alts": byproducts, "disaster": ""}


## ★ A2 → A1 的桥：把"占比"折成**放大整数**的原子收支。
##
## `batches_scaled` 的单位是「批数 × SCALE」（由 A1 的余数累加器攒出来）。
## 返回的每一项也是「化合物数量 × SCALE」的整数 —— **全程无浮点**，
## 因为一旦这里出现浮点，A1 的"零容差对账"就会在几步之后失效。
##
## ⚠️ 守恒在这里必须成立：
##     主占比 + Σ副占比 ≤ 1   ⇒   **没分出去的那部分仍然是输入**（未反应完）。
##     —— 这正是"副产物是另一组配平输出"这个模型的直接好处：
##     每一组输出都独立配平，所以任意占比的混合也自动配平。
func resolve_scaled(step: Dictionary, conditions: Dictionary, batches_scaled: int) -> Dictionary:
	assert(batches_scaled >= 0)
	var ev := evaluate(step, conditions)
	if ev["band"] == "disaster":
		return {"band": "disaster", "disaster": ev["disaster"],
				"inputs": {}, "outputs": {}, "unreacted_scaled": batches_scaled}

	# 主份（按最优输出）
	var parts: Array = [{"out": step.get("outputs", {}), "share_scaled": int(round(ev["main_share"] * batches_scaled))}]
	var used := parts[0]["share_scaled"] as int
	# 各副份（各自带一组配平输出）
	var alts: Dictionary = ev["alts"]
	for p: StringName in alts:
		var share_scaled := int(round(float(alts[p]["share"]) * batches_scaled))
		if share_scaled <= 0:
			continue
		parts.append({"out": alts[p]["alt"], "share_scaled": share_scaled})
		used += share_scaled
	# 兜底：四舍五入可能让 used 略超 batches_scaled（极端条件下）—— 不允许超过
	if used > batches_scaled:
		parts[0]["share_scaled"] = (parts[0]["share_scaled"] as int) - (used - batches_scaled)
		used = batches_scaled

	var inputs_scaled := {}
	for k: String in (step.get("inputs", {}) as Dictionary):
		inputs_scaled[k] = int(step["inputs"][k]) * used
	var outputs_scaled := {}
	for part: Dictionary in parts:
		for k: String in (part["out"] as Dictionary):
			outputs_scaled[k] = int(outputs_scaled.get(k, 0)) + int(part["out"][k]) * int(part["share_scaled"])

	return {"band": ev["band"], "disaster": "",
			"inputs": inputs_scaled, "outputs": outputs_scaled,
			"unreacted_scaled": batches_scaled - used}


# ---------------------------------------------------------------- 内部

static func _inputs_key(inputs: Dictionary) -> String:
	var keys := _sorted_strings(inputs.keys())      # 同上：必须按字符串排，不按 StringName 内部次序
	var parts := PackedStringArray()
	for k: String in keys:
		parts.append("%s*%d" % [k, int(inputs[k])])
	return "+".join(parts)


## 把"组成式 key + 数量"折算成原子总数。
## ⚠️ 它依赖 key 的规范写法（`元素+个数` 用 `|` 连接）—— 由 composition_key 保证。
static func atom_totals_by_key(key: String, times: int) -> Dictionary:
	var out := {}
	if key == "" or key == "∅":
		return out
	for seg: String in key.split("|"):
		var m := _parse_segment(seg)
		out[m[0]] = int(out.get(m[0], 0)) + int(m[1]) * times
	return out


## 把 `H2` 这样的片段解析成 [元素, 个数]。元素符号可以是一或两个字母。
static func _parse_segment(seg: String) -> Array:
	var i := 0
	while i < seg.length() and not (seg[i] >= "0" and seg[i] <= "9"):
		i += 1
	var sym := StringName(seg.substr(0, i))
	var n := int(seg.substr(i)) if i < seg.length() else 1
	assert(sym != StringName(""), "组成式片段解析失败：%s" % seg)
	return [sym, n]


## 把一批 key（可能是 StringName）按【字符串形式】升序排好。
## 存在的唯一理由是：`Array[StringName].sort()` 不是字母序（实测），
## 而我们的键必须是字典序、可跨版本复现。
static func _sorted_strings(keys: Array) -> Array:
	var ss := PackedStringArray()
	for k in keys:
		ss.append(String(k))
	ss.sort()
	var out: Array = []
	for s: String in ss:
		# 还原成 StringName（本项目的元素符号都是 StringName）
		out.append(StringName(s))
	return out


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k: StringName in b:
		out[k] = int(out.get(k, 0)) + int(b[k])
	return out
