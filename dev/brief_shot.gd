extends Node
## 每一章的任務卡各截一張，檢查有沒有超出框

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://dev/preview/")
	Flow.driving = true
	for ch in 4:
		Flow.chapter_index = ch
		var m: Node2D = load("res://scenes/Main.tscn").instantiate()
		get_tree().root.add_child(m)
		await _frames(6)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://dev/preview/brief_ch%d.png" % (ch + 1))
		print("[SHOT] brief_ch%d　%d 行" % [ch + 1, m.brief_label.get_line_count()])
		m.queue_free()
		await _frames(2)
	get_tree().quit()
