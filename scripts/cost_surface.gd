class_name CostSurface
extends RefCounted
## A6 · 参数与代价面 —— **只表达，不计算**（Core Rule ①）
##
## 【它不做什么】不定义旋钮（权威在 A1 / 登记册）· 不改变模拟（Core Rule ⑤）·
##   不把事实算出来（那归 A2/A3）。它只把**已经能算的事实**组织成"你为此付出了什么"。
##
## 【它的代价是一个权衡三角，不是一个标量】（§Formulas ①）
##   代价(p) = { 能耗, 耗时, 纯度 } —— **能耗与耗时是"付出"，纯度是"所得"**。
##   ⚠️ **不得把它们加权成一个"总代价分数"** —— 那会把权衡压平，玩家就看不到取舍了。
##
## 【三项的生产者现状 —— 如实记，不假装】
##   · 纯度 ✅ 有主：A2 的 `evaluate()` 给 `main_share`（= `max(0, 1 − Σδₖ)`，A2 §Formulas ④）
##   · 能耗 ✅ 有主，且**浅层恒为 0**：浅层的能量由**光**免费供给（`oxygen-economy.md` 规则 ⑨）；
##     深层的燃料那一份**推迟到深度轴变成真的时**才落（见登记册 `ENERGY_IS_AN_EDGE`）
##   · 耗时 ⏸ **没有生产者** —— 记为 A6 的 Open Question，**本文件不编一个口径塞进去**
##     （接口留好：`COST_FIELDS` 里有它的位置，值此刻是 `null`）
##
## 【它为什么必须能"采样"】（Core Rule ④ + F-A6-1）
##   代价面要给玩家的**不是当前值，而是"一片区域（含当前点）"** ——
##   玩家必须能看见"往哪边调更省"。所以本文件的核心不是 `cost_at`，而是 `slice`。

## 代价的三项。**顺序即语义**：前两个是付出、最后一个是所得。
const COST_FIELDS := ["energy", "purity", "time"]

## 5 个旋钮的规格来自**生成物**（真相源 = `design/schema/contract.yaml`；
## 权威 = 登记册的 `param_*`；两者的**逐字段一致**由 `--check` 证明，不是我抄了一遍）。
const KNOBS := SchemaContract.KNOBS

## 默认采样点数。⚠️ `[待定]`（A6 §Tuning Knobs）—— 先用一个能画曲线的值，等你有画面感再定。
const DEFAULT_RESOLUTION := 21


## 某个参数点上的代价。返回**三角**，不返回标量。
##
## ⚠️ `band` / `disaster` **照抄 A2 的判定**（Core Rule ①：A6 不重新定义条件语义）。
static func cost_at(step: Dictionary, conditions: Dictionary, table: CompoundData) -> Dictionary:
	var ev: Dictionary = table.evaluate(step, conditions)
	return {
		"energy": 0.0,                      # 浅层：光免费 ⇒ 0（深层要燃料时才会非 0）
		"purity": float(ev.get("main_share", 0.0)),
		"time": null,                       # ⏸ 口径未定 —— 刻意不是 0："未知"≠"零代价"
		"band": String(ev.get("band", "")),
		"disaster": String(ev.get("disaster", "")),
		"conditions": conditions.duplicate(true),
	}


## **单旋钮切片**（默认视角，F-A6-1）：固定其余 4 个，只把 `knob` 从 lo 扫到 hi。
##
## 为什么默认是"单旋钮"而不是全维：**玩家的实际操作就是逐个调旋钮** ——
## 界面要对齐的是"这一个旋钮往左/往右，代价怎么变"，而不是"整个 5 维空间长什么样"。
##
## 连续型旋钮 -> `resolution` 个**等距**采样点（**含两端** —— 边界代价必须在曲线上）；
## 枚举型旋钮 -> **逐个选项各一点**（离散，没有"之间"）。
## 返回：点数组，每点 = `cost_at` 的结果 + `knob_value`。
static func slice(step: Dictionary, conditions: Dictionary, knob: StringName,
		table: CompoundData, resolution: int = DEFAULT_RESOLUTION) -> Array:
	var key := String(knob)
	assert(KNOBS.has(key), "切片要求一个【已声明】的旋钮：%s —— A6 的验收 4：不得另立定义" % key)
	var spec: Dictionary = KNOBS[key]
	assert(String(spec.get("unit", "")) != "", "旋钮 %s 缺单位 —— 表达不出范围就没有意义" % key)

	var values: Array = []
	if String(spec.get("kind", "")) == "enum":
		for opt in (spec.get("options") as Array):
			values.append(opt)
	else:
		var lo := float(spec["min"])
		var hi := float(spec["max"])
		var n := maxi(resolution, 2)                     # 至少两点，否则画不出"一片区域"
		for i in n:
			values.append(lo + (hi - lo) * (float(i) / float(n - 1)))

	var points: Array = []
	for v in values:
		var c := conditions.duplicate(true)
		c[knob] = v
		var pt := cost_at(step, c, table)
		pt["knob_value"] = v
		points.append(pt)
	return points


## 对**任意一个**旋钮都能切片（验收 5：**若只能给全维数据即为失败**）。
## 返回 `{旋钮名: 切片}`，其余 4 个固定为 `conditions` 里的值。
static func all_slices(step: Dictionary, conditions: Dictionary,
		table: CompoundData, resolution: int = DEFAULT_RESOLUTION) -> Dictionary:
	var out := {}
	for k in KNOBS:
		out[k] = slice(step, conditions, StringName(k), table, resolution)
	return out
