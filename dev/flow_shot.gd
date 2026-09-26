extends Node
## 劇情模式截圖：劇情頁、任務卡、貓草、時間到。要開視窗跑（不能 --headless）。
##   Godot_v4.7.2-stable_win64_console.exe --path antarctic res://dev/flow_shot.tscn

const OUT := "res://dev/preview/"


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("[SHOT] ", name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	Flow.start()
	await _frames(30)
	await _shot("flow_story")

	Flow.story_finished()
	await _frames(10)
	await _shot("flow_brief")

	var m := get_tree().current_scene
	# 找第一撮貓草，停在它前面
	for e in m.elements:
		if e.type == "cheer":
			m.dist = float(e.d) - 180.0
			m.off = float(e.off)
			break
	m.state = 1
	m.mates[0].dist = m.dist + 60.0
	m.mates[1].dist = m.dist + 120.0
	await _frames(3)
	m.paused = true
	await _frames(3)
	await _shot("flow_catgrass")
	# 田鼠跳到一半
	for e in m.elements:
		if e.has("fish"):
			m.dist = float(e.d) - 160.0
			m.off = float(e.off) - 40.0
			e["fish_t"] = float(e.fish.get("up", 1.6)) * 0.5
			break
	await _frames(3)
	await _shot("flow_vole")
	# 農村 → 海邊：沿路三個位置
	for spec in [[0.04, "ground_farm"], [0.50, "ground_mid"], [0.95, "ground_sea"]]:
		m.dist = m.track_len * float(spec[0])
		m.off = 0.0
		m.mates[0].dist = m.dist + 120.0
		m.mates[1].dist = m.dist + 220.0
		await _frames(3)
		await _shot(str(spec[1]))

	# 終點的碼頭
	m.dist = m.track_len - 260.0
	m.off = 0.0
	m.mates[0].dist = m.dist + 100.0
	m.mates[1].dist = m.dist + 180.0
	await _frames(3)
	await _shot("ground_finish")

	# 轉彎：整隻貓要傾斜
	m.paused = false
	Input.action_press("move_right")
	await _frames(12)
	await _shot("flow_turn")          # 不能暫停：暫停後 lean 會歸零，就看不到傾斜
	Input.action_release("move_right")
	m.paused = false
	await _frames(2)
	m.paused = true

	# 跌倒的樣子
	m.state = 2
	m.stumble_t = 9.0
	m.mates[0].dist = m.dist + 26.0
	m.mates[0].off = -62.0
	m.mates[1].dist = m.dist + 26.0
	m.mates[1].off = 62.0
	m._pick_laugh_lines()
	await _frames(3)
	await _shot("flow_hit")
	m.state = 1
	m.paused = false

	m._force_end(false)
	await _frames(10)
	await _shot("flow_timeup")
	get_tree().quit()
