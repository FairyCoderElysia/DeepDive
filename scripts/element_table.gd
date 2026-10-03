class_name ElementTable
extends Resource
## A1 的 ③：**元素表 = 内核数据的唯一来源**，且**必须带 `atomic_mass`**。
##
## 为什么 `atomic_mass` 是硬前置（概念文档 T0 实测）：
##   海水质量分数换算后 H:O 原子比 = 2.0006（≈水的 2:1 ✅）
##   若把质量分数直接当原子数用，H:O = 0.126 ——**海水连水都造不出来**。
##   ⇒ 所以「质量 → 原子」这一步必须存在，而它必须有原子量。
##
## 分类组（A1 的契约给 B13）：元素不直接上色，必须走分类组 ——
##   否则 art-bible §1「青色只给氧气」会破。

## 元素的分类组（B13 按这四组区分，而不是按元素符号）
enum Group {
	WATER,      ## 水 / 氢氧：海水的主体
	SALT,       ## 食盐：Na / Cl（氯污染的来源）
	HARDNESS,   ## 硬度：Mg / Ca（结垢的来源）
	SULFATE,    ## 硫酸盐：S（CaSO₄ 的共犯）
}

## 元素符号 -> 数据
##   atomic_mass（g/mol）· group（分类组）· name（给百科 B7 用）
@export var elements: Dictionary = {}


## 原子量。**不存在则报错**，不得静默返回 0（那会让质量→原子悄悄算错）。
func atomic_mass(symbol: StringName) -> float:
	_require(symbol)
	var m: float = elements[symbol].get("atomic_mass", -1.0)
	assert(m > 0.0, "元素 %s 缺 atomic_mass —— 那会让『质量→原子』静默算错" % symbol)
	return m


func group_of(symbol: StringName) -> int:
	_require(symbol)
	return int(elements[symbol].get("group", -1))


## 质量分数（%）→ 原子数（相对值，不取整 —— 取整是池的事）。
## 这是 T0 那条实测事实的可执行形式。
func mass_pct_to_atom_units(mass_pct: Dictionary) -> Dictionary:
	var out := {}
	for sym: StringName in mass_pct:
		out[sym] = float(mass_pct[sym]) / atomic_mass(sym)
	return out


func _require(symbol: StringName) -> void:
	assert(elements.has(symbol), "元素表里没有 %s —— 内核不允许猜元素" % symbol)
