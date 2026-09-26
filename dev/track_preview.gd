extends Node
## 把每一關的賽道形狀畫成 PNG，存到 dev/preview/。
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path antarctic ^
##     res://dev/track_preview.tscn
##
## 賽道是隨機長出來的，光看數字（曲率半徑、周長）判斷不了「像不像賽車場」，
## 得真的畫出來看。

const W := 900
const H := 680
const MARGIN := 40.0


func _ready() -> void:
	# 自動掃描，新增關卡不用回來改這裡
	var found: Array[int] = []
	var dir := DirAccess.open("res://data/levels")
	if dir:
		for f in dir.get_files():
			if f.begins_with("stage-") and f.ends_with(".json"):
				found.append(int(f.substr(6, 2)))
	found.sort()
	for idx in found:
		var f := "res://data/levels/stage-%02d.json" % idx
		if not FileAccess.file_exists(f):
			continue
		var file := FileAccess.open(f, FileAccess.READ)
		var stage: Dictionary = JSON.parse_string(file.get_as_text())
		file.close()

		var lap: float = float(stage.get("lapLength", 4000))
		var track := TrackPath.new()
		track.build(int(stage.get("seed", 0)), lap, str(stage.get("layout", "simple")),
			int(stage.get("prototype", -1)), float(stage.get("minRadius", 90.0)))
		_render(track, "res://dev/preview/track_%02d.png" % idx, str(stage.get("name", "")))

		# 診斷：最小曲率出現在哪、那附近的點距正不正常
		var span := 8
		var arc: float = track.total / track.SAMPLES * span
		var worst := 1e9
		var worst_i := 0
		for i in track.SAMPLES:
			var turn: float = absf(wrapf(track.headings[(i + span) % track.SAMPLES]
				- track.headings[i], -PI, PI))
			if turn > 0.0001 and arc / turn < worst:
				worst = arc / turn
				worst_i = i
		var gaps := []
		for k in range(-2, 3):
			var a: Vector2 = track.points[(worst_i + k + track.SAMPLES) % track.SAMPLES]
			var b: Vector2 = track.points[(worst_i + k + 1) % track.SAMPLES]
			gaps.append("%.1f" % a.distance_to(b))
		print("   最小曲率在 index %d/%d（距離 %du）　附近點距 %s（理想 %.1f）" %
			[worst_i, track.SAMPLES, int(track.total * worst_i / track.SAMPLES),
			 str(gaps), track.total / track.SAMPLES])

		var straights := _count_straights(track)
		var hairpins := _count_hairpins(track)
		var closest := track.min_self_distance()
		var need_gap: float = Cfg.track_width + 40.0
		print("   兩段路最近距離 %du（賽道寬 %du）%s" %
			[int(closest), int(Cfg.track_width),
			 "　→ 有立體交叉" if closest < need_gap else "　→ 無交叉"])
		print("stage-%02d %s　一圈 %du　最小曲率 %du　長直線 %d 段　急彎 %d 個　外框 %d×%d" %
			[idx, stage.get("name", ""), int(lap), int(track.min_radius),
			 straights, hairpins, int(track.bounds.size.x), int(track.bounds.size.y)])
	get_tree().quit()


func _count_straights(t: TrackPath) -> int:
	## 連續 300u 以上幾乎不轉向的段落 = 直線
	var step := t.total / t.SAMPLES
	var run := 0.0
	var count := 0
	for i in t.SAMPLES:
		var turn: float = absf(wrapf(t.headings[(i + 1) % t.SAMPLES] - t.headings[i], -PI, PI))
		if turn / step < 0.0006:       # 曲率半徑 > 1600u 就算直的
			run += step
		else:
			if run > 300.0:
				count += 1
			run = 0.0
	if run > 300.0:
		count += 1
	return count


func _count_hairpins(t: TrackPath) -> int:
	## 在 600u 內轉超過 120 度 = 髮夾彎
	var span := int(600.0 / (t.total / t.SAMPLES))
	var count := 0
	var i := 0
	while i < t.SAMPLES:
		var a: float = t.headings[i]
		var b: float = t.headings[(i + span) % t.SAMPLES]
		if absf(wrapf(b - a, -PI, PI)) > deg_to_rad(120.0):
			count += 1
			i += span
		else:
			i += 1
	return count


func _render(t: TrackPath, path: String, label: String) -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.22, 0.34))

	var b := t.bounds
	var sc: float = min((W - MARGIN * 2) / maxf(b.size.x, 1.0),
					  (H - MARGIN * 2) / maxf(b.size.y, 1.0))
	var off := Vector2(W, H) * 0.5 - b.get_center() * sc

	# 賽道在彎道會依曲率收窄，畫的就是玩家實際會看到的寬度
	var narrowest := 9999.0
	for i in t.SAMPLES:
		var d: float = t.total * i / t.SAMPLES
		var h := _half_at(t, d)
		narrowest = minf(narrowest, h)
		_line(img, t.world(d, -h) * sc + off, t.world(d, h) * sc + off,
			Color(0.92, 0.96, 1.0), 2)
	for i in t.SAMPLES:
		var d: float = t.total * i / t.SAMPLES
		var d2: float = t.total * (i + 1) / t.SAMPLES
		_line(img, t.world(d, -_half_at(t, d)) * sc + off,
			t.world(d2, -_half_at(t, d2)) * sc + off, Color(0.35, 0.55, 0.75), 1)
		_line(img, t.world(d, _half_at(t, d)) * sc + off,
			t.world(d2, _half_at(t, d2)) * sc + off, Color(0.35, 0.55, 0.75), 1)
	print("   最窄處半寬 %du（平地 %du）" % [int(narrowest), int(Cfg.track_width * 0.5)])
	# 起點
	var s0 := t.pos_at(0.0) * sc + off
	_dot(img, s0, 7, Color(1.0, 0.82, 0.2))
	# 每 1000u 一個里程點，看得出長度分布
	var m := 1000.0
	while m < t.total:
		_dot(img, t.pos_at(m) * sc + off, 3, Color(0.95, 0.4, 0.3))
		m += 1000.0

	img.save_png(path)
	print("  → ", ProjectSettings.globalize_path(path))


func _half_at(t: TrackPath, _d: float) -> float:
	return Cfg.track_width * 0.5


func _line(img: Image, a: Vector2, b: Vector2, col: Color, r: int) -> void:
	var n := int(maxf(a.distance_to(b), 1.0)) + 1
	for i in n + 1:
		_dot(img, a.lerp(b, float(i) / n), r, col)


func _dot(img: Image, p: Vector2, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x >= 0 and x < W and y >= 0 and y < H:
				img.set_pixel(x, y, col)
