extends GdUnitTestSuite
## B6 · 储罐与容量 —— 逐条对应 B6 的 Acceptance Criteria
##
## ★ 本文件的重点是**验收 3（产物身份）**与**验收 2（守恒不误报）** ——
##   GDD 自己写着：「**第 3 条是本文档存在的理由的可测形式**：
##   如果实现者把罐子做成元素池，第 3 条会失败 —— **而那正是最容易犯、也最隐蔽的错**
##   （它在单次运行里看不出）」。

const TK := preload("res://scripts/tank.gd")
const CD := preload("res://scripts/compound_data.gd")
const EP := preload("res://scripts/element_pool.gd")

static func _water() -> String: return CD.composition_key({&"H": 2, &"O": 1})
static func _h2() -> String: return CD.composition_key({&"H": 2})
static func _o2() -> String: return CD.composition_key({&"O": 2})


# ============================================================ 验收 3：产物身份（本文档存在的理由）

## ★ 「把一种化合物存进罐子再取出 → **取回的仍是该化合物（不是它的元素）**」
func test_a_stored_compound_comes_back_as_that_compound_not_as_elements() -> void:
	var t := TK.new(10000)
	var water := _water()
	var left := t.put({water: 5})
	assert_int(left.size()).is_equal(0)                  # 装得下，没有余量
	assert_int(int(t.contents()[water])).is_equal(5)     # 存的是【水】，不是 H 和 O
	var got := t.take_atoms(3)                           # 3 个原子 = 1 个水（水是 3 原子）
	assert_int(int(got.get(water, 0))).is_equal(1)       # 取回来的**仍然是水**
	# 而**罐里不该出现任何元素键** —— 那会是"做成了元素池"的迹象
	for k: String in t.contents():
		assert_bool(k.contains("|")).is_true()           # 化合物 key 形如 "H2|O1"


## ★ 反例可辨：**若罐子做成元素池**，把水存进去再取出来就只剩氢氧原子、**没有水了**。
##   这条测试就是"产物身份"这件事的可测形式。
func test_the_tank_is_not_an_element_pool() -> void:
	var t := TK.new(10000)
	var water := _water()
	t.put({water: 2})
	# 罐里的键必须是【化合物】——不得是 &"H" / &"O" 这种元素符号
	for k: String in t.contents():
		assert_bool(k == water).is_true()
	# 而且占用要按【原子总数】算：2 个水 = 6 个原子（不是 2）
	assert_int(t.occupied()).is_equal(6)


# ============================================================ 验收 2：守恒不误报（F-B6-1）

## ★ 「存入 / 取出罐子时，**A1 的守恒判定必须仍然通过**（不得误报）」。
##
## 为什么这条要紧：A1 的对账式里**没有"罐内存量"这一项** ⇒ 若罐子是"池之外的地方"，
## 存进去就会**误报不守恒**，而 A1 的规则 ⑤ 是「对账失败 → **拒绝该动作 + 锁**」
## ⇒ **整个工厂会在玩家第一次存料时锁死**。
##
## 判据（可直接测）：**存入 / 取出的整个过程里，A1 的元素池一个原子都不动** ——
## 因为"罐子 = 池的有界子集"，移动只发生在**化合物账**之间。
func test_storing_and_retrieving_leave_the_element_pool_untouched() -> void:
	var pool = EP.new()
	var water := _water()
	pool.add_formula({&"H": 2, &"O": 1}, 4)              # 池里有 4 个水的原子
	# ⚠️ **净导入由加料器自己记**（`net_imported()` 是取值器，不是设值器）——
	#    我第一版把它当设值器调了，两行都参数错、而且多余。
	assert_bool(pool.conservation_ok()).is_true()
	var h_before := pool.count(&"H")
	var o_before := pool.count(&"O")

	var t := TK.new(10000)
	var flowing := {water: 4}                            # 流动的化合物账
	var moving := int(flowing[water])
	t.put({water: moving})                               # 存进罐
	flowing.erase(water)
	# ★ 池没被动过 —— 这正是"池内部移动"的含义
	assert_int(pool.count(&"H")).is_equal(h_before)
	assert_int(pool.count(&"O")).is_equal(o_before)
	assert_bool(pool.conservation_ok()).is_true()
	# 再取回来
	var back := t.take_atoms(t.occupied())
	assert_int(int(back.get(water, 0))).is_equal(4)
	assert_bool(pool.conservation_ok()).is_true()


# ============================================================ 验收 4：按比例取出

## ★ 「一个 `{A: 3, B: 1}` 的罐子取出 2 个原子 → 必须得到 `A:1.5, B:0.5` 的比例
##   （整数量化后仍保持比例）」
##
## 这里用两个**各 2 原子**的化合物（H₂ 与 O₂）来把比例做成整数，
## 从而让"整数量化后仍保持比例"这件事**可精确断言**（不靠浮点容差）。
func test_taking_atoms_is_proportional_to_the_tanks_composition() -> void:
	var t := TK.new(10000)
	var a := _h2()                                       # 每个 2 原子
	var b := _o2()                                       # 每个 2 原子
	t.put({a: 3, b: 1})                                  # 占用 = 8 原子
	assert_int(t.occupied()).is_equal(8)
	var got := t.take_atoms(8)                           # 全取
	assert_int(int(got.get(a, 0))).is_equal(3)
	assert_int(int(got.get(b, 0))).is_equal(1)
	assert_bool(t.is_empty()).is_true()


## 而**罐内只有一种化合物时，自然退化为"取出纯物质"** —— 不需要特例。
func test_a_single_compound_tank_yields_a_pure_substance() -> void:
	var t := TK.new(10000)
	var o2 := _o2()
	t.put({o2: 5})
	var got := t.take_atoms(4)                           # 4 个原子 = 2 个 O₂
	assert_int(int(got.get(o2, 0))).is_equal(2)
	assert_int(int(t.contents()[o2])).is_equal(3)


## ★ 余数累加器：**反复取一小口，不得把罐子取空**（比例是分数时最容易丢料）。
##   判据：连取很多次"远小于 1 个"的量，罐内剩下的总数**仍守恒**（罐内 + 取出 = 原量）。
func test_repeated_small_takes_do_not_lose_material() -> void:
	var t := TK.new(10000)
	var a := _h2()
	var b := _o2()
	t.put({a: 3, b: 1})
	var out := {}
	for i in 200:
		var got := t.take_atoms(1)                       # 每次只取 1 个原子（远小于一个化合物）
		for k: String in got:
			out[k] = int(out.get(k, 0)) + int(got[k])
	var total_out := 0
	for k: String in out:
		total_out += int(out[k]) * TK._atoms_per_unit(k)
	# 取出的原子数 + 罐内剩余原子数 == 原来的 8
	assert_int(total_out + t.occupied()).is_equal(8)


# ============================================================ 容量（公式 ①）与硬上限

## ★ 罐容是**硬上限**：满了就是满了；**没装下的必须【原样交回】**（好让 A5 去阻塞上游，
##   而不是被静默丢弃）—— 这与 A1 的"饱和 → 上游阻塞"是同一条语义。
func test_a_full_tank_hands_back_what_it_could_not_take() -> void:
	var t := TK.new(6)                                   # 只装得下 2 个水（水 = 3 原子）
	var water := _water()
	var left := t.put({water: 5})
	assert_int(int(t.contents()[water])).is_equal(2)     # 只装下 2 个
	assert_int(int(left.get(water, 0))).is_equal(3)      # **剩下 3 个原样交回，没有丢**
	assert_bool(t.is_full()).is_true()
	assert_int(t.remaining()).is_equal(0)


## 空的罐子：占用 0，取出量为 0（**不是错误**）
func test_an_empty_tank_yields_nothing_and_does_not_error() -> void:
	var t := TK.new(100)
	assert_bool(t.is_empty()).is_true()
	assert_int(t.occupied()).is_equal(0)
	assert_int(t.take_atoms(10).size()).is_equal(0)


## 占用是**跨化合物求和** —— 这正是"允许混装"在数值上的含义。
func test_occupancy_sums_across_compounds() -> void:
	var t := TK.new(10000)
	t.put({_water(): 1, _h2(): 2})                       # 3 + 2×2 = 7
	assert_int(t.occupied()).is_equal(7)


## 三档容量是**暂定**的（可检查 —— 否则下一个人会当成设计结论）
func test_tank_sizes_are_marked_provisional() -> void:
	assert_bool(TK.SIZES_ARE_PROVISIONAL).is_true()
	assert_int(TK.SIZE_SMALL).is_less(TK.SIZE_MEDIUM)
	assert_int(TK.SIZE_MEDIUM).is_less(TK.SIZE_LARGE)
