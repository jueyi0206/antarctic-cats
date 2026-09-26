extends Node
## 第二關的截圖：海豹、裂縫、魚罐頭、冰柱、冰洞、小玲的旗子。
##   Godot_v4.7.2-stable_win64_console.exe --path antarctic res://dev/stage2_shot.tscn

const OUT := "res://dev/preview/"

var m: Node2D


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("[SHOT] ", name)


## 停在某個元素前面，順便在身後補幾支旗子
func _park(e: Dictionary, back := 150.0) -> void:
	m.dist = float(e.d) - back
	m.off = float(e.off) * 0.4
	m.state = 1
	m.trail.clear()
	for i in 3:
		m.trail.append({"d": m.dist - 40.0 - i * 120.0, "off": (i % 2) * 40.0 - 20.0})
	m.mates[0].dist = m.dist + 90.0
	m.mates[1].dist = m.dist + 170.0


func _find(pred: Callable) -> Dictionary:
	for e in m.elements:
		if pred.call(e):
			return e
	return {}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	m = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(m)
	await _frames(4)
	var stage := "res://data/levels/stage-02.json"
	var tag := "s2"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = "res://data/levels/stage-%s.json" % a.substr(8)
			tag = "s" + a.substr(8).trim_prefix("0")
	m.start_stage(stage)
	await _frames(4)

	# 海豹：把時鐘轉到牠探頭到一半的那一刻
	var seal := _find(func(e): return e.has("seal"))
	if not seal.is_empty():
		_park(seal, 190.0)
		var s: Dictionary = seal.seal
		var period: float = float(s.get("period", 2.4))
		var up: float = float(s.get("up", 1.0))
		m.elapsed = period * 4.0 + up * 0.75 - float(s.get("phase", 0.0))
		await _frames(2)
		m.paused = true
		await _frames(2)
		await _shot(tag + "_seal")
		m.paused = false

	for spec in [["crevasse", "_crevasse", 210.0], ["cheer", "_can", 150.0],
			["flag", "_pillar", 150.0], ["hole_l", "_hole", 170.0],
			["ice_block", "_drift", 170.0], ["blizzard", "_blizzard", -80.0],
			["power", "_power", 150.0]]:
		var want := str(spec[0])
		var e := _find(func(x): return str(x.type) == want)
		if e.is_empty():
			print("找不到 ", want)
			continue
		_park(e, float(spec[2]))
		await _frames(3)
		m.paused = true
		await _frames(2)
		await _shot(tag + str(spec[1]))
		if want == "power":
			# 撿到之後的樣子：無敵中的閃爍與螺旋槳尾巴
			m.power_t = 8.0
			m.invuln_t = 8.0
			m.dist = float(e.d) + 40.0
			await _frames(3)
			await _shot(tag + "_powerfx")
			m.power_t = 0.0
			m.invuln_t = 0.0
		m.paused = false

	# 路邊揮手的海豹（第四關才有）
	if not m.wavers.is_empty():
		var wv: Dictionary = m.wavers[0]
		m.dist = float(wv.d) - 150.0
		m.off = 0.0
		m.state = 1
		m.mates[0].dist = m.dist + 90.0
		m.mates[1].dist = m.dist + 170.0
		await _frames(3)
		m.paused = true
		await _frames(2)
		await _shot(tag + "_waver")

	get_tree().quit()
