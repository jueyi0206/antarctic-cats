extends Node
## 海豹拋魚的實測：會拋、追著小玲飛、自動吃掉

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

func _run() -> void:
	var m: Node2D = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(m)
	await _frames(2)
	m.start_stage("res://data/levels/stage-04.json")
	await _frames(2)
	_ok(m.waving and not m.wavers.is_empty(), "第四關有 %d 隻海豹" % m.wavers.size())

	var wv: Dictionary = m.wavers[0]
	m.dist = float(wv.d) - 320.0
	m.off = 0.0
	m.state = 1
	await _frames(6)
	_ok(not m.tossed.is_empty(), "靠近時海豹把魚拋出來了")
	if m.tossed.is_empty():
		get_tree().quit(1)
		return
	var f: Dictionary = m.tossed[0]
	_ok(absf(float(f.off) - m.off) < 60.0, "魚是朝小玲飛的")

	# 追蹤的魚一定會飛到小玲身上
	var before: float = m.time_left
	var fish0: int = m.fish_eaten
	await get_tree().create_timer(m.TOSS_FLY + 0.25).timeout
	_ok(m.tossed.is_empty(), "魚飛完就自動吃掉了")
	_ok(m.fish_eaten > fish0, "計入吃到的魚（%d → %d）" % [fish0, m.fish_eaten])
	_ok(m.time_left > before - 0.7, "時間有補回來（%.1f → %.1f）" % [before, m.time_left])

	# 就算閃到路邊，魚也會追過來
	var wv2: Dictionary = m.wavers[1]
	m.dist = float(wv2.d) - 320.0
	m.off = -80.0
	await _frames(6)
	var n0: int = m.fish_eaten
	await get_tree().create_timer(m.TOSS_FLY + 0.35).timeout
	_ok(m.fish_eaten > n0, "閃到路邊一樣接得到（魚會追人）")


	print("\n" + ("全部通過" if fails == 0 else "%d 項失敗" % fails))
	get_tree().quit(1 if fails else 0)
