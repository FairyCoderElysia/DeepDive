#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A4 · Schema 契约生成器 —— 把【唯一真相源】翻译成 GDScript 侧的契约头。

════════════════════════════════════════════════════════════════════════════
它为什么存在（Core Rule ①）
════════════════════════════════════════════════════════════════════════════
A4 的真相源是 `design/schema/contract.yaml`。但**实测（Godot 4.7.2）Godot 没有 YAML**：

    ClassDB.class_exists("YAML")            -> false
    JSON.parse_string(<一份 YAML>)          -> null（报 Parse failed）
    ConfigFile.parse(<同一份 YAML>)          -> err = 0  ← ⚠️ 返回"成功"！

最后一行才是危险的：`ConfigFile` 是 INI 风格，它把 `- id: a` 当成**键名 `- id`**、
返回成功而结构与 YAML 语义完全不同。**又一条"看起来正常"的失败形态。**

⇒ 所以 GDScript 侧**不解析 YAML**：这个脚本在**开发期**读 YAML，
产出 `scripts/generated/schema_contract.gd`（版本号 + 内容指纹 + 字段名清单）。
运行时不碰 YAML、不需要 YAML 依赖 —— 与 Core Rule ②「运行时只做轻量版本检查」一致。

用户拍板的正是这条（三选一里的第一项）：**「YAML 真相源 + 开发期生成轻量契约头」**。

════════════════════════════════════════════════════════════════════════════
两条纪律
════════════════════════════════════════════════════════════════════════════
1. **生成物必须入库**。否则新克隆/clone 出来的仓库跑不了测试。
   而"入库"就带来一个风险：**有人改了 YAML、忘了重新生成**。
   ⇒ 所以本脚本带 `--check`：它重新生成一遍、与磁盘上的比，**不一致就 exit 1**。
      把这条挂进构建/CI，那个风险就从"靠自觉"变成"过不去"。

2. **内容指纹（Core Rule ⑦）覆盖的是「本文件 ↔ 数据文件」，不是「GDD ↔ 本文件」。**
   指纹算的是本 YAML 的规范化摘要；数据文件（.tres）里记着它们按哪一版写的。
   ⇒ 改了 schema 却忘了升版本号：指纹会变 ⇒ 数据文件对不上 ⇒ **拒绝载入**。
   ⇒ 但"GDD 改了、YAML 没跟上"**抓不到** —— 那是已知边界，不假装它不存在。

════════════════════════════════════════════════════════════════════════════
用法
════════════════════════════════════════════════════════════════════════════
    python tools/gen_schema_contract.py            # 生成（写盘）
    python tools/gen_schema_contract.py --check    # 只校验生成物是不是最新的
    python tools/gen_schema_contract.py --print-fingerprint   # 只打印指纹（给数据文件盖章用）
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - 环境问题，不是逻辑问题
    print("需要 PyYAML： pip install pyyaml", file=sys.stderr)
    raise SystemExit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE = REPO_ROOT / "design" / "schema" / "contract.yaml"
GENERATED = REPO_ROOT / "scripts" / "generated" / "schema_contract.gd"
# A6 的验收 4（不重定义测试）要的是"旋钮必须与登记册逐字段一致" ——
# 而登记册开篇自称【跨系统事实的权威来源】⇒ 权威在登记册，契约必须与它一致。
REGISTRY = REPO_ROOT / "design" / "registry" / "entities.yaml"

# 本机（Windows 中文环境）控制台默认是 cp936，而本脚本的消息里全是中文 ——
# 不显式改编码的话，消息会变成一串问号，排错时等于没有消息。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")   # type: ignore[attr-defined]
    except (AttributeError, ValueError):        # pragma: no cover
        pass

# 指纹取前 16 个 hex 字符（64 bit）。它只需要"能区分版本"，不需要抗碰撞攻击 ——
# 这是**数据损坏检测**，不是安全边界。写明长度是为了让两侧不会各取一段。
FINGERPRINT_HEX_LEN = 16


# ---------------------------------------------------------------- 读取与规范化

def load_contract() -> dict:
    """读真相源，并做【最小】自检（形状自检，不是数据校验）。"""
    if not SOURCE.exists():
        raise SystemExit(f"找不到真相源：{SOURCE}")

    with io.open(SOURCE, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    if not isinstance(data, dict):
        raise SystemExit("真相源的顶层必须是一个映射（mapping）")

    # 版本号必须是 >= 1 的整数。0 保留给"无版本"（= 缺失），所以不许用它。
    version = data.get("version")
    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        raise SystemExit(f"version 必须是 >= 1 的整数，实际是 {version!r}")

    if not isinstance(data.get("tables"), dict) or not data["tables"]:
        raise SystemExit("tables 必须是一个非空映射")

    # 空表与缺键必须能区分（A2 的写法先例）：migrations 必须**存在**。
    if "migrations" not in data:
        raise SystemExit("migrations 必须存在（初版也要写 `{}` —— 空表是判断，缺键是没想）")

    return data


def canonical_bytes(contract: dict) -> bytes:
    """规范化序列化 —— 指纹的输入必须是**唯一确定**的一串字节。

    ★ 为什么不能用原始文件字节：YAML 允许注释/缩进/键序的等价写法，
      用原始字节的话"只加一行注释"也会改指纹 ⇒ 指纹会因无关改动而失效，
      于是迁移被无谓地触发。**指纹该覆盖的是语义，不是排版。**
    """
    text = json.dumps(contract, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"))
    return text.encode("utf-8")


def fingerprint(contract: dict) -> str:
    return hashlib.sha256(canonical_bytes(contract)).hexdigest()[:FINGERPRINT_HEX_LEN]


# ---------------------------------------------------------------- 生成

def collect_field_names(contract: dict) -> tuple[dict, dict]:
    """抽出"哪张表有哪些字段"与"哪条记录有哪些字段" —— 给开发期的测试用。

    运行时**不用**这些（Core Rule ②：运行时只做轻量版本检查，完整校验离线）。
    它们进生成物是为了让 gdUnit 侧的测试能拿**与 Python 侧同源**的期望值去比 ——
    这正是"两侧不漂移"的可执行形式。
    """
    tables: dict[str, list[str]] = {}
    records: dict[str, list[str]] = {}

    for tname, tspec in contract["tables"].items():
        names = [f["name"] for f in tspec.get("fields", [])]
        tables[str(tname)] = sorted(names)
        for rname, rspec in (tspec.get("records") or {}).items():
            records[str(rname)] = sorted(f["name"] for f in rspec.get("fields", []))

    return tables, records


def collect_knobs(contract: dict) -> dict:
    """契约里声明的 5 个旋钮 —— **完整规格**（名字 -> 规格）。

    ★ 为什么要有这个（A6 的验收 4「不重定义测试」）：
      「有哪些旋钮、各自范围与单位」这份 schema 的**权威在 A1**（登记册的 `param_*`），
      而 A6 只**引用与表达**。本函数把它从真相源里取出来，供 GDScript 侧读 ——
      然后 `compare_knobs()` 负责证明**它与登记册逐字段一致**（而不是各写一遍）。
    """
    spec = contract["tables"].get("param_schema") or {}
    out: dict = {}
    for k in spec.get("knobs", []):
        out[k["name"]] = {kk: vv for kk, vv in k.items() if kk != "name"}
    return dict(sorted(out.items()))


def _num_eq(a, b) -> bool:
    """数字比较：20 与 20.0 必须算相等（YAML 里一个是 int 一个是 float）。"""
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) < 1e-9
    return a == b


def load_registry_knobs() -> dict:
    """登记册里的 `param_*` —— **它是权威**。"""
    if not REGISTRY.exists():
        raise SystemExit(f"找不到登记册：{REGISTRY}")
    with io.open(REGISTRY, "r", encoding="utf-8") as fh:
        reg = yaml.safe_load(fh)
    out: dict = {}
    for c in reg.get("constants", []):
        name = str(c.get("name", ""))
        if not name.startswith("param_"):
            continue
        v = c.get("value") or {}
        spec: dict = {"unit": c.get("unit", "")}
        if isinstance(v, dict) and "options" in v:
            spec["kind"] = "enum"
            spec["options"] = list(v["options"])
            spec["default"] = v.get("default")
        else:
            spec["kind"] = "continuous"
            spec["min"] = v.get("min")
            spec["max"] = v.get("max")
            spec["default"] = v.get("default")
        out[name] = spec
    return dict(sorted(out.items()))


def compare_knobs(contract: dict, registry: dict) -> list[str]:
    """逐字段比：契约 vs 登记册。返回不符项（空 = 通过）。"""
    bad: list[str] = []
    mine = collect_knobs(contract)
    for name in sorted(set(mine) | set(registry)):
        if name not in mine:
            bad.append(f"{name}: 登记册有，契约里没有")
            continue
        if name not in registry:
            bad.append(f"{name}: 契约里有，登记册里没有（A6 的验收 4 要求逐字段一致）")
            continue
        a, b = mine[name], registry[name]
        for field in ("kind", "unit", "default", "min", "max"):
            if field in a or field in b:
                if not _num_eq(a.get(field), b.get(field)):
                    bad.append(f"{name}.{field}: 契约={a.get(field)!r} 登记册={b.get(field)!r}")
        if "options" in a or "options" in b:
            if list(a.get("options") or []) != list(b.get("options") or []):
                bad.append(f"{name}.options: 契约={a.get('options')!r} 登记册={b.get('options')!r}")
    return bad


def gdscript_literal(obj) -> str:
    """JSON 是 GDScript 字面量的子集（数组/字典/字符串/数字/true/false 写法一致）。"""
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, indent="\t")


def render(contract: dict) -> str:
    fp = fingerprint(contract)
    version = contract["version"]
    tables, records = collect_field_names(contract)
    knobs = collect_knobs(contract)

    return f'''class_name SchemaContract
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
const SCHEMA_VERSION := {version}

## **内容指纹**（Core Rule ⑦）：真相源的规范化摘要。
## 它与版本号**一起**比：人可能忘了升版本号，指纹不会。
const SCHEMA_FINGERPRINT := "{fp}"

## 真相源路径（报错信息里要指得出它）
const SOURCE_PATH := "design/schema/contract.yaml"


# ---------------------------------------------------------------- 期望值（开发期用）
## 表名 -> 字段名（**升序**，与 Python 侧同源同序）。
## ⚠️ 它**不**供运行时校验用 —— 完整校验在离线侧。
const TABLE_FIELDS := {gdscript_literal(tables)}

## 记录名 -> 字段名（升序）。
const RECORD_FIELDS := {gdscript_literal(records)}

## A1 的 5 个工艺旋钮 —— **完整规格**（名字 -> {{kind, 单位, 范围/选项, 默认值}}）。
##
## ★ 权威在【登记册】`design/registry/entities.yaml` 的 `param_*`（A2 的 ⑦：只引用、不另立定义）。
##   本表与登记册的一致性由 `python tools/gen_schema_contract.py --check` 逐字段验证 ——
##   所以"两处定义"这件事在结构上被钉住了（A6 的验收 4 要的正是它）。
const KNOBS := {gdscript_literal(knobs)}


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
		errors.append("schema 内容指纹不符：数据是 \\"%s\\"，本内核是 \\"%s\\" —— 这说明 schema 改过（即使版本号相同）" % [data_fingerprint, SCHEMA_FINGERPRINT])
	return errors
'''


# ---------------------------------------------------------------- 入口

def main() -> int:
    ap = argparse.ArgumentParser(description="A4 schema 契约生成器")
    ap.add_argument("--check", action="store_true",
                    help="只校验生成物是不是最新的（不一致则 exit 1）")
    ap.add_argument("--print-fingerprint", action="store_true",
                    help="只打印内容指纹（给数据文件盖章时用）")
    args = ap.parse_args()

    contract = load_contract()

    if args.print_fingerprint:
        print(fingerprint(contract))
        return 0

    rendered = render(contract)

    if args.check:
        # ★ 先跑【契约 ↔ 登记册】的逐字段交叉校验（A6 的验收 4）。
        #   放在生成物比对【之前】—— 因为它才是"真正的错处"；
        #   让它先报，报错就直接指着"哪一条旋钮的哪个字段不一致"。
        bad = compare_knobs(contract, load_registry_knobs())
        if bad:
            print("[schema-check] ❌ 契约里的旋钮与登记册不一致（A6 验收 4）", file=sys.stderr)
            for line in bad:
                print(f"  · {line}", file=sys.stderr)
            print(f"  契约：{SOURCE.relative_to(REPO_ROOT)}", file=sys.stderr)
            print(f"  权威：{REGISTRY.relative_to(REPO_ROOT)}（登记册自称【跨系统事实的权威来源】）", file=sys.stderr)
            return 1
        if not GENERATED.exists():
            print(f"[schema-check] 生成物不存在：{GENERATED.relative_to(REPO_ROOT)}", file=sys.stderr)
            print("[schema-check] 跑 `python tools/gen_schema_contract.py` 生成它", file=sys.stderr)
            return 1
        with io.open(GENERATED, "r", encoding="utf-8", newline="") as fh:
            on_disk = fh.read()
        if on_disk != rendered:
            print("[schema-check] ❌ 生成物与真相源不一致", file=sys.stderr)
            print(f"  真相源：{SOURCE.relative_to(REPO_ROOT)}", file=sys.stderr)
            print(f"  生成物：{GENERATED.relative_to(REPO_ROOT)}", file=sys.stderr)
            print("  ⇒ 跑 `python tools/gen_schema_contract.py` 重新生成它", file=sys.stderr)
            return 1
        print(f"[schema-check] OK · v{contract['version']} · 指纹 {fingerprint(contract)}")
        return 0

    GENERATED.parent.mkdir(parents=True, exist_ok=True)
    # newline="" + 显式 "\n"：生成物的换行必须是 LF，不能随平台变 ——
    # 否则 CI（Linux）与本地（Windows）会各生成一个"与对方不一致"的文件。
    with io.open(GENERATED, "w", encoding="utf-8", newline="") as fh:
        fh.write(rendered)

    print(f"[schema] 已生成 {GENERATED.relative_to(REPO_ROOT)}")
    print(f"[schema] v{contract['version']} · 指纹 {fingerprint(contract)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
