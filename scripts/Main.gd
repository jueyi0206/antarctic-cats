extends Node2D
## 南極大冒險 —— 物理原型 / 手感實驗室
##
## 這支原型的任務不是「好玩」，是回答一個問題：
##   LEVELS.md 第 3 節那些常數，手感對不對？
## 所以它同時是遊戲、參數調整台、和關卡驗證器的輸出視窗。
##
## 設計單位 u 與螢幕像素刻意分開（SC = 渲染尺度）：
## 換畫面解析度時只動 SC，LEVELS.md 裡的所有數字都不必跟著改。

const SCREEN_W := 720.0
const SCREEN_H := 1280.0
const CENTER_X := 360.0
const PLAYER_Y := 1040.0       ## 玩家固定在畫面這個高度
const SC := 1.5                ## 1u = 1.5px
const VIEW_AHEAD := PLAYER_Y / SC

enum Mode { JUMP_LAB, STAGE }
enum State { READY, RUN, STUMBLE, CLEARED, TIMEUP }

# --- 賽道 ---
var builder := TrackBuilder.new()
var elements: Array = []
var widths: Array = [[0.0, 288.0]]
var track := TrackPath.new()        ## 封閉迴圈的賽道形狀
var lap_len := 4000.0              ## 一圈多長
var laps := 1                      ## 這一關要跑幾圈
var track_len := 6000.0
var time_limit := 40.0
var stage_name := ""
var stage_index := 0
var pal_sea := Color(0.13, 0.35, 0.55)
var pal_ice := Color(0.58, 0.69, 0.80)
## 這一關的地面會不會沿路變色（關卡檔的 "ground"）：farm_to_sea = 農村雪原 → 海邊
var ground_shift := ""
## 這一關的地形長相（關卡檔的 "terrain"）：snow 第一章的雪地、ice 第二章之後的冰原
var terrain := "snow"
var cur_sea := Color(0.13, 0.35, 0.55)     ## 這一幀實際用的顏色
var cur_ice := Color(0.58, 0.69, 0.80)
var decor: Array = []                      ## 路邊裝飾 {d, off, name, w}
var scatter: Array = []                    ## 路外的點綴（雪原的雪丘、海上的浮冰）
## 第四關路邊送行的海豹叔叔（關卡檔的 "waving"）。牠們不擋路、不會頂人，
## 就只是探出頭來左右晃 —— 第四章的劇情是牠們幫忙把魚頂上冰面，這是回禮
var wavers: Array = []
## 海豹拋過來的魚：{from_d, from_off, d, off, t}。
## 飛到小玲身上就自動吃掉 —— 第四章的劇情就是牠們幫忙把魚頂上冰面
var tossed: Array = []
const TOSS_FLY := 0.85         ## 飛多久（秒）
const TOSS_RANGE := 340.0      ## 玩家離海豹多遠時牠開始拋
## 小玲沿路插的紅旗。第二章她偷了一捆旗子做記號，第三章大家靠這些旗子找路 ——
## 所以這不是裝飾，是把劇情演在畫面上。純視覺，不參與碰撞
var trail: Array = []
var trail_t := 0.0
var trail_on := false
## 加分道具長什麼樣子（關卡檔的 "pickup"）。機制都一樣是 +50，只換外觀，
## 讓每一章路邊撿的東西跟著場景走：flag 小黃旗、catgrass 貓草、can 魚罐頭、
## lingflag 小玲去程插的紅旗（第四關回程，撿起來就是拔回來）
var pickup_style := "flag"
## 洞裡跳出來、碰到會加時間的東西（關卡檔的 "jumper"）：fish 魚、vole 田鼠
var jumper_style := "fish"
## 這一關的木天蓼能飛幾秒（第四關是獎勵關，飛久一點）
var power_time := POWER_TIME
var waving := false                        ## 這一關路邊有沒有海豹叔叔送行
var build_log: Array = []
var lab_labels: Array = []

# --- 遊戲狀態 ---
var mode: int = Mode.JUMP_LAB
var state: int = State.READY
var dist := 0.0
var off := 0.0
var speed := 240.0
var time_left := 40.0
var score := 0
var elapsed := 0.0
var fish_eaten := 0
var flags_taken := 0
var trips := 0
var falls := 0

# --- 跳躍 ---
var jumping := false
var jump_t := 0.0
var jump_start_d := 0.0
var last_jump_dist := 0.0      ## 上一次實際跳了多遠 —— 調參數時最重要的回饋
var last_jump_speed := 0.0

# --- 跌倒 ---
var stumble_t := 0.0
var invuln_t := 0.0
## 木天蓼：撿到之後短暫無敵。小玲會嗨到尾巴畫圓飛起來（純視覺，碰撞仍然照 invuln_t 判斷）
var power_t := 0.0                ## 爬起來之後的短暫無敵，不然會在原地撞個沒完

# --- UI ---
var hud: Label
var hud_full: Label
var center_label: Label
var log_label: Label
var tune_label: Label
var ui_layer: CanvasLayer
var test_buttons: Array = []   ## 測試用的直接失敗／過關，觸控模式下要收起來
var brief_panel: ColorRect         ## 任務卡（劇情模式、開跑前）
var brief_label: Label
var end_t := 0.0                   ## 過關／時間到之後過了多久。太快按空白會直接跳過結果
var toast := ""
var toast_t := 0.0
var show_help := true
var paused := false
var cornering := false             ## 這一刻是不是被彎道限速壓著
var _last_off := 0.0               ## 上一幀的橫向位置，用來算尾巴要甩多少
var trips_before_pick := 0
var mates: Array = []              ## 陪跑的小玲與竹竹
var prop_tex := {}                 ## 道具與地形的圖：art/props/<名字>.png
var cat_tint := Color(1, 1, 1, 1)   ## 畫貓時的著色，無敵閃爍用
var cat_tex := {}                  ## 貓的圖：key -> {狀態 -> Texture2D}。沒有圖就退回向量畫法
var _tick_at := 0            ## 上一次滴答是在第幾秒，避免同一秒響兩次
var tune_idx := 0
var font: Font
var cam_pos := Vector2.ZERO        ## 相機在世界上的位置（= 玩家）
var cam_rot := 0.0                 ## 相機轉角，讓前進方向永遠朝上

const FISH_LEAD := 260.0           ## 玩家還有這麼遠時，魚才開始躍出
const WIDTH_BLEND := 150.0         ## 賽道寬度變化的過渡距離
## 玩家操作的是小玲：跑在最後面、一直被笑的那一隻。莎莎和竹竹陪跑
## 貼圖是正方形畫布、貓擺在正中間（tools/cut_sprites.py 切的）。
## 畫面上的寬度 = 貓的半徑 × 這個數 —— 畫布四周有留白，所以要比向量貓大不少
const SPRITE_W := 5.2
const SPRITE_ANCHOR := 0.62      ## 貼圖上緣離腳下多高（佔貼圖高度的比例）
## 換一次腳要跑幾 u（Cfg.step_len）。用距離而不是時間：速度變快，腳步自然跟著變快。
## 步幅也會隨速度稍微拉長（衝刺是大步跨，不是小碎步跑更快），
## 不然全速時腳步快到只剩閃爍。
## 預設 32u：慢跑 120u/s 約 3.5 次／秒，巡航 240 約 6.5 次，全速 420 約 10 次。
const POWER_TIME := 10.0        ## 木天蓼的無敵秒數（預設；關卡檔可用 "powerTime" 蓋過）
const STEP_PER_SPEED := 0.02
## 轉彎時整隻貓傾斜幾弧度（滿舵時）。用跑步那兩張去傾斜，
## 所以轉彎時腳一樣在動 —— 左右各生一張靜態圖的話，一轉彎腳就停了
const LEAN_MAX := 0.32
const PLAYER_CAT := "ling"
const STAGE_COUNT := 4             ## 一共幾站（第四關是獎勵關）
const MAX_TURN_RATE := 1.9         ## 畫面每秒最多轉幾弧度 —— 彎道限速由它反推         ## 賽道寬度變化的過渡距離 —— 沒有它，窄道入口是一堵牆


func _ready() -> void:
	font = load("res://fonts/NotoSansTC-Game.ttf")
	if font == null:
		font = ThemeDB.fallback_font
	if not builder.load_segments():
		push_error("segments.json 載入失敗")
	_load_cat_textures()
	_load_prop_textures()
	_build_ui()
	if Flow.driving:
		start_stage(Flow.stage_path())
	else:
		start_stage("res://data/levels/stage-01.json")


# ============================================================ 關卡載入

func start_lab() -> void:
	## 手感實驗室：一排寬度遞增的缺口，用身體直接驗證「到底跳得過多寬」。
	mode = Mode.JUMP_LAB
	stage_name = "跳躍實驗室"
	stage_index = 0
	elements.clear()
	lab_labels.clear()
	widths = [[0.0, Cfg.track_width]]
	laps = 1
	lap_len = 9000.0
	track.build(0, lap_len)        # seed 0 = 正圓，半徑夠大所以局部幾乎是直線
	var gaps := [80, 100, 120, 140, 160, 180, 200, 220, 240]
	var d := 800.0
	for w in gaps:
		elements.append({"type": "crevasse", "d": d, "off": 0.0, "w": float(w),
			"full": true, "alive": true})
		lab_labels.append([d, w])
		d += 700.0
	for i in 6:
		elements.append({"type": "fish", "d": 500.0 + i * 900.0,
			"off": [-90.0, 0.0, 90.0][i % 3], "w": 24.0, "alive": true})
	track_len = min(d + 400.0, lap_len)
	time_limit = 999.0
	build_log = [
		"跳躍實驗室：缺口 80 → 240u，每個前面留 700u 助跑。",
		"待驗證：基礎速該跳過 %du、全速該跳過 %du。" % [int(Cfg.safe_gap()), int(Cfg.max_gap())],
		"跳完看 LAST JUMP —— 那是實際跳出來的距離。",
	]
	_reset_run()


func start_stage(path: String) -> void:
	var stage := builder.load_stage(path)
	if stage.is_empty():
		_toast("讀不到 " + path)
		return
	var r := builder.build(stage)
	mode = Mode.STAGE
	elements = r.elements
	widths = r.widths
	laps = int(stage.get("laps", 1))
	lap_len = r.length / float(maxi(laps, 1))
	track.build(int(stage.get("seed", 0)), lap_len, str(stage.get("layout", "simple")),
		int(stage.get("prototype", -1)), float(stage.get("minRadius", 90.0)))
	track_len = r.length
	time_limit = r.timeLimit
	stage_name = r.name
	if Flow.driving:
		# 劇情模式顯示劇本裡的關卡名（「第一關：跑到碼頭」取冒號後面）
		var lv_name := str(Flow.current_chapter().get("level", {}).get("name", ""))
		if lv_name != "":
			stage_name = lv_name.get_slice("：", lv_name.get_slice_count("：") - 1)
	stage_index = int(stage.get("index", 0))
	pickup_style = str(stage.get("pickup", "flag"))
	ground_shift = str(stage.get("ground", ""))
	waving = bool(stage.get("waving", false))
	terrain = str(stage.get("terrain", "snow"))
	trail_on = bool(stage.get("flagTrail", false))
	jumper_style = str(stage.get("jumper", "fish"))
	power_time = float(stage.get("powerTime", POWER_TIME))
	_apply_palette(str(stage.get("palette", "day_clear")))
	build_log = r.log
	lab_labels.clear()
	_clamp_elements()
	_build_decor(int(stage.get("seed", 0)))
	_reset_run()
	# 每一關一首（關卡檔可以用 "music" 指定，預設照站數）
	Aud.music_play(str(stage.get("music", "level%d" % maxi(stage_index, 1))))


func _apply_palette(name: String) -> void:
	## 三站走一圈南極，天色會變 —— 後段光看畫面就知道自己走多遠了
	match name:
		"dusk":
			pal_sea = Color(0.17, 0.25, 0.44); pal_ice = Color(0.54, 0.52, 0.67)
		"storm":
			pal_sea = Color(0.24, 0.33, 0.41); pal_ice = Color(0.52, 0.59, 0.65)
		"storm_dusk":
			pal_sea = Color(0.13, 0.17, 0.32); pal_ice = Color(0.44, 0.47, 0.60)
		"night":
			pal_sea = Color(0.05, 0.08, 0.18); pal_ice = Color(0.34, 0.40, 0.53)
		_:
			pal_sea = C_SEA; pal_ice = C_ICE


func _next_stage_path() -> String:
	var n := stage_index + 1
	return "" if n > STAGE_COUNT else "res://data/levels/stage-%02d.json" % n


## 冰原上不會有稻草堆和漁網 —— 路邊的東西要跟著這一關的地形換
const DECOR_ICE := ["ice_pillar", "scenery_floe_l", "scenery_mound"]
const SCATTER_ICE := ["scenery_floe_s", "scenery_floe_l", "scenery_mound", "ice_pillar"]


func _decor_pool(sea_mix: float, rng: RandomNumberGenerator) -> Array:
	if terrain == "ice":
		return DECOR_ICE
	return DECOR_SEA if rng.randf() < sea_mix else DECOR_FARM


func _scatter_pool(sea_t: float, rng: RandomNumberGenerator) -> Array:
	if terrain == "ice":
		return SCATTER_ICE
	return SCATTER_SEA if rng.randf() < sea_t else SCATTER_FARM


func _build_decor(seed_v: int) -> void:
	## 路邊的東西不參與碰撞，也不進 elements —— 它們純粹是風景，
	## 所以不必經過關卡驗證，也不會佔掉賽道的空間預算。
	## 位置由關卡的 seed 決定，同一關每次跑都長一樣。
	decor.clear()
	if prop_tex.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + 7
	var d := 200.0
	while d < track_len:
		d += rng.randf_range(260.0, 520.0)
		if rng.randf() < 0.18:
			continue                      # 偶爾留白，不然整條路像行道樹
		var p: float = clampf(d / maxf(track_len, 1.0), 0.0, 1.0)
		# 海邊的比重隨距離上升：0.3 之前全是農村，0.75 之後全是海邊
		var sea_mix: float = clampf((p - 0.30) / 0.45, 0.0, 1.0)
		var pool: Array = _decor_pool(sea_mix, rng)
		var name: String = pool[rng.randi() % pool.size()]
		if not prop_tex.has(name):
			continue
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		var tex: Texture2D = prop_tex[name]
		var w: float = tex.get_width() * DECOR_PX * rng.randf_range(0.85, 1.15)
		# 貼著路邊擺：離賽道邊緣半個自己的寬度再多一點，才不會壓到路面
		var off: float = side * (_track_half_at(d) + w / SC * 0.5 + rng.randf_range(14.0, 60.0))
		decor.append({"d": d, "off": off, "name": name, "w": w})

	# 路外的點綴：擺得更遠，數量更多。純粹填滿雪原與海面，不會靠近賽道
	# 路邊送行的海豹：間隔比裝飾大，貼著路緣，才看得清楚在揮手
	wavers.clear()
	if waving and (prop_tex.has("ice_seal_wave") or prop_tex.has("ice_seal_peek")):
		var wd := 400.0
		while wd < track_len - 400.0:
			wd += rng.randf_range(520.0, 900.0)
			var wside: float = 1.0 if rng.randf() < 0.5 else -1.0
			wavers.append({
				"d": wd,
				"off": wside * (_track_half_at(wd) + rng.randf_range(34.0, 78.0)),
				"phase": rng.randf() * TAU,
				"w": rng.randf_range(0.85, 1.15),
			})

	scatter.clear()
	var sd := 0.0
	while sd < track_len:
		sd += rng.randf_range(90.0, 220.0)
		var sp: float = clampf(sd / maxf(track_len, 1.0), 0.0, 1.0)
		var sea_t: float = clampf((sp - 0.30) / 0.45, 0.0, 1.0)
		var spool: Array = _scatter_pool(sea_t, rng)
		var sname: String = spool[rng.randi() % spool.size()]
		if not prop_tex.has(sname):
			continue
		var sside: float = 1.0 if rng.randf() < 0.5 else -1.0
		var sw: float = float(prop_tex[sname].get_width()) * SCATTER_PX * rng.randf_range(0.7, 1.4)
		# 只有離路緣 ~150u 以內看得到（畫面寬 720px、SC 1.5），擺太遠等於沒畫
		var soff: float = sside * (_track_half_at(sd) + rng.randf_range(60.0, 210.0))
		scatter.append({"d": sd, "off": soff, "name": sname, "w": sw})


func _clamp_elements() -> void:
	## TrackBuilder 夾限時還不知道賽道形狀（彎道會收緊），所以載入後再收一次
	for e in elements:
		var margin := 24.0
		if e.type == "cheer":
			margin = 12.0
		elif str(e.type).begins_with("hole"):
			margin = float(e.w) * 0.42
		var lim: float = maxf(_track_half_at(float(e.d)) - margin, 0.0)
		e["off"] = clampf(float(e.off), -lim, lim)
		if e.has("base_off"):
			e["base_off"] = clampf(float(e.base_off), -lim, lim)


## 五張關鍵姿勢就夠：跑、左、右、跳、撞。
## 剩下的動態（起伏、縮放、抖動）由程式補 —— 讓 AI 生一整套幀動畫，
## 同一隻貓很難維持長得一樣，五張的一致性好控制得多。
## 跑步兩張交替換腳；轉彎不換圖，直接把跑步的圖整隻傾斜（見 LEAN_MAX），
## 所以不需要左傾／右傾的圖。
## 陪跑的兩隻不會跌倒，但你跌倒時她們會回頭笑 —— 所以有 laugh 沒有 hit
## fly（腳縮起來、沒有尾巴）與 tail（單獨一條尾巴）只有玩家用得到，
## 吃到木天蓼變竹蜻蜓時把尾巴單獨轉起來
const CAT_POSES := ["run", "run2", "jump", "hit", "laugh", "fly", "tail"]

## 你跌倒時她們說的話。會隨次數升級 —— 貓是會記得的。
## 竹竹大部分時候只有「…………」，那是他的預設反應，偶爾才吐一句。
const LAUGH_LINES := {
	"sasa": {
		"early": ["噗，地板很香厚？", "欸，腳打結了嗎？", "哎唷，是在拜年逆？",
			"妳是在演哪齣？"],
		"mid": ["又來？眼睛放口袋嗎？", "地板是不是跟妳有仇！", "我阿嬤都走比妳穩。"],
		"late": ["乾脆用爬的比較快啦。", "要不要幫妳叫救護車？", "好了啦，回家躺著啦。"],
	},
	"zhuzhu": {
		"early": ["…………", "很痛？", "躺著舒服？"],
		"mid": ["…………", "起來，很丟臉。", "妳在擦地板？"],
		"late": ["…………", "釘在那裡算了。", "需要輪椅嗎。", "習慣了。"],
	},
}

## 時間快用完的時候，她們不笑了。
##
## 這是全劇唯一安靜的那一刻，而且它是用機制演的，不是用台詞講的：
## 玩家跑了三關，已經習慣「跌倒 = 被笑」。所以當他在最後十秒又跌倒、
## 卻沒有被笑的時候，他會自己發現。
##
## 不要給任何提示。不要做成過場。這一刻的效果完全來自「他本來預期會被笑」。
const URGENT_LINES := {
	"sasa": ["快起來。", "還來得及。", "走了走了。"],
	"zhuzhu": ["還有時間。", "起來。"],
}

## 撿到東西時的稱讚。短就好 —— 而且刻意不是每次都講。
const PRAISE_LINES := {
	"sasa": ["真棒", "厲害喔", "好欸"],
	"zhuzhu": ["不錯。", "可以。", "有了。"],
}


## 道具與地形的圖。少一張就退回程式畫法，所以不用一次到齊
## 任務卡的排版
const BRIEF_FONT := 25
const BRIEF_GAP := 8
const BRIEF_PAD := 28.0
const PROP_NAMES := ["props_grass_s", "props_grass_m", "props_grass_l",
	"props_vole_peek", "props_vole_up", "props_burrow",
	"holes_pit_m", "holes_pit_l", "holes_puddle",
	"decor_hay", "decor_fence", "decor_tree", "decor_shed",
	"decor_piling", "decor_boat", "decor_crates", "decor_net",
	"scenery_dock", "scenery_floe_s", "scenery_floe_l",
	"scenery_mound", "scenery_reeds", "scenery_ice",
	"ice_flag", "ice_can", "ice_pillar", "ice_seal_peek", "ice_seal_up", "ice_fish",
	"ice_seal_wave",
	"icehole_s", "icehole_m", "icehole_l", "icehole_crack"]
## 路外的點綴：雪原上是雪丘、枯蘆葦、結冰的水漥；海上是浮冰
const SCATTER_FARM := ["scenery_mound", "scenery_reeds", "scenery_ice"]
const SCATTER_SEA := ["scenery_floe_s", "scenery_floe_l"]
const SCATTER_PX := 0.30
## 路邊裝飾：前半段是農村，後半段是海邊。中間那一段兩邊都會出現，
## 所以「農村慢慢變成海邊」是漸層的，不是某一格突然換場
const DECOR_FARM := ["decor_hay", "decor_fence", "decor_tree", "decor_shed"]
const DECOR_SEA := ["decor_piling", "decor_boat", "decor_crates", "decor_net"]
const DECOR_PX := 0.26
## 道具貼圖的縮放：畫面像素 / 貼圖像素。貓草與田鼠照這個畫，
## 洞則是照元素自己的寬度縮放（碰撞範圍多大，洞就畫多大）
const PROP_PX := 0.22
## 貓草要比田鼠大一點：它是路邊的加分道具，看不見就撿不到
const GRASS_PX := 0.30
## 洞的圖比碰撞範圍大一點 —— 雪堆的邊緣本來就不算在洞裡
const HOLE_ART := 1.3


func _load_prop_textures() -> void:
	for n in PROP_NAMES:
		var path := "res://art/props/%s.png" % n
		if ResourceLoader.exists(path):
			prop_tex[n] = load(path)


func _load_cat_textures() -> void:
	for key in CATS.keys():
		cat_tex[key] = {}
		for pose in CAT_POSES:
			var path := "res://art/cats/%s_%s.png" % [key, pose]
			if ResourceLoader.exists(path):
				cat_tex[key][pose] = load(path)


func _spawn_mates() -> void:
	## 小玲與竹竹不參與碰撞、不影響玩家 —— 她們純粹是演出。
	## 但「演得像在跑同一條路」比什麼都重要，所以她們會撞、會跌、會追。
	mates = [
		{   # 莎莎：衝第一、東奔西跑。老遠就開始繞，繞完發現自己跑太偏又急著追回來
			"key": "sasa", "dist": -60.0, "off": -40.0, "target": -40.0,
			"speed": Cfg.speed_base, "stumble": 0.0, "think": 0.0, "jump": -1.0,
			"lead": 95.0,          # 想待在玩家前方多遠
			"wander": 70.0,        # 左右晃的幅度
			"laugh": "", "taunt": 0.0, "say": "", "say_t": 0.0,
			"teleport": false,
		},
		{   # 竹竹：慢吞吞，常常落後。但只要跑出畫面，他就會出現在你前面。
			"key": "zhuzhu", "dist": 160.0, "off": 45.0, "target": 45.0,
			"speed": Cfg.speed_base * 0.9, "stumble": 0.0, "think": 0.0, "jump": -1.0,
			"lead": 175.0,
			"wander": 28.0,
			"laugh": "", "taunt": 0.0, "say": "", "say_t": 0.0,
			"teleport": true,      # 那個「從不跑卻先到」的笑點
		},
	]


func _update_mates(delta: float) -> void:
	if state != State.RUN and state != State.STUMBLE:
		return
	var half := _track_half_at(dist)

	# 你一跌倒，兩隻立刻出現在你旁邊 —— 不是跑回來，是瞬間就在那裡。
	# 然後笑你。這是整個陪跑系統最重要的一段。
	if state == State.STUMBLE:
		for m in mates:
			m.jump = -1.0
			# 莎莎在右、竹竹在左
			var slot: float = 62.0 if str(m.key) == "sasa" else -62.0
			m.target = clampf(slot, -half + 18.0, half - 18.0)
			m.dist = dist + 26.0          # 站在你前面一點，回頭看你
			m.off = float(m.target)
		return

	for m in mates:
		if float(m.say_t) > 0.0:
			m.say_t = float(m.say_t) - delta

		# 繞你一圈再跑走
		if float(m.taunt) > 0.0:
			m.taunt = float(m.taunt) - delta
			var a: float = (1.0 - float(m.taunt) / 1.25) * TAU
			m.dist = dist + 30.0 + cos(a) * 95.0
			m.off = clampf(sin(a) * 78.0, -half + 18.0, half - 18.0)
			m.target = float(m.off)
			continue

		# 想待在玩家附近的某個相對位置，差太多就加速／放慢
		var want: float = dist + float(m.lead)
		var diff: float = want - float(m.dist)
		# 下限必須是 0：玩家跌倒時 dist 不動，同伴要停下來等。
		# 原本設 speed_min * 0.6，於是她們一路跑出畫面再也回不來。
		var base_speed: float = 0.0 if state == State.STUMBLE else speed
		var target_speed: float = clampf(base_speed + diff * 2.0, 0.0,
			Cfg.speed_max * 1.15)
		m.speed = move_toward(float(m.speed), target_speed, Cfg.accel * 1.6 * delta)
		m.dist = float(m.dist) + float(m.speed) * delta

		# 竹竹：掉出畫面就傳送到前面。玩家永遠看不到他怎麼超過去的。
		if m.teleport and float(m.dist) < dist - 40.0:
			m.dist = dist + randf_range(300.0, 560.0)
			m.off = randf_range(-half * 0.6, half * 0.6)

		# 東奔西跑：每隔一陣子換一個橫向目標
		m.think = float(m.think) - delta
		if m.think <= 0.0:
			m.think = randf_range(0.5, 1.6)
			m.target = clampf(randf_range(-1.0, 1.0) * float(m.wander),
				-half + 20.0, half - 20.0)
			if randf() < 0.12:
				m.jump = 0.0                      # 沒事跳一下

		# 前面有洞就跳過去。她們是無敵的，跳不跳都不會怎樣 ——
		# 但「看到洞會跳」讓她們像在跑同一條路，而不是飄過去的貼圖
		if float(m.jump) < 0.0 and _hole_ahead(float(m.dist), float(m.off)):
			m.jump = 0.0
		m.off = move_toward(float(m.off), float(m.target), Cfg.lateral_speed * 1.1 * delta)

		if float(m.jump) >= 0.0:
			m.jump = float(m.jump) + delta
			if float(m.jump) > Cfg.jump_airtime:
				m.jump = -1.0

		# 常駐畫面：不管跌了幾次、追得多慢，都不准跑出視野。
		# 她們是演出，看不到就沒有意義。
		m.dist = clampf(float(m.dist), dist - 70.0, dist + VIEW_AHEAD * 0.82)


func _hole_ahead(d: float, o: float) -> bool:
	## 這個位置再往前一點會不會踩到洞。起跳點抓在洞前 40~110u，
	## 跟玩家在同樣的距離起跳（滯空 0.62 秒，跳得過去）
	for e in elements:
		if not e.get("alive", true):
			continue
		var t := str(e.type)
		if t != "crevasse" and not t.begins_with("hole"):
			continue
		var gap: float = float(e.d) - d
		if gap < 40.0 or gap > 110.0:
			continue
		if t == "crevasse" or absf(float(e.off) - o) < float(e.w) * 0.6:
			return true
	return false


func _reset_run() -> void:
	dist = 0.0
	off = 0.0
	speed = Cfg.speed_base
	time_left = time_limit
	score = 0
	elapsed = 0.0
	fish_eaten = 0
	flags_taken = 0
	trips = 0
	falls = 0
	jumping = false
	jump_t = 0.0
	stumble_t = 0.0
	invuln_t = 0.0
	power_t = 0.0
	_tick_at = 0
	end_t = 0.0
	Aud.set_power(false)
	trail.clear()
	trail_t = Cfg.flag_period
	tossed.clear()
	for wv in wavers:
		wv["thrown"] = false
	state = State.READY
	_spawn_mates()
	for e in elements:
		e["alive"] = true
		e["fish_done"] = false
		e["fish_t"] = 0.0
		e.erase("seal_cool")
		if e.has("base_off"):
			e["off"] = e["base_off"]


# ============================================================ 主迴圈

func _process(delta: float) -> void:
	if paused:
		_update_ui()
		queue_redraw()
		return

	if toast_t > 0.0:
		toast_t -= delta

	match state:
		State.RUN:
			_step_run(delta)
		State.STUMBLE:
			stumble_t -= delta
			elapsed += delta
			if mode == Mode.STAGE:
				time_left -= delta
				if time_left <= 0.0:
					time_left = 0.0
					state = State.TIMEUP
			if stumble_t <= 0.0:
				state = State.RUN
				_mates_taunt()
		State.CLEARED, State.TIMEUP:
			end_t += delta
		_:
			pass

	_update_moving()
	_update_mates(delta)
	_update_fish(delta)
	_update_ui()
	queue_redraw()


func _step_run(delta: float) -> void:
	elapsed += delta

	# 速度
	var target := Cfg.speed_base
	if Input.is_action_pressed("speed_up"):
		target = Cfg.speed_max
	elif Input.is_action_pressed("speed_down"):
		target = Cfg.speed_min
	speed = move_toward(speed, target, Cfg.accel * delta)

	# 過彎極限：轉向速率 = 速度 / 曲率半徑，把它壓在 MAX_TURN_RATE 以內。
	# 對玩家來說就是「髮夾要減速」——賽車遊戲的核心樂趣，也是時間會流失的地方。
	var corner_limit: float = maxf(track.radius_at(dist) * MAX_TURN_RATE, Cfg.speed_min)
	speed = minf(speed, corner_limit)
	cornering = speed < Cfg.speed_base * 0.92

	dist += speed * delta

	# 橫向
	var lat := Input.get_axis("move_left", "move_right")
	off += lat * Cfg.lateral_speed * delta
	off += _blizzard_push() * delta

	# 跳躍
	if invuln_t > 0.0:
		invuln_t -= delta
	if power_t > 0.0:
		power_t = maxf(power_t - delta, 0.0)
		if power_t <= 0.0:
			# 先放提示音再切音高：讓那顆音蓋住音樂變回原速的瞬間
			Aud.play("power_off")
			Aud.set_power(false)
			_toast("無敵結束")

	if jumping:
		jump_t += delta
		if jump_t >= Cfg.jump_airtime:
			jumping = false
			last_jump_dist = dist - jump_start_d
			Aud.play("land", randf_range(0.94, 1.08), -3.0)

	# 出界落海
	var half := _track_half_at(dist)
	if abs(off) > half:
		off = clampf(off, -half + 4.0, half - 4.0)
		_stumble(Cfg.water_penalty, "落海")
		return

	if mode == Mode.STAGE:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			Aud.play("timeup")
			Aud.music_stop()
			state = State.TIMEUP
			return

		# 最後十秒：曲子催快，每秒一記滴答
		var hurry := time_left < 10.0
		Aud.set_hurry(hurry)
		if hurry and int(time_left) != _tick_at:
			_tick_at = int(time_left)
			Aud.play("tick", 1.0 + (10.0 - time_left) * 0.03)

	# 邊跑邊插旗
	if trail_on:
		trail_t -= delta
		if trail_t <= 0.0:
			trail_t = Cfg.flag_period
			# 插在腳邊、偏左或偏右：正下方會被小玲自己的身體蓋住，
			# 而且擺在同一個距離（不是身後）能在畫面上多停留半秒
			trail.append({"d": dist - 6.0, "off": off + (34.0 if randf() < 0.5 else -34.0),
				"t": elapsed})
			Aud.play("flag", randf_range(0.94, 1.08))
			if trail.size() > 400:
				trail.remove_at(0)

	if waving:
		_update_toss(delta)

	_check_collisions()

	if dist >= track_len:
		Aud.play_goal()
		Aud.set_hurry(false)
		_throw_confetti()
		state = State.CLEARED
		if mode == Mode.STAGE:
			score += int(time_left * 100.0)


func _update_fish(delta: float) -> void:
	## 魚以「玩家距離」為時鐘：進入 FISH_LEAD 才起跳，所以你一定看得到牠在空中。
	for e in elements:
		if not e.has("fish") or e.get("fish_done", false):
			continue
		var gap: float = e.d - dist
		if gap < FISH_LEAD and gap > -100.0:
			var period: float = float(e.fish.get("period", 2.4))
			var t: float = float(e.get("fish_t", 0.0)) + delta
			e["fish_t"] = 0.0 if t > period else t
		else:
			e["fish_t"] = 0.0


func _fish_up(e: Dictionary) -> bool:
	if e.get("fish_done", false):
		return false
	return float(e.get("fish_t", 0.0)) > 0.0 		and float(e.fish_t) < float(e.fish.get("up", 1.6))


func _fish_phase(e: Dictionary) -> float:
	return clampf(float(e.get("fish_t", 0.0)) / maxf(float(e.fish.get("up", 1.6)), 0.001), 0.0, 1.0)


func _update_toss(delta: float) -> void:
	## 海豹看到小玲跑過來，就把魚朝她拋過去。
	## 這是獎勵關，魚會追著她飛、一定接得到 —— 不用瞄、不用繞，張嘴就有
	for wv in wavers:
		if wv.get("thrown", false):
			continue
		var gap: float = float(wv.d) - dist
		if gap > TOSS_RANGE or gap < -40.0:
			continue
		wv["thrown"] = true
		tossed.append({
			"from_d": float(wv.d), "from_off": float(wv.off),
			"d": dist, "off": off,          # 落點每幀更新成小玲現在的位置
			"t": 0.0,
		})

	var caught := []
	for f in tossed:
		f["t"] = minf(float(f.t) + delta / TOSS_FLY, 1.0)
		# 追蹤：終點一直修正成小玲當下的位置，所以她怎麼閃都會落在嘴邊
		f["d"] = dist + speed * TOSS_FLY * (1.0 - float(f.t)) * 0.35
		f["off"] = off
		if float(f.t) >= 1.0:
			caught.append(f)
	for f in caught:
		tossed.erase(f)
		fish_eaten += 1
		score += 100
		time_left = min(time_left + Cfg.fish_time, time_limit)
		Aud.play("fish", randf_range(0.99, 1.04), -2.0)
		_mates_praise(0.25)
		_toast("海豹叔叔請客　+%.1fs" % Cfg.fish_time)


func _update_moving() -> void:
	for e in elements:
		if e.type == "ice_block":
			var rng: float = max(float(e.get("range", 120.0)), 1.0)
			e["off"] = e.base_off + sin(elapsed * float(e.speed) / rng) * rng * 0.5


# ============================================================ 碰撞

func _check_collisions() -> void:
	var safe := invuln_t > 0.0
	var half := _track_half_at(dist)
	for e in elements:
		if not e.get("alive", true):
			continue
		var dd: float = e.d - dist
		var ex: float = float(e.off)

		# 冰洞裡跳出來的魚 —— 跳躍中也吃得到，所以「跳過洞順手撈一條」是成立的
		if e.has("fish") and _fish_up(e):
			var r_f: float = float(e.w) * 0.5 + 20.0
			if abs(dd) < r_f and abs(ex - off) < r_f:
					e["fish_done"] = true      # 吃掉了就沒了，不會再長回來
					e["fish_t"] = 0.0
					fish_eaten += 1
					score += 100
					time_left = min(time_left + Cfg.fish_time, time_limit)
					Aud.play("fish", randf_range(0.99, 1.04), -2.0)
					_mates_praise(0.32)
					_toast("+%.1fs" % Cfg.fish_time)

		# 撿的東西放在無敵判斷之前：無敵時還是撿得到，不然吃了木天蓼反而什麼都拿不到
		if e.type == "power":
			if absf(dd) < 30.0 and absf(ex - off) < 34.0:
				e["alive"] = false
				power_t = power_time
				invuln_t = maxf(invuln_t, power_time)
				score += 200
				Aud.play("power")
				Aud.set_power(true)
				_mates_praise(0.9)
				_toast("木天蓼！無敵 %d 秒" % int(power_time))
				continue
		elif e.type == "cheer":
			if absf(dd) < 20.0 and absf(ex - off) < 24.0:
				e["alive"] = false
				flags_taken += 1
				score += 50
				Aud.play("point", randf_range(0.99, 1.03), 2.0)
				_mates_praise(0.18)
				_toast("+50")
				continue

		if safe:
			continue

		match e.type:
			"fish":
				if abs(dd) < 22.0 and abs(ex - off) < 26.0:
					e["alive"] = false
					fish_eaten += 1
					score += 100
					time_left = min(time_left + Cfg.fish_time, time_limit)
					Aud.play("fish", randf_range(0.99, 1.04), -2.0)
					_mates_praise(0.32)
					_toast("+%.1fs" % Cfg.fish_time)
			"crevasse":
				if jumping:
					continue
				if abs(dd) < e.w * 0.5:
					dist = e.d + e.w * 0.5 + 20.0
					_stumble(Cfg.fall_penalty, "掉進裂縫")
					return
			"hole_s", "hole_m", "hole_l":
				var r: float = e.w * 0.5
				if abs(dd) >= r or abs(ex - off) >= r:
					continue
				# 海豹探出頭時，跳過去也一樣被頂飛 —— 這個洞只能繞，不能跳
				if _cycle_up(e.get("seal", {}), float(e.get("seal_cool", -1.0))):
					off = clampf(off + 46.0 * signf(off - ex + 0.01), -half, half)
					e["seal_cool"] = elapsed + 3.0      # 頂完就縮回去
					_stumble(Cfg.trip_penalty, "被海豹頂飛")
					return
				if jumping:
					continue
				dist = e.d + r + 20.0
				_stumble(Cfg.fall_penalty, "掉進冰洞")
				return
			"flag":
				if abs(dd) < 12.0 and abs(ex - off) < 14.0:
					e["alive"] = false                  # 撞倒了就是倒了
					_stumble(Cfg.trip_penalty, "撞到旗竿")
					return
			"ice_block":
				if abs(dd) < 26.0 and abs(ex - off) < 26.0:
					_stumble(Cfg.trip_penalty, "撞到浮冰")
					return


func _pick_laugh_lines() -> void:
	## 跌倒的當下就決定要說什麼，之後每幀都用同一句
	# 最後十秒不笑。時限寬裕的關卡幾乎不會踩到，所以實際上這件事
	# 幾乎只發生在第三關 —— 也就是最難、最可能撐不住的那一關。
	var urgent := mode == Mode.STAGE and time_left < 10.0

	var n := trips + falls
	var tier := "early"
	if n >= 6:
		tier = "late"
	elif n >= 3:
		tier = "mid"

	# 不是每次跌倒都會被笑。兩隻每次都喊，笑點會被講爛 ——
	# 有時候沒人出聲，反而讓出聲的那次有份量。跌越多次越可能被笑（她們也是會煩的）。
	# 最後十秒那句話很重要，一定要說出來，所以不受這個機率影響。
	var chance: float = {"early": 0.40, "mid": 0.50, "late": 0.60}[tier]
	for m in mates:
		if not urgent and randf() > chance:
			m.laugh = ""
			continue
		var pool: Array = URGENT_LINES[str(m.key)] if urgent 			else LAUGH_LINES[str(m.key)][tier]
		m.laugh = pool[randi() % pool.size()]


func _mates_praise(chance: float) -> void:
	## 撿到東西時隨機挑一隻出聲。兩隻一起講會洗版。
	if randf() > chance or mates.is_empty():
		return
	var m: Dictionary = mates[randi() % mates.size()]
	if float(m.say_t) > 0.0:
		return
	var pool: Array = PRAISE_LINES[str(m.key)]
	m.say = pool[randi() % pool.size()]
	m.say_t = 1.4


func _mates_taunt() -> void:
	## 你爬起來之後，小玲會繞你一圈才跑走。竹竹不會 —— 他不做這種事。
	for m in mates:
		if str(m.key) == "sasa":
			m.taunt = 1.25


func _stumble(penalty: float, kind: String) -> void:
	if kind == "被海豹頂飛":
		Aud.play("seal")
	elif penalty >= Cfg.fall_penalty or kind == "落海":
		Aud.play("splash", randf_range(0.95, 1.06))
	else:
		Aud.play("trip", randf_range(0.95, 1.08))
	state = State.STUMBLE
	stumble_t = penalty
	invuln_t = penalty + 1.0
	trips_before_pick = trips + falls   ## 爬起來還有 1 秒 —— 全速下等於 420u 的緩衝
	jumping = false
	speed = Cfg.speed_base
	if penalty >= Cfg.fall_penalty:
		falls += 1
	else:
		trips += 1
	_pick_laugh_lines()
	_toast("%s  -%.1fs" % [kind, penalty])


func _cycle_up(s: Dictionary, cool_until: float = -1.0) -> bool:
	## 海豹探頭 / 魚躍出，共用同一組週期定義
	if s.is_empty() or elapsed < cool_until:
		return false
	return fmod(elapsed + float(s.get("phase", 0.0)), float(s.get("period", 2.4))) 		< float(s.get("up", 1.0))


func _cycle_index(s: Dictionary) -> int:
	## 第幾次露出 —— 同一次露出的魚只能吃一條
	var period: float = float(s.get("period", 2.4))
	return int((elapsed + float(s.get("phase", 0.0))) / period)


func _cycle_t(s: Dictionary) -> float:
	## 這次露出進行到幾成（0~1），畫動畫用
	var period: float = float(s.get("period", 2.4))
	var up: float = maxf(float(s.get("up", 1.0)), 0.001)
	return clampf(fmod(elapsed + float(s.get("phase", 0.0)), period) / up, 0.0, 1.0)


func _track_half_at(d: float) -> float:
	## 寬度變化要漸進。階梯式的寬度會讓邊界在畫面上瞬移，
	## 加上取樣相位每幀不同，看起來就是整條路在抖。
	var w := Cfg.track_width
	var prev_w := w
	var at := -99999.0
	for pair in widths:
		if pair[0] <= d:
			prev_w = w
			w = pair[1]
			at = pair[0]
		else:
			break
	if at > -99998.0 and prev_w != w and d < at + WIDTH_BLEND:
		var t: float = (d - at) / WIDTH_BLEND
		w = lerpf(prev_w, w, t * t * (3.0 - 2.0 * t))
	return w * 0.5


func _blizzard_push() -> float:
	for e in elements:
		if e.type == "blizzard" and dist >= e.d and dist <= e.d + float(e.get("len", 400.0)):
			return float(e.get("push", 40.0))
	return 0.0


func _in_blizzard() -> bool:
	for e in elements:
		if e.type == "blizzard" and dist >= e.d and dist <= e.d + float(e.get("len", 400.0)):
			return true
	return false


# ============================================================ 輸入

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		# 劇情模式：過關／時間到之後，空白鍵交回給 Flow 播劇情
		if Flow.driving and (state == State.CLEARED or state == State.TIMEUP):
			if end_t > 0.8:
				_finish_level()
			return
		if state == State.CLEARED and mode == Mode.STAGE:
			var nxt := _next_stage_path()
			if nxt != "":
				start_stage(nxt)
			else:
				_toast("全部跑完了！")
			return
		if state == State.READY:
			state = State.RUN
		elif state == State.RUN and not jumping:
			jumping = true
			jump_t = 0.0
			jump_start_d = dist
			last_jump_speed = speed
			Aud.play("jump", randf_range(0.96, 1.05))
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if state == State.READY:
		state = State.RUN

	match event.keycode:
		KEY_R:
			_reset_run()
		KEY_F:                            # 測試用：直接失敗
			_force_end(false)
		KEY_G:                            # 測試用：直接過關
			_force_end(true)
		KEY_N:
			var nxt := _next_stage_path()
			if nxt != "":
				start_stage(nxt)
		KEY_PERIOD:                       # 測試用：往前跳 1000u
			dist = minf(dist + 1000.0, track_len - 20.0)
			_toast("跳到 %du（%d%%）" % [int(dist), int(dist / track_len * 100.0)])
		KEY_COMMA:                        # 測試用：往後退 1000u
			dist = maxf(dist - 1000.0, 0.0)
			_toast("退到 %du（%d%%）" % [int(dist), int(dist / track_len * 100.0)])
		KEY_B:                            # 測試用：跳到下一段暴風雪
			_jump_to_blizzard()
		KEY_1:
			start_stage("res://data/levels/stage-01.json")
		KEY_2:
			start_stage("res://data/levels/stage-02.json")
		KEY_3:
			start_stage("res://data/levels/stage-03.json")
		KEY_4:
			start_stage("res://data/levels/stage-04.json")
		KEY_L:
			start_lab()
		KEY_H:
			show_help = not show_help
		KEY_P:
			tune_label.visible = not tune_label.visible
		KEY_TAB:
			tune_idx = (tune_idx + 1) % Cfg.TUNABLES.size()
		KEY_Q:
			_tune(-1)
		KEY_E:
			_tune(1)
		KEY_F5:
			_toast(Cfg.save_tuning())
		KEY_F9:
			_toast(Cfg.load_tuning())
		KEY_ESCAPE:
			if event.shift_pressed:
				get_tree().quit()
			else:
				paused = not paused
				Aud.set_paused(paused)
				_toast("暫停" if paused else "繼續")
		KEY_F12:
			_shoot()


func _force_end(won: bool) -> void:
	## 測試用：不用真的跑完，直接看過關／失敗之後接得對不對
	if mode != Mode.STAGE or state == State.CLEARED or state == State.TIMEUP:
		return
	paused = false
	Aud.set_paused(false)
	Aud.set_hurry(false)
	end_t = 0.0
	if won:
		dist = track_len
		Aud.play_goal()
		_throw_confetti()
		state = State.CLEARED
	else:
		time_left = 0.0
		Aud.play("timeup")
		state = State.TIMEUP


func _finish_level() -> void:
	var won := state == State.CLEARED
	Aud.music_stop()
	Flow.level_finished(won)


func _tune(dir: int) -> void:
	var t: Array = Cfg.TUNABLES[tune_idx]
	var key: String = t[0]
	Cfg.set(key, clampf(Cfg.get(key) + t[1] * dir, t[2], t[3]))
	_toast("%s = %.2f" % [key, Cfg.get(key)])


func _jump_to_blizzard() -> void:
	## 測試用：直接衝到下一段暴風雪，省得整關跑一遍找
	for e in elements:
		if e.type == "blizzard" and e.d > dist + 50.0:
			dist = e.d - 120.0
			_toast("跳到暴風雪（%du）" % int(e.d))
			return
	_toast("前面沒有暴風雪了")


func _shoot() -> void:
	## 存一張畫面到 user://，路徑印在畫面上。卡在哪裡就按 F12，圖檔直接拿去對。
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://shot_%d.png" % (Time.get_ticks_msec() / 100)
	var err := img.save_png(path)
	if err == OK:
		print("[SHOT] ", ProjectSettings.globalize_path(path))
		_toast("已存圖 " + path.get_file())
	else:
		_toast("存圖失敗 %d" % err)


func _throw_confetti() -> void:
	## 過關撒彩帶。掛在 UI 層（不是世界座標），所以不會跟著賽道轉
	var c := Confetti.new()
	ui_layer.add_child(c)


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 1.6


# ============================================================ UI

func _mk_label(pos: Vector2, size: Vector2, fsize: int, layer: CanvasLayer) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.08, 0.14, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	layer.add_child(l)
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_layer = layer
	# 跑的時候：兩行大字，放在地圖右邊
	hud = _mk_label(Vector2(186, 26), Vector2(520, 90), 30, layer)
	# 暫停時：全部攤開
	hud_full = _mk_label(Vector2(186, 26), Vector2(520, 420), 20, layer)
	hud_full.visible = false
	# 狀態提示放畫面中間，不跟數字擠在一起
	center_label = _mk_label(Vector2(0, 700), Vector2(SCREEN_W, 90), 34, layer)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tune_label = _mk_label(Vector2(452, 150), Vector2(260, 460), 17, layer)
	log_label = _mk_label(Vector2(18, 1105), Vector2(690, 170), 16, layer)
	tune_label.visible = false   ## 調手感時才按 P 叫出來

	# 任務卡：劇情模式開跑前擋在畫面中間，按空白鍵開跑就收起來
	brief_panel = ColorRect.new()
	brief_panel.color = Color(0.231, 0.165, 0.145, 0.92)
	brief_panel.position = Vector2(40, 330)
	brief_panel.size = Vector2(SCREEN_W - 80, 420)     # 高度每次依文字重算，見 _update_ui
	brief_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(brief_panel)
	brief_label = Label.new()
	brief_label.position = Vector2(BRIEF_PAD, BRIEF_PAD)
	brief_label.size = Vector2(brief_panel.size.x - BRIEF_PAD * 2.0, 400.0)
	brief_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	brief_label.add_theme_font_size_override("font_size", BRIEF_FONT)
	brief_label.add_theme_constant_override("line_spacing", BRIEF_GAP)
	brief_label.add_theme_color_override("font_color", Color(0.965, 0.933, 0.875))
	brief_panel.add_child(brief_label)
	brief_panel.visible = false

	# 測試按鈕。focus_mode = NONE：不然按過一次之後，空白鍵會變成再按一次這顆按鈕
	var y := SCREEN_H - 110.0
	for spec in [["測試：失敗 (F)", false], ["測試：過關 (G)", true]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(SCREEN_W - 196, y)
		b.size = Vector2(180, 40)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_force_end.bind(spec[1]))
		test_buttons.append(b)
		layer.add_child(b)
		y += 48.0


func _update_ui() -> void:
	var lap := mini(int(dist / maxf(lap_len, 1.0)) + 1, laps)
	var full := paused or (state == State.TIMEUP and not Flow.driving)

	hud.visible = not full
	hud_full.visible = full

	if not full:
		# 跑的時候只留最必要的五項，兩行解決
		hud.text = "%s　第 %d 站　%d/%d 圈
%.1fs　%d/%du　%du/s%s　%d 分" % [
			stage_name, stage_index, lap, laps,
			time_left, int(dist), int(track_len), int(speed),
			"（無敵 %.1fs）" % power_t if power_t > 0.0 else ("（彎道）" if cornering else ""),
			score]
	else:
		var lines := [
			"%s　第 %d 站（%d/%d 圈）" % [stage_name, stage_index, lap, laps],
			"時間　%.1f / %.0f s" % [time_left, time_limit],
			"距離　%d / %d u（一圈 %du）" % [int(dist), int(track_len), int(lap_len)],
			"速度　%d u/s" % int(speed),
			"分數　%d　　加時 %d　加分 %d" % [score, fish_eaten, flags_taken],
			"跌倒 %d　落洞 %d" % [trips, falls],
			"",
			"LAST JUMP　%d u（起跳 %d u/s）" % [int(last_jump_dist), int(last_jump_speed)],
			"理論值　基礎 %d / 全速 %d u" % [int(Cfg.safe_gap()), int(Cfg.max_gap())],
			"賽道半寬　%d u　曲率半徑 %d u" %
				[int(_track_half_at(dist)), int(track.radius_at(dist))],
			"彎道限速　%d u/s%s" % [int(track.radius_at(dist) * MAX_TURN_RATE),
				"　← 正被壓著" if cornering else ""],
			"暴風雪　%s" % ("是（畫面整片偏白，這是特效不是破圖）" if _in_blizzard() else "否"),
			"",
			"P 參數台　Esc 繼續　F12 存圖　R 重跑",
			"F 直接失敗　G 直接過關",
			"測試鍵　1/2/3 選關　L 實驗室　N 下一站　. , 前後 1000u　B 暴風雪",
		]
		hud_full.text = "
".join(lines)

	# 狀態提示：只在該說話的時候出現
	# 手機上右半邊整片都是跳躍區，測試按鈕擺在那裡會被誤觸
	for b in test_buttons:
		b.visible = not Touch.active()

	var br: Dictionary = Flow.brief() if Flow.driving else {}
	brief_panel.visible = state == State.READY and not br.is_empty()
	if brief_panel.visible:
		brief_label.text = "【%s】\n\n%s\n\n　　　　　按空白鍵出發" % [
			str(br.get("title", "")), "\n".join(br.get("lines", []))]
		# 任務卡的行數每一關都不一樣（還會自動換行），框要照文字長高，
		# 不然像第三關那種十五行的就會滿出來
		var rows: int = maxi(brief_label.get_line_count(), 1)
		# get_line_count() 是「這一幀排好的行數」，字剛換掉的那一幀還是舊的，
		# 所以少算的那幾行會掉到框外面。多留兩行的餘裕，換關卡的瞬間才不會露餡
		var bh: float = (rows + 2) * (BRIEF_FONT + BRIEF_GAP) + BRIEF_PAD * 2.0
		brief_label.size.y = bh - BRIEF_PAD * 2.0
		brief_panel.size.y = bh
		brief_panel.position.y = clampf(600.0 - bh * 0.5, 120.0, SCREEN_H - bh - 200.0)

	match state:
		State.READY:
			center_label.text = "" if brief_panel.visible else "按空白鍵開始"
		State.CLEARED when Flow.driving:
			center_label.text = "抵達！按空白鍵繼續"
		State.TIMEUP when Flow.driving:
			center_label.text = "來不及了……按空白鍵繼續"
		State.CLEARED:
			if mode == Mode.STAGE and stage_index < STAGE_COUNT:
				center_label.text = "抵達！按空白鍵前往第 %d 站" % (stage_index + 1)
			elif mode == Mode.STAGE:
				center_label.text = "全部跑完了！"
			else:
				center_label.text = "跑完了，按 R 重來"
		State.TIMEUP:
			center_label.text = "時間到　按 R 重跑"
		_:
			center_label.text = "暫停中（Esc 繼續）" if paused else ""

	if tune_label.visible:
		var tl := ["── 參數（Tab 選 / Q E 調）──"]
		for i in Cfg.TUNABLES.size():
			var key: String = Cfg.TUNABLES[i][0]
			tl.append("%s %-15s %.2f" % ["▶" if i == tune_idx else "　", key, Cfg.get(key)])
		tl.append("")
		tl.append("F5 存　F9 載　1 實驗室")
		tune_label.text = "
".join(tl)

	var ll: Array = build_log.duplicate()
	if toast_t > 0.0:
		ll.append("▶ " + toast)
	log_label.text = "
".join(ll) if show_help else ("▶ " + toast if toast_t > 0.0 else "")



# ============================================================ 繪製
# 全部用向量畫，不吃任何美術資源 —— 原型階段換數值比換圖重要。

const C_SEA := Color(0.13, 0.35, 0.55)
const C_ICE := Color(0.58, 0.69, 0.80)       ## 地面。照「跟貓的對比」定，不是照寫實的冰
											 ## 兩隻白貓一隻棕貓 —— 地板要避開白與淺棕
const C_ICE_LINE := Color(0.74, 0.84, 0.93)
const C_HOLE := Color(0.10, 0.28, 0.45)
const C_PENGUIN := Color(0.11, 0.12, 0.17)
const C_BELLY := Color(1, 1, 1)
const C_BEAK := Color(1.0, 0.62, 0.16)
const C_FLAG := Color(0.85, 0.18, 0.20)
const C_FISH := Color(0.98, 0.66, 0.28)
const C_SEAL := Color(0.45, 0.44, 0.50)
const C_OUTLINE := Color(0.23, 0.16, 0.15)   ## 深咖啡輪廓，照 ../pinball/STYLE.md
const ROAD_EDGE := 7.0                       ## 路緣那圈粗輪廓的寬度（像素）
const C_SNOW_PATCH := Color(1, 1, 1, 0.16)   ## 路面上的雪斑，只比路面亮一點

## 三隻貓的配色。照片在 art/reference/，設定在 STORY.md。
## 俯視角度下只看得到耳朵、頭頂、背和尾巴 —— 辨識就靠這四個地方。
const CATS := {
	"sasa": {            # 莎莎：白身體 + 歪掉的黑帽 + 黑尾巴（屁股靠尾巴根一塊黑斑）+ 大耳朵
		"body": Color(0.97, 0.97, 0.96),
		"cap": Color(0.13, 0.12, 0.14),
		"tail": Color(0.13, 0.12, 0.14),
		"stripes": false,
		"ear": Color(0.98, 0.78, 0.80),
		"nose": Color(0.95, 0.60, 0.65),
		"eye": Color(0.72, 0.80, 0.35),
		"ear_scale": 1.25,          # 她的耳朵特別大
		"notch": false,
	},
	"ling": {            # 小玲：白身體 + 灰虎斑帽 + 虎斑環紋尾（最好認的地方）
		"body": Color(0.97, 0.97, 0.95),
		"cap": Color(0.52, 0.47, 0.42),
		"tail": Color(0.52, 0.47, 0.42),
		"stripes": true,
		"body_stripes": false,      # 身體是白的，只有背上一小塊
		"back_patch": true,
		"split_cap": true,          # 頭上左右兩塊，中間一條白線（像中分）
		"ear": Color(0.97, 0.76, 0.76),
		"nose": Color(0.95, 0.62, 0.66),
		"eye": Color(0.70, 0.82, 0.58),
		"ear_scale": 1.1,
		"notch": false,
	},
	"zhuzhu": {          # 竹竹：全身棕虎斑 + 左耳缺一角
		"body": Color(0.60, 0.52, 0.40),
		"cap": Color(0.40, 0.33, 0.25),
		"tail": Color(0.52, 0.45, 0.34),
		"stripes": true,
		"body_stripes": true,       # 全身虎斑
		"back_patch": false,
		"ear": Color(0.88, 0.70, 0.66),
		"nose": Color(0.92, 0.62, 0.60),
		"eye": Color(0.55, 0.78, 0.45),
		"ear_scale": 1.0,
		"notch": true,
	},
}


func _to_screen(w: Vector2) -> Vector2:
	## 賽道會真的轉彎，所以畫面得跟著轉：把相機的前進方向轉到螢幕正上方。
	var v := (w - cam_pos).rotated(-cam_rot + PI * 0.5)
	return Vector2(CENTER_X + v.x * SC, PLAYER_Y - v.y * SC)


func _track_screen(d: float, off: float) -> Vector2:
	return _to_screen(track.world(d, off))


func _draw() -> void:
	# 相機貼著賽道中心線走，並轉成「前進方向朝上」—— 所以彎道是路在轉，不是玩家在飄
	cam_pos = track.pos_at(dist)
	cam_rot = track.heading_at(dist)

	var d0 := dist - 90.0
	var d1 := dist + VIEW_AHEAD + 60.0

	_update_ground_colors()
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), cur_sea)

	# 路外的點綴先畫：萬一擺得離路太近，也會被路面蓋掉，不會壓到賽道
	for it in scatter:
		var sdd: float = float(it.d)
		if sdd < d0 or sdd > d1:
			continue
		var spt := _track_screen(sdd, float(it.off))
		_draw_prop(str(it.name), spt.x, spt.y, float(it.w))

	_draw_crossings(d0, d1)

	# --- 冰面：沿中心線掃出一串圓 ---
	#
	# 為什麼不用「中心線 ± 半寬」拼四邊形：髮夾彎的曲率半徑小於半寬時，
	# 內側邊界會翻到另一邊，四邊形自交、triangulation 失敗、整片冰面消失。
	# 圓串沒有這個問題 —— 急彎處只是圓互相重疊，畫出來正是粗線轉彎該有的樣子。
	# 代價是每幀多幾十個 draw_circle，換到的是「賽道想怎麼彎就怎麼彎」。
	# 取樣間距要夠密：彎道外側的圓與圓之間會留縫，縫裡會露出底下的描邊圓，
	# 看起來像賽道上有一條條扇形裂紋。10u 的間距在 90u 半徑下縫就看不見了。
	# 貼圖全是「粗深咖啡輪廓 + 平塗」，路面也要用同一套語言：
	# 先掃一圈深咖啡的粗邊，再掃一圈路面色蓋在裡面
	var d: float = floor(d0 / 10.0) * 10.0
	while d <= d1:
		draw_circle(_track_screen(d, 0.0), _track_half_at(d) * SC + ROAD_EDGE, C_OUTLINE)
		d += 10.0
	d = floor(d0 / 10.0) * 10.0
	while d <= d1:
		draw_circle(_track_screen(d, 0.0), _track_half_at(d) * SC, cur_ice)
		d += 10.0

	# --- 路面的雪斑 ---
	# 原本是每 100u 一條橫線（原型時期用來看速度的）。線條太幾何，
	# 跟貼圖擺在一起像兩種畫風。改成散落的平塗雪斑：一樣看得出速度，
	# 但它是「地上的雪」，不是格線
	var g: float = floor(d0 / 60.0) * 60.0
	while g < d1:
		var hg := _track_half_at(g)
		var k := int(g / 60.0)
		for i in 2:
			var seed_i := k * 2 + i
			var sx: float = (fmod(seed_i * 0.6180339887, 1.0) * 2.0 - 1.0) * hg * 0.82
			var sd: float = g + fmod(seed_i * 0.3819660113, 1.0) * 60.0
			var rr: float = 7.0 + fmod(seed_i * 0.7548776662, 1.0) * 9.0
			_ellipse(_track_screen(sd, sx), rr * SC * 0.5, rr * SC * 0.34, C_SNOW_PATCH)
		g += 60.0

	# --- 每一圈的計圈線，最後一條是終點 ---
	for k in range(1, laps + 1):
		var ld := lap_len * k
		if ld < d0 or ld > d1:
			continue
		var hl := _track_half_at(ld)
		if k == laps:
			var a := _track_screen(ld, -hl)
			var b := _track_screen(ld, hl)
			# 終點是碼頭。有圖就沿著賽道方向鋪一塊木棧道，沒圖才退回黑白格
			var dock: Texture2D = prop_tex.get("scenery_dock")
			if dock != null:
				var w: float = a.distance_to(b) * 1.08
				var h: float = w * dock.get_height() / maxf(dock.get_width(), 1.0)
				draw_set_transform(a.lerp(b, 0.5), (b - a).angle(), Vector2.ONE)
				draw_texture_rect(dock, Rect2(-w * 0.5, -h * 0.5, w, h), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				var n := 12
				for i in n:
					var p0 := a.lerp(b, float(i) / n)
					var p1 := a.lerp(b, float(i + 1) / n)
					draw_line(p0, p1, Color.BLACK if i % 2 == 0 else Color.WHITE, 14.0)
		else:
			draw_line(_track_screen(ld, -hl), _track_screen(ld, hl), C_OUTLINE, 12.0)
			draw_line(_track_screen(ld, -hl), _track_screen(ld, hl),
				Color(1.0, 0.85, 0.3), 8.0)

	_draw_decor(d0, d1)
	_draw_trail(d0, d1)
	_draw_tossed()
	_draw_elements(d0, d1)
	_draw_mates(d0, d1)
	_draw_penguin()
	_draw_blizzard_overlay()
	_draw_lab_labels(d0, d1)
	_draw_minimap()


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


## 農村的雪原與壓實的雪路。跑到後段才變成冰原與海
const C_FIELD := Color(0.88, 0.92, 0.95)
const C_ROAD := Color(0.70, 0.75, 0.79)


func _update_ground_colors() -> void:
	if ground_shift != "farm_to_sea":
		cur_sea = pal_sea
		cur_ice = pal_ice
		return
	# 用「跑了多遠」當進度：前 30% 還是農村，75% 之後完全是海邊
	var p: float = clampf(dist / maxf(track_len, 1.0), 0.0, 1.0)
	var t: float = clampf((p - 0.30) / 0.45, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	cur_sea = C_FIELD.lerp(pal_sea, t)
	cur_ice = C_ROAD.lerp(pal_ice, t)


func _draw_tossed() -> void:
	## 飛行中的魚：從海豹那邊沿著拋物線飛到小玲身上，邊飛邊轉
	var tex: Texture2D = prop_tex.get("ice_fish")
	for f in tossed:
		var t: float = float(f.t)
		var fd: float = lerpf(float(f.from_d), float(f.d), t)
		var fo: float = lerpf(float(f.from_off), float(f.off), t)
		var pt := _track_screen(fd, fo)
		var lift: float = sin(t * PI) * 86.0
		if tex == null:
			_ellipse(Vector2(pt.x, pt.y - lift), 20, 12, C_FISH)
			continue
		var w: float = tex.get_width() * PROP_PX * 0.8
		var h: float = w * tex.get_height() / maxf(tex.get_width(), 1.0)
		draw_set_transform(Vector2(pt.x, pt.y - lift), lerpf(-1.1, 1.1, t), Vector2.ONE)
		draw_texture_rect(tex, Rect2(-w * 0.5, -h * 0.5, w, h), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_waver(d: float, off: float, phase: float, scale: float) -> void:
	## 海豹叔叔：先畫冰洞，再把海豹畫在洞口，身體左右晃就是在揮手
	var pt := _track_screen(d, off)
	# 有專用的揮手圖就用它，沒有就拿探頭那張湊合
	var waving_tex: bool = prop_tex.has("ice_seal_wave")
	var tex: Texture2D = prop_tex["ice_seal_wave"] if waving_tex else prop_tex["ice_seal_peek"]
	var w: float = tex.get_width() * PROP_PX * (0.85 if waving_tex else 1.05) * scale
	var hole: Texture2D = prop_tex.get("icehole_m")
	if hole != null:
		_draw_prop("icehole_m", pt.x, pt.y + 6.0, w * 1.15)
	# 揮手圖的鰭是舉著的，擺大一點才像在揮；探頭那張只是輕輕晃
	var swing := sin(elapsed * 4.4 + phase) * (0.34 if waving_tex else 0.22)
	var h: float = w * tex.get_height() / maxf(tex.get_width(), 1.0)
	draw_set_transform(pt + Vector2(0.0, 6.0), swing, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-w * 0.5, -h * 0.78, w, h), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_decor(d0: float, d1: float) -> void:
	for wv in wavers:
		var wd: float = float(wv.d)
		if wd < d0 or wd > d1:
			continue
		_draw_waver(wd, float(wv.off), float(wv.phase), float(wv.w))

	for it in decor:
		var d: float = float(it.d)
		if d < d0 or d > d1:
			continue
		var pt := _track_screen(d, float(it.off))
		# 陰影統一由程式畫（圖本身不帶陰影），三隻貓、道具、景物才會是同一種光
		_ellipse(Vector2(pt.x, pt.y + float(it.w) * 0.22), float(it.w) * 0.42,
			float(it.w) * 0.16, Color(0, 0, 0, 0.16))
		_draw_prop(str(it.name), pt.x, pt.y, float(it.w))


const C_TRAIL := Color(0.86, 0.20, 0.22)


func _draw_trail(d0: float, d1: float) -> void:
	## 小玲插的紅旗。跑過去就留在那裡，小地圖上會連成一條記號。
	## 插下去那一刻要有戲：畫面上只看得到她身後 160u，等於不到一秒，
	## 所以用「啵一聲彈出來 + 腳邊噴雪」把那一秒用滿
	for f in trail:
		var d: float = float(f.d)
		if d < d0 or d > d1:
			continue
		var pt := _track_screen(d, float(f.off))
		var age: float = elapsed - float(f.get("t", -99.0))
		# 剛插下去：從 0 彈到 1.15 再回到 1
		var pop := 1.0
		if age < 0.26:
			var u: float = clampf(age / 0.26, 0.0, 1.0)
			pop = 1.0 + sin(u * PI) * 0.55 - (1.0 - u) * (1.0 - u) * 0.9
		# 雪花從插旗的地方噴開
		if age < 0.30:
			var k: float = clampf(age / 0.30, 0.0, 1.0)
			for i in 5:
				var a2: float = TAU * i / 5.0 + float(f.d)
				var rr: float = 6.0 + k * 22.0
				draw_circle(pt + Vector2(cos(a2), sin(a2) * 0.5) * rr,
					3.2 * (1.0 - k), Color(1, 1, 1, 0.9 * (1.0 - k)))
		# 風吹：每支旗的相位不一樣，整排才不會像節拍器
		var sway := sin(elapsed * 6.0 + float(f.d) * 0.05) * 0.10
		var tex: Texture2D = prop_tex.get("ice_flag")
		if tex != null:
			var w: float = tex.get_width() * PROP_PX * 0.85 * pop
			var h: float = w * tex.get_height() / maxf(tex.get_width(), 1.0)
			draw_set_transform(pt + Vector2(0, 4.0), sway, Vector2.ONE)
			draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			continue
		draw_line(pt, pt + Vector2(0, -30), C_OUTLINE, 5.0)
		draw_line(pt, pt + Vector2(0, -30), Color(0.55, 0.50, 0.46), 3.0)
		draw_colored_polygon(PackedVector2Array([
			pt + Vector2(0, -30), pt + Vector2(17, -24), pt + Vector2(0, -18)]), C_TRAIL)


func _draw_crossings(d0: float, d1: float) -> void:
	## 賽道允許交叉（立體交會）。這裡把「畫面內、但不是玩家現在這一段」的路
	## 畫成暗色 —— 玩家的路稍後會蓋在上面，看起來就是從橋上切過去。
	var here := fposmod(dist, lap_len)
	var step := 34.0
	var d := 0.0
	while d < lap_len:
		# 沿賽道距離差得夠遠，才算是另一段路（不然是自己腳下）
		var along: float = absf(d - here)
		along = minf(along, lap_len - along)
		if along < 420.0:
			d += step
			continue
		var h := _track_half_at(d)
		var a := _track_screen(d, 0.0)
		if a.x < -260.0 or a.x > SCREEN_W + 260.0 or a.y < -260.0 or a.y > SCREEN_H + 260.0:
			d += step
			continue
		draw_circle(_track_screen(d, 0.0), h * SC, cur_ice * Color(0.55, 0.60, 0.70))
		d += step


func _draw_elements(d0: float, d1: float) -> void:
	for e in elements:
		if e.d < d0 or e.d > d1:
			continue
		if not e.get("alive", true):
			continue
		var pt := _track_screen(e.d, float(e.off))
		var x := pt.x
		var y := pt.y
		match e.type:
			"crevasse" when prop_tex.has("icehole_crack"):
				# 橫跨整條賽道：把裂縫圖沿著賽道的橫向鋪過去
				var ha2 := _track_half_at(float(e.d))
				var pa := _track_screen(float(e.d), -ha2)
				var pb := _track_screen(float(e.d), ha2)
				var crack: Texture2D = prop_tex["icehole_crack"]
				var cw: float = pa.distance_to(pb) * 1.06
				var ch2: float = float(e.w) * SC * 1.5
				draw_set_transform(pa.lerp(pb, 0.5), (pb - pa).angle(), Vector2.ONE)
				draw_texture_rect(crack, Rect2(-cw * 0.5, -ch2 * 0.5, cw, ch2), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"crevasse":
				# 橫跨整條賽道，四個角各自貼著彎曲的邊界
				var da: float = e.d - e.w * 0.5
				var db: float = e.d + e.w * 0.5
				var ha := _track_half_at(da)
				var hb := _track_half_at(db)
				draw_colored_polygon(PackedVector2Array([
					_track_screen(da, -ha), _track_screen(db, -hb),
					_track_screen(db, hb), _track_screen(da, ha)]), C_HOLE)
			"hole_s", "hole_m", "hole_l":
				var r: float = e.w * 0.5 * SC
				if not _draw_hole_art(str(e.type), e, x, y, r):
					_ellipse(Vector2(x, y), r, r * 0.62, C_HOLE)
					if e.has("fish") and jumper_style == "vole":
						_draw_burrow(x, y, r)
				if _cycle_up(e.get("seal", {}), float(e.get("seal_cool", -1.0))):
					_draw_seal(x, y, r, _cycle_t(e.seal))
				elif e.has("fish") and _fish_up(e):
					if jumper_style == "vole":
						_draw_vole_art(x, y, r, _fish_phase(e))
					else:
						_draw_jumping_fish(x, y, _fish_phase(e))
			"flag" when prop_tex.has("ice_pillar"):
				var pt2: Texture2D = prop_tex["ice_pillar"]
				_ellipse(Vector2(x, y + 2), 16, 6, Color(0, 0, 0, 0.18))
				_draw_prop("ice_pillar", x, y + 6.0, pt2.get_width() * PROP_PX * 1.1, 1.0)
			"flag":
				draw_line(Vector2(x, y), Vector2(x, y - 46), Color(0.25, 0.25, 0.3), 4.0)
				draw_colored_polygon(PackedVector2Array([
					Vector2(x, y - 46), Vector2(x + 26, y - 38), Vector2(x, y - 30)]), C_FLAG)
			"ice_block" when prop_tex.has("scenery_floe_l"):
				# 漂來漂去的浮冰：沿用路外點綴的大浮冰圖，放在路上就是障礙。
				# 碰撞是 ±26u，圖畫得比碰撞框大一圈 —— 撞到的時候才不會覺得「明明沒碰到」
				_ellipse(Vector2(x, y + 10), 44, 12, Color(0, 0, 0, 0.20))
				_draw_prop("scenery_floe_l", x, y, 52.0 * SC * 1.25)
			"ice_block":
				draw_rect(Rect2(x - 26, y - 18, 52, 36), Color(0.86, 0.93, 1.0))
				draw_rect(Rect2(x - 26, y - 18, 52, 36), Color(0.55, 0.72, 0.85), false, 3.0)
			"power":
				_draw_power(x, y)
			"cheer" when pickup_style == "lingflag" and prop_tex.has("ice_flag"):
				# 第四關回程：路上的紅旗是小玲去程一路插的，跑過去就是把它拔回來。
				# 跟她插旗時一樣會被風吹得擺
				var ft: Texture2D = prop_tex["ice_flag"]
				var fw: float = ft.get_width() * PROP_PX * 0.95
				var fh: float = fw * ft.get_height() / maxf(ft.get_width(), 1.0)
				_ellipse(Vector2(x, y + 2), 14, 5, Color(0, 0, 0, 0.18))
				draw_set_transform(Vector2(x, y + 4.0), sin(elapsed * 6.0 + float(e.d) * 0.05) * 0.10,
					Vector2.ONE)
				draw_texture_rect(ft, Rect2(-fw * 0.5, -fh, fw, fh), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"cheer" when pickup_style == "can" and prop_tex.has("ice_can"):
				var ct: Texture2D = prop_tex["ice_can"]
				_ellipse(Vector2(x, y + 2), 18, 6, Color(0, 0, 0, 0.18))
				_draw_prop("ice_can", x, y, ct.get_width() * PROP_PX * 0.95, 0.72)
			"cheer" when pickup_style == "catgrass":
				var gname := _grass_name(float(e.d))
				var gt: Texture2D = prop_tex.get(gname)
				if gt == null:
					_draw_catgrass(x, y, e.d)
				else:
					_ellipse(Vector2(x, y + 2), 20, 7, Color(0, 0, 0, 0.18))
					_draw_prop(gname, x, y + 4.0, gt.get_width() * GRASS_PX, 1.0)
			"cheer":
				# 加分道具：+50。立在冰緣上，要拿就得靠邊跑
				draw_line(Vector2(x, y), Vector2(x, y - 34), Color(0.45, 0.45, 0.5), 3.0)
				draw_colored_polygon(PackedVector2Array([
					Vector2(x, y - 34), Vector2(x + 20, y - 27), Vector2(x, y - 20)]),
					Color(1.0, 0.85, 0.3))


const C_GRASS := Color(0.42, 0.74, 0.30)
const C_GRASS_DARK := Color(0.28, 0.55, 0.22)


const C_VINE := Color(0.45, 0.72, 0.33)
const C_VINE_DARK := Color(0.30, 0.55, 0.24)


func _draw_power(x: float, y: float) -> void:
	## 木天蓼：一小截樹枝加兩片葉子，外面一圈會呼吸的光暈。
	## 它是全場唯一會發光的東西 —— 玩家第一次看到就知道這個不一樣
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 4.0)
	draw_circle(Vector2(x, y - 14), 30.0 + pulse * 6.0, Color(1.0, 0.95, 0.55, 0.20 + pulse * 0.12))
	draw_circle(Vector2(x, y - 14), 19.0, Color(1.0, 0.97, 0.72, 0.35))
	_ellipse(Vector2(x, y + 2), 15, 5, Color(0, 0, 0, 0.18))
	# 枝
	draw_line(Vector2(x, y), Vector2(x, y - 30), C_OUTLINE, 7.0)
	draw_line(Vector2(x, y), Vector2(x, y - 30), Color(0.72, 0.60, 0.44), 4.0)
	# 兩片葉子
	for side in [-1.0, 1.0]:
		var c := Vector2(x + side * 13.0, y - 22 - side * 4.0)
		_ellipse(c, 13, 8, C_OUTLINE)
		_ellipse(c, 10.5, 6.0, C_VINE if side < 0.0 else C_VINE_DARK)
	# 亮晶晶
	for i in 3:
		var a: float = elapsed * 2.2 + TAU * i / 3.0
		var p := Vector2(x, y - 16) + Vector2(cos(a), sin(a) * 0.55) * (24.0 + pulse * 4.0)
		draw_circle(p, 2.6, Color(1, 1, 1, 0.85))


func _draw_rotor(centre: Vector2, r: float) -> void:
	## 竹蜻蜓：把尾巴的圖繞著身體轉。前後各補一片半透明的殘影，看起來才有轉速。
	## 沒有尾巴圖時退回一條粗弧線 —— 會動，但看不出是尾巴
	var spin := elapsed * 16.0
	var tail: Texture2D = cat_tex.get(PLAYER_CAT, {}).get("tail")
	if tail == null:
		for k in 2:
			var rr: float = r * (1.25 - k * 0.22)
			draw_arc(centre, rr, spin + k * 1.1, spin + k * 1.1 + 2.3, 14,
				C_OUTLINE, 7.0 - k * 2.0, true)
		return

	# 轉出來的圓盤（動態模糊）
	draw_circle(centre, r * 1.7, Color(1, 1, 1, 0.13))
	# 尾巴又細又長，照「長度」縮放才對得上身體 —— 照寬度縮放會變成比貓還長的葉片
	var h: float = r * 3.1
	var w: float = h * tail.get_width() / maxf(tail.get_height(), 1.0)
	for ghost in [[-0.75, 0.25], [-0.38, 0.45], [0.0, 1.0]]:
		draw_set_transform(centre, spin + float(ghost[0]), Vector2.ONE)
		draw_texture_rect(tail, Rect2(-w * 0.5, -h * 0.86, w, h), false,
			Color(1, 1, 1, float(ghost[1])))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_prop(name: String, x: float, y: float, w: float, anchor := 0.5) -> bool:
	## 把道具圖畫在 (x, y)。anchor 是「y 對到圖的哪個高度」：
	## 0.5 = 圖的正中（洞這種躺在地上的），1.0 = 圖的底部（貓草這種立著的）
	var tex: Texture2D = prop_tex.get(name)
	if tex == null:
		return false
	var h: float = w * tex.get_height() / maxf(tex.get_width(), 1.0)
	draw_texture_rect(tex, Rect2(x - w * 0.5, y - h * anchor, w, h), false)
	return true


func _grass_name(seed_d: float) -> String:
	## 同一撮草每次都長一樣（用它在賽道上的距離當種子），整排才不會每幀跳動
	return ["props_grass_s", "props_grass_m", "props_grass_l"][int(absf(seed_d)) % 3]


func _draw_hole_art(kind: String, e: Dictionary, x: float, y: float, r: float) -> bool:
	## 洞用圖畫。回傳 false 表示沒有圖，交給原本的深色橢圓。
	## 有田鼠的小洞是田鼠洞，中洞是雪坑，大洞是水窪
	var name := "holes_pit_m"
	if terrain == "ice":
		name = {"hole_s": "icehole_s", "hole_m": "icehole_m",
			"hole_l": "icehole_l"}.get(kind, "icehole_m")
	elif e.has("fish") and jumper_style == "vole":
		name = "props_burrow"
	elif kind == "hole_l":
		name = "holes_puddle"
	return _draw_prop(name, x, y, r * 2.0 * HOLE_ART)


func _draw_vole_art(x: float, y: float, r: float, t: float) -> void:
	## 田鼠：剛冒出來時只探個頭，跳到最高才整隻離地
	var up: Texture2D = prop_tex.get("props_vole_up")
	if up == null:
		_draw_vole(x, y, r, t)
		return
	var tt := clampf(t, 0.0, 1.0)
	if tt < 0.26 or tt > 0.86:
		var peek: Texture2D = prop_tex.get("props_vole_peek", up)
		_draw_prop("props_vole_peek" if prop_tex.has("props_vole_peek") else "props_vole_up",
			x, y + 6.0, peek.get_width() * PROP_PX, 0.9)
		return
	_draw_prop("props_vole_up", x, y - sin(tt * PI) * 52.0,
		up.get_width() * PROP_PX, 0.9)


func _draw_catgrass(x: float, y: float, seed_d: float) -> void:
	## 第一章的加分道具：從雪地裡冒出來的一小撮貓草。
	## 冰面是灰藍、貓是白與棕 —— 綠色在這條路上最跳。
	## 草尖隨時間輕輕晃，每一撮的相位不同，才不會整排一起擺
	var sway := sin(elapsed * 3.0 + seed_d * 0.013) * 3.0
	_ellipse(Vector2(x, y + 2), 22, 8, Color(0, 0, 0, 0.18))
	var blades := [[-18.0, 28.0], [-9.0, 42.0], [0.0, 50.0], [9.0, 40.0], [18.0, 27.0]]
	# 先畫一層深咖啡當輪廓，再疊綠色
	for pass_i in 2:
		for i in blades.size():
			var bx: float = blades[i][0]
			var bh: float = blades[i][1]
			var root := Vector2(x + bx * 0.45, y)
			var tip := Vector2(x + bx + sway * bh / 50.0, y - bh)
			var col: Color = C_OUTLINE if pass_i == 0 else (C_GRASS if i % 2 == 0 else C_GRASS_DARK)
			var wdt: float = 10.0 if pass_i == 0 else 6.0
			draw_line(root, tip, col, wdt)
			if pass_i == 0:
				draw_circle(tip, wdt * 0.5, col)
	# 根部一小團雪，看起來是從雪裡長出來的
	_ellipse(Vector2(x, y + 1), 18, 6, Color(0.95, 0.97, 1.0))


const C_VOLE := Color(0.62, 0.48, 0.36)
const C_VOLE_BELLY := Color(0.86, 0.76, 0.62)
const C_BURROW := Color(0.30, 0.24, 0.22)


func _draw_burrow(x: float, y: float, r: float) -> void:
	## 田鼠洞：雪地上一圈白邊，中間是土色的洞
	_ellipse(Vector2(x, y), r + 5.0, r * 0.62 + 4.0, Color(0.95, 0.97, 1.0))
	_ellipse(Vector2(x, y), r, r * 0.62, C_BURROW)


func _draw_vole(x: float, y: float, r: float, t: float) -> void:
	## 田鼠從洞裡蹦出來又縮回去。圓滾滾的一坨，看得到耳朵和尾巴就夠了
	var tt := clampf(t, 0.0, 1.0)
	var h := sin(tt * PI) * 58.0
	var vy := y - h
	var s := 1.0 + sin(tt * PI) * 0.15          # 跳到最高時伸長一點
	# 洞口噴雪
	var puff: float = (1.0 - absf(tt - 0.5) * 2.0) * 12.0
	for k in 3:
		var sx: float = x + (k - 1) * 14.0
		draw_line(Vector2(sx, y - 2), Vector2(sx + (k - 1) * 6.0, y - 6 - puff),
			Color(0.97, 0.98, 1.0, 0.95), 4.0)
	# 尾巴
	draw_line(Vector2(x + 12, vy + 8), Vector2(x + 26, vy + 16 + sin(elapsed * 14.0) * 3.0),
		C_OUTLINE, 3.0)
	# 身體（先墊輪廓）
	_ellipse(Vector2(x, vy), 21, 18 * s, C_OUTLINE)
	_ellipse(Vector2(x, vy), 18, 15 * s, C_VOLE)
	_ellipse(Vector2(x, vy + 5 * s), 11, 8 * s, C_VOLE_BELLY)
	# 耳朵
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(x + side * 10.0, vy - 13 * s), 6.0, C_OUTLINE)
		draw_circle(Vector2(x + side * 10.0, vy - 13 * s), 4.2, Color(0.90, 0.66, 0.64))
	# 臉
	draw_circle(Vector2(x - 6, vy - 3 * s), 2.6, Color.BLACK)
	draw_circle(Vector2(x + 6, vy - 3 * s), 2.6, Color.BLACK)
	draw_circle(Vector2(x, vy + 2 * s), 2.4, Color(0.95, 0.55, 0.60))


func _draw_seal(x: float, y: float, r: float, t: float) -> void:
	# 有圖就用圖：剛探頭是 peek，頂到最高換成 up（那一下就是把你頂飛的瞬間）
	if prop_tex.has("ice_seal_peek") and prop_tex.has("ice_seal_up"):
		var tt := clampf(t, 0.0, 1.0)
		if tt < 0.35:
			var pk: Texture2D = prop_tex["ice_seal_peek"]
			_draw_prop("ice_seal_peek", x, y, pk.get_width() * PROP_PX * 1.15, 0.62)
		else:
			var uz: Texture2D = prop_tex["ice_seal_up"]
			_draw_prop("ice_seal_up", x, y - sin((tt - 0.35) / 0.65 * PI) * 16.0,
				uz.get_width() * PROP_PX * 1.15, 0.72)
		return
	_draw_seal_vec(x, y, r, t)


func _draw_seal_vec(x: float, y: float, r: float, t: float) -> void:
	## 探頭探得夠高 —— 這個洞跳過去也會撞到，畫面上要看得出來牠比企鵝高
	var rise := sin(clampf(t, 0.0, 1.0) * PI) * 0.6 + 0.4
	var h := 52.0 * rise
	_ellipse(Vector2(x, y - h * 0.45), r * 0.62, h * 0.55, C_SEAL)
	draw_circle(Vector2(x, y - h * 0.9), r * 0.5, C_SEAL)
	draw_circle(Vector2(x - r * 0.2, y - h * 0.98), 3.5, Color.BLACK)
	draw_circle(Vector2(x + r * 0.2, y - h * 0.98), 3.5, Color.BLACK)
	draw_line(Vector2(x - r * 0.5, y - h * 0.82), Vector2(x + r * 0.5, y - h * 0.82),
		Color(0.3, 0.3, 0.34), 1.5)


func _draw_jumping_fish(x: float, y: float, t: float) -> void:
	var tt := clampf(t, 0.0, 1.0)
	var ftex: Texture2D = prop_tex.get("ice_fish")
	if ftex != null:
		# 沿著拋物線飛，順便照飛行方向轉 —— 一張圖就夠了
		var fy2: float = y - sin(tt * PI) * 76.0
		var w2: float = ftex.get_width() * PROP_PX * 0.9
		var h2: float = w2 * ftex.get_height() / maxf(ftex.get_width(), 1.0)
		for k in 3:
			var sx2: float = x + (k - 1) * 13.0
			draw_line(Vector2(sx2, y - 2), Vector2(sx2 + (k - 1) * 5.0, y - 10),
				Color(0.85, 0.94, 1.0, 0.9), 3.0)
		draw_set_transform(Vector2(x, fy2), lerpf(-0.7, 0.7, tt), Vector2.ONE)
		draw_texture_rect(ftex, Rect2(-w2 * 0.5, -h2 * 0.5, w2, h2), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var fy := y - sin(tt * PI) * 76.0
	var ang := lerpf(-0.9, 0.9, tt)
	var dir := Vector2(cos(ang), sin(ang))
	var splash: float = (1.0 - abs(tt - 0.5) * 2.0) * 14.0
	for k in 3:
		var sx: float = x + (k - 1) * 13.0
		draw_line(Vector2(sx, y - 2), Vector2(sx + (k - 1) * 5.0, y - 6 - splash),
			Color(0.85, 0.94, 1.0, 0.9), 3.0)
	_ellipse(Vector2(x, fy), 22, 14, C_FISH)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, fy) - dir * 19.0,
		Vector2(x, fy) - dir * 37.0 + Vector2(-dir.y, dir.x) * 13.0,
		Vector2(x, fy) - dir * 37.0 - Vector2(-dir.y, dir.x) * 13.0]), C_FISH)
	_ellipse(Vector2(x + 7, fy - 3), 4, 4, Color.WHITE)
	draw_circle(Vector2(x + 8, fy - 3), 2.5, Color.BLACK)


func _draw_blizzard_overlay() -> void:
	## 暴風雪。畫法照第三章的劇情插圖：平塗的白色風帶 + 圓圓的雪片，
	## 不是寫實的雨絲 —— 原本的斜線看起來像下雨，跟貼紙畫風也不搭。
	if not _in_blizzard():
		return

	var fog := Color(1, 1, 1, 0.42)
	var clear := Color(1, 1, 1, 0.0)
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(SCREEN_W, 0),
			Vector2(SCREEN_W, SCREEN_H * 0.92), Vector2(0, SCREEN_H * 0.92)]),
		PackedColorArray([fog, fog, clear, clear]))

	# 風帶：幾條很寬、半透明的白色弧帶從左往右掃過去
	for i in 5:
		var fi := float(i)
		var base_y: float = fmod(fi * 263.0 + elapsed * (60.0 + fi * 14.0), SCREEN_H + 300.0) - 150.0
		var pts := PackedVector2Array()
		for k in 13:
			var t := float(k) / 12.0
			var x: float = -80.0 + t * (SCREEN_W + 160.0)
			pts.append(Vector2(x, base_y - sin(t * PI + fi) * 70.0 + t * 90.0))
		draw_polyline(pts, Color(1, 1, 1, 0.16 + 0.05 * fmod(fi, 2.0)), 34.0 + fi * 6.0, true)

	# 雪片：圓的、大小不一，被風吹得斜斜飛。位置由 index 的偽隨機加上時間推移
	for i in 110:
		var rx := fmod(i * 97.317, 1.0)
		var ry := fmod(i * 61.173, 1.0)
		var size: float = 2.0 + fmod(i * 13.7, 1.0) * 4.5
		var fall: float = 180.0 + ry * 160.0 + size * 25.0      # 大片的比較近，飛得比較快
		var y := fmod(ry * SCREEN_H + elapsed * fall, SCREEN_H)
		var x := fmod(rx * SCREEN_W + elapsed * (260.0 + size * 40.0)
			+ sin(elapsed * 1.3 + i) * 18.0, SCREEN_W)
		var a: float = 0.55 + 0.4 * (1.0 - y / SCREEN_H)
		draw_circle(Vector2(x, y), size, Color(1, 1, 1, a))

	# 講清楚這是天氣，不是畫面壞了
	draw_string_outline(font, Vector2(0, 250), "暴　風　雪", HORIZONTAL_ALIGNMENT_CENTER,
		SCREEN_W, 44, 8, Color(0.23, 0.16, 0.15, 0.55))
	draw_string(font, Vector2(0, 250), "暴　風　雪", HORIZONTAL_ALIGNMENT_CENTER,
		SCREEN_W, 44, Color(1, 1, 1, 0.9))

func _step_phase(travel: float, spd: float) -> float:
	## 跑到現在踏了幾步。整數部分變了就換一張腳
	return travel / maxf(Cfg.step_len + maxf(spd, 0.0) * STEP_PER_SPEED, 1.0)


func _draw_penguin() -> void:
	var base := _track_screen(dist, off)
	var t := jump_t / maxf(Cfg.jump_airtime, 0.001)
	var h: float = (4.0 * Cfg.jump_height * t * (1.0 - t) * SC) if jumping else 0.0
	var r: float = Cfg.player_radius * SC

	var flying := power_t > 0.0
	if flying:
		# 吃了木天蓼：尾巴像竹蜻蜓一樣轉起來，整隻貓浮在空中。
		# 最後 2 秒閃得更快，等於在倒數
		h += 30.0 + sin(elapsed * 7.0) * 5.0
		draw_circle(Vector2(base.x, base.y + r * 0.5), r * 0.55, Color(0, 0, 0, 0.12))
		_draw_rotor(Vector2(base.x, base.y - h - r * 1.15), r)
		var rate: float = 9.0 if power_t > 2.0 else 18.0
		var on := fmod(elapsed * rate, 1.0) < 0.62
		cat_tint = Color(1, 1, 1, 1) if on else Color(1.0, 0.98, 0.72, 0.45)

	# 飛的時候換成「腳縮起來、沒有尾巴」那張（尾巴由 _draw_rotor 單獨畫）
	var pose_key := PLAYER_CAT
	if flying and cat_tex.get(PLAYER_CAT, {}).has("fly"):
		pose_key = PLAYER_CAT + "|fly"
	_draw_cat(base, r, CATS[PLAYER_CAT], h,
		state == State.STUMBLE, (off - _last_off) * 60.0, pose_key, false,
		_step_phase(dist, speed))
	cat_tint = Color(1, 1, 1, 1)
	_last_off = off


## 一隻貓。俯視偏後的視角：看得到臉、背、以及靠近鏡頭的尾巴。
## lean 是橫向移動量，用來讓尾巴甩向外側 —— 這是目前唯一的轉向視覺回饋。
func _draw_cat(base: Vector2, r: float, c: Dictionary, lift: float,
		fallen: bool, lean: float, key := "", laughing := false, travel := 0.0) -> void:
	if key != "" and _draw_cat_sprite(base, r, key, lift, fallen, lean, laughing, travel):
		return
	var x := base.x
	var y := base.y

	# 影子留在地面，跳多高一眼看得出來
	_ellipse(Vector2(x, y + r * 0.5), r * (0.9 - lift / 300.0), r * 0.42,
		Color(0, 0, 0, 0.22))

	var by: float = y - lift

	if fallen:
		_ellipse(Vector2(x, by + r * 0.3), r * 1.30, r * 0.80, C_OUTLINE)
		_ellipse(Vector2(x, by + r * 0.3), r * 1.2, r * 0.7, c.body)
		_ellipse(Vector2(x - r * 0.5, by + r * 0.1), r * 0.5, r * 0.45, c.cap)
		draw_string(font, Vector2(x - 10, by - r * 1.4), "×_×",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.2, 0.2))
		return

	# 尾巴：往後伸，並甩向轉彎的外側
	var sway: float = clampf(-lean * 0.9, -1.4, 1.4)
	var tail_root := Vector2(x, by + r * 0.75)
	var tail_mid := tail_root + Vector2(sway * r * 0.8, r * 0.75)
	var tail_tip := tail_mid + Vector2(sway * r * 1.1, r * 0.55)
	draw_line(tail_root, tail_mid, C_OUTLINE, r * 0.42)
	draw_line(tail_mid, tail_tip, C_OUTLINE, r * 0.34)
	draw_line(tail_root, tail_mid, c.tail, r * 0.30)
	draw_line(tail_mid, tail_tip, c.tail, r * 0.24)
	if c.stripes:
		draw_line(tail_mid, tail_mid + (tail_tip - tail_mid) * 0.35,
			c.cap, r * 0.26)
		draw_line(tail_root + (tail_mid - tail_root) * 0.55,
			tail_root + (tail_mid - tail_root) * 0.85, c.cap, r * 0.30)

	# 身體（先墊一層深色當輪廓 —— 白貓在冰上沒有輪廓會整隻糊掉）
	_ellipse(Vector2(x, by), r * 1.05, r * 1.22, C_OUTLINE)
	_ellipse(Vector2(x, by), r * 0.95, r * 1.12, c.body)
	if c.get("back_patch", false):
		_ellipse(Vector2(x + r * 0.15, by + r * 0.10), r * 0.38, r * 0.30, c.cap)
	if c.get("body_stripes", false):
		for i in 3:
			var sy: float = by - r * 0.5 + i * r * 0.5
			draw_line(Vector2(x - r * 0.75, sy), Vector2(x + r * 0.75, sy),
				c.cap, r * 0.16)

	# 頭
	var hy: float = by - r * 1.05
	draw_circle(Vector2(x, hy), r * 0.84, C_OUTLINE)
	draw_circle(Vector2(x, hy), r * 0.74, c.body)

	# 耳朵（莎莎的特別大；竹竹左耳缺一角）
	var es: float = r * 0.52 * float(c.ear_scale)
	var lear := PackedVector2Array([
		Vector2(x - r * 0.62, hy - r * 0.18),
		Vector2(x - r * 0.70, hy - r * 0.30 - es),
		Vector2(x - r * 0.10, hy - r * 0.55)])
	if c.notch:
		lear = PackedVector2Array([
			Vector2(x - r * 0.62, hy - r * 0.18),
			Vector2(x - r * 0.70, hy - r * 0.30 - es),
			Vector2(x - r * 0.48, hy - r * 0.18 - es * 0.55),   # V 形缺口
			Vector2(x - r * 0.34, hy - r * 0.30 - es * 0.9),
			Vector2(x - r * 0.10, hy - r * 0.55)])
	draw_colored_polygon(lear, c.cap)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + r * 0.62, hy - r * 0.18),
		Vector2(x + r * 0.70, hy - r * 0.30 - es),
		Vector2(x + r * 0.10, hy - r * 0.55)]), c.ear)

	# 頭頂的花紋。莎莎是一頂歪掉的黑帽；小玲是左右兩塊、中間留白
	if c.get("split_cap", false):
		_ellipse(Vector2(x - r * 0.40, hy - r * 0.30), r * 0.30, r * 0.30, c.cap)
		_ellipse(Vector2(x + r * 0.40, hy - r * 0.30), r * 0.30, r * 0.30, c.cap)
	else:
		_ellipse(Vector2(x - r * 0.10, hy - r * 0.26), r * 0.60, r * 0.38, c.cap)

	# 臉
	draw_circle(Vector2(x - r * 0.26, hy + r * 0.06), r * 0.11, c.eye)
	draw_circle(Vector2(x + r * 0.26, hy + r * 0.06), r * 0.11, c.eye)
	draw_circle(Vector2(x - r * 0.26, hy + r * 0.06), r * 0.05, Color.BLACK)
	draw_circle(Vector2(x + r * 0.26, hy + r * 0.06), r * 0.05, Color.BLACK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - r * 0.10, hy + r * 0.30),
		Vector2(x + r * 0.10, hy + r * 0.30),
		Vector2(x, hy + r * 0.44)]), c.nose)


func _draw_mates(d0: float, d1: float) -> void:
	for m in mates:
		var d: float = float(m.dist)
		if d < d0 or d > d1:
			continue
		var lift := 0.0
		if float(m.jump) >= 0.0:
			var t: float = float(m.jump) / maxf(Cfg.jump_airtime, 0.001)
			lift = 4.0 * Cfg.jump_height * t * (1.0 - t) * SC
		var pos := _track_screen(d, float(m.off))
		var r: float = Cfg.player_radius * SC * 0.92
		var laughing := state == State.STUMBLE
		var urgent := mode == Mode.STAGE and time_left < 10.0
		if laughing and not urgent:
			# 笑到發抖。最後十秒她們不笑，所以也不抖 —— 這個細節不能漏，
			# 台詞變了但身體還在抖的話，那一刻就毀了。
			pos.y += sin(elapsed * 26.0) * r * 0.12
		_draw_cat(pos, r, CATS[m.key], lift, false,
			float(m.target) - float(m.off), str(m.key), laughing,
			_step_phase(float(m.dist), float(m.speed)))
		# 跌倒時講嘲諷的，平常講稱讚的。
		# 寬度要夠 —— 原本給 r*2.4（約 43px），中文字連兩個都放不下。
		var line := str(m.laugh) if laughing else (str(m.say) if float(m.say_t) > 0.0 else "")
		if line != "":
			var box := 380.0
			var tp := pos + Vector2(-box * 0.5, -r * 2.8)
			draw_string_outline(font, tp, line, HORIZONTAL_ALIGNMENT_CENTER,
				box, 24, 6, Color(0.05, 0.08, 0.14, 0.95))
			draw_string(font, tp, line, HORIZONTAL_ALIGNMENT_CENTER,
				box, 24, Color(1, 1, 1))


func _draw_cat_sprite(base: Vector2, r: float, key: String, lift: float,
		fallen: bool, lean: float, laughing := false, travel := 0.0) -> bool:
	## 用圖畫貓。回傳 false 表示這隻還沒有圖，交給向量畫法。
	##
	## key 可以寫成 "ling|fly"，指定一定要用哪個姿勢（竹蜻蜓飛行用）。
	## 這個拆解一定要在查表之前做 —— 之前寫在後面，"ling|fly" 查不到表就退回向量貓，
	## 於是飛起來的瞬間整隻貓變成程式畫的，而且向量貓自帶尾巴，畫面上就有兩條尾巴。
	var forced_pose := ""
	if key.contains("|"):
		var parts := key.split("|")
		key = parts[0]
		forced_pose = parts[1]

	var set: Dictionary = cat_tex.get(key, {})
	if set.is_empty():
		return false

	var pose := "run"
	var tilt := 0.0
	if forced_pose != "" and set.has(forced_pose):
		pose = forced_pose
	elif fallen:
		pose = "hit"
	elif laughing and set.has("laugh"):
		pose = "laugh"
	elif lift > 1.0:
		pose = "jump"
	else:
		# 轉彎不換圖，改成把跑步的圖整隻傾斜。
		# left / right 那兩張是靜態的，一轉彎腳就停住了 —— 那正是「沒有腳步」的感覺
		tilt = clampf(lean * 0.0013, -LEAN_MAX, LEAN_MAX)
	# 跑步有兩張就交替踏步 —— 單張圖再怎麼上下晃，腳都是不動的
	if pose == "run" and set.has("run2") and int(floor(travel)) % 2 == 1:
		pose = "run2"
	var tex: Texture2D = set.get(pose, set.get("run"))
	if tex == null:
		return false

	# 影子留在地面
	_ellipse(Vector2(base.x, base.y + r * 0.5), r * (0.9 - lift / 300.0), r * 0.42,
		Color(0, 0, 0, 0.22))

	# 跑步的起伏：單張圖靠這個活起來。跌倒時改成左右抖。
	var bob := 0.0
	var shake := 0.0
	if fallen:
		shake = sin(elapsed * 42.0) * r * 0.10
	elif lift <= 1.0:
		bob = sin(elapsed * 13.0) * r * (0.04 if set.has("run2") else 0.09)

	var scale: float = 1.0 + lift / 260.0
	var w: float = r * SPRITE_W * scale
	var h: float = w * tex.get_height() / maxf(tex.get_width(), 1.0)
	var rect := Rect2(-w * 0.5, -h * SPRITE_ANCHOR, w, h)
	var at := Vector2(base.x + shake, base.y - lift + bob)
	if absf(tilt) > 0.001:
		# 繞著「腳下」轉，不是繞貼圖中心 —— 繞中心的話整隻貓會在路上左右飄
		draw_set_transform(at, tilt, Vector2.ONE)
		draw_texture_rect(tex, rect, false, cat_tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(tex, Rect2(rect.position + at, rect.size), false, cat_tint)
	return true


func _draw_lab_labels(d0: float, d1: float) -> void:
	if mode != Mode.JUMP_LAB:
		return
	var safe := Cfg.safe_gap()
	var hard := Cfg.max_gap()
	for pair in lab_labels:
		var d: float = pair[0]
		if d < d0 or d > d1:
			continue
		var w: float = float(pair[1])
		var col := Color(0.15, 0.55, 0.25)
		var tag := "基礎速可過"
		if w > hard:
			col = Color(0.80, 0.15, 0.15)
			tag = "過不去"
		elif w > safe:
			col = Color(0.85, 0.55, 0.10)
			tag = "要全速"
		var edge := _track_screen(d, _track_half_at(d))
		draw_string(font, edge + Vector2(12, 6), "%du %s" % [int(w), tag],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, col)


# ============================================================ 賽道地圖

const MAP_X := 20.0
const MAP_Y := 28.0
const MAP_SIZE := 148.0


func _map_pos(w: Vector2) -> Vector2:
	## 把整圈賽道縮進左上角的方框裡
	var b := track.bounds
	var sc: float = MAP_SIZE / maxf(maxf(b.size.x, b.size.y), 1.0)
	return Vector2(MAP_X + MAP_SIZE * 0.5, MAP_Y + MAP_SIZE * 0.5) \
		+ (w - b.get_center()) * sc


func _draw_minimap() -> void:
	draw_rect(Rect2(MAP_X - 10, MAP_Y - 10, MAP_SIZE + 20, MAP_SIZE + 44),
		Color(0.05, 0.14, 0.24, 0.80))

	# 整圈路線
	var pts := PackedVector2Array()
	for p in track.points:
		pts.append(_map_pos(p))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.70, 0.85, 1.0, 0.9), 4.0)

	# 起點／終點線
	var s0 := _map_pos(track.pos_at(0.0))
	draw_circle(s0, 5.0, Color(1.0, 0.85, 0.3))

	# 前方 1600u 內該小心的東西
	for e in elements:
		if not e.get("alive", true):
			continue
		var gap: float = e.d - dist
		if gap < -40.0 or gap > 1600.0:
			continue
		if e.type == "crevasse" or e.has("seal"):
			# 危險用琥珀色，跟小玲的紅旗分開 —— 兩種都紅的話，地圖上看不出差別
			draw_circle(_map_pos(track.world(e.d, float(e.off))), 3.2,
				Color(0.98, 0.70, 0.25, 0.95))

	# 小玲插過的旗子：整條記號留在地圖上
	for f in trail:
		draw_circle(_map_pos(track.world(float(f.d), float(f.off))), 2.0, C_TRAIL)

	# 你在這裡
	var me := _map_pos(track.world(dist, off))
	draw_circle(me, 7.0, Color.WHITE)
	draw_circle(me, 4.5, Color(0.12, 0.13, 0.18))

	var lap := mini(int(dist / maxf(lap_len, 1.0)) + 1, laps)
	var pct := int(clampf(dist / maxf(track_len, 1.0), 0.0, 1.0) * 100.0)
	draw_string(font, Vector2(MAP_X - 2, MAP_Y + MAP_SIZE + 24),
		"第 %d/%d 圈　%d%%" % [lap, laps, pct],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1))
