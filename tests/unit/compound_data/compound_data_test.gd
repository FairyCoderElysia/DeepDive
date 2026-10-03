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

func test_shipped_table_has_four_steps_and_validates_clean() -> void:
	const ET3 := preload("res://data/element_table.tres")
	var known := {}
	for sym: StringName in ET3.elements:
		known[sym] = true
	assert_array(DATA.validate(known)).is_empty()
	# 4 条 = 水电解低T + 水电解高T（一对分支）+ 氯碱 + 除硬
	assert_int(DATA.steps.size()).is_equal(4)


## 概念文档那条："条件不同，结果真的会不一样" —— 出厂表里必须真的能看出来
func test_shipped_water_electrolysis_changes_with_temperature() -> void:
	# ⚠️ 出厂表里水电解是【一对分支】，所以必须按分支取，不能拿 steps[0] 当"那条水电解"
	var br := DATA.steps_for({CD.composition_key(H2O): 2})
	assert_int(br.size()).is_equal(2)
	var low: Dictionary = br[0]
	var high: Dictionary = br[1]
	# 各自的最优带里都是 optimal、主占比 1.0
	assert_float(float(DATA.evaluate(low, {&"param_temperature": 50.0})["main_share"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(DATA.evaluate(high, {&"param_temperature": 80.0})["main_share"])).is_equal_approx(1.0, 0.0001)
	# 而高温分支往热了拧 -> 进偏移带，主占比下降、出副产物（这就是"条件不同结果不同"）
	var off: Dictionary = DATA.evaluate(high, {&"param_temperature": 125.0})
	assert_str(String(off["band"])).is_equal("offset")
	assert_bool(float(off["main_share"]) < 1.0).is_true()
	assert_bool((off["alts"] as Dictionary).size() > 0).is_true()
	# 再往热 -> 灾难
	assert_str(String(DATA.evaluate(high, {&"param_temperature": 150.0})["band"])).is_equal("disaster")
	# 低温分支往下 -> 灾难（brk_lo = 20）
	assert_str(String(DATA.evaluate(low, {&"param_temperature": 10.0})["band"])).is_equal("disaster")
# ============================================================ 验收 2/3/4/5（承重约束的翻译）

## ★ 验收 2：**同一输入在两组不同条件下必须能产出不同输出**。
##   这是用户那句「**一台机器是反应中一个或多个步骤，而不是把反应定死**」的翻译。
func test_branching_same_input_different_conditions_different_outputs() -> void:
	var s := DATA.steps_for({CD.composition_key(H2O): 2})
	assert_int(s.size()).is_greater_equal(2)                 # 两条分支
	var lo: Dictionary = DATA.evaluate(s[0], {&"param_temperature": 50.0})   # 低温最优
	var hi: Dictionary = DATA.evaluate(s[1], {&"param_temperature": 80.0})   # 高温最优
	assert_str(String(lo["band"])).is_equal("optimal")
	assert_str(String(hi["band"])).is_equal("optimal")
	# 而两者**产出不同的化合物**（不是同一条反应换个数字）
	assert_str(String(s[0]["id"])).is_not_equal(String(s[1]["id"]))
	assert_bool(s[0]["outputs"] != s[1]["outputs"]).is_true()


## ★ 验收 3：**至少一个产物存在两条以上可达路径**。
##   这是用户那句「**同一产物允许多条路线**」的翻译（概念文档的承重约束 #1）。
func test_at_least_one_product_has_two_or_more_paths() -> void:
	var h2 := CD.composition_key({&"H": 2})
	var paths := 0
	for s: Dictionary in DATA.steps:
		if (s["outputs"] as Dictionary).has(h2):
			paths += 1
	assert_int(paths).is_greater_equal(2)


## ★ 验收 4：分支区间**既不重叠也不留缝**（否则会有"平局"或"无人区"）
func test_shipped_branches_tile_without_gap() -> void:
	var s := DATA.steps_for({CD.composition_key(H2O): 2})
	var a: Dictionary = s[0]["conditions"][0]
	var b: Dictionary = s[1]["conditions"][0]
	# 无缝拼接：一个的上界恰好是另一个的下界
	assert_bool(is_equal_approx(float(a["opt_hi"]), float(b["opt_lo"]))).is_true()
	# 而朝内一侧必须是**零宽偏移带** —— 否则偏移带会侵入邻段的最优带
	assert_bool(is_equal_approx(float(a["brk_hi"]), float(a["opt_hi"]))).is_true()
	assert_bool(is_equal_approx(float(b["brk_lo"]), float(b["opt_lo"]))).is_true()


func test_gap_between_branches_is_rejected() -> void:
	var d := _new_data()
	var a := _ok_step(); a["id"] = "a"
	a["conditions"][0]["opt_lo"] = 20.0; a["conditions"][0]["opt_hi"] = 40.0
	a["conditions"][0]["brk_lo"] = 10.0; a["conditions"][0]["brk_hi"] = 40.0
	var b := _ok_step(); b["id"] = "b"
	b["conditions"][0]["opt_lo"] = 50.0; b["conditions"][0]["opt_hi"] = 90.0   # 40..50 是无人区
	b["conditions"][0]["brk_lo"] = 50.0; b["conditions"][0]["brk_hi"] = 100.0
	d.steps = [a, b]
	var errs := d.validate()
	assert_int(errs.size()).is_greater(0)
	assert_bool(String(errs[0]).contains("无人区")).is_true()


## ★ 验收 5：引用 A1 未登记的元素时必须**报出缺的是哪个**（不得静默失败）
func test_unknown_element_is_reported_by_name() -> void:
	var d := _new_data()
	var s := _ok_step()
	s["outputs"] = {CD.composition_key({&"H": 2}): 1, CD.composition_key({&"Xx": 1}): 1}
	d.steps = [s]
	# 不传 known_elements -> 跳过这项；传了 -> 必须报
	assert_array(d.validate()).is_not_empty()                  # 先因为配平被拒
	const ET2 := preload("res://data/element_table.tres")
	var known := {}
	for sym: StringName in ET2.elements:
		known[sym] = true
	var errs := d.validate(known)
	assert_int(errs.size()).is_greater(0)
	var joined := " ".join(errs)
	assert_bool(joined.contains("Xx")).is_true()


## 出厂表引用的元素必须全都在元素表里（否则是数据错误）
func test_shipped_table_references_only_registered_elements() -> void:
	const ET := preload("res://data/element_table.tres")
	var known := {}
	for sym: StringName in ET.elements:
		known[sym] = true
	assert_array(DATA.validate(known)).is_empty()

# ============================================================ 验收 7：序列化往返

func test_binary_round_trip_preserves_the_table() -> void:
	var rb = CD.from_bytes(DATA.to_bytes())
	assert_int(rb.steps.size()).is_equal(DATA.steps.size())
	assert_int(rb.schema_version).is_equal(DATA.schema_version)
	# 类型也必须仍是 int（这一条是只比 == 会漏掉的）
	assert_int(typeof(rb.schema_version)).is_equal(TYPE_INT)
	# 而且回来的表必须仍然自洽（能过校验、能求值）
	const ET4 := preload("res://data/element_table.tres")
	var known := {}
	for sym: StringName in ET4.elements:
		known[sym] = true
	assert_array(rb.validate(known)).is_empty()
	var br := rb.steps_for({CD.composition_key(H2O): 2})
	var ev = rb.evaluate(br[0], {&"param_temperature": 50.0})
	assert_str(String(ev["band"])).is_equal("optimal")


## ★ 这条测试记录一个**诚实的发现**（并更正了 A2 的验收 7）：
##
## A2 的数据过一遍 JSON 之后，**功能上仍然正确** —— 校验通过、求值正确。
## 它坏掉的只是【类型】：`schema_version` 从 `INT` 变 `FLOAT`，`param` 从 `StringName` 变 `String`。
##
## ⚠️ 这与 A1 **不一样**：A1 过 JSON 是**值真的坏了**（int64 掉精度，而 `==` 还说相等）。
## **⇒ 同一条纪律换一个系统，失效方式会不一样 —— 所以验收不能照抄。**
func test_json_channel_corrupts_types_but_not_behaviour() -> void:
	var via = JSON.parse_string(JSON.stringify({"v": DATA.schema_version, "steps": DATA.steps}))
	# ① 类型确实坏了
	assert_int(typeof(via["v"])).is_equal(TYPE_FLOAT)
	assert_int(typeof(via["steps"][0]["conditions"][0]["param"])).is_equal(TYPE_STRING)
	# ② 但功能没坏 —— 校验照样过、求值照样对
	var d = CD.new()
	d.schema_version = int(via["v"])
	d.steps = via["steps"]
	assert_array(d.validate({})).is_empty()
	assert_str(String(d.evaluate(d.steps[0], {&"param_temperature": 50.0})["band"])).is_equal("optimal")
	# ③ 所以二进制通道仍然是【必须的】—— 它保住了类型；而 JSON 的代价此刻只是"类型不干净"，
	#    但一旦将来某个字段变成大整数（例如把原子数写进表），它就会像 A1 那样【静默掉精度】。

## ★ A2 的 §Edge Cases：「**空组成式 / 某元素原子数为 0** -> 拒绝
##   —— 组成式必须非空，且只记实际存在的元素」。
func test_empty_composition_is_rejected() -> void:
	var d := _new_data()
	var s := _ok_step()
	# 输入里塞一个空组成式
	s["inputs"] = {"": 2}
	s["outputs"] = {CD.composition_key({&"H": 2}): 2}
	d.steps = [s]
	var errs := d.validate()
	assert_int(errs.size()).is_greater(0)
	assert_bool(" ".join(errs).contains("空组成式")).is_true()


func test_zero_atom_count_in_key_is_rejected() -> void:
	var d := _new_data()
	var s := _ok_step()
	# 手写一个含 0 个数的组成式（composition_key 不会生成这种，但数据文件可能手改坏）
	s["inputs"] = {"H0|O1|O1": 2}
	d.steps = [s]
	var errs := d.validate()
	assert_int(errs.size()).is_greater(0)
