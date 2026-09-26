extends Node
## 觸控介面的截圖

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m: Node2D = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await get_tree().process_frame
	m.start_stage("res://data/levels/stage-02.json")
	m.dist = 1200.0
	m.state = 1
	Touch.forced = true
	await get_tree().process_frame
	# 手指按在左下、往右上推一點
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = Vector2(170, 980)
	t.pressed = true
	Touch._input(t)
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = Vector2(265, 1020)
	Touch._input(d)
	for i in 4:
		await get_tree().process_frame
	m.paused = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dev/preview/touch_ui.png")
	print("[SHOT] touch_ui")
	get_tree().quit()
