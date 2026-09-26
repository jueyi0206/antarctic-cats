class_name TrackBuilder
extends RefCounted
## 把 data/levels/stage-XX.json 的「配方」展開成實際賽道，並跑 docs 第 7 節的驗證器。
##
## 關卡檔只存權重 + seed + 釘死的橋段，這裡負責長出賽道。
## 同一個 seed 永遠長出同一條賽道 —— 可重現，才能調平衡。

var segments := {}          ## id -> segment 定義
var build_log: Array[String] = []

func load_segments(path := "res://data/segments.json") -> bool:
	if not FileAccess.file_exists(path):
		push_error("找不到 " + path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("segments.json 解析失敗")
		return false
	for s in parsed.get("segments", []):
		segments[s["id"]] = s
	return segments.size() > 0

func load_stage(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("找不到 " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## 展開關卡。回傳 { elements, widths, length, timeLimit, name, log }
func build(stage: Dictionary) -> Dictionary:
	build_log.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(stage.get("seed", 0))

	var length: float = float(stage.get("length", 6000))
	var rules: Dictionary = stage.get("rules", {})
	var max_diff: float = float(rules.get("maxDifficulty", 10))
	var valley_after: float = float(rules.get("valleyAfter", 5))
	var min_fish: int = int(rules.get("minFish", 0))
	var clear_tail: float = float(rules.get("clearTail", 600))
	var weights: Dictionary = stage.get("weights", {})

	# 釘死的橋段：距離 -> segment id
	var forced := {}
	for e in stage.get("forced", []):
		forced[float(e["at"])] = e["segment"]

	var placed: Array = []   # [{id, start, def}]
	var pos := 0.0
	var last_id := ""
	var last_def := {}
	var guard := 0

	while pos < length - clear_tail and guard < 2000:
		guard += 1
		var pick_id := ""

		# 1) 釘死的橋段優先。
		# 段落長度不一，pos 幾乎不會剛好落在指定的距離上，
		# 所以改成「跑過那個距離就馬上排進來」，指定 3600u 就是「3600u 之後的第一段」。
		var due := -1.0
		for at in forced.keys():
			if at <= pos + 0.5 and (due < 0.0 or at < due):
				due = at
		if due >= 0.0:
			pick_id = forced[due]
			forced.erase(due)

		# 2) 否則依權重抽，並套用組合規則
		if pick_id == "":
			pick_id = _weighted_pick(weights, rng, last_id, last_def, max_diff, valley_after)

		if pick_id == "" or not segments.has(pick_id):
			pick_id = "s_open"

		var def: Dictionary = segments[pick_id]

		# 規則 3：需要助跑的段落（crevasse），前一段必須是 runway
		var req: Dictionary = def.get("requires", {})
		if req.has("prevTags"):
			var ok := false
			for t in req["prevTags"]:
				if last_def.get("tags", []).has(t):
					ok = true
			if not ok:
				# 自動插入助跑區，而不是放棄這段 —— 對應驗證器「助跑距離」
				placed.append({"id": "s_open", "start": pos, "def": segments["s_open"]})
				build_log.append("· %d: %s 前插入助跑區" % [int(pos), pick_id])
				pos += float(segments["s_open"]["length"])
				last_def = segments["s_open"]
				last_id = "s_open"

		placed.append({"id": pick_id, "start": pos, "def": def})
		pos += float(def["length"])
		last_id = pick_id
		last_def = def

	# 規則 5：終點前強制淨空
	var tail_start := pos
	while pos < length:
		placed.append({"id": "s_open", "start": pos, "def": segments["s_open"]})
		pos += float(segments["s_open"]["length"])
	build_log.append("· 終點前淨空 %du" % int(pos - tail_start))

	var result := _flatten(placed, length)
	_vary_pickups(result, rng)

	# 規則 4：魚量不足就補（時間不夠就不是難，是不可能）
	var fish_count := 0
	for e in result.elements:
		if e.has("fish"):
			fish_count += 1
	if fish_count < min_fish:
		_sprinkle_fish(result, min_fish - fish_count, rng, length, clear_tail)
		build_log.append("· 跳魚池 %d < %d，補了 %d 個" % [fish_count, min_fish, min_fish - fish_count])
		fish_count = min_fish

	_validate(result, length)

	var diff_sum := 0.0
	var used: Array[String] = []
	for p in placed:
		diff_sum += float(p.def.get("difficulty", 0))
		used.append(p.id)
	result["fish_count"] = fish_count
	result["difficulty_sum"] = diff_sum
	result["segment_count"] = placed.size()
	result["segments_used"] = used
	result["length"] = length
	result["timeLimit"] = float(stage.get("timeLimit", 40))
	result["name"] = stage.get("name", "?")
	result["log"] = build_log.duplicate()
	return result


func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator, last_id: String,
		last_def: Dictionary, max_diff: float, valley_after: float) -> String:
	var pool: Array = []
	var total := 0.0
	var last_diff: float = float(last_def.get("difficulty", 0))
	# 規則 1：高難度段之後只能接難度 <=1（波谷法則）
	var force_valley := last_diff >= valley_after

	for id in weights.keys():
		if not segments.has(id):
			continue
		var def: Dictionary = segments[id]
		var d: float = float(def.get("difficulty", 0))
		if d > max_diff:
			continue
		if force_valley and d > 2.0:   # 波谷可以是彎道或旗門，不必永遠是空地
			continue
		if id == last_id:          # 規則 2：同一段不連兩次
			continue
		var w: float = float(weights[id])
		if w <= 0.0:
			continue
		pool.append([id, w])
		total += w

	if total <= 0.0:
		return "s_open"
	var r := rng.randf() * total
	for p in pool:
		r -= p[1]
		if r <= 0.0:
			return p[0]
	return pool[-1][0]


## 加分道具不要每次都左右對稱各一個。
##
## segment 裡寫的是「這裡有兩個」，但兩個永遠對稱地擺在路的兩邊，跑起來像一排路燈。
## 這裡照關卡 seed 重新排：有時候只留一個、有時候擺在路中間、有時候一左一右錯開。
## 只動加分道具 —— 障礙物的位置是難度設計的一部分，不能亂動。
func _vary_pickups(result: Dictionary, rng: RandomNumberGenerator) -> void:
	var groups := {}          # 同一個 x 的算同一組
	for e in result.elements:
		if e.type != "cheer" or e.get("fixed", false):
			continue        # 標了 fixed 的是設計好的隊形（第四關的之字形旗陣），不要打亂
		var key := int(e.d / 40.0)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(e)

	var drop := []
	for key in groups:
		var g: Array = groups[key]
		var half: float = maxf(_half_at(result.widths, float(g[0].d)) - 12.0, 10.0)
		var mode := rng.randi() % 5
		if g.size() >= 2 and mode == 0:
			# 只留一個，擺在隨便一邊
			drop.append(g[1])
			g[0]["off"] = rng.randf_range(0.35, 1.0) * half * (1.0 if rng.randf() < 0.5 else -1.0)
		elif g.size() >= 2 and mode == 1:
			# 併成一個擺正中間
			drop.append(g[1])
			g[0]["off"] = rng.randf_range(-0.12, 0.12) * half
		elif mode == 2:
			# 兩個都偏同一邊，前後錯開
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			for i in g.size():
				g[i]["off"] = side * half * rng.randf_range(0.3, 0.95)
				g[i]["d"] = float(g[i].d) + i * rng.randf_range(40.0, 90.0)
		elif mode == 3:
			# 一個靠邊、一個靠中間
			for i in g.size():
				var t: float = 0.9 if i == 0 else 0.25
				g[i]["off"] = half * t * (1.0 if rng.randf() < 0.5 else -1.0)
				g[i]["d"] = float(g[i].d) + i * rng.randf_range(30.0, 70.0)
		else:
			# 維持左右各一，但深淺和前後都抖一下
			for i in g.size():
				var side2: float = 1.0 if i % 2 == 0 else -1.0
				g[i]["off"] = side2 * half * rng.randf_range(0.45, 1.0)
				g[i]["d"] = float(g[i].d) + rng.randf_range(-35.0, 35.0)
	for e in drop:
		result.elements.erase(e)


## 把 segment 串攤平成世界座標的元素清單
func _flatten(placed: Array, length: float) -> Dictionary:
	var elements: Array = []
	var widths: Array = [[0.0, Cfg.track_width]]   # [距離, 賽道寬]
	var curves: Array = [[0.0, 0.0]]               # [距離, 中心線橫向位移]
	var centre := 0.0
	# 先把寬度變化掃出來，元素才知道自己該被夾在哪
	for p in placed:
		for e in p.def.get("elements", []):
			if e.get("type", "") == "track_width":
				widths.append([p.start + float(e.get("x", 0)), float(e.get("value", Cfg.track_width))])
	widths.sort_custom(func(a, b): return a[0] < b[0])

	for p in placed:
		var base: float = p.start
		centre += float(p.def.get("curve", 0))
		curves.append([base + float(p.def["length"]), centre])
		for e in p.def.get("elements", []):
			var t: String = e.get("type", "")
			var d: float = base + float(e.get("x", 0))
			if d > length:
				continue
			if t == "track_width":
				continue                       # 上面已經掃過了
			# 夾進賽道：旗竿留 24u 邊距、加油旗貼冰緣、洞不要有一半泡在海裡
			var half := _half_at(widths, d)
			var margin := 24.0
			if t == "cheer":
				margin = 12.0
			elif t.begins_with("hole"):
				margin = float(e.get("width", 60)) * 0.42
			var lim: float = maxf(half - margin, 0.0)
			var el := {
				"type": t,
				"d": d,
				"off": clampf(float(e.get("offset", 0)), -lim, lim),
				"w": float(e.get("width", 60)),
				"alive": true,
			}
			if e.has("seal"):
				el["seal"] = e["seal"]
			if e.has("fish"):
				el["fish"] = e["fish"]
			if e.get("fixed", false):
				el["fixed"] = true
			if t == "ice_block":
				el["speed"] = float(e.get("speed", 60))
				el["range"] = float(e.get("range", 120))
				el["base_off"] = el["off"]
			if t == "blizzard":
				el["len"] = float(e.get("length", 400))
				el["vis"] = float(e.get("visibility", 0.6))
				el["push"] = float(e.get("push", 40))
			if t == "crevasse":
				el["full"] = true
			elements.append(el)
	elements.sort_custom(func(a, b): return a.d < b.d)
	widths.sort_custom(func(a, b): return a[0] < b[0])
	curves.sort_custom(func(a, b): return a[0] < b[0])
	return {"elements": elements, "widths": widths, "curves": curves}


const WIDTH_BLEND := 150.0

func _half_at(widths: Array, d: float) -> float:
	## 與 Main.gd 的 _track_half_at 同一套漸進規則，兩邊算出來的邊界必須一致
	var w := Cfg.track_width
	var prev_w := w
	var at := -99999.0
	for pair in widths:
		if pair[0] <= d:
			prev_w = w
			w = pair[1]
			at = pair[0]
		else:
			break
	if at > -99998.0 and prev_w != w and d < at + WIDTH_BLEND:
		var t: float = (d - at) / WIDTH_BLEND
		return lerpf(prev_w, w, t * t * (3.0 - 2.0 * t)) * 0.5
	return w * 0.5


func _sprinkle_fish(result: Dictionary, n: int, rng: RandomNumberGenerator,
		length: float, clear_tail: float) -> void:
	# 需要跳的大缺口，前後都是保護區：前面 380u 給助跑，後面 320u 給落地。
	# 原本後方只留 30u，結果跳過裂縫落地就撞上補進來的洞。
	var keep_clear: Array = []
	for e in result.elements:
		if float(e.get("w", 0)) > Cfg.safe_gap():
			keep_clear.append([e.d - 380.0, e.d + 320.0])

	for i in n:
		var d := rng.randf_range(400.0, length - clear_tail)
		for attempt in 12:
			var ok := true
			for zone in keep_clear:
				if d > zone[0] and d < zone[1]:
					ok = false
					break
			if ok:
				break
			d = rng.randf_range(400.0, length - clear_tail)
		var lim: float = maxf(_half_at(result.widths, d) - 34.0, 0.0)
		result.elements.append({
			"type": "hole_s", "d": d,
			"off": rng.randf_range(-lim, lim),
			"w": 68.0, "alive": true,
			"fish": {"period": 2.2, "up": 1.1, "phase": rng.randf() * 2.2},
		})
	result.elements.sort_custom(func(a, b): return a.d < b.d)


## docs 第 7 節驗證器：不合格不是靜靜放過，是印在畫面上讓人看見
func _validate(result: Dictionary, length: float) -> void:
	var safe := Cfg.safe_gap()
	var hard := Cfg.max_gap()
	var problems := 0

	for e in result.elements:
		if e.type != "crevasse" and e.type != "hole_m" and e.type != "hole_s":
			continue
		if e.w <= safe:
			continue
		if e.w > hard:
			build_log.append("× %du 處缺口 %du > 全速可跳 %du —— 過不去" % [int(e.d), int(e.w), int(hard)])
			problems += 1
			continue
		# 需要助跑：檢查前方 350u 是否淨空
		var blocked := false
		for o in result.elements:
			if o == e or o.type == "fish" or o.type == "cheer" or o.type == "blizzard":
				continue
			if o.d < e.d and o.d > e.d - 350.0:
				blocked = true
				break
		if blocked:
			build_log.append("× %du 處缺口 %du 需助跑，但前方 350u 有障礙" % [int(e.d), int(e.w)])
			problems += 1

	# 大障礙之間要留距離：繞過一個之後，得有時間看清楚下一個該往哪邊繞。
	# 250u 在基礎速下只有一秒，玩家回報「梯形後面再接水窪」就是這個。
	var bigs: Array = []
	for e in result.elements:
		if float(e.get("w", 0)) >= 100.0:
			bigs.append(e)
	bigs.sort_custom(func(a, c): return a.d < c.d)
	for i in range(bigs.size() - 1):
		var gap: float = bigs[i + 1].d - bigs[i].d
		if gap > 12.0 and gap < 350.0:
			build_log.append("× %du 與 %du 兩個大障礙只隔 %du（要 350u）" %
				[int(bigs[i].d), int(bigs[i + 1].d), int(gap)])
			problems += 1

	# 洞會不會大到繞不過去？窄道（賽道只剩 120u）後面接一個 110u 的水窪，
	# 剩下的通道只有 10u —— 企鵝寬 26u，等於整條路被塞死。
	for e in result.elements:
		if not str(e.type).begins_with("hole"):
			continue
		var road: float = _half_at(result.widths, e.d) * 2.0
		if float(e.w) > road * 0.62:
			build_log.append("× %du 的 %s 寬 %du，佔賽道 %d%%，繞不過去" %
				[int(e.d), e.type, int(e.w), int(float(e.w) / road * 100.0)])
			problems += 1

	# 落地緩衝：跳完大缺口需要地方站穩，後方 300u 不該再有東西。
	# 這條是玩家回報「梯形後面又接水窪」之後補的。
	for e in result.elements:
		if float(e.get("w", 0)) <= Cfg.safe_gap():
			continue
		for o in result.elements:
			if o == e or o.type == "cheer" or o.type == "blizzard":
				continue
			if o.d > e.d + float(e.w) * 0.5 and o.d < e.d + 300.0:
				build_log.append("× %du 的 %du 缺口，落地後 %du 就撞上 %s" %
					[int(e.d), int(e.w), int(o.d - e.d), o.type])
				problems += 1
				break

	# 沒有東西該站在海裡 —— 這條規則是玩家回報「旗子插到海裡」之後補的
	var outside := 0
	for e in result.elements:
		var lim: float = _half_at(result.widths, e.d)
		if e.type == "crevasse":
			continue
		if abs(float(e.off)) > lim - 6.0:
			outside += 1
	if outside > 0:
		build_log.append("× 有 %d 個元素站在賽道邊界外" % outside)
		problems += outside

	build_log.append("驗證：%s（安全缺口 %du / 最大缺口 %du）" %
		["通過" if problems == 0 else "%d 項不合格" % problems, int(safe), int(hard)])
