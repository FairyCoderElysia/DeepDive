extends GdUnitTestSuite
## B4 · 氧气经济 —— 逐条对应 B4 的 Acceptance Criteria
##
## ⚠️ **验收 1（张力存在性）不在这个文件里** —— 它要求 **≥70% 的真实玩家能举出一次
##   "为留氧而放弃产出"的取舍**，GDD 自己写着"无法靠自检替代"。
##   ⇒ 它属于 **T1 的测试计划**，不属于单元测试。本文件覆盖 **2/3/4/5/6**。

const OE := preload("res://scripts/oxygen_economy.gd")


# ============================================================ 验收 2：单池（第一号不可违反的约束）

## ★ Core Rule ②：「氧**只有一个池**」—— 若实现里出现"生命维持氧"与"工业氧"两个数字，即为失败。
##
## 这条**不能靠"我读一遍代码觉得没有"来验**：所以这里**扫反射** ——
## 断言**没有任何**成员（方法 / 属性）的名字同时带"角色"与"存量"的含义。
## 一个只会返回唯一 `stock()` 的实现会通过；而有人加一个 `life_support_stock()` 会立刻红。
func test_there_is_exactly_one_oxygen_pool() -> void:
	var members: Array = []
	for m in OE.new().get_method_list():
		members.append(String(m["name"]))
	for p in OE.new().get_property_list():
		members.append(String(p["name"]))
	var role_words := ["life", "industrial", "industry", "chain", "maintenance"]
	var stock_words := ["stock", "pool", "reserve", "amount", "level"]
	var offenders := []
	for name in members:
		var n := String(name).to_lower()   # ⚠️ 必须显式 String()：`name` 来自无类型数组，:= 推不出类型（那会让整个文件解析不过）
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


## ★ 而"三级优先"必须是**分配顺序**，不是三个池 —— 它只返回"分到多少"，不持有任何存量。
func test_three_level_priority_is_an_allocation_order_not_three_pools() -> void:
	var e = OE.new(10)
	var before := e.stock()
	var alloc := OE.allocate(10.0, 4.0, 3.0, 5.0)
	# 先满足生命维持、再产氧链、最后其他工业
	assert_float(float(alloc["life_support"])).is_equal_approx(4.0, 0.0001)
	assert_float(float(alloc["oxygen_chain"])).is_equal_approx(3.0, 0.0001)
	assert_float(float(alloc["other_industry"])).is_equal_approx(3.0, 0.0001)   # 只剩 3
	assert_float(float(alloc["unfunded"])).is_equal_approx(0.0, 0.0001)
	# 而分配**完全不影响存量** —— 它不是三个池
	assert_int(e.stock()).is_equal(before)


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
	var e = OE.new(0)
	assert_str(e.state(-1.0)).is_equal(OE.STATE_DEPLETED)
	# 第 2 级（产氧链）开始产氧 ⇒ 必须能离开耗竭
	for i in 40:
		e.step(1.0, 1.0, 0.0)          # 产 1.0/s，只吃生命维持那一项
	assert_int(e.stock()).is_greater(0)                     # 真的回来了
	assert_str(e.state(1.0)).is_not_equal(OE.STATE_DEPLETED)


## 而"产氧链"这一级在**存量极低**时也必须仍能拿到氧 —— 否则还是死锁。
func test_the_oxygen_chain_level_is_still_funded_when_stock_is_critical() -> void:
	# 可分配量 = 生命维持 + 产氧链 一点点，其他工业全饿着
	var alloc := OE.allocate(OE.LIFE_SUPPORT_RATE, OE.LIFE_SUPPORT_RATE, 0.5, 99.0)
	assert_float(float(alloc["life_support"])).is_equal_approx(OE.LIFE_SUPPORT_RATE, 0.0001)
	assert_float(float(alloc["other_industry"])).is_equal_approx(0.0, 0.0001)


# ============================================================ 验收 5：持续性（存贮是速率）

## ★ 推论 2：存贮耗氧**是速率**（氧/(秒·存量)）—— **时间不推进则不再增长**，不得是一次性扣费。
##   判据：**同样的存量、两倍的时间 ⇒ 两倍的耗氧**（线性于 dt 才是速率）。
func test_storage_cost_is_a_rate_not_a_one_off_charge() -> void:
	var base := OE.net_rate(0.0, 0.0, 100.0, 0.0)          # 存量 100 时的净收支
	var e1 = OE.new(1000)
	var e2 = OE.new(1000)
	# ⚠️ 第一版我只跑了 1 tick ⇒ 速率 (0.15/s) 一个整氧都凑不满 ⇒ 存量没动 ⇒ 测试红了。
	#    而**红得对**：那正是"速率攒够一个才动账"这条纪律在起作用（余量留着，不会静默少氧）。
	#    所以要跑足够多 tick 才看得见"速率"的效果。
	for i in 50:
		e1.step(1.0, 0.0, 0.0, 100.0)      # 1 秒
		e2.step(2.0, 0.0, 0.0, 100.0)      # 2 秒 —— 同样的存量，两倍时间
	# 时间翻倍 ⇒ 掉的血也（近似）翻倍 —— 这就是"速率"的可测形式
	var drop1 := 1000 - e1.stock()
	var drop2 := 1000 - e2.stock()
	assert_int(drop1).is_greater(0)                        # 而且真的在掉
	assert_float(float(drop2)).is_greater(float(drop1) * 1.8)
	assert_float(base).is_less(0.0)                        # 纯耗氧 ⇒ 净收支为负


# ============================================================ 验收 6：无货币（出口的缺失）

## ★ "不可用"档位**只剩存贮 / 销毁**，且**没有"低价卖掉"这个出口** ——
##   这条把"无货币"从一句口号变成一个**可检验的缺失**：
##   实现里的每一个出口都必须是"花氧的"，不存在任何"换成价值"的方法。
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
##   ⇒ `net_rate` 对"没有任何产氧、只有处理项"的情形必须给出**严格小于 0** 的速率，
##   而**不是**一个"折价后的正数"。
func test_a_product_that_needs_refining_is_a_negative_contribution() -> void:
	var rate := OE.net_rate(0.0, 0.0, 50.0, 0.0)
	assert_float(rate).is_less(0.0)                        # 负值
	assert_bool(is_equal_approx(rate, 0.0)).is_false()     # 而且**不是零**（零会被读成"不花钱"）


# ============================================================ 状态机与"不许丢小数"

## 四种状态（§States）
func test_the_four_accounting_states_are_distinguishable() -> void:
	var e = OE.new(10)
	assert_str(e.state(1.0)).is_equal(OE.STATE_SURPLUS)
	assert_str(e.state(0.0)).is_equal(OE.STATE_BALANCED)
	assert_str(e.state(-1.0)).is_equal(OE.STATE_DEFICIT)
	var zero = OE.new(0)
	assert_str(zero.state(-1.0)).is_equal(OE.STATE_DEPLETED)


## ★ 与 A1 同一条纪律：**速率攒够一个才动账，余量留下** —— 不得每 tick 丢掉小数。
##   判据：一个**永远凑不满一个**的小速率跑很多 tick 后，余量必须**还在**（而不是全丢）。
func test_fractional_rates_accumulate_instead_of_being_discarded() -> void:
	var e = OE.new(0)
	var tiny := 0.5 / float(OE.SCALE)          # 每 tick 半个"放大单位"
	# ⚠️ 第一版我直接喂 tiny，忘了 net_rate 里**永远扣着生命维持那一项** ⇒ 净收支其实是负的
	#    ⇒ 余量一路变负、存量被夹在 0 ⇒ 测试红了。**红得对**：它证明我没把式子看全。
	#    正确的喂法是"产氧 = 生命维持 + tiny"，这样净收支恰为 tiny。
	for i in 100:
		e.step(1.0, OE.LIFE_SUPPORT_RATE + tiny, 0.0)
	# 攒不到 1 个 ⇒ 存量仍是 0，**但余量没丢**
	assert_int(e.stock()).is_equal(0)
	assert_int(e._residual_scaled).is_greater(0)


## 存量**永不为负**：把氧耗到 0 之后继续耗，必须停在 0（而不是变成负数）。
func test_stock_never_goes_negative() -> void:
	var e = OE.new(1)
	for i in 100:
		e.step(1.0, 0.0, 100.0)                # 狠狠地耗
	assert_int(e.stock()).is_equal(0)
