extends Node
## 結局的 QR code 兩頁要能點：檢查連結有進劇情檔。
##
## 「點下去真的開得了新分頁」只能在網頁版驗（桌面版 OS.has_feature("web") 是 false，
## WebLink 會直接跳過）。那一半請在手機或瀏覽器上實際點一次。

var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _ok(c: bool, m: String) -> void:
	print(("  ✓ " if c else "  × ") + m)
	if not c:
		fails += 1


func _run() -> void:
	var ill: Dictionary = Flow.campaign.get("illustrations", {})
	_ok(str(ill.get("ending_08", {}).get("link", "")).begins_with("https://www.facebook.com"),
		"FB 那頁有連結：%s" % ill.get("ending_08", {}).get("link", "（無）"))
	_ok(str(ill.get("ending_09", {}).get("link", "")).begins_with("https://www.instagram.com"),
		"IG 那頁有連結：%s" % ill.get("ending_09", {}).get("link", "（無）"))

	var with_link := 0
	for k in ill:
		if str(ill[k].get("link", "")) != "":
			with_link += 1
	_ok(with_link == 2, "只有那兩頁掛連結（共 %d 頁）" % with_link)

	# 結局的最後一句要停在 IG 那頁：玩家要有時間點它
	var ending: Array = Flow.campaign.get("ending", [])
	var last_scene := ""
	for line in ending:
		if str(line.get("scene", "")) != "":
			last_scene = str(line.get("scene"))
	_ok(last_scene == "ending_09", "最後停在 IG 那頁（實際 %s）" % last_scene)

	print("\n" + ("全部通過" if fails == 0 else "%d 項失敗" % fails))
	get_tree().quit(1 if fails else 0)
