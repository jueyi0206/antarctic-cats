extends CanvasLayer
## 手機觸控（autoload「Touch」）。
##
##   左半邊　按住任何地方 → 那裡就長出一個搖桿
##             左右推 = 轉向（推多少轉多少）
##             往下拉 = 煞車
##   右半邊　點任何地方 → 跳
##   右上角　暫停
##
## 手機版**自動全速跑**：一路按著加速本來就是最佳解，與其要玩家用拇指一直頂著，
## 不如直接幫他按住，把搖桿留給真正需要判斷的事（轉向與煞車）。
##
## 只在關卡畫面生效。劇情畫面本來就能點擊翻頁，這一層完全不攔它的輸入。
## 沒有觸控螢幕就不畫也不攔；電腦上想試，按 T 強制打開（滑鼠當手指用）。

const STICK_RADIUS := 130.0      ## 推到底的距離
const DEAD_ZONE := 16.0          ## 這個範圍內當作沒推
const JUMP_HINT := Vector2(575.0, 1090.0)
const JUMP_HINT_R := 86.0
const PAUSE_RECT := Rect2(612.0, 24.0, 84.0, 84.0)

## 設計解析度。事件座標要換算回這個空間再判斷左右半邊，
## 不然視窗被縮放時（或 headless 測試裡根本沒有視窗）座標會整個跑掉
const DESIGN := Vector2(720.0, 1280.0)

const C_LINE := Color(1, 1, 1, 0.55)
const C_FILL := Color(1, 1, 1, 0.12)
const C_KNOB := Color(1, 1, 1, 0.34)

var forced := false              ## 電腦上按 T 強制顯示，用滑鼠測手感

var _ui: Control
var _level: Node = null
var _stick_id := -1              ## 正在當搖桿的那根手指
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _jump_ids := {}              ## 右半邊按著的手指
var _held := []                  ## 這一幀按著的動作，換場景時要放掉
var _seen_touch := false         ## 收過真正的觸控事件之後，就不再理會模擬出來的滑鼠


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.draw.connect(_draw_ui)
	add_child(_ui)


func active() -> bool:
	return _level != null and (forced or DisplayServer.is_touchscreen_available())


func _process(_delta: float) -> void:
	var cur := get_tree().current_scene
	var lv: Node = cur if cur != null and cur.has_method("start_stage") else null
	if lv != _level:
		_release_all()
		_level = lv
	_ui.visible = active()
	if not _ui.visible:
		if not _held.is_empty():
			_release_all()
		return
	_drive()
	_ui.queue_redraw()


## 把搖桿的位置換成實際的動作
func _drive() -> void:
	var running: bool = _level != null and int(_level.state) == 1 and not bool(_level.paused)
	if not running:
		_release_all()
		return

	var v := Vector2.ZERO
	if _stick_id != -1:
		v = _stick_pos - _stick_origin
		if v.length() < DEAD_ZONE:
			v = Vector2.ZERO
		else:
			v = v.limit_length(STICK_RADIUS) / STICK_RADIUS

	_hold("move_left", maxf(-v.x, 0.0))
	_hold("move_right", maxf(v.x, 0.0))
	# 往下拉是煞車；沒在煞車就自動全速
	var brake: float = maxf(v.y, 0.0)
	_hold("speed_down", brake)
	_hold("speed_up", 0.0 if brake > 0.25 else 1.0)


func _hold(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
		if not _held.has(action):
			_held.append(action)
	elif _held.has(action):
		Input.action_release(action)
		_held.erase(action)


func _release_all() -> void:
	for a in _held:
		Input.action_release(a)
	_held.clear()
	_stick_id = -1
	_jump_ids.clear()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_T:
		forced = not forced          # 電腦上測手感
		return
	if not active():
		return

	# Godot 會把觸控事件再複製一份成滑鼠事件（emulate_mouse_from_touch）。
	# 兩條都收的話，同一根手指會被當成兩根，搖桿的 index 會被滑鼠那條蓋掉。
	# 規則：看過真正的觸控事件之後就不再理滑鼠。
	# 電腦上按 T 測手感時沒有觸控事件，滑鼠那條才會生效。
	if event is InputEventScreenTouch:
		_seen_touch = true
		_touch(event.index, event.position, event.pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_seen_touch = true
		_drag(event.index, event.position)
	elif _seen_touch:
		return
	elif event is InputEventMouseButton:
		_touch(-2, event.position, event.pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _stick_id == -2:
		_drag(-2, event.position)


## 把事件座標換算成設計解析度下的座標
func _norm(pos: Vector2) -> Vector2:
	var size := get_viewport().get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		return pos
	return Vector2(pos.x / size.x * DESIGN.x, pos.y / size.y * DESIGN.y)


func _touch(id: int, pos: Vector2, pressed: bool) -> void:
	pos = _norm(pos)
	if not pressed:
		if id == _stick_id:
			_stick_id = -1
		_jump_ids.erase(id)
		return

	if PAUSE_RECT.has_point(pos):
		_send_key(KEY_ESCAPE)
		return
	if pos.x < 360.0:
		# 搖桿長在手指按下去的地方 —— 不用瞄準，也不會被拇指擋住
		_stick_id = id
		_stick_origin = pos
		_stick_pos = pos
	else:
		_jump_ids[id] = true
		_send_action("jump")


func _drag(id: int, pos: Vector2) -> void:
	pos = _norm(pos)
	if id == _stick_id:
		_stick_pos = pos


## 跳躍要送成真的輸入事件：Main 是在 _unhandled_input 裡用 is_action_pressed 判斷的，
## Input.action_press() 不會產生事件，按了不會跳
func _send_action(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)


func _send_key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)


func _draw_ui() -> void:
	var running: bool = _level != null and int(_level.state) == 1 and not bool(_level.paused)

	# 跳躍：右半邊整片都能按，右下角只是提示
	_ui.draw_circle(JUMP_HINT, JUMP_HINT_R, C_FILL)
	_ui.draw_arc(JUMP_HINT, JUMP_HINT_R, 0.0, TAU, 48, C_LINE, 3.0)
	var a := JUMP_HINT + Vector2(0, 16)
	_ui.draw_colored_polygon(PackedVector2Array([
		a + Vector2(0, -34), a + Vector2(22, -4), a + Vector2(-22, -4)]), C_LINE)

	# 暫停
	for i in 2:
		_ui.draw_rect(Rect2(PAUSE_RECT.position + Vector2(24 + i * 22, 22),
			Vector2(12, 40)), C_LINE)

	if not running:
		return
	if _stick_id == -1:
		# 沒按的時候，在左下角提示搖桿可以放哪裡
		_ui.draw_arc(Vector2(150, 1090), 74.0, 0.0, TAU, 40, Color(1, 1, 1, 0.18), 3.0)
		return
	_ui.draw_circle(_stick_origin, STICK_RADIUS, C_FILL)
	_ui.draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, C_LINE, 3.0)
	var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(STICK_RADIUS)
	_ui.draw_circle(knob, 46.0, C_KNOB)
	_ui.draw_arc(knob, 46.0, 0.0, TAU, 32, C_LINE, 3.0)
