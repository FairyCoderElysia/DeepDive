class_name SchemaContract
extends RefCounted
## A4 · schema 契约的 **GDScript 侧契约头**。
##
## ⚠️⚠️ **本文件是生成物，不要手改。**⚠️⚠️
##   真相源： `design/schema/contract.yaml`
##   生成器： `python tools/gen_schema_contract.py`
##   改了真相源却没重新生成 -> `python tools/gen_schema_contract.py --check` 会 exit 1。
##   （"生成物入库 + 一条一致性检查"是为了让"忘了重新生成"从"靠自觉"变成"过不去"。）
##
## 它为什么只装这么点东西：Core Rule ② 定了**运行时只做轻量版本检查**、
## 完整校验**离线**做。把完整校验放进运行时 = 把开发期问题的代价推给玩家（启动变慢），
## 而拦住的东西本不该发生。所以这里只有：版本号 · 内容指纹 · 给开发期测试用的字段名清单。
##
## 为什么 GDScript 侧不直接读 YAML：**Godot 没有 YAML**（本机实测）
##   `ClassDB.class_exists("YAML")` -> false
##   `JSON.parse_string(<YAML>)`    -> null
##   `ConfigFile.parse(<YAML>)`     -> err = 0  ← ⚠️ 返回"成功"但语义全错（把 `- id: a` 当键名）
## 所以真相源的翻译在**开发期**由 Python 完成，运行时零 YAML 依赖。


## 真相源里的 `version`（全局一个 —— 见 A4 §States and Transitions）
const SCHEMA_VERSION := 1

## **内容指纹**（Core Rule ⑦）：真相源的规范化摘要。
## 它与版本号**一起**比：人可能忘了升版本号，指纹不会。
const SCHEMA_FINGERPRINT := "6db0c6fc2fea2c7c"

## 真相源路径（报错信息里要指得出它）
const SOURCE_PATH := "design/schema/contract.yaml"


# ---------------------------------------------------------------- 期望值（开发期用）
## 表名 -> 字段名（**升序**，与 Python 侧同源同序）。
## ⚠️ 它**不**供运行时校验用 —— 完整校验在离线侧。
const TABLE_FIELDS := {
	"compound_table": [
		"schema_fingerprint",
		"schema_version",
		"steps"
	],
	"element_table": [
		"elements",
		"schema_fingerprint",
		"schema_version"
	],
	"param_schema": []
}

## 记录名 -> 字段名（升序）。
const RECORD_FIELDS := {
	"condition_record": [
		"alt",
		"brk_hi",
		"brk_lo",
		"coef_hi",
		"coef_lo",
		"opt_hi",
		"opt_lo",
		"param"
	],
	"step_record": [
		"conditions",
		"disaster",
		"id",
		"inputs",
		"outputs"
	]
}

## A1 的 5 个工艺旋钮 —— **完整规格**（名字 -> {kind, 单位, 范围/选项, 默认值}）。
##
## ★ 权威在【登记册】`design/registry/entities.yaml` 的 `param_*`（A2 的 ⑦：只引用、不另立定义）。
##   本表与登记册的一致性由 `python tools/gen_schema_contract.py --check` 逐字段验证 ——
##   所以"两处定义"这件事在结构上被钉住了（A6 的验收 4 要的正是它）。
const KNOBS := {
	"param_anode_material": {
		"default": "铱钽涂层钛_析氧型",
		"kind": "enum",
		"options": [
			"石墨阳极",
			"钌铱涂层钛_析氯型",
			"铱钽涂层钛_析氧型"
		],
		"unit": "枚举 3"
	},
	"param_catalyst": {
		"default": "铂片",
		"kind": "enum",
		"options": [
			"无催化剂",
			"镍网",
			"铂片"
		],
		"unit": "枚举 3"
	},
	"param_pressure": {
		"default": 6,
		"kind": "continuous",
		"max": 40,
		"min": 1,
		"unit": "atm"
	},
	"param_residence_time": {
		"default": 4.0,
		"kind": "continuous",
		"max": 15,
		"min": 0.5,
		"unit": "相对"
	},
	"param_temperature": {
		"default": 80,
		"kind": "continuous",
		"max": 200,
		"min": 20,
		"unit": "°C"
	}
}


# ---------------------------------------------------------------- 轻量检查
## Core Rule ②：**运行时唯一把关的地方** —— 一份数据自称按哪一版写的，
## 与本内核认的那一版是否**同时**在版本号与指纹上一致。
##
## 返回错误列表（空 = 通过）。**调用方负责拒绝载入** —— 本函数不抛异常，
## 因为它要能报告**全部**不符项，而不是第一项就中断（那会让排错变成挤牙膏）。
static func check_head(data_version: int, data_fingerprint: String) -> Array:
	var errors: Array = []
	# ★ §Edge Cases：「schema 版本号【缺失】→ 拒绝载入（不得当成 v1 猜）」
	#   ⇒ 所以 0 是"无版本"的哨兵，不是"版本 0"。
	if data_version <= 0:
		errors.append("数据没有声明 schema 版本号（读到的值是 %d）—— 拒绝载入：猜一版会静默损坏数据" % data_version)
	elif data_version != SCHEMA_VERSION:
		errors.append("schema 版本不匹配：数据是 v%d，本内核认 v%d" % [data_version, SCHEMA_VERSION])
	if data_fingerprint != SCHEMA_FINGERPRINT:
		# 这一条独立于版本号，是为了抓 Core Rule ⑦ 那个最危险的洞：
		# **改了 schema 却忘了升版本号** —— 版本检查会通过、迁移不会跑，
		# 数据会被静默地按新 schema 解读。**指纹不会忘。**
		errors.append("schema 内容指纹不符：数据是 \"%s\"，本内核是 \"%s\" —— 这说明 schema 改过（即使版本号相同）" % [data_fingerprint, SCHEMA_FINGERPRINT])
	return errors
