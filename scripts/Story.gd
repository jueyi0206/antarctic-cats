extends Control
## 劇情播放器。照 ../pinball/scripts/story.gd，拿掉網頁連結那一段。
##
## 畫面：上面一張插圖、下面文字框。台詞帶 "scene" 時換插圖，沒帶就沿用上一張。
## 插圖還沒放進 art/story/ 時，框裡顯示這張圖該畫什麼，看劇情就知道還缺哪張。

const CHARS_PER_SECOND := 34.0

@onready var _title: Label = $Title
@onready var _art: TextureRect = $Frame/Art
@onready var _placeholder: Label = $Frame/Placeholder
@onready var _who: Label = $Box/Lines/Who
@onready var _act: Label = $Box/Lines/Act
@onready var _body: Label = $Box/Lines/Body
@onready var _hint: Label = $Box/Hint

var _lines: Array = []
var _i := -1
var _revealed := 0.0
var _illustrations: Dictionary = {}
var _scene := ""
var _ended := false


func _ready() -> void:
	# 失敗那一段配失敗的收尾句（不循環），其他劇情都用主題曲
	Aud.music_play("lose" if Flow.beat == Flow.Beat.LOSE else "theme")
	_ignore_mouse(self)
	_lines = Flow.pending_lines
	_title.text = Flow.pending_title
	_title.visible = _title.text != ""
	_illustrations = Flow.campaign.get("illustrations", {})
	_placeholder.text = ""
	_advance_line()


func _process(delta: float) -> void:
	if _i < 0:
		return
	var total := float(_body.text.length())
	if _revealed < total:
		_revealed = minf(_revealed + CHARS_PER_SECOND * delta, total)
		_body.visible_characters = int(_revealed)
		_hint.visible = false
	else:
		_body.visible_characters = -1
		_hint.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE:
			# 測試用：整段跳過
			get_viewport().set_input_as_handled()
			if not _ended:
				Flow.story_finished()
			return
		if _ended and k == KEY_R:
			get_viewport().set_input_as_handled()
			Flow.start()
			return
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			# 先標記已處理再推進：最後一句會換場景，之後 get_viewport() 會是 null
			get_viewport().set_input_as_handled()
			_on_confirm()
		return
	var tapped: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		get_viewport().set_input_as_handled()
		_on_confirm()


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _on_confirm() -> void:
	# 第一下先把整句補完，第二下才換下一句
	var total := float(_body.text.length())
	if _revealed < total:
		_revealed = total
		return
	if _ended:
		return
	_advance_line()


func _advance_line() -> void:
	_i += 1
	if _i >= _lines.size():
		Flow.story_finished()
		return
	var line: Dictionary = _lines[_i]
	_who.text = str(line.get("who", ""))
	_who.visible = _who.text != ""
	var act := str(line.get("act", ""))
	_act.text = "（%s）" % act
	_act.visible = act != ""
	_body.text = str(line.get("text", ""))
	_body.visible_characters = 0
	_revealed = 0.0
	if Flow.pending_is_ending and _i == _lines.size() - 1:
		_ended = true
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_show_scene(str(line.get("scene", "")))
	if _ended:
		_hint.text = "—　全劇終　—　（按 R 再玩一次）"
	else:
		_hint.text = "Enter / 空白鍵　繼續　·　Esc 跳過"


func _show_scene(id: String) -> void:
	if id == "" or id == _scene:
		return
	_scene = id
	var info: Dictionary = _illustrations.get(id, {})
	var path := str(info.get("image", ""))
	if path != "" and ResourceLoader.exists(path):
		_art.texture = load(path)
		_placeholder.visible = false
		_art.modulate.a = 0.0
		create_tween().tween_property(_art, "modulate:a", 1.0, 0.25)
	else:
		_art.texture = null
		_placeholder.visible = true
		_placeholder.text = "插圖 %s（還沒放圖）\n\n%s" % [id, str(info.get("note", ""))]
