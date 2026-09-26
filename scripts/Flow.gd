extends Node
## 遊戲流程（autoload 名稱：Flow）。照 ../pinball/scripts/game_flow.gd 的骨架。
##
##   開場劇情 → 關卡 → 過關劇情 → 下一章 → ... → 結局
##               ↑       │
##               └ 失敗劇情 ┘   （失敗劇情播完，重跑同一關，不重播開場）
##
## 劇情內容全部在 story/campaign.json（由 SCRIPT.md 產生），改劇情不用碰程式。
## 直接開 Main.tscn（編輯器 F6）時 driving = false，關卡維持原本的測試行為。

const CAMPAIGN_PATH := "res://story/campaign.json"
const STORY_SCENE := "res://scenes/Story.tscn"
const LEVEL_SCENE := "res://scenes/Main.tscn"

enum Beat { INTRO, LEVEL, OUTRO, ENDING, LOSE }

var driving := false
var campaign: Dictionary = {}
var chapter_index := 0
var beat: Beat = Beat.INTRO

## 給 Story.tscn 讀的
var pending_lines: Array = []
var pending_title := ""
var pending_is_ending := false


func _ready() -> void:
	var f := FileAccess.open(CAMPAIGN_PATH, FileAccess.READ)
	if f == null:
		push_error("找不到 %s" % CAMPAIGN_PATH)
		campaign = {"chapters": [], "ending": []}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	campaign = parsed if typeof(parsed) == TYPE_DICTIONARY else {"chapters": [], "ending": []}


func chapter_count() -> int:
	return (campaign.get("chapters", []) as Array).size()


func current_chapter() -> Dictionary:
	var list: Array = campaign.get("chapters", [])
	if chapter_index < 0 or chapter_index >= list.size():
		return {}
	return list[chapter_index]


## 這一章要跑哪個關卡檔
func stage_path() -> String:
	var lv: Dictionary = current_chapter().get("level", {})
	return "res://data/levels/%s.json" % str(lv.get("stage", "stage-01"))


## 這一章的任務卡：{title, lines}
func brief() -> Dictionary:
	return current_chapter().get("level", {}).get("brief", {})


# ── 流程 ────────────────────────────────────────────────────

func start(from_chapter := 0) -> void:
	driving = true
	chapter_index = from_chapter
	_go_intro()


func _go_intro() -> void:
	var ch := current_chapter()
	if ch.is_empty():
		_go_ending()
		return
	_play(Beat.INTRO, str(ch.get("title", "")), ch.get("intro", []))


func _go_level() -> void:
	beat = Beat.LEVEL
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _go_outro() -> void:
	var ch := current_chapter()
	_play(Beat.OUTRO, str(ch.get("outro_title", "")), ch.get("outro", []))


func _go_lose() -> void:
	var ch := current_chapter()
	_play(Beat.LOSE, str(ch.get("lose_title", "")), ch.get("lose", []))


func _go_ending() -> void:
	_play(Beat.ENDING, str(campaign.get("ending_title", "")), campaign.get("ending", []))


func _play(b: Beat, title: String, lines: Array) -> void:
	beat = b
	pending_title = title
	pending_lines = lines
	pending_is_ending = b == Beat.ENDING
	if lines.is_empty():
		story_finished()
		return
	get_tree().change_scene_to_file(STORY_SCENE)


func _next_chapter() -> void:
	chapter_index += 1
	if chapter_index >= chapter_count():
		_go_ending()
	else:
		_go_intro()


# ── 各場景回報 ──────────────────────────────────────────────

## Story.tscn 播完最後一句時呼叫
func story_finished() -> void:
	match beat:
		Beat.OUTRO:
			_next_chapter()
		Beat.ENDING:
			start()
		_:
			_go_level()     # 開場、失敗劇情播完都是去跑關卡


## Main.tscn 跑完一關時呼叫
func level_finished(won: bool) -> void:
	if not driving:
		return
	if won:
		_go_outro()
	else:
		_go_lose()
