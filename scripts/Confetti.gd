class_name Confetti
extends Node2D
## 過關時從上方兩側撒下來的彩帶。程式畫的，不需要素材。
##
## 每一片是一個會翻面的小長方形：一邊往下飄一邊自轉，
## 翻到側面時看起來變窄（用 cos 縮寬度模擬），這樣才像紙片而不是色塊。
##
## 用法：過關時 add_child(Confetti.new())，撒完自己會消失。
## 從 ../pinball/scripts/confetti.gd 搬過來，只改了噴出的位置與輪廓色
## （這邊沒有 CatArt，輪廓色直接寫死成同一個深咖啡）。

## 從哪兩個位置噴出來（檯面座標，畫面 720x1280）。
## 放在翼板上方的兩側，往中間斜噴，紙片才會灑滿整個檯面
const SPOUTS: Array[Vector2] = [Vector2(70.0, 1120.0), Vector2(650.0, 1120.0)]
## 一邊噴幾片
const PER_SPOUT := 48
const GRAVITY := 520.0
## 空氣阻力：紙片很輕，衝上去之後會慢慢飄下來
const DRAG := 0.8
## 飄出畫面下緣多遠就不畫了
const FLOOR_Y := 1330.0

## 貓咪配色，加上派對用的亮色
const COLORS: Array[Color] = [
	Color(0.898, 0.361, 0.302),   # 毛線球紅
	Color(0.949, 0.651, 0.353),   # 橘
	Color(0.976, 0.855, 0.463),   # 黃
	Color(0.588, 0.808, 0.553),   # 綠
	Color(0.478, 0.729, 0.910),   # 雪兒藍
	Color(0.937, 0.573, 0.639),   # 肉球粉
	Color(0.965, 0.933, 0.875),   # 米白
]


class Piece:
	var pos: Vector2
	var vel: Vector2
	var size: Vector2
	var color: Color
	## 紙片自轉的角度與速度
	var spin: float
	var spin_speed: float
	## 翻面的相位：翻到側面時寬度縮成 0，看起來像紙片轉過去
	var flip: float
	var flip_speed: float


var _pieces: Array[Piece] = []


func _ready() -> void:
	z_index = 40
	for spout in SPOUTS:
		var inward := 1.0 if spout.x < 360.0 else -1.0
		for i in PER_SPOUT:
			var p := Piece.new()
			p.pos = spout + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
			# 往內上方噴，散開的角度大一點才熱鬧
			p.vel = Vector2(inward * randf_range(170.0, 620.0), randf_range(-1150.0, -720.0))
			p.size = Vector2(randf_range(9.0, 15.0), randf_range(14.0, 22.0))
			p.color = COLORS[randi() % COLORS.size()]
			p.spin = randf() * TAU
			p.spin_speed = randf_range(-5.0, 5.0)
			p.flip = randf() * TAU
			p.flip_speed = randf_range(4.0, 9.0)
			_pieces.append(p)
	set_process(true)


func _process(delta: float) -> void:
	var alive := 0
	for p in _pieces:
		p.vel.y += GRAVITY * delta
		p.vel -= p.vel * DRAG * delta
		# 左右飄：紙片落下時會像樹葉一樣搖
		p.pos += (p.vel + Vector2(sin(p.flip) * 60.0, 0.0)) * delta
		p.spin += p.spin_speed * delta
		p.flip += p.flip_speed * delta
		if p.pos.y < FLOOR_Y:
			alive += 1
	if alive == 0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for p in _pieces:
		if p.pos.y >= FLOOR_Y:
			continue
		var w: float = p.size.x * absf(cos(p.flip))
		if w < 0.6:
			continue
		draw_set_transform(p.pos, p.spin, Vector2.ONE)
		var r := Rect2(Vector2(-w * 0.5, -p.size.y * 0.5), Vector2(w, p.size.y))
		# 翻到背面時暗一點，才有厚度感
		var shade: float = 0.72 if cos(p.flip) < 0.0 else 1.0
		draw_rect(r, Color(p.color.r * shade, p.color.g * shade, p.color.b * shade))
		draw_rect(r, Color(Color(0.23, 0.16, 0.15), 0.35), false, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
