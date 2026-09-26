class_name TrackPath
extends RefCounted
## 一圈封閉的賽道，像賽車地圖那樣。
##
## 用諧波在極座標上生成：r(θ) = R × (1 + Σ aₖ·sin(kθ + φₖ))。
## 這種寫法**天然閉合**（θ 走完 2π 必定回到起點），諧波越多彎越多 ——
## 「九彎十八拐」就是加幾個高次項的事，不必手工調控制點去對頭尾。
##
## 生成之後重新取樣成等弧長，這樣「賽道距離 d」才是真的距離，
## 關卡系統那套以 u 為單位的尺度（跳躍距離、缺口寬度）才依然成立。

const SAMPLES := 1440           ## 等弧長取樣點數，越多越平滑

var points := PackedVector2Array()   ## 等弧長的中心線點
var headings := PackedFloat32Array() ## 每個點的前進方向（弧度）
var total := 0.0                     ## 一圈的長度
var radius := 0.0                    ## 名目半徑，畫地圖用
var bounds := Rect2()
var min_radius := 0.0   ## 全圈最小曲率半徑
var radii := PackedFloat32Array()   ## 每個取樣點的曲率半徑


## 賽道原型。每一組是一圈的控制點（逆時針，歸一化到大約 ±1.3 × ±0.9）。
##
## 為什麼用手工原型而不是純隨機：賽車場的「好形狀」——長直線接髮夾、
## 連續 S 彎、一快一慢的節奏——是設計出來的。隨機演算法要碰巧長出這種結構
## 很難，而且曲率一失控就破圖。原型保證結構，變化交給鏡像／旋轉／小幅擾動。
const PROTOTYPES := [
	# 0 經典跑道：兩段長直線 + 一個髮夾 + 一組 S 彎（給第一關，好跑）
	[Vector2(-1.25, -0.55), Vector2(-0.30, -0.78), Vector2(0.70, -0.75),
	 Vector2(1.22, -0.42), Vector2(1.28, 0.02), Vector2(0.85, 0.28),
	 Vector2(0.28, 0.18), Vector2(0.18, 0.52), Vector2(0.72, 0.68),
	 Vector2(0.10, 0.86), Vector2(-0.70, 0.80), Vector2(-1.20, 0.45)],

	# 1 雙髮夾：左右各一個折返，中間用直線接起來
	[Vector2(-1.30, -0.30), Vector2(-0.70, -0.72), Vector2(0.30, -0.80),
	 Vector2(1.05, -0.62), Vector2(1.32, -0.18), Vector2(0.62, 0.05),
	 Vector2(1.10, 0.38), Vector2(0.75, 0.80), Vector2(-0.05, 0.82),
	 Vector2(-0.45, 0.42), Vector2(-0.95, 0.62), Vector2(-1.32, 0.20)],

	# 2 摺疊型：外圈跑一圈，再鑽進內部蛇行三層才出來。
	#   賽道允許交叉（當作立體交會），所以層距不必大於賽道寬 ——
	#   密度就是靠這個來的。交叉處畫面會把另一段畫成橋下的暗色路。
	[Vector2(-1.25, -0.88), Vector2(0.50, -0.92), Vector2(1.18, -0.84),
	 Vector2(1.32, -0.50), Vector2(1.34, 0.00), Vector2(1.32, 0.50),
	 Vector2(1.02, 0.88), Vector2(0.00, 0.92), Vector2(-1.02, 0.88),
	 Vector2(-1.30, 0.58), Vector2(-1.20, 0.42),
	 Vector2(-0.80, 0.38), Vector2(0.30, 0.42), Vector2(0.92, 0.36),
	 Vector2(1.04, 0.16), Vector2(0.92, -0.02),
	 Vector2(0.30, -0.06), Vector2(-0.50, -0.02), Vector2(-0.95, -0.10),
	 Vector2(-1.06, -0.30), Vector2(-0.86, -0.44),
	 Vector2(-0.20, -0.40), Vector2(0.55, -0.44), Vector2(0.95, -0.56),
	 Vector2(0.70, -0.70), Vector2(-0.20, -0.66), Vector2(-0.90, -0.72)],

	# 3 雙葉型：左右各一個內凹的葉片，中間交會處是全場最慢的點
	[Vector2(-1.30, -0.35), Vector2(-0.95, -0.80), Vector2(-0.30, -0.78),
	 Vector2(-0.05, -0.40), Vector2(0.20, -0.78), Vector2(0.85, -0.82),
	 Vector2(1.28, -0.48), Vector2(1.30, -0.05), Vector2(0.95, 0.20),
	 Vector2(1.25, 0.55), Vector2(0.70, 0.84), Vector2(0.05, 0.60),
	 Vector2(-0.10, 0.86), Vector2(-0.80, 0.84), Vector2(-1.28, 0.50),
	 Vector2(-1.05, 0.15), Vector2(-1.30, -0.05)],

	# 4 八字形：Lemniscate 參數式，在正中央真的交會。
	#   控制點自己畫八字很難畫準，交叉點一偏就變成內凹的花瓣 —— 用公式生比較實在。
	[
	 Vector2(1.32, 0.00), Vector2(1.29, 0.27), Vector2(1.19, 0.48),
	 Vector2(1.03, 0.60), Vector2(0.82, 0.60), Vector2(0.57, 0.48),
	 Vector2(0.29, 0.27), Vector2(0.00, 0.00), Vector2(-0.29, -0.27),
	 Vector2(-0.57, -0.48), Vector2(-0.82, -0.60), Vector2(-1.03, -0.60),
	 Vector2(-1.19, -0.48), Vector2(-1.29, -0.27), Vector2(-1.32, -0.00),
	 Vector2(-1.29, 0.27), Vector2(-1.19, 0.48), Vector2(-1.03, 0.60),
	 Vector2(-0.82, 0.60), Vector2(-0.57, 0.48), Vector2(-0.29, 0.27),
	 Vector2(-0.00, 0.00), Vector2(0.29, -0.27), Vector2(0.57, -0.48),
	 Vector2(0.82, -0.60), Vector2(1.03, -0.60), Vector2(1.19, -0.48),
	 Vector2(1.29, -0.27)],
]

## 哪一關用哪一組：簡單的給第一關，摺疊型給後段
const LAYOUTS := {"simple": [0, 1], "technical": [2, 3, 4]}


func build(seed_value: int, target_length: float, layout := "simple", forced := -1,
		min_radius_target := 90.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# 選一個原型，再鏡像／轉向／小幅擾動 —— 4 個原型 × 8 種變換，夠用了
	var pool: Array = LAYOUTS.get(layout, LAYOUTS["simple"])
	var pick: int = forced if forced >= 0 and forced < PROTOTYPES.size() 		else pool[rng.randi() % pool.size()]
	var proto: Array = PROTOTYPES[pick]
	var flip_x := 1.0 if rng.randf() < 0.5 else -1.0
	var flip_y := 1.0 if rng.randf() < 0.5 else -1.0
	var swap := rng.randf() < 0.5

	var ctrl := PackedVector2Array()
	for p in proto:
		var v: Vector2 = p
		var squash := 0.62 if layout == "simple" else 0.95
		v = Vector2(v.x * 1.15 * flip_x, v.y * squash * flip_y)
		if swap:
			v = Vector2(v.y * 1.45, v.x * 0.69)   # 轉 90 度，順便保持橫長
		var jitter := 0.045 if layout == "simple" else 0.018
		v += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		ctrl.append(v)
	if flip_x * flip_y < 0.0:
		ctrl.reverse()                            # 鏡像會翻轉繞行方向，轉回逆時針

	# Catmull-Rom 穿過每個控制點，所以設計出來的形狀不會被平滑掉
	var curve := PackedVector2Array()
	var m := ctrl.size()
	for i in m:
		var p0: Vector2 = ctrl[(i - 1 + m) % m]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % m]
		var p3: Vector2 = ctrl[(i + 2) % m]
		for k in 24:
			curve.append(_catmull(p0, p1, p2, p3, float(k) / 24.0))

	# 縮放到指定的一圈長度
	var n := curve.size()
	var peri := 0.0
	for i in n:
		peri += curve[i].distance_to(curve[(i + 1) % n])
	var sc := target_length / peri
	var raw := PackedVector2Array()
	for p in curve:
		raw.append(p * sc)
	total = target_length
	radius = sc

	_resample(raw)
	_finish()

	# 曲率不夠就把彎撐開。彎道半徑一旦小於賽道半寬，內側邊界會翻折成破圖，
	# 所以這一步不是美化而是保命 —— 寧可髮夾變鈍，也不能讓賽道穿過自己。
	# 不再硬把彎磨鈍 —— 賽道會依曲率自動收窄（見 Main._track_half_at），
	# 這裡只擋掉極端值：那種地方路會窄到不能玩。
	# 這個門檻管的是「手感」不是「破圖」（冰面用圓串畫，再急也不會自交）。
	#
	# 相機朝向跟著賽道走，所以轉向速率 = 速度 / 曲率半徑。半徑 55u 配基礎速 240 u/s
	# 等於每秒轉 4 弧度，配上彎道限速才進到可控範圍。
	# 由關卡指定（minRadius）：教學關給大一點的值把彎磨緩，後段關卡才放狠彎。
	var need := min_radius_target
	# 平滑窗口要跟「想撐到多大的半徑」同一個量級，窗口太小撐不開急彎
	var win := int(clampf(need / maxf(total / SAMPLES, 0.001), 8.0, 60.0))
	var guard_pass := 0
	while min_radius < need and guard_pass < 12:
		guard_pass += 1
		_smooth_points(win)
		_renormalize()          # 平滑會讓點分布變不均，一定要重新等弧長化，
		_finish()               # 否則相鄰點距離趨近 0，量出來的曲率全是噪音


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((p1 * 2.0) + (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3)


func _finish() -> void:
	headings = PackedFloat32Array()
	for i in SAMPLES:
		var a := points[i]
		var b := points[(i + 1) % SAMPLES]
		headings.append((b - a).angle())
	_smooth_headings(6)

	bounds = Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)

	min_radius = _measure_min_radius()
	_build_radii()


func _build_radii() -> void:
	## 每點的曲率半徑。賽道拿它來決定「這裡最寬能多寬」——
	## 彎道半徑小於半寬的話內側會翻折，所以那種地方的路本來就只能窄。
	var span := 10
	var arc := total / SAMPLES * span
	radii = PackedFloat32Array()
	radii.resize(SAMPLES)
	for i in SAMPLES:
		var turn: float = absf(wrapf(headings[(i + span) % SAMPLES] - headings[i], -PI, PI))
		radii[i] = 99999.0 if turn < 0.0001 else arc / turn


func min_self_distance() -> float:
	## 沿賽道相距 400u 以上的兩點，在世界上最近有多近。
	## 小於賽道全寬就表示兩段路黏在一起了。降取樣檢查，1440² 太慢。
	var stride := 10
	var step := total / SAMPLES
	var worst := 1e9
	var i := 0
	while i < SAMPLES:
		var j := i + stride
		while j < SAMPLES:
			var gap: int = mini(absi(i - j), SAMPLES - absi(i - j))
			if gap * step >= 400.0:
				worst = minf(worst, points[i].distance_to(points[j]))
			j += stride
		i += stride
	return worst


func radius_at(d: float) -> float:
	if radii.is_empty():
		return 99999.0
	return radii[int(_idx(d)) % SAMPLES]


func _renormalize() -> void:
	## 平滑後周長會縮短。先量新周長、縮放回原本的一圈長度，再重新等弧長取樣 ——
	## 少了這一步，等弧長取樣會繞過頭，形狀自己疊在一起。
	var n := points.size()
	var peri := 0.0
	for i in n:
		peri += points[i].distance_to(points[(i + 1) % n])
	var k := total / maxf(peri, 0.0001)
	var scaled := PackedVector2Array()
	for p in points:
		scaled.append(p * k)
	_resample(scaled)


func _smooth_points(w: int) -> void:
	## 環形移動平均。對已經很密的曲線，這比 Chaikin 有效得多 ——
	## Chaikin 只切掉相鄰兩點之間那個微小的角，撐不開真正的急彎。
	var out := PackedVector2Array()
	out.resize(SAMPLES)
	for i in SAMPLES:
		var acc := Vector2.ZERO
		for k in range(-w, w + 1):
			acc += points[(i + k + SAMPLES) % SAMPLES]
		out[i] = acc / float(w * 2 + 1)
	points = out


func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


func _resample(raw: PackedVector2Array) -> void:
	## 重新取樣成等弧長 —— 不做的話彎道處的「距離」會被壓縮，
	## 關卡那套以 u 為單位的尺度就全歪了。
	## 注意不要去改 raw：邊走邊覆蓋起點的話，繞第二圈會讀到改過的資料而卡死。
	var n := raw.size()
	points = PackedVector2Array()
	var step := total / SAMPLES
	var idx := 0
	var cur := raw[0]
	var remain := step
	var guard := 0
	points.append(cur)
	while points.size() < SAMPLES and guard < n * 8:
		guard += 1
		var nxt := raw[(idx + 1) % n]
		var seg := cur.distance_to(nxt)
		if seg >= remain:
			cur = cur + (nxt - cur) / maxf(seg, 0.0001) * remain
			points.append(cur)
			remain = step
		else:
			remain -= seg
			cur = nxt
			idx += 1
	while points.size() < SAMPLES:
		points.append(raw[0])


func _smooth_headings(win: int) -> void:
	## 環形移動平均。相鄰取樣點只差幾 u，角度的數值噪音會被放大成假的急彎，
	## 而且相機直接吃這個角度 —— 不平滑的話畫面每幀都在抖。
	var out := PackedFloat32Array()
	out.resize(SAMPLES)
	for i in SAMPLES:
		var base := headings[i]
		var acc := 0.0
		for k in range(-win, win + 1):
			acc += wrapf(headings[(i + k + SAMPLES) % SAMPLES] - base, -PI, PI)
		out[i] = base + acc / float(win * 2 + 1)
	headings = out


func _measure_min_radius() -> float:
	## 離散曲率半徑 = 弧長 / 轉角。跨 8 個取樣點量，單點間距太小會被噪音主導。
	var span := 8
	var arc := total / SAMPLES * span
	var worst := 1e9
	for i in SAMPLES:
		var a := headings[i]
		var b := headings[(i + span) % SAMPLES]
		var turn: float = absf(wrapf(b - a, -PI, PI))
		if turn > 0.0001:
			worst = minf(worst, arc / turn)
	return worst


func _idx(d: float) -> float:
	## 賽道距離 → 取樣索引（會自動繞圈，所以跑第二圈直接沿用同一條路）
	return fposmod(d / total, 1.0) * SAMPLES


func pos_at(d: float) -> Vector2:
	var f := _idx(d)
	var i := int(f)
	return points[i % SAMPLES].lerp(points[(i + 1) % SAMPLES], f - i)


func heading_at(d: float) -> float:
	var f := _idx(d)
	var i := int(f)
	var a := headings[i % SAMPLES]
	var b := headings[(i + 1) % SAMPLES]
	return a + wrapf(b - a, -PI, PI) * (f - i)


func normal_at(d: float) -> Vector2:
	## 指向賽道右側的單位向量，元素的 offset 就是沿這個方向擺
	var h := heading_at(d)
	return Vector2(sin(h), -cos(h))


## 世界座標：賽道距離 + 橫向偏移
func world(d: float, off: float) -> Vector2:
	return pos_at(d) + normal_at(d) * off
