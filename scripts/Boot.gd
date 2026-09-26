extends Node
## 遊戲入口：直接交給 Flow 從第一章開始。
## 想單獨測關卡，在編輯器開 Main.tscn 按 F6。


func _ready() -> void:
	Flow.start.call_deferred()
