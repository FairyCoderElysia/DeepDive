extends GdUnitTestSuite
## A2 化合物与反应数据表 —— 逐条对应 A2 的验收标准
##
## 重点在【四条它在结构上强制的东西】，而不是"能不能查表"：
##   ① 化合物 = 组成式唯一标识（所以"同一组成两个名字"结构上不可能）
##   ④ 强制配平 —— 校验对象是「记录的输出集合」；**不过就拒绝整张表**
##   分支 = 同一输入的多条记录，条件区间**不得重叠**
##   不得假设一个产物只有一条路径（所以查询返回数组）

const CD := preload("res://scripts/compound_data.gd")
const DATA := preload("res://data/reactions.tres")

const H2O := {&"H": 2, &"O": 1}


func _new_data() -> CompoundData:
	var d = CD.new()
	d.schema_version = CD.SCHEMA_VERSION
	return d


## 一条最小合法步骤，测试再按需改坏它
func _ok_step() -> Dictionary:
	return {
		"id": "t",
		"inputs": {CD.composition_key(H2O): 2},
		"outputs": {CD.composition_key({&"H": 2}): 2, CD.composition_key({&"O": 2}): 1},
		"conditions": [{
			"param": &"param_temperature",
			"opt_lo": 60.0, "opt_hi": 90.0, "brk_lo": 20.0, "brk_hi": 130.0,
			"coef_lo": 0.6, "coef_hi": 0.4,
			"alt": {CD.composition_key({&"H": 2}): 1, CD.composition_key({&"H": 2, &"O": 2}): 1},
		}],
		"disaster": "boom",
	}


# ============================================================ ① 组成式 = 主键

## ★ 键必须【字典序、与版本无关】—— 见下面那条回归测试说明。
func test_composition_key_is_lexicographic() -> void:
	# 按字母序：Cl < H < Na < O
	assert_str(CD.composition_key({&"Na": 1, &"Cl": 1})).is_equal("Cl1|Na1")
	assert_str(CD.composition_key({&"H": 1, &"O": 1, &"Na": 1})).is_equal("H1|Na1|O1")


## ★ 回归测试：`Array[StringName].sort()` **不是**字母序（Godot 4.7.2 实测
##   `[&"Na",&"Cl",&"H"].sort()` -> `[&"Na",&"H",&"Cl"]`）。
##   若直接用它会得到"确定但任意"的键 —— 而那个次序由引擎实现决定，
##   一旦随版本变动，**已经烤进 .tres 的键就会与运行时算出的键对不上，而且不会报错**。
func test_composition_key_does_not_depend_on_stringname_internal_order() -> void:
	# 同一个组成的任意插入顺序，必须得到同一个键
	var a := CD.composition_key({&"Na": 1, &"Cl": 1})
	var b := CD.composition_key({&"Cl": 1, &"Na": 1})
	assert_str(a).is_equal(b)
	# 而且必须【恰好等于】字典序的期望值 —— 光"相等"不够（两个都错也会相等）
	assert_str(a).is_equal("Cl1|Na1")


func test_same_composition_from_different_sources_shares_one_key() -> void:
	# 水：从"两个 H + 一个 O"与"一个 H2 + 半个 O2"之外的写法都必须归一
	assert_str(CD.composition_key({&"H": 2, &"O": 1})) \
		.is_equal(CD.composition_key({&"O": 1, &"H": 2}))


# ============================================================ ④ 强制配平（导入期）

func test_valid_table_passes_validation() -> void:
	assert_array(_new_data().validate()).is_empty()


func test_unbalanced_step_is_rejected_and_the_message_names_it() -> void:
	var d := _new_data()
	var s := _ok_step()
	s["outputs"] = {CD.composition_key({&"H": 2}): 3}      # 凭空多一个 H
	d.steps = [s]
	var errs := d.validate()
	assert_int(errs.size()).is_greater(0)
	# 必须**指出是哪一条**
	assert_bool(String(errs[0]).contains("t")).is_true()
	assert_bool(String(errs[0]).contains("配平")).is_true()


## ★ 校验对象是「**记录的输出集合**」，**不是单个产物**。
##
## 怎么证明这件事：拿一条**多产物**反应 —— `2H₂O -> 2H₂ + O₂`。
##   · 单看 H₂：它给出 H4，而输入是 H4O2 -> **单个产物永远配不平**；
##   · 单看 O₂：同理。
##   · 但**把输出当一个集合**：H4O2 == H4O2 ✅ 配平。
## 所以若实现者写成了"逐产物校验"，这条合法记录会被拒 —— 这条测试就是防那个。
func test_balance_checks_the_output_SET_not_a_single_product() -> void:
	var d := _new_data()
	var s := _ok_step()                        # outputs = {H₂: 2, O₂: 1}（两个产物）
	d.steps = [s]
	assert_array(d.validate()).is_empty()      # 集合配平 -> 通过

	# 反证：把其中一个产物单独拿出来当"整个输出"，它必然配不平 -> 被拒
	var s2 := _ok_step()
	s2["outputs"] = {CD.composition_key({&"H": 2}): 2}      # 只有 H₂
	d.steps = [s2]
	assert_int(d.validate().size()).is_greater(0)


## ★ 这条是本轮实现时才显形的要求：**每一组 alt 必须【独立配平同一份输入】**。
##   否则条件一偏移，守恒就破 —— 而 A2 的 ③ 说偏移会出副产物，那副产物也得是配平的。
func test_alt_output_set_must_balance_independently() -> void:
	var d := _new_data()
	var s := _ok_step()
	# 把 alt 改坏：H₂ + H₂O₂ 本来配平（H4O2），这里少一个 O
	s["conditions"][0]["alt"] = {
		CD.composition_key({&"H": 2}): 1,
		CD.composition_key({&"H": 2, &"O": 1}): 1,     # 水 —— H4O1，缺一个 O
	}
	d.steps = [s]
	var errs := d.validate()
	assert_int(errs.size()).is_greater(0)
	assert_bool(String(errs[0]).contains("alt")).is_true()


## F-A2-1：Σ副产物系数 ≤ 1（否则副产物占比会超过 100%）
func test_sum_of_byproduct_coefficients_must_not_exceed_one() -> void:
	var d := _new_data()
	var s := _ok_step()
	s["conditions"][0]["coef_lo"] = 0.8
	s["conditions"][0]["coef_hi"] = 0.5            # Σ = 1.3 > 1
	d.steps = [s]
	var errs := d.validate()
	assert_int(errs.size()).is_greater(0)
	assert_bool(String(errs[0]).contains("系数")).is_true()


## ★ 零宽偏移带是合法的（"最优带以下立刻是灾难"）——
##   而它在实现时最容易被误判成"数序错了"。
func test_zero_width_offset_band_is_legal() -> void:
	var d := _new_data()
	var s := _ok_step()
	s["conditions"][0]["brk_lo"] = s["conditions"][0]["opt_lo"]     # 下侧偏移带宽度 0
	d.steps = [s]
	assert_array(d.validate()).is_empty()
	# 而它的行为是对的：刚好在 opt_lo 是【最优】，低于它就是【灾难】（没有中间态）
	assert_str(String(d.evaluate(s, {&"param_temperature": 60.0})["band"])).is_equal("optimal")
	assert_str(String(d.evaluate(s, {&"param_temperature": 59.9})["band"])).is_equal("disaster")


## 但【最优带】不能为零宽（否则那个旋钮没有"对"的位置）
func test_zero_width_optimal_band_is_rejected() -> void:
	var d := _new_data()
	var s := _ok_step()
	s["conditions"][0]["opt_hi"] = s["conditions"][0]["opt_lo"]
	d.steps = [s]
	assert_int(d.validate().size()).is_greater(0)


func test_condition_bands_must_be_ordered() -> void:
	var d := _new_data()
	var s := _ok_step()
	s["conditions"][0]["opt_lo"] = 100.0            # opt_lo > opt_hi，数序反了
	d.steps = [s]
	assert_int(d.validate().size()).is_greater(0)


# ============================================================ 分支 = 不重叠的区间划分

func test_overlapping_branches_are_rejected() -> void:
	var d := _new_data()
	var a := _ok_step(); a["id"] = "branch_a"
	var b := _ok_step(); b["id"] = "branch_b"
	# 两条记录输入相同、旋钮相同、最优带重叠 -> 同一个点会属于两条路径
	d.steps = [a, b]
	var errs := d.validate()
	assert_int(errs.size()).is_greater(0)
	assert_bool(String(errs[0]).contains("重叠")).is_true()


func test_non_overlapping_branches_are_accepted() -> void:
	var d := _new_data()
	var a := _ok_step(); a["id"] = "low_T"
	a["conditions"][0]["opt_lo"] = 20.0; a["conditions"][0]["opt_hi"] = 50.0
	var b := _ok_step(); b["id"] = "high_T"
	b["conditions"][0]["opt_lo"] = 50.0; b["conditions"][0]["opt_hi"] = 90.0   # 左闭右开 -> 不重叠
	d.steps = [a, b]
	assert_array(d.validate()).is_empty()


## ★ A2 的契约：「**不得假设一个产物只有一条路径**」—— 所以查询必须返回数组。
func test_steps_for_returns_a_list_not_a_single_record() -> void:
	var d := _new_data()
	var a := _ok_step(); a["id"] = "low_T"
	a["conditions"][0]["opt_lo"] = 20.0; a["conditions"][0]["opt_hi"] = 50.0
	var b := _ok_step(); b["id"] = "high_T"
	b["conditions"][0]["opt_lo"] = 50.0; b["conditions"][0]["opt_hi"] = 90.0
	d.steps = [a, b]
	var found := d.steps_for({CD.composition_key(H2O): 2})
	assert_int(found.size()).is_equal(2)


# ============================================================ ③ 三段区间与 δ

func test_optimal_band_gives_zero_delta() -> void:
	var ev = _new_data().evaluate(_ok_step(), {&"param_temperature": 75.0})
	assert_str(String(ev["band"])).is_equal("optimal")
	assert_float(float(ev["main_share"])).is_equal_approx(1.0, 0.0001)


func test_offset_band_gives_delta_and_byproduct() -> void:
	# 上侧偏移：opt_hi=90, brk_hi=130 -> 在 110 时 δ = 20/40 = 0.5
	var ev = _new_data().evaluate(_ok_step(), {&"param_temperature": 110.0})
	assert_str(String(ev["band"])).is_equal("offset")
	assert_float(float(ev["deltas"][&"param_temperature"])).is_equal_approx(0.5, 0.0001)
	# 主产物占比 = 1 - 0.5 = 0.5
	assert_float(float(ev["main_share"])).is_equal_approx(0.5, 0.0001)
	# 副产物那一份 = δ × 系数（上侧系数 0.4）= 0.5 × 0.4 = 0.2
	assert_float(float(ev["alts"][&"param_temperature"]["share"])).is_equal_approx(0.2, 0.0001)


func test_out_of_bounds_goes_to_disaster_not_proportion() -> void:
	var ev = _new_data().evaluate(_ok_step(), {&"param_temperature": 150.0})
	assert_str(String(ev["band"])).is_equal("disaster")
	assert_str(String(ev["disaster"])).is_equal("boom")


func test_delta_is_zero_inside_and_positive_in_offset() -> void:
	var d := _new_data()
	var s := _ok_step()
	# 下侧偏移：opt_lo=60, brk_lo=20 -> 在 40 时 δ = 20/40 = 0.5
	var ev = d.evaluate(s, {&"param_temperature": 40.0})
	assert_float(float(ev["deltas"][&"param_temperature"])).is_equal_approx(0.5, 0.0001)
	# 边界语义 [a,b)：恰好 60 属于最优带
	var ev2 = d.evaluate(s, {&"param_temperature": 60.0})
	assert_float(float(ev2["deltas"][&"param_temperature"])).is_equal(0.0)


# ============================================================ ★ A2 → A1 的桥：守恒

## 这条测试是 A2 与 A1 之间**唯一**真正要紧的事：
## 无论条件怎么偏移，折算出来的原子收支**必须守恒**。
func test_resolve_scaled_conserves_atoms_in_every_band() -> void:
	var d := _new_data()
	var s := _ok_step()
	var SCALE: int = preload("res://scripts/element_pool.gd").SCALE
	for temp in [75.0, 110.0, 40.0, 95.0]:
		var r: Dictionary = d.resolve_scaled(s, {&"param_temperature": temp}, 1000 * SCALE)
		assert_str(String(r["band"])).is_not_equal("disaster")
		# ★ 要验的不变量只有一句：**消耗掉的输入原子 == 产出的输出原子**
		#   （未反应的部分两边都不算 —— 它既没被消耗，也没被产出）
		var in_atoms: int = CD.total_atoms_of(r["inputs"])
		var out_atoms: int = CD.total_atoms_of(r["outputs"])
		assert_int(in_atoms).is_equal(out_atoms)
		# 并且两本账都必须非空（否则"相等"是 0 == 0 这种没意义的相等）
		assert_int(in_atoms).is_greater(0)


func test_resolve_scaled_is_disaster_aware() -> void:
	var SCALE: int = preload("res://scripts/element_pool.gd").SCALE
	var r: Dictionary = _new_data().resolve_scaled(_ok_step(), {&"param_temperature": 200.0}, 100 * SCALE)
	assert_str(String(r["band"])).is_equal("disaster")
	assert_str(String(r["disaster"])).is_equal("boom")


# ============================================================ 真实数据表

func test_shipped_table_is_valid_and_has_the_three_steps() -> void:
	assert_array(DATA.validate()).is_empty()
	assert_int(DATA.steps.size()).is_equal(3)


## 概念文档那条："条件不同，结果真的会不一样" —— 出厂表里必须真的能看出来
func test_shipped_water_electrolysis_changes_with_temperature() -> void:
	var s: Dictionary = DATA.steps[0]
	var opt = DATA.evaluate(s, {&"param_temperature": 75.0})
	var off = DATA.evaluate(s, {&"param_temperature": 118.0})
	assert_float(float(opt["main_share"])).is_equal_approx(1.0, 0.0001)
	assert_bool(float(off["main_share"]) < 1.0).is_true()
	assert_bool((off["alts"] as Dictionary).size() > 0).is_true()
	var bad = DATA.evaluate(s, {&"param_temperature": 150.0})
	assert_str(String(bad["band"])).is_equal("disaster")
