extends GdUnitTestSuite
## A1 的池与累加器 —— **真实实现**的对账测试
##
## 它逐条对应 A1 的验收标准（那份 GDD 的 §Acceptance Criteria）：
##   验收 1 · 原子守恒     —— **全程整数比较、无容差**，且**断言累加器的小数部分未被计入**
##   验收 2 · 溢出不丢料   —— 饱和时**接受量 < 请求量**（而不是回绕成负数）
##   验收 3 · 累加器精确   —— 分数速率能攒成整数原子，且**不漂移**
##
## ⚠️ 为什么容差是 0：P2 是「严谨是美感」。T0 时期因为把累加器的小数部分算进了总量，
## 误报过 32 次"假不守恒"——所以"对账"这件事必须是**整数相等**。

const ElementPoolScript := preload("res://scripts/element_pool.gd")
const TABLE := preload("res://data/element_table.tres")

const WATER := {&"H": 2, &"O": 1}
const HYDROGEN := {&"H": 2}
const OXYGEN := {&"O": 2}


# ============================================================ 验收 1：原子守恒（无容差）

func test_add_then_take_returns_to_zero_with_zero_tolerance() -> void:
	var pool = ElementPoolScript.new()
	assert_int(pool.add(&"H", 1000)).is_equal(1000)
	assert_int(pool.take(&"H", 400)).is_equal(400)
	assert_int(pool.take(&"H", 600)).is_equal(600)
	# **无容差**：必须是 0，不是"约等于 0"
	assert_int(pool.count(&"H")).is_equal(0)
	assert_bool(pool.conservation_ok()).is_true()


func test_formula_round_trip_conserves_every_element() -> void:
	var pool = ElementPoolScript.new()
	pool.add_formula(WATER, 3)                       # H×6, O×3
	var before_h := pool.count(&"H")
	var before_o := pool.count(&"O")
	var before_total := pool.total()

	# 2 H₂O → 2 H₂ + O₂（做 1 次）
	var got: Array = pool.take_formula({&"H": 4, &"O": 2})
	assert_bool(got[0]).is_true()
	pool.add_formula(HYDROGEN, 2)
	pool.add_formula(OXYGEN, 1)

	# 原子层面这个反应是恒等的 —— 所以**每个元素的量都不该变**
	assert_int(pool.count(&"H")).is_equal(before_h)
	assert_int(pool.count(&"O")).is_equal(before_o)
	assert_int(pool.total()).is_equal(before_total)
	assert_bool(pool.conservation_ok()).is_true()


## ★ 这条是专门为 T0 那 32 次误报写的：**累加器的小数部分【不得】被算进原子总量**。
func test_residual_is_not_counted_in_atom_total() -> void:
	var pool = ElementPoolScript.new()
	# 攒一个远不够一个原子的需求（0.5 个原子）
	var half := ElementPoolScript.SCALE / 2
	var got := pool.accumulate(&"m1", &"H", half)
	assert_int(got).is_equal(0)                      # 还攒不够，搬 0 个
	assert_int(pool.count(&"H")).is_equal(0)          # **总量里没有它**
	assert_int(pool.total()).is_equal(0)
	# 再攒 0.5 —— 这次够一个
	assert_int(pool.accumulate(&"m1", &"H", half)).is_equal(1)
	assert_int(pool.residual(&"m1", &"H")).is_equal(0)
	# 而且上界式仍然成立
	assert_int(pool.residual_atom_upper_bound()).is_equal(1)


# ============================================================ 验收 2：溢出不丢料

## ★ **绝不允许**靠 `current + amount > MAX` 判断 —— 那会先静默回绕。
func test_saturation_accepts_less_and_never_wraps_to_negative() -> void:
	var pool = ElementPoolScript.new()
	var M: int = ElementPoolScript.MAX_ATOMS
	pool.add(&"H", M - 5)
	var accepted := pool.add(&"H", 100)
	# 只接受 5 个，剩下 95 个被挡住（上游据此阻塞）
	assert_int(accepted).is_equal(5)
	assert_int(pool.count(&"H")).is_equal(M)
	# **必须为正** —— 回绕的话这里会是负数
	assert_bool(pool.count(&"H") > 0).is_true()
	assert_bool(pool.conservation_ok()).is_true()


func test_saturation_emits_a_signal_so_upstream_can_block() -> void:
	var pool = ElementPoolScript.new()
	pool.add(&"H", ElementPoolScript.MAX_ATOMS - 1)
	# 用 Godot 的 signal 记录：饱和必须**可被上游听见**
	var seen := []
	pool.pool_saturated.connect(func(e: StringName, req: int, acc: int) -> void: seen.append([e, req, acc]))
	pool.add(&"H", 50)
	assert_int(seen.size()).is_equal(1)
	assert_str(String(seen[0][0])).is_equal("H")
	assert_int(int(seen[0][2])).is_equal(1)          # 只接受了 1


func test_formula_add_is_all_or_nothing() -> void:
	var pool = ElementPoolScript.new()
	pool.add(&"H", ElementPoolScript.MAX_ATOMS - 1)  # H 只剩 1 个位
	# 水需要 H×2 —— 放不下，所以【整批都不放】（不许只放进一半）
	assert_bool(pool.add_formula(WATER, 1)).is_false()
	assert_int(pool.count(&"O")).is_equal(0)
	assert_bool(pool.conservation_ok()).is_true()


# ============================================================ 验收 3：累加器精确

## ★ 分数速率攒成整数原子：**不多不少**。
func test_fractional_rate_accumulates_to_exact_integer_atoms() -> void:
	var pool = ElementPoolScript.new()
	# 每 tick 0.37 个原子（= 37/100），跑 100 tick ⇒ 恰好 37 个
	var per_tick: int = 37 * ElementPoolScript.SCALE / 100
	var total := 0
	for i in 100:
		total += pool.accumulate(&"m", &"H", per_tick)
	# ⚠️ 期望值必须按【整数算术】算，不能按"0.37"这个十进制意图算 ——
	#    37*SCALE/100 截断成 387973，它代表 0.369999886；100 tick 的 floor 是 36，不是 37。
	#    这不是漂移（残留 1048564 < SCALE，一个原子都没丢），而是【表示误差】：
	#    它在编译前就固定了。见下面那条把它钉住的测试。
	assert_int(total).is_equal(100 * per_tick / ElementPoolScript.SCALE)
	assert_int(pool.count(&"H")).is_equal(0)          # 池还没被喂 —— 累加器只负责"攒够"
	# 而且遗留的残留小于 1 个原子
	assert_bool(pool.residual(&"m", &"H") < ElementPoolScript.SCALE).is_true()


## ★ 这条测试的存在意义：**把"十进制意图"与"放大整数表示"之间的差钉住**。
##
## 本项目的速率一律以 `SCALE` 为单位的整数给定。若有人写成 `37 * SCALE / 100` 并
## 期望它等于 0.37，他会得到 0.369999886 —— 而 100 tick 之后差整整 1 个原子。
## **那不是 bug，那是表示误差**（A1 的"无漂移"指的是【给定整数速率下不漂移】）。
func test_decimal_rate_intent_is_not_exactly_representable() -> void:
	var per_tick: int = 37 * ElementPoolScript.SCALE / 100
	assert_int(per_tick).is_equal(387973)                 # 截断，不是 387973.12
	var relative_error: float = absf(0.37 - float(per_tick) / float(ElementPoolScript.SCALE)) / 0.37
	# 误差极小（~1.2e-7），但它【不是零】—— 而它会在足够多 tick 后攒成整整一个原子
	assert_float(relative_error).is_greater(0.0)
	assert_float(relative_error).is_less(0.000001)
	# 而那一个原子的差，恰好就是"100 tick 期望 37 实际 36"这件事
	assert_int(100 * per_tick / ElementPoolScript.SCALE).is_equal(36)


## 舍入方向必须是 floor：**只会少搬、绝不超搬**（否则池会凭空多出原子）。
## （注：gdUnit4 6.2.0 的 `is_equal_approx` 需要两个参数）
func test_accumulator_never_over_delivers() -> void:
	var pool = ElementPoolScript.new()
	var delivered := 0
	for i in 1000:
		delivered += pool.accumulate(&"m", &"H", 3)   # 每 tick 3/SCALE 个原子
	var ideal := 3000.0 / float(ElementPoolScript.SCALE)
	# 实发 ≤ 理想（永不超搬），且差值 < 1
	assert_bool(float(delivered) <= ideal).is_true()
	assert_float(ideal - float(delivered)).is_less(1.0)


## 每 `(机器, 元素)` 一个残留 —— 所以上界是【配对数】，不是元素数。
func test_residual_upper_bound_counts_machine_element_pairs() -> void:
	var pool = ElementPoolScript.new()
	pool.accumulate(&"m1", &"H", 1)
	pool.accumulate(&"m1", &"O", 1)
	pool.accumulate(&"m2", &"H", 1)
	assert_int(pool.residual_atom_upper_bound()).is_equal(3)   # 3 对，不是 2 个元素


# ============================================================ 元素表（概念文档的硬前置）

func test_element_table_has_atomic_mass_for_every_element() -> void:
	for sym: StringName in TABLE.elements:
		assert_float(TABLE.atomic_mass(sym)).is_greater(0.0)


## 概念文档那条 T0 实测：海水质量分数换算后 H:O = 2.0006
func test_seawater_ratio_via_element_table_is_two() -> void:
	var units := TABLE.mass_pct_to_atom_units({
		&"O": 85.84, &"H": 10.82, &"Cl": 1.94, &"Na": 1.08,
		&"Mg": 0.13, &"S": 0.09, &"Ca": 0.04, &"K": 0.04,
	})
	var ratio: float = float(units[&"H"]) / float(units[&"O"])
	assert_float(ratio).is_between(1.98, 2.02)

# ============================================================ 稀疏语义（A1 的 ② + §Edge Cases）

## ★ A1 明写：稀疏池里「**从未出现**」与「**存在且为 0**」必须**语义等价**
##   ——「否则相等判定会出鬼」。
func test_never_seen_element_is_equivalent_to_zero() -> void:
	var pool = ElementPoolScript.new()
	# 从未放过的元素：读它必须是 0（而不是报错、也不是 -1）
	assert_int(pool.count(&"Fe")).is_equal(0)
	# 放一个再取干净 —— 现在它是"存在且为 0"
	pool.add(&"Fe", 5)
	pool.take(&"Fe", 5)
	assert_int(pool.count(&"Fe")).is_equal(0)
	# 两者对一切可观测操作必须等价：总量、对账、序列化后的形状
	assert_int(pool.total()).is_equal(0)
	assert_bool(pool.conservation_ok()).is_true()
	var restored = ElementPoolScript.from_bytes(pool.to_bytes())
	assert_int(restored.count(&"Fe")).is_equal(0)      # 稀疏：0 不会被存下来，读回来仍是 0
	assert_int(restored.total()).is_equal(0)


## 稀疏标记：**0 的条目不该出现在存档里**（否则"只存出现过的元素"就名存实亡）
func test_zero_entries_are_not_serialized() -> void:
	var pool = ElementPoolScript.new()
	pool.add(&"H", 10)
	pool.add(&"O", 3)
	pool.take(&"O", 3)                                  # O 归零 -> 不该被存
	var d = bytes_to_var(pool.to_bytes())
	var atoms: Dictionary = d["atoms"]
	assert_bool(atoms.has(&"H")).is_true()
	assert_bool(atoms.has(&"O")).is_false()


# ============================================================ 序列化（A1 的 ⑥ + 验收 3）

## ★ 验收 3：**二进制通道必须通过**（且必须断言 `typeof()`，不能只比 `==`）
func test_binary_round_trip_is_bit_exact_for_huge_int64() -> void:
	var pool = ElementPoolScript.new()
	# 2^53 + 1 —— 超出 float 能精确表示的范围（JSON 在这就坏）
	pool.add(&"H", 9007199254740993)
	pool.add(&"O", 123456789012345)
	pool.accumulate(&"m", &"H", 12345)
	var restored = ElementPoolScript.from_bytes(pool.to_bytes())
	# 值必须逐位相同
	assert_int(restored.count(&"H")).is_equal(9007199254740993)
	assert_int(restored.count(&"O")).is_equal(123456789012345)
	# **类型也必须仍是 int** —— 这一条是只比 == 会漏掉的那条
	assert_int(typeof(restored.count(&"H"))).is_equal(TYPE_INT)
	# 累加器与净导入账也必须一起回来（否则恢复后对账会立刻失败）
	assert_int(restored.residual(&"m", &"H")).is_equal(pool.residual(&"m", &"H"))
	assert_bool(restored.conservation_ok()).is_true()


## ★★ 验收 3 的另一半：**JSON 通道【必须失败】**（它是反例，不是备选方案）
##
## 这条测试的价值在于**它把陷阱本身钉住**：JSON 的坏是【静默的】——
## 值变成了 float，而 `==` 仍然说"相等"。
## 所以任何"只比 =="的断言都会放过它；**只有 `typeof()` 能抓住**。
func test_json_channel_must_fail_because_it_silently_becomes_float() -> void:
	var big := 9007199254740993                      # 2^53 + 1
	var via_json = JSON.parse_string(JSON.stringify({"v": big}))["v"]

	# ① 它已经坏了：类型从 INT 变成了 FLOAT
	assert_int(typeof(via_json)).is_equal(TYPE_FLOAT)
	# ② 而 == 会说"相等" —— 这正是"静默"的含义
	assert_bool(via_json == big).is_true()
	# ③ 真正能抓住它的是整数化后的不等
	assert_int(int(via_json)).is_equal(9007199254740992)   # 少了 1
	# ④ 所以 A1 的 ⑥ 是必须的：池【绝不能】走 JSON

# ============================================================ A1 §Edge Cases 的补测

## ★ A1 的承诺：「**任何元素计数恒 ≥ 0** —— 任何产生负数的路径都是 bug，必须被对账拦住」
##   而"结构上不可能"这件事**必须被测试**，否则它只是一个说法。
func test_element_count_can_never_go_negative() -> void:
	var pool = ElementPoolScript.new()
	# 从未有过 -> 是 0，不是负数
	assert_int(pool.count(&"H")).is_equal(0)
	assert_bool(pool.count(&"H") >= 0).is_true()
	# 取超过持有量 -> 只给到 0，**绝不越过**
	pool.add(&"H", 5)
	assert_int(pool.take(&"H", 999)).is_equal(5)
	assert_int(pool.count(&"H")).is_equal(0)
	assert_bool(pool.count(&"H") >= 0).is_true()
	# 对账也必须仍然通过（"负物质"是对账要拦的东西）
	assert_bool(pool.conservation_ok()).is_true()


## ★ A1 的 §Edge Cases：「**需求小于 1/SCALE** → 累加器永远攒不够一个整原子 →
##   **接受它**（那本来就是'还没反应完'）」—— 即它既不该报错，也不该丢。
func test_demand_smaller_than_one_scale_is_accepted_and_kept() -> void:
	var pool = ElementPoolScript.new()
	var tiny := 1                       # 1/SCALE 个原子，最小的非零需求
	var delivered := 0
	for i in 100:
		delivered += pool.accumulate(&"m", &"H", tiny)
	assert_int(delivered).is_equal(0)                  # 攒不够就是 0（不是错误）
	assert_int(pool.residual(&"m", &"H")).is_equal(100)  # 而它【没丢】—— 100 份都还在残留里
	assert_int(pool.count(&"H")).is_equal(0)            # 也不该进池


## ★ A1 的 §Edge Cases B：原子量缺失/为 0 -> **拒绝整表并指出坏在哪一行**。
func test_element_table_rejects_missing_or_zero_atomic_mass_and_names_the_row() -> void:
	var ET := preload("res://scripts/element_table.gd")
	var good = preload("res://data/element_table.tres")
	assert_array(good.validate()).is_empty()

	# 造一张坏表：把 O 的原子量设成 0
	var bad = ET.new()
	bad.elements = good.elements.duplicate(true)
	bad.elements[&"O"]["atomic_mass"] = 0.0
	var errs := bad.validate()
	assert_int(errs.size()).is_greater(0)
	assert_bool(" ".join(errs).contains("O")).is_true()      # 必须指出是哪个元素

	# 缺字段也算坏
	var bad2 = ET.new()
	bad2.elements = {&"Xx": {"group": 0, "name": "某元素"}}   # 没有 atomic_mass
	assert_int(bad2.validate().size()).is_greater(0)
