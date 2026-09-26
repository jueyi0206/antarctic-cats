extends Node
## 實測：小玲邊跑邊插旗（Cfg.flag_period 秒一支）

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m: Node2D = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	m.start_stage("res://data/levels/stage-02.json")
	await get_tree().process_frame
	print("插旗開關 flagTrail = ", m.trail_on, "　每 ", Cfg.flag_period, " 秒一支")
	m.state = 1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 7000:
		await get_tree().process_frame
	print("跑了 7 秒，插了 ", m.trail.size(), " 支旗，跑了 ", int(m.dist), "u")
	for f in m.trail:
		print("   旗子 @ %du  off %d" % [int(f.d), int(f.off)])
	# 第一關不該有旗子（那時候小玲還沒偷到）
	m.start_stage("res://data/levels/stage-01.json")
	await get_tree().process_frame
	print("第一關 flagTrail = ", m.trail_on)
	get_tree().quit()
