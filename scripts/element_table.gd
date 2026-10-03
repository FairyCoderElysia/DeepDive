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

## ★ A4：**schema 版本号**（A4 §Core Rules ② 的轻量检查要用它）。
##
## **默认值写 `0` 而不是 `1`，这是故意的** ——
## A4 的 §Edge Cases 明写：「schema 版本号**缺失** → 拒绝载入（**不得当成 `v1` 猜**）」。
## 若默认写成 `1`，那么"忘了在 .tres 里写版本号"会被**静默补成 v1** —— 那正是这条边界要防的事。
## ⇒ `0` 是"**无版本**"的哨兵，不是"版本 0"。
@export var schema_version: int = 0

## ★ A4：**schema 内容指纹**（Core Rule ⑦）。
##
## 光有版本号抓不住最危险的那一类：**改了 schema 却忘了升版本号** ——
## 那时版本检查会通过、迁移不会跑，数据被**静默地**按新 schema 解读。
## 指纹是人可能忘、而数据自己不会忘的那一份证据。
##
## 默认空串同样是"缺失"的哨兵（**不得**回落到"那就当它是最新的吧"）。
@export var schema_fingerprint: String = ""


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


## 整表校验（A1 的 §Edge Cases B）：**原子量为 0 或缺失 -> 拒绝整表导入，并指出坏在哪一行。**
##
## 理由（A1 原文）：除以 0 会污染**整张**元素表，而那张表是 **8 个下游**的基座。
## 返回错误列表（空 = 通过）。
func validate() -> Array:
	var errors: Array = []
	if elements.is_empty():
		errors.append("元素表是空的")
	# ★ A4：**"缺版本号"与"版本号不对"是两件事** —— 这里只负责前者（后者要拿 A4 的契约头比）。
	#   而这一条必须在这里、必须硬：A4 的 §Edge Cases 明写"缺失 -> 拒绝载入，不得当 v1 猜"。
	if schema_version <= 0:
		errors.append("元素表没有声明 schema 版本号（读到 %d）—— 拒绝载入：猜一版会静默损坏数据（A4 §Edge Cases）" % schema_version)
	if schema_fingerprint == "":
		errors.append("元素表没有声明 schema 内容指纹 —— 只比版本号抓不住『改了 schema 却忘了升版本号』（A4 Core Rule ⑦）")
	for sym: StringName in elements:
		var e: Dictionary = elements[sym]
		var m := float(e.get("atomic_mass", -1.0))
		if m <= 0.0:
			errors.append("元素「%s」的 atomic_mass = %s（必须是 > 0 的数）—— 缺它会让『质量→原子』除以 0 或静默算错" % [sym, e.get("atomic_mass", "<缺失>")])
		var g := int(e.get("group", -1))
		if g < Group.WATER or g > Group.SULFATE:
			# 注：矿脉元素用 4（不属海水四组），所以这里放宽到 0..4
			if g < 0 or g > 4:
				errors.append("元素「%s」的 group = %d（必须在 0..4）" % [sym, g])
		if String(e.get("name", "")) == "":
			errors.append("元素「%s」缺 name（百科 B7 要用它）" % sym)
	return errors


func _require(symbol: StringName) -> void:
	assert(elements.has(symbol), "元素表里没有 %s —— 内核不允许猜元素" % symbol)
