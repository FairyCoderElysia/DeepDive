class_name Tank
extends RefCounted
## B6 · 储罐与容量 —— **装得下多少、装的是什么、取出时按什么比例**
##
## ⚠️ **三条接缝已经划好，不得越界**（`tanks-capacity.md` §Overview ③）：
##   **B6（本类）**：装得下多少（罐容上限、单位、装的是什么）
##   **B4 氧气经济**：存贮的**持续耗氧率**（它是速率，属 B4）—— 本类只提供"当前存储量"
##   **A5 工艺图**：**"装不下时怎么办"** —— 走它的阻塞语义（上游阻塞 + 告警，**绝不丢弃**）
##
## ⚠️⚠️ **本类最要紧的一条（F-B6-1）：罐子 = 池的一个【有界子集】，不是"池之外的地方"。**
##
##   A1 的守恒判定式 `T_end(e) = 池(e) + 在途(e) + 机器内已整数量(e)` **没有"罐内存量"这一项**。
##   若罐子被做成"池之外的地方"：
##     · **存进去** → 池里原子少一批、而 `T_end` 没有对应项 → **误报"不守恒"**
##     · **取出来** → 反过来 → **物质凭空出现**
##   而 A1 的规则 ⑤ 是「对账失败 → 拒绝该动作 + **锁**」
##     ⇒ **整个工厂会在玩家第一次存料时锁死**（这比"算错"严重得多）。
##
##   ⇒ 所以：**存入 / 取出只是池【内部】的移动**（从"流动的化合物账"移到"罐的化合物账"），
##     **A1 的元素池一个原子都不动** ⇒ 守恒自动成立。本类的 `put`/`take` **不碰元素池**。
##
## ⚠️ **罐内表示必须是「化合物 → 数量」，不是元素池**（Core Rule ①）：
##   A1 的池记的是 `{元素: 数量}` —— **它不记化合物**。
##   若罐子也用元素池，那么「把水存进去、再取出来」就**只剩氢氧原子、没有水了**
##   ⇒ 产物身份被丢掉。**这正是本文档存在的理由**（验收 3）。

## 罐的容量（单位：**原子总数**）—— 三档**暂定**值（GDD §Tuning Knobs 写"待定"）。
## ★ 用原子总数计容的好处：**不引入新量纲**（不要求 A2 补"分子体积"）。
const SIZE_SMALL := 200
const SIZE_MEDIUM := 1000
const SIZE_LARGE := 5000
const SIZES_ARE_PROVISIONAL := true

## 罐容（原子）
var capacity: int = 0
## 罐内表示：**化合物 key -> 整数数量**（不是元素池！见文件头）
var _contents: Dictionary = {}
## 取出时的**余数**（化合物 key -> 数量 ×SCALE）—— 与 A1/A3/A5 同一条纪律：
## **速率/比例攒够一个才动账，余量留下**，不得每 tick 丢小数。
var _residual: Dictionary = {}


func _init(capacity_atoms: int = SIZE_MEDIUM) -> void:
	capacity = maxi(capacity_atoms, 0)


# ---------------------------------------------------------------- 容量（公式 ①②）

## 罐内每种化合物的原子数（单个）。
static func _atoms_per_unit(key: String) -> int:
	return int(CompoundData.total_atoms_of({key: 1}))


## **占用**（公式 ①）：`Σ_{罐内化合物 c} 数量(c) × 原子数(c)`
## ★ 注意它是**跨化合物求和** —— 这正是"允许混装"在数值上的含义。
func occupied() -> int:
	var n := 0
	for k: String in _contents:
		n += int(_contents[k]) * _atoms_per_unit(k)
	return n


func remaining() -> int:
	return maxi(capacity - occupied(), 0)


func is_full() -> bool:
	return remaining() <= 0


func is_empty() -> bool:
	return occupied() <= 0


## 罐内化合物的**副本**（化合物 -> 数量）。**取出的是化合物，不是它的元素**（验收 3）。
func contents() -> Dictionary:
	return _contents.duplicate()


# ---------------------------------------------------------------- 存入

## 存入 `{化合物 key -> 数量}`。**返回【没存进去的那部分】**（装不下就交回来）。
##
## ★ 为什么返回余量而不是"报错"或"静默丢弃"：
##   **"装不下怎么办"属 A5 的阻塞语义**（规则 ⑤）—— 本类只负责"装得下多少"。
##   把**没装下的原样交回**，调用方才有依据去**阻塞上游**而不是丢弃。
##   （与 A1 的"饱和 → 上游阻塞"是同一条语义。）
func put(counts: Dictionary) -> Dictionary:
	var left := {}
	for k: String in counts:
		var want := int(counts[k])
		if want <= 0:
			continue
		var per := _atoms_per_unit(k)
		var room_units := 0
		if per > 0:
			room_units = remaining() / per          # 向零取整：只会少装、绝不超装
		var got := mini(want, room_units)
		if got > 0:
			_contents[k] = int(_contents.get(k, 0)) + got
		if want > got:
			left[k] = want - got
	return left


# ---------------------------------------------------------------- 取出（公式 ②）

## 按**原子数**取出，且**按罐内组成比例**（混装物流取出时不能只挑一种）。
##
## 公式（把 GDD 的 ② 写成一般形式）：对每种化合物 c，
##   `取出的原子数(c) = k × 原子数(c) / 占用`
##   `取出的数量(c)   = 取出的原子数(c) / 该化合物的原子数`
## ⇒ **罐内只有一种化合物时自然退化为"取出纯物质"**，不需要特例。
##
## ★ 整数量化走**余数累加器**（A1 的纪律）：比例一般是分数，
##   **攒够一个才动账、余量留下** —— 否则每次取出都丢一点，罐子会凭空少料。
## 返回实际取出的 `{化合物 -> 数量}`（**已从罐里扣掉**）。
func take_atoms(k: int) -> Dictionary:
	var out := {}
	if k <= 0 or is_empty():
		return out
	var occ := occupied()
	if occ <= 0:
		return out
	var kk := mini(k, occ)                              # 不能取出比罐里还多
	var scale: int = ElementPool.SCALE
	var taken_atoms := 0
	for key: String in _contents.keys():
		var have := int(_contents[key])
		if have <= 0:
			continue
		var per := _atoms_per_unit(key)
		var atoms_c := have * per
		# 取出的【原子数】按组成比例；再折回【数量】（单位 = 化合物个数）
		var take_atoms_c := float(kk) * float(atoms_c) / float(occ)
		var take_units := take_atoms_c / float(per)
		# ★ 余数累加器：把这一次的分数加进余量、取整数部分、**余数留下**
		var acc: int = int(_residual.get(key, 0)) + int(round(take_units * float(scale)))
		var whole := acc / scale
		_residual[key] = acc - whole * scale
		if whole > have:
			whole = have                                # 不能取超过罐里有的
		if whole > 0:
			out[key] = whole
			taken_atoms += whole * per
			var rest := have - whole
			if rest > 0:
				_contents[key] = rest
			else:
				_contents.erase(key)
	return out
