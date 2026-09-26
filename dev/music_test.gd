extends Node
## 音樂系統實測：換曲、交叉淡入淡出、加速、暫停壓低

var fails := 0

func _ready() -> void:
	_run.call_deferred()

func _ok(c: bool, m: String) -> void:
	print(("  ✓ " if c else "  ✗ ") + m)
	if not c:
		fails += 1

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _run() -> void:
	var players: Array = []
	for c in Aud.get_children():
		if c is AudioStreamPlayer and c.bus == "Master" and c.stream == null:
			players.append(c)
	print("音樂播放器 ", Aud._music.size(), " 台")
	Aud.music_play("theme")
	await _wait(1.0)
	var a: AudioStreamPlayer = Aud._music[Aud._cur]
	_ok(a.playing, "theme 正在放")
	_ok(a.stream.loop, "theme 會循環")
	_ok(abs(a.volume_db - Aud.MUSIC_DB) < 0.6, "淡入到 %.1f dB（現在 %.1f）" % [Aud.MUSIC_DB, a.volume_db])

	Aud.set_hurry(true)
	await _wait(0.6)
	_ok(abs(a.pitch_scale - Aud.HURRY_PITCH) < 0.01, "最後十秒加速 pitch %.2f" % a.pitch_scale)
	Aud.set_hurry(false)
	await _wait(0.6)

	Aud.set_paused(true)
	await _wait(0.5)
	_ok(a.volume_db < Aud.MUSIC_DB - 5.0, "暫停時壓低到 %.1f dB" % a.volume_db)
	Aud.set_paused(false)
	await _wait(0.4)

	Aud.set_power(true)
	await _wait(0.5)
	_ok(abs(a.pitch_scale - Aud.POWER_PITCH) < 0.01, "木天蓼：音高升到 %.2f" % a.pitch_scale)
	_ok(a.volume_db > Aud.MUSIC_DB + 1.0, "木天蓼：音量升到 %.1f dB" % a.volume_db)
	Aud.set_hurry(true)
	await _wait(0.5)
	_ok(abs(a.pitch_scale - Aud.POWER_PITCH * Aud.HURRY_PITCH) < 0.02,
		"木天蓼 + 最後十秒：兩個效果相乘 %.3f" % a.pitch_scale)
	Aud.set_hurry(false)
	Aud.set_power(false)
	await _wait(0.7)
	_ok(abs(a.pitch_scale - 1.0) < 0.01, "效果結束後回到原速")

	Aud.music_play("level3")
	await _wait(0.3)
	var b: AudioStreamPlayer = Aud._music[Aud._cur]
	_ok(b != a and b.playing and a.playing, "換曲時兩首同時在放（交叉淡入淡出中）")
	await _wait(1.2)
	_ok(not a.playing, "舊曲淡完就停掉")
	_ok(abs(b.volume_db - Aud.MUSIC_DB) < 0.6, "新曲淡入完成")

	Aud.music_play("level3")
	await _wait(0.2)
	_ok(Aud._music[Aud._cur] == b, "同一首不重播")

	var lose: AudioStream = Aud.MUSIC["lose"]
	_ok(not lose.loop, "lose 不循環（一次性的收尾句）")
	_ok(not Aud.GOAL_STINGER.loop, "過關號角不循環")
	var cur: AudioStreamPlayer = Aud._music[Aud._cur]      # 前面換過曲，要看現在這一台
	Aud.play_goal()
	await _wait(0.4)
	_ok(Aud._stinger.playing, "過關號角播放中")
	_ok(cur.volume_db < Aud.MUSIC_DB - 5.0, "號角響的時候音樂壓低到 %.1f dB" % cur.volume_db)
	await _wait(Aud.GOAL_STINGER.get_length() + 0.8)
	_ok(abs(cur.volume_db - Aud.MUSIC_DB) < 1.5, "號角結束後音樂拉回 %.1f dB" % cur.volume_db)

	print("\n" + ("全部通過" if fails == 0 else "%d 項失敗" % fails))
	get_tree().quit(1 if fails else 0)
