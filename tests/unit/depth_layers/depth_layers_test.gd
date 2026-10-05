extends GdUnitTestSuite
## C1 · 深度分层 —— **本轮只覆盖【T1 义务】：表层通量天花板**
##
## ⚠️ **验收 3（通量阶梯）是玩家感受**：「**玩家必须真的感到"海水不够用"**」——
##   它与 B4 的验收 1 同类，**单元测试证不了**。
##   ⇒ 它属于 **T1 的测试计划**，不属于这里。
##   本文件能证的是**机制**：天花板真的在生效、**在 T1 里真的咬得住**、且它是**一个数**。
##
## ⚠️ 另外：C1 的 ①带宽 ②速度 ③许用通量 ④耗氧 ④'光 **一条都没实现**（属 T3）——
##   本文件里刻意**没有**它们的测试，免得读的人以为做过。

const DL := preload("res://scripts/depth_layers.gd")


# ============================================================ 天花板真的在生效

## ★ 未超限时**一分不让** —— 天花板不是"总是按比例扣"（那会把"没到顶"也变成惩罚）。
func test_below_the_cap_nothing_is_withheld() -> void:
	var req := [1.0, 0.5, 0.2]                       # 合计 1.7 < 3.0
	var got := DL.clamp_surface_intake(req)
	assert_int(got.size()).is_equal(req.size())
	for i in req.size():
		assert_float(float(got[i])).is_equal_approx(float(req[i]), 0.000001)
	assert_bool(DL.is_capped(req)).is_false()


## ★ 超限时**总量必须被压到上限**（在浮点容差内）—— 这是"天花板"唯一的意义。
func test_above_the_cap_the_total_is_held_to_the_cap() -> void:
	var req := [3.7, 1.0, 0.5]                       # 合计 5.2 > 3.0（= T1 的真实请求）
	assert_bool(DL.is_capped(req)).is_true()
	var got := DL.clamp_surface_intake(req)
	assert_float(DL.total_of(got)).is_equal_approx(DL.SURFACE_THROUGHPUT_CAP, 0.0001)
	# 而每一项都被**等比例**压了（不是只砍某一项）
	var f: float = DL.SURFACE_THROUGHPUT_CAP / 5.2
	for i in req.size():
		assert_float(float(got[i])).is_equal_approx(float(req[i]) * f, 0.0001)


## ★★ **本文件最要紧的一条**：天花板是 **一个数**，不是"每台泵各自一个上限"。
##
## 若做成后者，**多接几台泵就能线性放大产能** ⇒ 天花板等于不存在，
## 而"必须下潜"就退化成一句设定（Risk #8 说的正是这件事）。
func test_the_cap_is_one_number_not_one_per_intake() -> void:
	# 三台泵**各自都没超**（1.0 < 3.0），但合计 3.0 已经顶到上限
	var req := [1.0, 1.0, 1.0]
	var got := DL.clamp_surface_intake(req, 3.0)
	# 合计恰好等于上限 ⇒ 不该被砍
	assert_float(DL.total_of(got)).is_equal_approx(3.0, 0.0001)
	# 再加**第四台泵**：每台仍各自远低于上限，但合计超了 ⇒ **必须被砍**
	var req2 := [1.0, 1.0, 1.0, 1.0]
	var got2 := DL.clamp_surface_intake(req2, 3.0)
	assert_float(DL.total_of(got2)).is_equal_approx(3.0, 0.0001)
	assert_float(float(got2[3])).is_less(1.0)        # 第四台泵**分不到全额**
	# ⇒ 而这就是"加泵不能线性放大产能"的可测形式


## 确定性：同一组请求永远给同一组授予（A2/A3/A5 都要求这一条）。
func test_allocation_is_deterministic() -> void:
	var req := [3.7, 1.0, 0.5]
	var a := DL.clamp_surface_intake(req)
	var b := DL.clamp_surface_intake(req.duplicate())
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_float(float(a[i])).is_equal_approx(float(b[i]), 0.0)


## 请求为 0 的那一项**不占用配额**（乘 0 天然成立）—— 否则"不开的水龙头"也会吃掉天花板。
func test_a_zero_request_does_not_consume_quota() -> void:
	var got := DL.clamp_surface_intake([0.0, 6.0], 3.0)
	assert_float(float(got[0])).is_equal_approx(0.0, 0.000001)
	assert_float(float(got[1])).is_equal_approx(3.0, 0.0001)   # 另一项拿满


## 负数（不该出现，但边界要稳）：不得让它把别人的配额"抵"出来。
func test_negative_requests_cannot_buy_quota() -> void:
	var got := DL.clamp_surface_intake([-5.0, 6.0], 3.0)
	assert_float(float(got[0])).is_equal_approx(0.0, 0.000001)
	assert_float(DL.total_of(got)).is_less_equal(3.0001)


# ============================================================ 与 T1 的接缝（暂定值）

## ★ 天花板的值是**暂定**的，而"暂定"必须可检查 —— 否则下一个人会把 3.0 当成设计结论。
func test_the_cap_value_is_marked_provisional() -> void:
	assert_bool(DL.SURFACE_CAP_IS_PROVISIONAL).is_true()
	assert_float(DL.SURFACE_THROUGHPUT_CAP).is_greater(0.0)


## ★ 而它在 **T1 的真实请求**下必须**真的咬住** —— 否则"表层通量天花板"在这个切片里等于没做。
##   （T1 的三个进水口：水 3.7 + 盐 1.0 + CaCl₂ 0.5 = 5.2 份/秒）
func test_the_cap_actually_bites_on_t1s_real_intake_requests() -> void:
	var t1_requests := [3.7, 1.0, 0.5]
	assert_bool(DL.is_capped(t1_requests)).is_true()
	var got := DL.clamp_surface_intake(t1_requests)
	# 咬住的幅度可观（不是 99% 那种"看起来咬住了"）
	assert_float(DL.total_of(got)).is_less(DL.total_of(t1_requests) * 0.7)
