extends Node
## 劇情流程自動測試：開場 → 關卡 → 失敗劇情 → 重跑 → 過關劇情 → 第二章開場。
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path antarctic res://dev/flow_test.tscn

var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _scene() -> Node:
	return get_tree().current_scene


func _expect(cond: bool, msg: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + msg)
	if not cond:
		fails += 1


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


## 把目前這段劇情一路按到底，回傳看過的插圖 id
func _play_through_story() -> Array:
	var seen := []
	var story := _scene()
	for i in 400:
		# 換成別的場景（包括下一段劇情）就停，多按的空白鍵會被下一個場景吃掉
		if _scene() != story:
			break
		var sc := str(story.get("_scene"))
		if sc != "" and not seen.has(sc):
			seen.append(sc)
			var art: TextureRect = story.get_node("Frame/Art")
			_expect(art.texture != null, "插圖 %s 有載入" % sc)
		_key(KEY_SPACE)          # 一下補完整句，再一下換下一句
		await _frames(2)
	return seen


func _run() -> void:
	# 換場景會把 current_scene 釋放掉。先塞一個替身當 current_scene，自己才活得下來
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	Flow.start()
	await _frames(3)

	print("\n── 第一章開場 ──")
	_expect(_scene().name == "Story", "進到劇情畫面")
	_expect(str(_scene().get_node("Title").text).begins_with("第一章"), "標題是第一章")
	var seen := await _play_through_story()
	_expect(seen == ["ch01_01", "ch01_02"], "開場用了 ch01_01、ch01_02（實際 %s）" % str(seen))

	print("\n── 第一關 ──")
	_expect(_scene().name == "Main", "進到關卡")
	var m := _scene()
	await _frames(2)
	_expect(str(m.stage_name) != "" and int(m.stage_index) == 1, "載入第 1 站")
	_expect(str(m.pickup_style) == "catgrass", "加分道具是貓草")
	_expect(m.brief_panel.visible, "任務卡有顯示（state=%d）" % int(m.state))
	_key(KEY_F)
	await _frames(3)
	_expect(int(m.state) == 4, "按 F 直接失敗（TIMEUP）")
	_expect(not m.brief_panel.visible, "任務卡收起來了")
	_key(KEY_SPACE)
	await _frames(3)
	_expect(_scene() == m, "太快按空白鍵不會跳走")
	await get_tree().create_timer(1.0).timeout
	_key(KEY_SPACE)
	await _frames(3)

	print("\n── 失敗劇情 ──")
	_expect(_scene().name == "Story", "進到失敗劇情")
	seen = await _play_through_story()
	_expect(seen == ["ch01_lose"], "失敗劇情用了 ch01_lose（實際 %s）" % str(seen))

	print("\n── 重跑第一關 ──")
	_expect(_scene().name == "Main", "回到關卡")
	m = _scene()
	await _frames(2)
	_expect(int(m.stage_index) == 1, "還是第 1 站")
	_expect(m.brief_panel.visible, "任務卡又出現")
	# 按鈕也要能用
	var btn: Button = null
	for c in m.get_children():
		if c is CanvasLayer:
			for b in c.get_children():
				if b is Button and str(b.text).contains("過關"):
					btn = b
	_expect(btn != null, "有「測試：過關」按鈕")
	if btn:
		btn.pressed.emit()
	await _frames(3)
	_expect(int(m.state) == 3, "按鈕直接過關（CLEARED）")
	await get_tree().create_timer(1.0).timeout
	_key(KEY_SPACE)
	await _frames(3)

	print("\n── 過關劇情 ──")
	_expect(_scene().name == "Story", "進到過關劇情")
	seen = await _play_through_story()
	_expect(seen == ["ch01_03", "ch01_04"], "過關劇情用了 ch01_03、ch01_04（實際 %s）" % str(seen))

	print("\n── 第二章 ──")
	_expect(_scene().name == "Story", "接到下一段劇情")
	_expect(str(_scene().get_node("Title").text).begins_with("第二章"), "標題是第二章")
	_expect(Flow.chapter_index == 1, "Flow 走到第二章")

	print("\n" + ("全部通過" if fails == 0 else "%d 項失敗" % fails))
	get_tree().quit(1 if fails else 0)
