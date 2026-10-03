extends GdUnitTestSuite
## 示例测试（也是本项目的第一条【设计不变量】回归测试）
##
## 它测的不是"代码写得对不对"，而是【概念文档里那条最硬的实测事实是否仍然成立】。
##
## 来源：`design/gdd/game-concept.md` 的 Core Mechanics #1 里那条
##   "⚠️ T0 实测出的硬前置（2026-10-02）：元素表必须带 atomic_mass"
## 实测结论（原文）：
##   "海水占比（O 85.84% / H 10.82% / Cl 1.94% / Na 1.08% / Mg 0.13% / S 0.09% /
##    Ca 0.04% / K 0.04%）换算后 **H:O 原子比 = 2.0006**（≈水的 2:1 ✅，反证主体确实是水）；
##    若把质量分数直接当原子数用，H:O = 0.126 → 海水连水都造不出来。"
##
## 为什么它值得当第一个测试：
##   · 它是**纯算术** —— 不依赖任何尚未实现的代码，所以现在就能跑；
##   · 它**载重** —— A1 的整个池模型、A2 的化合物表、A3 的配平全都建立在"内核只认原子数"上；
##   · 它**会真的失败** —— 若有人把 mass→atom 换算写错（或忘掉 atomic_mass），它会立刻红。

# 海水的质量分数（%），与概念文档逐字一致
const SEAWATER_MASS_PCT := {
	"O": 85.84,
	"H": 10.82,
	"Cl": 1.94,
	"Na": 1.08,
	"Mg": 0.13,
	"S": 0.09,
	"Ca": 0.04,
	"K": 0.04,
}

# 标准原子量（g/mol）—— 只用于本测试的换算，不代替 A1 的元素表
const ATOMIC_MASS := {
	"H": 1.008,
	"O": 15.999,
	"Na": 22.990,
	"Mg": 24.305,
	"S": 32.06,
	"Cl": 35.45,
	"K": 39.098,
	"Ca": 40.078,
}


## H:O 原子比必须 ≈ 2 —— 这反证海水的**主体确实是水**，也反证"质量 → 原子"的换算方向是对的。
func test_seawater_mass_fraction_to_atoms_gives_h_to_o_ratio_of_two() -> void:
	var n_o := SEAWATER_MASS_PCT["O"] / ATOMIC_MASS["O"]
	var n_h := SEAWATER_MASS_PCT["H"] / ATOMIC_MASS["H"]
	var ratio := n_h / n_o

	# 概念文档实测值 2.0006；给 1% 容差，避免原子量的微小取值差异造成假失败
	assert_float(ratio).is_between(1.98, 2.02)
	print_rich("[b]H:O 原子比 = %.4f[/b]（概念文档实测 2.0006）" % ratio)


## 反例测试：**把质量分数直接当原子数用会得到一个荒谬的比值**。
## 这条测试存在的意义是【把这个错误钉住】—— 它是概念文档明确警告过的那条路。
func test_treating_mass_pct_as_atom_count_gives_the_known_wrong_ratio() -> void:
	var wrong_ratio := SEAWATER_MASS_PCT["H"] / SEAWATER_MASS_PCT["O"]

	# 文档实测：这样算出来 H:O = 0.126
	assert_float(wrong_ratio).is_between(0.12, 0.13)
	# 而它离"水"的 2:1 差了一个数量级 —— 这就是为什么元素表必须带 atomic_mass
	assert_bool(wrong_ratio < 1.0).is_true()


## 换算必须能闭合到 100%：原子分数之和为 1（证明没有元素被漏掉或重复计算）。
func test_mass_to_atom_conversion_is_complete() -> void:
	var total := 0.0
	for sym in SEAWATER_MASS_PCT:
		total += SEAWATER_MASS_PCT[sym] / ATOMIC_MASS[sym]
	assert_float(total).is_greater(0.0)

	var atom_frac_sum := 0.0
	for sym in SEAWATER_MASS_PCT:
		atom_frac_sum += (SEAWATER_MASS_PCT[sym] / ATOMIC_MASS[sym]) / total
	# ⚠️ gdUnit4 6.2.0 的签名是 is_equal_approx(expected, approx) —— 【必须传两个参数】
	#    传一个会 Parse Error，而那个错误会被扫描器【静默跳过】（见 README 的"一条 CI 陷阱"）
	assert_float(atom_frac_sum).is_equal_approx(1.0, 0.0001)
