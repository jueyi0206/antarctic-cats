extends Node
## 結局最後幾頁的截圖（真貓照片與 QR code）

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Flow.driving = true
	Flow.pending_title = Flow.campaign.get("ending_title", "")
	Flow.pending_lines = Flow.campaign.get("ending", [])
	Flow.pending_is_ending = true
	Flow.beat = Flow.Beat.ENDING
	var s: Control = load("res://scenes/Story.tscn").instantiate()
	get_tree().root.add_child(s)
	await get_tree().process_frame
	var want := {13: "ending_a", 15: "ending_b", 17: "ending_c", 19: "ending_fb", 21: "ending_ig"}
	for i in range(1, 22):
		s.set("_i", i - 1)
		s.call("_advance_line")
		s.set("_revealed", 9999.0)
		await get_tree().process_frame
		await get_tree().process_frame
		if want.has(i):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://dev/preview/%s.png" % want[i])
			print("[SHOT] %s　場景 %s" % [want[i], s.get("_scene")])
	get_tree().quit()
