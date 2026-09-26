extends Node
## 關卡驗證 —— headless 跑，不用開畫面。
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path antarctic ^
##     res://dev/validate.tscn
##
## 檢查 LEVELS.md 第 7 節的每一條，外加時間可行性 ——
## 也就是「這張關卡到底過不過得了」，在有人真的去玩之前先算出來。

## 熟練玩家的平均速度 = 基礎速 × 這個。
## 1.25（= 300u/s）是最早的紙上估計，但實際玩起來大家都是「一路按著加速」，
## 也就是接近全速 420u/s，只在彎道被限速壓下來。1.55 才對得上實測。
const CRUISE_MULT := 1.55
const MAX_TURN_RATE := 1.9   ## 與 Main.gd 同步

func _ready() -> void:
	var b := TrackBuilder.new()
	if not b.load_segments("res://data/segments.json"):
		printerr("segments.json 載入失敗")
		get_tree().quit(1)
		return

	print("\n════ 積木庫 ════")
	var ids := b.segments.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = b.segments[id]
		print("  %-16s 長 %4du  難度 %d  %s" %
			[id, int(s.length), int(s.difficulty), str(s.get("tags", []))])

	print("\n════ 跳躍推論（來自 Constants.gd）════")
	print("  基礎速 %d u/s → 可跳 %d u → 安全缺口上限 %d u" %
		[int(Cfg.speed_base), int(Cfg.jump_dist(Cfg.speed_base)), int(Cfg.safe_gap())])
	print("  全速   %d u/s → 可跳 %d u → 最大缺口上限 %d u" %
		[int(Cfg.speed_max), int(Cfg.jump_dist(Cfg.speed_max)), int(Cfg.max_gap())])

	var dir := DirAccess.open("res://data/levels")
	var files := []
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				files.append(f)
	files.sort()

	var bad := 0
	for f in files:
		bad += _check("res://data/levels/" + f, b)

	print("\n════ 總結 ════")
	if bad == 0:
		print("  全部關卡通過。")
	else:
		print("  %d 項不合格 —— 見上面標 ✗ 的行。" % bad)
	get_tree().quit(0)


func _check(path: String, b: TrackBuilder) -> int:
	var stage := b.load_stage(path)
	if stage.is_empty():
		printerr("讀不到 " + path)
		return 1
	var r := b.build(stage)
	var problems := 0

	# --- 元素統計 ---
	var count := {}
	for e in r.elements:
		count[e.type] = int(count.get(e.type, 0)) + 1
	var used := {}
	for id in r.segments_used:
		used[id] = int(used.get(id, 0)) + 1

	# --- 時間可行性 ---
	var cruise: float = Cfg.speed_base * CRUISE_MULT
	# 理想時間不能用「長度 ÷ 巡航速」——彎道會限速，急彎那幾段慢得多。
	# 沿賽道積分，每一小段用該處曲率允許的速度。
	var lap_len_probe: float = float(stage.get("lapLength", r.length))
	var laps_probe: int = int(stage.get("laps", 1))
	var probe := TrackPath.new()
	probe.build(int(stage.get("seed", 0)), lap_len_probe,
		str(stage.get("layout", "simple")), int(stage.get("prototype", -1)),
		float(stage.get("minRadius", 90.0)))
	var lap_time := 0.0
	var seg_len: float = probe.total / probe.SAMPLES
	for i in probe.SAMPLES:
		var v: float = minf(cruise, maxf(probe.radii[i] * MAX_TURN_RATE, Cfg.speed_min))
		lap_time += seg_len / v
	var ideal: float = lap_time * laps_probe
	var loss: float = r.difficulty_sum / 10.0     ## 難度的定義就是預期損失時間 ×10
	var fish_total: int = int(r.fish_count)       ## 魚是冰洞的屬性，不是獨立元素
	var gain: float = fish_total * Cfg.fish_time
	var slack: float = r.timeLimit - ideal - loss + gain

	# --- 迴圈幾何 ---
	var lap_len: float = float(stage.get("lapLength", r.length))
	var laps: int = int(stage.get("laps", 1))
	var loop := TrackPath.new()
	loop.build(int(stage.get("seed", 0)), lap_len, str(stage.get("layout", "simple")),
		int(stage.get("prototype", -1)), float(stage.get("minRadius", 90.0)))
	var half: float = Cfg.track_width * 0.5

	print("
──── %s（%s）────" % [stage.id, r.name])
	print("  一圈 %du × %d 圈 = %du　時限 %.0fs　段落 %d 塊　難度總和 %.0f" %
		[int(lap_len), laps, int(r.length), r.timeLimit, r.segment_count, r.difficulty_sum])
	print("  最小曲率半徑 %du（賽道半寬 %du）" % [int(loop.min_radius), int(half)])
	if loop.min_radius < half * 0.6:
		# 冰面是沿中心線掃出的圓串，急彎不會破圖；這裡只是提醒「這關有狠彎」
		print("  · 最急的彎只有半寬的 %.1f 倍 —— 會是全場最慢的點" %
			(loop.min_radius / half))

	print("  元素 %s" % str(count))
	print("  段落 %s" % str(used))
	print("  黃旗 %d 支（全拿 +%d 分）　躍魚池 %d 個（平均每 %du 一個）" %
		[int(count.get("cheer", 0)), int(count.get("cheer", 0)) * 50,
		 fish_total, int(r.length / maxf(fish_total, 1))])
	print("  理想跑完 %.1fs（巡航 %d u/s，已計入彎道限速；直線跑完要 %.1fs）" %
		[ideal, int(cruise), r.length / cruise])
	print("  預期損失 %.1fs　吃魚回補 %.1fs" % [loss, gain])

	for line in r.log:
		if line.begins_with("✗"):
			problems += 1
		if line.begins_with("✗") or line.begins_with("驗證"):
			print("  " + line)

	if slack < 0.0:
		print("  ✗ 時間餘裕 %.1fs —— 完美操作也過不了" % slack)
		problems += 1
	elif slack < 3.0:
		print("  ! 時間餘裕 %.1fs —— 幾乎不容許失誤，只該出現在最後一站" % slack)
	else:
		print("  ✓ 時間餘裕 %.1fs（可以撞 %d 次還過關）" % [slack, int(slack / Cfg.fall_penalty)])

	var target: float = float(stage.get("rules", {}).get("targetSlack", -1.0))
	if target > 0.0:
		print("  TUNE %s %.1f  (目標餘裕 %.1fs，現在 %.1fs)" %
			[stage.id, r.timeLimit + (target - slack), target, slack])

	# 助跑檢查的漏洞：原本只看「前方有沒有障礙」，沒看「前方跑不跑得快」。
	# 裂縫前若是彎道，彎道限速會讓玩家加速不到起跳所需的速度 —— 直接變成死關。
	for e in r.elements:
		var w: float = float(e.get("w", 0))
		if w <= Cfg.safe_gap():
			continue
		var need_speed: float = w / 0.8 / Cfg.jump_airtime
		var slowest := 99999.0
		var probe_d: float = e.d - 400.0
		while probe_d < e.d:
			var idx: int = int(fposmod(probe_d, lap_len_probe) / lap_len_probe * probe.SAMPLES)
			slowest = minf(slowest, probe.radii[idx % probe.SAMPLES] * MAX_TURN_RATE)
			probe_d += 40.0
		slowest = minf(slowest, Cfg.speed_max)
		if slowest < need_speed:
			print("  ✗ %du 處的 %du 缺口要 %d u/s 才跳得過，但助跑區被彎道限速在 %d u/s" %
				[int(e.d), int(w), int(need_speed), int(slowest)])
			problems += 1

	# 診斷：把挨得太近的障礙對列出來（跳過裝飾與純獎勵）
	# 常態診斷：把挨得近的障礙對列出來。規則只擋大障礙，
	# 小洞的密集排列（階梯、洞對）是設計內的，但人看一眼比較放心。
	if true:
		var hard: Array = []
		for e in r.elements:
			if e.type == "cheer" or e.type == "blizzard":
				continue
			if e.has("fish") and not e.has("seal"):
				continue
			hard.append(e)
		hard.sort_custom(func(a, c): return a.d < c.d)
		var tight: Array = []
		for i in range(hard.size() - 1):
			var gap: float = hard[i + 1].d - hard[i].d
			if gap > 12.0 and gap < 300.0:
				tight.append([hard[i], gap, hard[i + 1]])
		if not tight.is_empty():
			print("  ── 間距小於 300u 的障礙對（約 1.2 秒）──")
		for t in tight:
			print("     %du：%s(%du寬) → %du 後接 %s(%du寬)" %
				[int(t[0].d), t[0].type, int(t[0].w), int(t[1]),
				 t[2].type, int(t[2].w)])

	_spread_check(stage, b)

	# --- 三星（LEVELS.md 第 7 節）---
	print("  三星：3★ 零失誤且吃到 %d/%d 條魚　2★ 失誤 ≤2 且吃到 %d 條" %
		[int(ceil(fish_total * 0.8)), fish_total, int(ceil(fish_total * 0.5))])
	var clean_slack: float = r.timeLimit - ideal + fish_total * 0.8 * Cfg.fish_time
	if clean_slack < 0.0:
		print("  ✗ 零失誤也差 %.1fs 才夠 —— 3★ 不可能達成" % -clean_slack)
		problems += 1
	return problems


func _spread_check(stage: Dictionary, b: TrackBuilder) -> void:
	## 關卡是隨機長出來的，單一 seed 只是一個樣本。
	## 用 8 個 seed 跑同一份配方，看權重有給的積木是不是真的抽得到。
	var seen := {}
	var slack_min := 9999.0
	var slack_max := -9999.0
	var probe := stage.duplicate(true)
	for i in 8:
		probe["seed"] = 1000 + i * 7919
		var r := b.build(probe)
		for id in r.segments_used:
			seen[id] = int(seen.get(id, 0)) + 1
		var slack: float = r.timeLimit - r.length / (Cfg.speed_base * CRUISE_MULT) 			- r.difficulty_sum / 10.0 + r.fish_count * Cfg.fish_time
		slack_min = minf(slack_min, slack)
		slack_max = maxf(slack_max, slack)
	var never: Array = []
	for id in stage.get("weights", {}).keys():
		if float(stage.weights[id]) > 0.0 and not seen.has(id):
			never.append(id)
	print("  8 個 seed：餘裕 %.1f ~ %.1fs" % [slack_min, slack_max])
	if not never.is_empty():
		print("  ! 這些積木權重有給卻從來沒抽到：%s" % str(never))
