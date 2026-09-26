extends Node
## 手機觸控實測：搖桿轉向、下拉煞車、右半邊跳、自動全速

var fails := 0

func _ready() -> void:
	_run.call_deferred()

func _ok(c: bool, m: String) -> void:
	print(("  ✓ " if c else "  ✗ ") + m)
	if not c:
		fails += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _touch(pos: Vector2, pressed: bool, index := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	# 直接餵給觸控層：headless 沒有視窗，走 Input.parse_input_event 的話
	# 座標會被壞掉的視窗轉換矩陣放大十幾倍
	Touch._input(e)

func _drag(pos: Vector2, index := 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	Touch._input(e)

func _run() -> void:
	var m: Node2D = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await _frames(2)
	m.start_stage("res://data/levels/stage-01.json")
	m.state = 1
	Touch.forced = true
	await _frames(3)
	_ok(Touch.active(), "關卡畫面裡觸控層是開著的")

	# 搖桿往右推到底
	_touch(Vector2(150, 1000), true)
	_drag(Vector2(150 + Touch.STICK_RADIUS, 1000))
	await _frames(3)
	_ok(Input.get_action_strength("move_right") > 0.9, "右推到底 = 轉向強度 %.2f"
		% Input.get_action_strength("move_right"))
	_ok(Input.is_action_pressed("speed_up"), "沒煞車時自動全速")
	var off0: float = m.off
	await _frames(6)
	_ok(m.off > off0, "貓真的往右移動了（%.0f → %.0f）" % [off0, m.off])

	# 推一半 = 轉一半
	_drag(Vector2(150 + Touch.STICK_RADIUS * 0.5, 1000))
	await _frames(3)
	var half := Input.get_action_strength("move_right")
	_ok(half > 0.35 and half < 0.7, "推一半 = 轉一半（強度 %.2f）" % half)

	# 往下拉 = 煞車，而且不再自動全速
	_drag(Vector2(150, 1000 + Touch.STICK_RADIUS))
	await _frames(3)
	_ok(Input.is_action_pressed("speed_down"), "下拉 = 煞車")
	_ok(not Input.is_action_pressed("speed_up"), "煞車時不會同時踩加速")

	# 放開搖桿
	_touch(Vector2(150, 1000), false)
	await _frames(3)
	_ok(not Input.is_action_pressed("move_right") and not Input.is_action_pressed("speed_down"),
		"放手就全部鬆開")
	_ok(Input.is_action_pressed("speed_up"), "放手還是維持全速")

	# 右半邊點一下 = 跳
	_ok(not m.jumping, "跳之前是在地上")
	_touch(Vector2(600, 700), true, 1)
	await _frames(3)
	_ok(m.jumping, "點右半邊就跳了")
	_touch(Vector2(600, 700), false, 1)

	# 暫停鍵
	await get_tree().create_timer(0.7).timeout
	_touch(Touch.PAUSE_RECT.position + Vector2(40, 40), true, 2)
	await _frames(3)
	_ok(m.paused, "右上角可以暫停")
	_touch(Touch.PAUSE_RECT.position + Vector2(40, 40), false, 2)

	print("\n" + ("全部通過" if fails == 0 else "%d 項失敗" % fails))
	get_tree().quit(1 if fails else 0)
