class_name DepthLayers
extends RefCounted
## C1 · 深度分层与通量阶梯 —— **本轮只做【T1 义务】：表层通量天花板**
##
## ⚠️⚠️ **本轮的边界（不许读成"C1 做完了"）**：
##   ✅ 已做：**⑤ 表层通量天花板**（公式 ⑥）—— Risk #8 指定的 **T1 义务**
##   ❌ 未做（**属 T3**）：① 带宽(d) · ② 速度(d) · ③ 许用通量(d) · ④ 耗氧(d) · ④' 光(d) ·
##      4 段命名 · 海底深度 · 一维轴上的 depth 属性。
##      它们**一条都没实现** —— 本文件只是把那条**义务**先做出来。
##
## 【它为什么是 T1 义务，而不是 T3 的顺带】
##   Risk #8 原话：「『深海是必须项』在 MVP 里完全不成立 —— MVP 刻意只在最浅层…
##   → 计划：**从 T1 垂直切片起就必须把『表层通量天花板』做出来**（让玩家真的感到海水不够用），
##   **否则『必须下潜』在体感上不存在，P4 会退化成一句设定**。」
##
## 【它是什么】
##   `depth-layers.md` 公式 ⑥：`海水提取的通量上限（固定） -> 靠海水永远无法把产能放大到后期规模`
##   ⇒ 它是**一个数**，作用在**海水提取的总量**上 —— **不是每台泵各自一个上限**。
##      （这一条是本文件最要紧的语义：若做成"每台泵各自封顶"，那么**多接几台泵就能线性放大产能**，
##        天花板就等于不存在，而"必须下潜"又退化成了设定。）
##
## 【它不是什么】
##   工艺参数 P 属 **A1/A6** · 矿脉开采属 **C2** · 程序生成属 **C4** · 深度可读性的画面属 **B14**。

## ★ 表层通量上限（单位：海水提取"份" / 秒）—— **暂定**。
##
## GDD 的 §Tuning Knobs 写着 `待定`，而它真正的值**要靠手感定** ⇒ 先取一个"**会咬住**"的数：
## T1 现在的总请求是 5.2 份/秒（水 3.7 + 盐 1.0 + CaCl₂ 0.5）⇒ 取 3.0 会让它**真的咬住**。
## ⚠️ 与 B4 那四个数同一条纪律：**它是"先让它能跑"，不是"设计结论"。**
## 而它的手感对照物是 **B4 的生命维持耗氧率** —— 两个数要一起调，单独调任何一个都没有意义。
const SURFACE_THROUGHPUT_CAP := 3.0

## 暂定值的来源要写下来，否则下一个人会把 3.0 当成设计结论
const SURFACE_CAP_IS_PROVISIONAL := true


## 把一组"请求"按天花板裁剪，返回**与请求同长**的授予量数组，且 **总和 <= cap**。
##
## ★ 超限时用 **按比例公平分配** —— 与 A3 的「层内公平分配」**同一口径**
##   （`reaction-solver.gd` 的闭式解：算共同比例、再各自乘它）。为什么沿用而不是另立：
##   ① 那是本项目**已经验证过**的语义（A3 为此有专门的回归测试）；
##   ② 它是**确定性**的（同一组请求永远给同一组授予）—— A2/A3/A5 都要求这一条；
##   ③ 它**不引入新旋钮**（"按优先级分"就要新增一个旋钮，而旋钮的权威定义在 A1）。
##
## ★ 未超限时**一分不让** —— 天花板不是"总是按比例扣"（那会把"没到顶"也变成惩罚）。
static func clamp_surface_intake(requested: Array,
		cap: float = SURFACE_THROUGHPUT_CAP) -> Array:
	var total := 0.0
	for r in requested:
		total += maxf(float(r), 0.0)
	var out: Array = []
	if total <= cap or total <= 0.0:
		for r in requested:
			out.append(maxf(float(r), 0.0))
		return out
	var f: float = cap / total
	for r in requested:
		out.append(maxf(float(r), 0.0) * f)
	return out


## 授予量之和（供调用方与日志用）。
static func total_of(grants: Array) -> float:
	var n := 0.0
	for g in grants:
		n += float(g)
	return n


## 是否咬住了（请求 > 上限）。**这是"体感"的可测形式**：
## 只有它长期为真，"海水不够用"才不是一句设定。
static func is_capped(requested: Array, cap: float = SURFACE_THROUGHPUT_CAP) -> bool:
	return total_of(requested) > cap
