extends GdUnitTestSuite
## A4 · Schema 双解释器与契约校验 —— 逐条对应 A4 的 Acceptance Criteria
##
## ⚠️ **本系统的验收性质与别的系统不同，这决定了本文件长什么样**：
##   A1 验的是「守恒对不对」，而 **A4 验的是「校验器抓不抓得住」**。
##   ⇒ 所以本文件里最重要的断言**不是**"它通过了"，而是**"它该失败时真的失败"**。
##   A4 的 GDD 原话：「**一个"无论事实如何都会通过"的检查不算检查**」。
##
## 另一条纪律（本项目已实测到过教训）：**"测试通过"不等于"测试测到了东西"** ——
##   所以 §「校验器能失败吗」那一节是**配对的证据**，不是装饰。

const ET := preload("res://data/element_table.tres")
const CT := preload("res://data/reactions.tres")
const CD := preload("res://scripts/compound_data.gd")

## 指纹长度是**两侧契约的一部分**，所以钉在这里而不是散在各处。
const FINGERPRINT_HEX_LEN := 16


# ============================================================ 验收 6：指纹漂移（A4 最危险的洞）

## ★ Core Rule ⑦ + 验收 6：**版本号相同、而 schema 内容变了** -> 必须拒绝。
##
## 为什么这条是本系统最该钉住的：那时的失败形态是「**看起来正常**」——
## 版本检查通过、迁移不跑、数据被静默地按新 schema 解读。
## 指纹是"人可能忘、而数据自己不会忘"的那一份证据。
func test_same_version_but_different_content_fingerprint_is_rejected() -> void:
	var errs := SchemaContract.check_head(SchemaContract.SCHEMA_VERSION, "0000000000000000")
	assert_int(errs.size()).is_greater(0)
	assert_bool(" ".join(errs).contains("指纹")).is_true()


func test_matching_version_and_fingerprint_passes() -> void:
	assert_array(SchemaContract.check_head(
		SchemaContract.SCHEMA_VERSION, SchemaContract.SCHEMA_FINGERPRINT)).is_empty()


# ============================================================ §Edge Cases：不得猜版本

## ★ A4 §Edge Cases：「schema 版本号**缺失** → 拒绝载入（**不得当成 `v1` 猜** —— 猜错会静默损坏数据）」
func test_missing_version_is_rejected_not_silently_assumed_to_be_v1() -> void:
	var errs := SchemaContract.check_head(0, SchemaContract.SCHEMA_FINGERPRINT)
	assert_int(errs.size()).is_greater(0)
	assert_bool(" ".join(errs).contains("没有声明")).is_true()


func test_wrong_version_is_rejected() -> void:
	var errs := SchemaContract.check_head(
		SchemaContract.SCHEMA_VERSION + 1, SchemaContract.SCHEMA_FINGERPRINT)
	assert_int(errs.size()).is_greater(0)


## 报告**全部**不符项，而不是第一项就中断 —— 否则排错会变成挤牙膏。
func test_both_mismatches_are_reported_together() -> void:
	var errs := SchemaContract.check_head(SchemaContract.SCHEMA_VERSION + 1, "ffffffffffffffff")
	assert_int(errs.size()).is_equal(2)


## ★ A1 / A2 的 `validate()` 只管「**缺**没缺」，"对不对"由 A4 的契约头管。
##   这条钉的是那个切分本身：漏了版本号的表必须在**自己家**先被拦下。
func test_a_table_without_a_version_or_fingerprint_is_rejected_by_a2s_own_validate() -> void:
	var d = CD.new()
	# 故意不设 schema_version / schema_fingerprint —— 它们现在的默认值是"缺失"哨兵（0 / ""）
	var joined := " ".join(d.validate())
	assert_bool(joined.contains("没有声明 schema 版本号")).is_true()
	assert_bool(joined.contains("指纹")).is_true()


# ============================================================ 验收 5：对称覆盖

## ★ A2 的契约：「不得假设**只有元素表**需要版本化」。
##   而落地前实测的现状恰好相反：**偏偏是元素表一个版本字段都没有**。
func test_contract_covers_three_tables_not_just_the_element_table() -> void:
	for t: String in ["element_table", "compound_table", "param_schema"]:
		assert_bool(SchemaContract.TABLE_FIELDS.has(t)).is_true()


## 两张**数据表**都必须声明「版本 + 指纹」这两个字段 —— 少一个，"轻量检查"就有一半是空的。
func test_every_data_table_declares_version_and_fingerprint() -> void:
	for t: String in ["element_table", "compound_table"]:
		var names: Array = SchemaContract.TABLE_FIELDS[t]
		assert_bool(names.has("schema_version")).is_true()
		assert_bool(names.has("schema_fingerprint")).is_true()


## 「步骤 schema 同样被覆盖」不能只是一句话：记录形状必须在契约里写着。
func test_step_and_condition_records_are_declared() -> void:
	for r: String in ["step_record", "condition_record"]:
		assert_bool(SchemaContract.RECORD_FIELDS.has(r)).is_true()


## ★ A2 的 ⑦：条件只**引用** A1 的 `param_*`，**不得另立定义**。
func test_knob_names_are_the_declared_param_star_set() -> void:
	assert_int(SchemaContract.KNOB_NAMES.size()).is_greater(0)
	for n: String in SchemaContract.KNOB_NAMES:
		assert_bool(n.begins_with("param_")).is_true()


# ============================================================ 已入库的数据确实盖了章

## 这两条同时钉住两件事：**数据文件盖了章** 与 **契约头是当前那一版**。
## 若有人改了 YAML 却没重新给数据盖章，这两条会红 —— 那正是我们要的。
func test_committed_element_table_passes_the_lightweight_check() -> void:
	assert_array(SchemaContract.check_head(
		ET.schema_version, ET.schema_fingerprint)).is_empty()


func test_committed_reactions_table_passes_the_lightweight_check() -> void:
	assert_array(SchemaContract.check_head(
		CT.schema_version, CT.schema_fingerprint)).is_empty()


## 元素表自己的 `validate()` 也要过 —— 它现在含「必须有版本号 + 指纹」两条硬前置。
func test_committed_element_table_has_no_validation_errors() -> void:
	assert_array(ET.validate()).is_empty()


## 长度是**两侧契约的一部分**：各自取一段会各自"看起来对"。
func test_fingerprint_length_is_pinned() -> void:
	assert_int(SchemaContract.SCHEMA_FINGERPRINT.length()).is_equal(FINGERPRINT_HEX_LEN)


# ============================================================ 校验器能失败吗（验收 1 的味道）

## ★ 这一条的存在理由：本文件上面所有"通过"的断言，都必须有一条**配对的失败证据**。
##   做法：把指纹**只改一个字符**（其余全对）—— 一个真在比对的检查必须报错，
##   而一个"无论如何都返回空"的假检查会在这里现形。
func test_the_checker_actually_fails_on_a_minimal_one_character_drift() -> void:
	var drifted := SchemaContract.SCHEMA_FINGERPRINT
	var first := drifted.substr(0, 1)
	# 把它换成一个**不同**的 hex 字符
	var flipped := ("0" if first != "0" else "1") + drifted.substr(1, drifted.length() - 1)
	assert_str(flipped).is_not_equal(drifted)          # 先证明"确实改动了"
	var errs := SchemaContract.check_head(SchemaContract.SCHEMA_VERSION, flipped)
	assert_int(errs.size()).is_greater(0)              # 再证明"检查真的抓到了"


## ★ 同样地：**版本检查也要能失败**（别只测指纹那半边）。
func test_the_checker_actually_fails_on_a_one_step_version_drift() -> void:
	var errs := SchemaContract.check_head(
		SchemaContract.SCHEMA_VERSION + 1, SchemaContract.SCHEMA_FINGERPRINT)
	assert_int(errs.size()).is_greater(0)


# ============================================================ 真相源的位置是可追的

## 报错信息里必须指得出真相源 —— 否则"契约不符"是一句没有落点的话。
func test_source_path_points_at_the_truth_source() -> void:
	assert_str(SchemaContract.SOURCE_PATH).is_equal("design/schema/contract.yaml")
