extends GdUnitTestSuite
## B4 · 氧气经济 —— 逐条对应 B4 的 Acceptance Criteria
##
## ⚠️ **验收 1（张力存在性）不在这个文件里** —— 它要求 **≥70% 的真实玩家能举出一次
##   "为留氧而放弃产出"的取舍**，GDD 自己写着"无法靠自检替代"。
##   ⇒ 它属于 **T1 的测试计划**，不属于单元测试。本文件覆盖 **2/3/4/5/6**。
##
## ★ 而 2026-10-03 用户拍板：**B4 改成【不持有余额】的纯函数集** ——
##   那个【唯一的数字】由**化合物账**持有。所以本文件里的"存量"全是**测试自己拿的局部变量**，
##   而不是从 B4 里读的（B4 里根本没有）。

const OE := preload("res://scripts/oxygen_economy.gd")


# ============================================================ 验收 2：单池（第一号不可违反的约束）

## ★ Core Rule ②：「氧**只有一个池**」。
##
## 这条**不能靠"我读一遍代码觉得没有"来验**。而"两个数字"**不限于按角色分** ——
## **"谁持有"分出两份也是两个数字**。所以判据是**结构性**的：
##   ① B4 没有任何自定义实例属性  ② 记账方法全是 static（静态方法改不到实例状态）
##   ③ 没有成员名同时带"角色"与"存量"的含义（防有人加回来）
func test_b4_holds_no_balance_of_its_own() -> void:
	var probe = OE.new()
	# ① 没有自定义属性 —— ⚠️ 过滤条件必须认 `usage` 里的【分组表头】位：
	#    `get_property_list()` 会把基类名与脚本文件名当作 category/group 表头返回
	#    （实测三项：RefCounted / script / oxygen_economy.gd，后两项 usage=128）。
	#    第一版我只按名字过滤 ⇒ 把表头当成真属性 ⇒ 测试误报。**判据要认标志位，不认名字。**
	var custom_props := []
	for p in probe.get_property_list():
		var nm := String(p["name"])
		var is_header := (int(p["usage"]) & 128) != 0      # PROPERTY_USAGE_CATEGORY/GROUP
		if not is_header and nm != "script":
			custom_props.append(nm)
	assert_array(custom_props).is_empty()

	# ② 每个记账方法都必须能**按静态方式**调用 —— 不是 static 的话这几行会直接失败
	assert_float(OE.net_rate(1.0, 0.0)).is_greater(0.0)
	assert_str(OE.state_of(5, 1.0)).is_equal(OE.STATE_SURPLUS)
	assert_int(int(OE.integrate(0, 1.0, 1.0)["stock"])).is_equal(1)
	assert_float(OE.stock_ratio(5, 10.0)).is_equal_approx(0.5, 0.0001)
	assert_bool(OE.is_tight(1, 10.0)).is_true()

	# ③ 不许有"按角色分的存量"
	var names: Array = []
	for m in probe.get_method_list():
		names.append(String(m["name"]))
	var role_words := ["life", "industrial", "industry", "chain", "maintenance"]
	var stock_words := ["stock", "pool", "reserve", "amount", "level"]
	var offenders := []
	for name in names:
		var n := String(name).to_lower()
		var has_role := false
		var has_stock := false
		for r in role_words:
			if n.contains(r):
				has_role = true
		for s in stock_words:
			if n.contains(s):
				has_stock = true
		if has_role and has_stock:
			offenders.append(name)
	assert_array(offenders).is_empty()


## ★ 而"三级优先"必须是**分配顺序**，不是三个池 —— 它只返回"这一 tick 各分到多少"，
##   **不产生、也不持有任何存量**。
func test_three_level_priority_is_an_allocation_order_not_three_pools() -> void:
	var alloc := OE.allocate(10.0, 4.0, 3.0, 5.0)
	assert_float(float(alloc["life_support"])).is_equal_approx(4.0, 0.0001)
	assert_float(float(alloc["oxygen_chain"])).is_equal_approx(3.0, 0.0001)
	assert_float(float(alloc["other_industry"])).is_equal_approx(3.0, 0.0001)   # 只剩 3
	assert_float(float(alloc["unfunded"])).is_equal_approx(0.0, 0.0001)
	assert_int(alloc.size()).is_equal(4)                 # 就这几个键 —— 没有一个是"余额"


## 不够分时：**生命维持优先拿到**（③ 的本意："人不死"）。
func test_life_support_is_funded_first() -> void:
	var alloc := OE.allocate(1.0, 4.0, 3.0, 5.0)
	assert_float(float(alloc["life_support"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(alloc["oxygen_chain"])).is_equal_approx(0.0, 0.0001)
	assert_float(float(alloc["other_industry"])).is_equal_approx(0.0, 0.0001)


# ============================================================ 验收 3：可恢复性（F-B4-1）

## ★ 这是 B4 最要紧的一条：**"耗竭"必须是一个可离开的状态**。
##
## 为什么：若"工业全停"被直译，制氧设备也会停 ⇒ **永远无法产氧 ⇒ 不可恢复**，
## 那违反全项目"所有状态可复原"的纪律（P5 无时限、不能有死档）。
func test_depleted_is_not_a_dead_end_when_the_oxygen_chain_produces() -> void:
	var stock := 0
	var resid := 0
	assert_str(OE.state_of(stock, -1.0)).is_equal(OE.STATE_DEPLETED)
	for i in 40:                                              # 产氧链开始产氧
		var r := OE.integrate(stock, OE.net_rate(1.0, 0.0), 1.0, resid)
		stock = int(r["stock"])
		resid = int(r["residual_scaled"])
	assert_int(stock).is_greater(0)                           # 真的回来了
	assert_str(OE.state_of(stock, 1.0)).is_not_equal(OE.STATE_DEPLETED)


## 而"产氧链"这一级在**存量极低**时也必须仍能拿到氧 —— 否则还是死锁。
func test_the_oxygen_chain_level_is_still_funded_when_stock_is_critical() -> void:
	var alloc := OE.allocate(OE.LIFE_SUPPORT_RATE, OE.LIFE_SUPPORT_RATE, 0.5, 99.0)
	assert_float(float(alloc["life_support"])).is_equal_approx(OE.LIFE_SUPPORT_RATE, 0.0001)
	assert_float(float(alloc["other_industry"])).is_equal_approx(0.0, 0.0001)


# ============================================================ 验收 5：持续性（存贮是速率）

## ★ 推论 2：存贮耗氧**是速率**（氧/(秒·存量)）—— **时间不推进则不再增长**，不得是一次性扣费。
##   判据：**同样的存量、两倍的时间 ⇒ 两倍的耗氧**（线性于 dt 才是速率）。
func test_storage_cost_is_a_rate_not_a_one_off_charge() -> void:
	var base := OE.net_rate(0.0, 0.0, 100.0, 0.0)          # 存量 100 时的净收支
	assert_float(base).is_less(0.0)                        # 纯耗氧 ⇒ 净收支为负
	var stock1 := 1000
	var resid1 := 0
	var stock2 := 1000
	var resid2 := 0
	for i in 50:
		var r1 := OE.integrate(stock1, base, 1.0, resid1)  # 1 秒
		stock1 = int(r1["stock"]); resid1 = int(r1["residual_scaled"])
		var r2 := OE.integrate(stock2, base, 2.0, resid2)  # 2 秒 —— 同样的存量、两倍时间
		stock2 = int(r2["stock"]); resid2 = int(r2["residual_scaled"])
	var drop1 := 1000 - stock1
	var drop2 := 1000 - stock2
	assert_int(drop1).is_greater(0)                        # 而且真的在掉
	assert_float(float(drop2)).is_greater(float(drop1) * 1.8)


# ============================================================ 验收 6：无货币（出口的缺失）

## ★ "不可用"档位**只剩存贮 / 销毁**，且**没有"低价卖掉"这个出口** ——
##   这条把"无货币"从一句口号变成一个**可检验的缺失**。
func test_there_is_no_sell_outlet_at_all() -> void:
	var members: Array = []
	for m in OE.new().get_method_list():
		members.append(String(m["name"]).to_lower())
	for forbidden in ["sell", "sale", "price", "market", "money", "gold", "trade", "refund"]:
		var hits := []
		for name in members:
			if name.contains(forbidden):
				hits.append(name)
		assert_array(hits).is_empty()


## 而**销毁也要耗氧**（推论 3）：销毁量越大，净收支越低。
func test_destruction_costs_oxygen_too() -> void:
	var none := OE.net_rate(0.0, 0.0, 0.0, 0.0)
	var some := OE.net_rate(0.0, 0.0, 0.0, 10.0)
	assert_float(some).is_less(none)


# ============================================================ 验收 4：负值（不是折价正值）

## ★ 推论 1：「低纯产物不是'少赚'，而是'要花钱（氧气）去处理'」—— 它在账上是**负值**。
func test_a_product_that_needs_refining_is_a_negative_contribution() -> void:
	var rate := OE.net_rate(0.0, 0.0, 50.0, 0.0)
	assert_float(rate).is_less(0.0)                        # 负值
	assert_bool(is_equal_approx(rate, 0.0)).is_false()     # 而且**不是零**（零会被读成"不花钱"）


# ============================================================ §States 与"不许丢小数"

## 四种状态（§States）
func test_the_four_accounting_states_are_distinguishable() -> void:
	assert_str(OE.state_of(10, 1.0)).is_equal(OE.STATE_SURPLUS)
	assert_str(OE.state_of(10, 0.0)).is_equal(OE.STATE_BALANCED)
	assert_str(OE.state_of(10, -1.0)).is_equal(OE.STATE_DEFICIT)
	assert_str(OE.state_of(0, -1.0)).is_equal(OE.STATE_DEPLETED)


## ★ 与 A1 同一条纪律：**速率攒够一个才动账，余量留下** —— 不得每 tick 丢掉小数。
##   判据：一个**永远凑不满一个**的小速率跑很多 tick 后，余量必须**还在**（而不是全丢）。
func test_fractional_rates_accumulate_instead_of_being_discarded() -> void:
	var stock := 0
	var resid := 0
	var tiny := 0.5 / float(OE.SCALE)                 # 每 tick 半个"放大单位"
	for i in 100:
		# ⚠️ `net_rate` 里**永远扣着生命维持那一项** ⇒ 想只留 tiny 就得把它补回来。
		#    （第一版我直接喂 tiny，忘了这件事 ⇒ 净收支其实是负的 ⇒ 测试红了。**红得对**。）
		var r := OE.integrate(stock, OE.net_rate(OE.LIFE_SUPPORT_RATE + tiny, 0.0), 1.0, resid)
		stock = int(r["stock"]); resid = int(r["residual_scaled"])
	assert_int(stock).is_equal(0)                     # 攒不到 1 个 ⇒ 存量仍是 0
	assert_int(resid).is_greater(0)                   # **但余量没丢**


## 存量**永不为负**：把氧耗到 0 之后继续耗，必须停在 0（而不是变成负数）。
func test_stock_never_goes_negative() -> void:
	var stock := 1
	var resid := 0
	for i in 100:
		var r := OE.integrate(stock, OE.net_rate(0.0, 100.0), 1.0, resid)
		stock = int(r["stock"]); resid = int(r["residual_scaled"])
	assert_int(stock).is_equal(0)
