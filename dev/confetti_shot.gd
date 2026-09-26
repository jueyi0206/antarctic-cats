extends Node
## 過關彩帶的截圖

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m: Node2D = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	m.start_stage("res://data/levels/stage-01.json")
	await get_tree().process_frame
	m.state = 1
	m._force_end(true)
	for shot in [0.35, 0.9, 1.8]:
		await get_tree().create_timer(shot if shot == 0.35 else 0.55).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://dev/preview/confetti_%.0f.png" % (shot * 100))
		print("[SHOT] ", shot)
	get_tree().quit()
