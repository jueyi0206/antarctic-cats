extends Node
## 物理常數 —— 對應 docs/level-design.md 第 3 節。
##
## 這裡每一個數字目前都只是「按原作手感估的」，尚未被任何實際遊玩驗證過。
## 物理原型存在的唯一目的，就是把它們調到對。
## 遊戲中：Tab 選參數 / Q E 微調 / F5 存檔 / F9 載回。

const UNIT := "u (1u = 1px @ scale 1.0)"

# --- 賽道 ---
var track_width := 180.0      # 左右邊界外是海（288→180：繞圈賽道裡，寬度是空間預算的大宗）
var lane_width := 60.0        # 資料用的隱形車道寬（非格子制）

# --- 速度 ---
var speed_base := 240.0       # 不按任何鍵的巡航速度
var speed_max := 420.0        # 加速上限
var speed_min := 120.0        # 減速下限
var accel := 150.0            # u/s^2 → 240→420 約 1.2 秒
var lateral_speed := 200.0    # 左右移動

# --- 跳躍（關卡所有尺度的來源）---
var jump_airtime := 0.62      # 滯空時間，固定不隨速度變
var jump_height := 44.0       # 純視覺高度

# --- 懲罰（本作唯一的失敗貨幣：時間）---
var trip_penalty := 1.2       # 撞旗 / 撞海豹 / 撞浮冰
var fall_penalty := 2.0       # 掉進冰洞
var water_penalty := 1.5      # 衝出賽道落海
var fish_time := 0.5          # 吃到魚補回的時間（2.0→1.0→0.5：魚愈密，單條就得愈便宜）

# --- 玩家 ---
var player_radius := 13.0

# --- 貼圖動畫 ---
var step_len := 32.0          # 換一次腳要跑幾 u（越小腳步越快）
# 小玲每幾秒插一支紅旗（劇情裡她沿路做記號）。
# 3 秒的話旗子插完馬上就落到畫面外 —— 畫面裡她身後只看得到約 160u
var flag_period := 1.5

# 可在遊戲中即時調整的參數表：[屬性名, 每次調整量, 下限, 上限]
const TUNABLES := [
	["speed_base", 10.0, 60.0, 600.0],
	["speed_max", 10.0, 60.0, 900.0],
	["speed_min", 10.0, 40.0, 400.0],
	["accel", 10.0, 20.0, 600.0],
	["lateral_speed", 10.0, 40.0, 600.0],
	["step_len", 2.0, 10.0, 90.0],
	["flag_period", 0.5, 0.5, 12.0],
	["jump_airtime", 0.02, 0.20, 1.60],
	["jump_height", 2.0, 10.0, 120.0],
	["trip_penalty", 0.1, 0.0, 5.0],
	["fall_penalty", 0.1, 0.0, 5.0],
	["fish_time", 0.5, 0.0, 10.0],
	["track_width", 8.0, 120.0, 480.0],
]

## 以速度 v 起跳能跨越的水平距離
func jump_dist(v: float) -> float:
	return v * jump_airtime

## 基礎速度就跳得過的缺口上限（留 20% 安全邊際）→ 關卡「安全缺口」定義
func safe_gap() -> float:
	return jump_dist(speed_base) * 0.8

## 全速才跳得過的缺口上限 → 關卡「最大合法缺口」定義
func max_gap() -> float:
	return jump_dist(speed_max) * 0.8

func to_dict() -> Dictionary:
	var d := {}
	for t in TUNABLES:
		d[t[0]] = get(t[0])
	return d

func from_dict(d: Dictionary) -> void:
	for k in d.keys():
		if k in self:
			set(k, d[k])

func save_tuning() -> String:
	var path := "user://tuning.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "存檔失敗"
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return "已存到 " + ProjectSettings.globalize_path(path)

func load_tuning() -> String:
	var path := "user://tuning.json"
	if not FileAccess.file_exists(path):
		return "沒有 tuning.json"
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return "tuning.json 格式錯誤"
	from_dict(parsed)
	return "已載入 tuning.json"
