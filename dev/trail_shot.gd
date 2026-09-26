extends Node
## 插旗當下的樣子

func _ready() -> void:
	_run.call_deferred()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dev/preview/%s.png" % n)
	print("[SHOT] ", n)

func _run() -> void:
	var m: Node2D = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	m.start_stage("res://data/levels/stage-02.json")
	await get_tree().process_frame
	m.state = 1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	# 強制現在插一支，然後停在彈出來的那一瞬間
	m.trail_t = 0.0001
	await get_tree().process_frame
	await get_tree().process_frame
	m.paused = true
	await get_tree().process_frame
	for spec in [[0.02, "s2_flag_a"], [0.13, "s2_flag_b"], [0.30, "s2_flag_c"]]:
		m.trail[m.trail.size() - 1]["t"] = m.elapsed - float(spec[0])
		await get_tree().process_frame
		await _shot(str(spec[1]))
	print("旗子 ", m.trail.size(), " 支")
	get_tree().quit()
