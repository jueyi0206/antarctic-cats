extends Node
## 聲音（autoload「Aud」）。目前只有音效，沒有背景音樂。
##
## 全部是程式合成的，原始碼在 tools/make_audio.py，改完重跑就覆蓋 audio/*.wav。
## 專案裡沒有任何外來音檔。
##
## 「什麼時候放什麼」不在這裡決定 —— Main 負責叫，這支只負責讓它響。

const SFX := {
	"jump": preload("res://audio/jump.wav"),
	"land": preload("res://audio/land.wav"),
	"splash": preload("res://audio/splash.wav"),
	"trip": preload("res://audio/trip.wav"),
	"seal": preload("res://audio/seal.wav"),
	"fish": preload("res://audio/fish.wav"),
	"point": preload("res://audio/point.wav"),
	"tick": preload("res://audio/tick.wav"),
	"goal": preload("res://audio/goal.wav"),
	"timeup": preload("res://audio/timeup.wav"),
	"flag": preload("res://audio/flag.wav"),
	"power": preload("res://audio/power.wav"),
	"power_off": preload("res://audio/power_off.wav"),
}
const SFX_DB := -5.0
var _pool: Array[AudioStreamPlayer] = []
var _slot := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_make_music_players()


func play(name: String, pitch := 1.0, db := 0.0) -> void:
	if not SFX.has(name):
		return
	var p := _pool[_slot]
	_slot = (_slot + 1) % _pool.size()
	p.stream = SFX[name]
	p.pitch_scale = pitch
	p.volume_db = SFX_DB + db
	p.play()


# ════════════════════════════════════════════ 音樂
#
# 六首都是 Google Flow 生的（風格定調見 AUDIO.md），放在 audio/music/。
# 除了 lose 之外都設成循環播放（在 .import 裡）。
#
# 用兩個播放器互相交叉淡入淡出：換關卡時舊曲淡出、新曲淡入，
# 不然切場景會「啪」一聲斷掉。

# Flow 生的是一兩分鐘的完整曲子，這裡放的是剪過的版本：
#   五首循環曲　../pinball/tools/make_loop.py（找波形最像的兩點接起來）
#   過關號角、失敗句　tools/trim_music.py（從長曲裡剪一段）
# 原始的 mp3 留在旁邊，想重剪隨時可以。
const MUSIC := {
	"theme": preload("res://audio/music/theme.ogg"),
	"level1": preload("res://audio/music/level1.ogg"),
	"level2": preload("res://audio/music/level2.ogg"),
	"level3": preload("res://audio/music/level3.ogg"),
	"level4": preload("res://audio/music/level4.ogg"),
	"lose": preload("res://audio/music/lose_cue.ogg"),
}
## 過關號角。它不是背景音樂，是疊在音樂上面放一次的
const GOAL_STINGER := preload("res://audio/music/goal.ogg")
const STINGER_DB := -4.0
var _stinger: AudioStreamPlayer
const MUSIC_DB := -12.0        ## 音樂比音效小聲：跑酷要聽得到撞擊與吃魚
const FADE := 0.8              ## 交叉淡入淡出的秒數
const DUCK_DB := -10.0         ## 暫停時壓低多少
const HURRY_PITCH := 1.06      ## 最後十秒稍微變快變急
const POWER_PITCH := 1.07      ## 吃到木天蓼：整首往上飄一點，像貓自己嗨起來
## 音高用「很快切過去」而不是慢慢滑：滑音會像錄音帶轉慢，聽起來很滑稽。
## 切換的瞬間都有音效蓋著（撿到時 power、結束時 power_off、過關時號角）
const PITCH_SNAP := 0.08
const POWER_DB := 2.5          ## 同時大聲一點點

var _music: Array[AudioStreamPlayer] = []
var _cur := 0                  ## 現在是哪一台在放
var _playing := ""             ## 正在放的曲名（同一首不重播）
var _hurry := false
var _powered := false
var _ducked := false


func _make_music_players() -> void:
	_stinger = AudioStreamPlayer.new()
	_stinger.volume_db = STINGER_DB
	add_child(_stinger)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -60.0
		add_child(p)
		_music.append(p)


func _target_db() -> float:
	return MUSIC_DB + (DUCK_DB if _ducked else 0.0) + (POWER_DB if _powered else 0.0)


func _target_pitch() -> float:
	## 最後十秒與木天蓼可以同時發生，兩個效果相乘
	return (HURRY_PITCH if _hurry else 1.0) * (POWER_PITCH if _powered else 1.0)


## 把現在該有的音高與音量套到正在放的那一台
func _apply_mods(pitch_time := PITCH_SNAP, db_time := 0.25) -> void:
	for p in _music:
		if not p.playing:
			continue
		create_tween().tween_property(p, "pitch_scale", _target_pitch(), pitch_time)
		create_tween().tween_property(p, "volume_db", _target_db(), db_time)


## 換曲。同一首就不動（跨場景時才不會每次都從頭開始）
func music_play(name: String) -> void:
	if not MUSIC.has(name):
		music_stop()
		return
	if name == _playing and _music[_cur].playing:
		return
	_playing = name
	var old := _music[_cur]
	_cur = 1 - _cur
	var now := _music[_cur]
	now.stream = MUSIC[name]
	now.pitch_scale = _target_pitch()
	now.volume_db = -60.0
	now.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(now, "volume_db", _target_db(), FADE)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.chain().tween_callback(old.stop)


## 過關：音樂先壓低，疊上號角，放完再拉回來。
## 不停音樂是因為過關畫面停留很短，停掉再淡入反而更亂
func play_goal() -> void:
	_stinger.stream = GOAL_STINGER
	_stinger.play()
	_ducked = true
	_apply_mods(0.1, 0.15)
	var back := create_tween()
	back.tween_interval(GOAL_STINGER.get_length() - 0.4)
	back.tween_callback(func():
		_ducked = false
		_apply_mods(0.3, 0.6))


## 舊名字留著，Main 呼叫的是這個
func music_start() -> void:
	music_play("theme")


func music_stop() -> void:
	_playing = ""
	for p in _music:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, FADE * 0.6)
			tw.tween_callback(p.stop)


## 最後十秒：曲子稍微加速，不換曲
func set_hurry(on: bool) -> void:
	if on == _hurry:
		return
	_hurry = on
	_apply_mods()


## 吃到木天蓼、貓飛起來的那十秒：音樂往上飄一點、也大聲一點。
## 用同一首曲子變調，而不是換曲 —— 十秒太短，換曲只會聽到兩次淡入淡出
func set_power(on: bool) -> void:
	if on == _powered:
		return
	_powered = on
	_apply_mods()


## 暫停時壓低音量（不是停掉 —— 停掉再開會從頭開始）
func set_paused(on: bool) -> void:
	if on == _ducked:
		return
	_ducked = on
	_apply_mods(0.2, 0.25)
