extends Control

## 커스터마이징 화면의 외형 미리보기.
##
## **실제 캐릭터 그림은 아직 없다**(INBOX #4 범위 밖 — 그림은 별도 [DESIGN] 항목).
## 그때까지 고른 색이 어디에 쓰이는지만 보이면 되므로 색 사각형을 쌓아서 사람 형태만
## 흉내낸다. 그림이 생기면 이 스크립트를 스프라이트로 갈아끼운다.

const Appearance := preload("res://scripts/character_appearance.gd")

## 사각형 좌표는 이 격자(가로 24 × 세로 32칸) 기준이고, 컨트롤 크기에 맞춰 확대된다.
## 도트 느낌을 유지하려고 칸 단위로만 그린다. 사람은 3~30번째 칸만 써서 위아래에
## 여백을 남긴다 — 발이 미리보기 틀에 딱 붙으면 잘린 것처럼 보인다.
const GRID := Vector2i(24, 32)

const OUTLINE := Color(0.070588, 0.082353, 0.058824)
const BACKDROP := Color(0.164706, 0.192157, 0.14902)
## 바지/신발은 옷색을 어둡게 쓴다 — 팔레트를 늘리지 않고 상하의를 구분하려는 것이다.
const PANTS_DARKEN := 0.55
const SHOES_DARKEN := 0.32

var appearance: Dictionary = Appearance.default_appearance():
	set(value):
		appearance = Appearance.normalize(value)
		queue_redraw()


func _draw() -> void:
	var unit := minf(size.x / GRID.x, size.y / GRID.y)
	var origin := (size - Vector2(GRID) * unit) * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)

	var skin: Color = Appearance.color_of("skin", appearance["skin"])
	var hair: Color = Appearance.color_of("hair_color", appearance["hair_color"])
	var cloth: Color = Appearance.color_of("clothes_color", appearance["clothes_color"])
	var pants := cloth.darkened(1.0 - PANTS_DARKEN)
	var shoes := cloth.darkened(1.0 - SHOES_DARKEN)

	# 머리 뒤쪽(긴머리/묶은머리의 늘어진 부분)은 몸보다 먼저 그려서 뒤로 보낸다.
	for rect in _back_hair_blocks():
		_block(rect, hair, unit, origin)

	_block(Rect2(5, 15, 3, 8), cloth, unit, origin)    # 왼팔 소매
	_block(Rect2(16, 15, 3, 8), cloth, unit, origin)   # 오른팔 소매
	_block(Rect2(5, 23, 3, 2), skin, unit, origin)     # 왼손
	_block(Rect2(16, 23, 3, 2), skin, unit, origin)    # 오른손
	_block(Rect2(7, 15, 10, 9), cloth, unit, origin)   # 상의
	_block(Rect2(8, 24, 4, 4), pants, unit, origin)    # 왼다리
	_block(Rect2(12, 24, 4, 4), pants, unit, origin)   # 오른다리
	_block(Rect2(8, 28, 4, 2), shoes, unit, origin)    # 왼신발
	_block(Rect2(12, 28, 4, 2), shoes, unit, origin)   # 오른신발
	_block(Rect2(11, 13, 2, 2), skin, unit, origin)    # 목
	_block(Rect2(8, 4, 8, 9), skin, unit, origin)      # 얼굴

	for rect in _front_hair_blocks():
		_block(rect, hair, unit, origin)

	# 눈 — 얼굴 방향을 알아볼 수 있게 두 점만 찍는다.
	_block(Rect2(10, 8, 1, 1), OUTLINE, unit, origin)
	_block(Rect2(13, 8, 1, 1), OUTLINE, unit, origin)


## 몸 뒤로 늘어지는 머리카락 (머리모양마다 다르다).
func _back_hair_blocks() -> Array[Rect2]:
	match String(appearance["hairstyle"]):
		"long":
			return [Rect2(6, 5, 12, 14)]
		"ponytail":
			return [Rect2(16, 6, 3, 10)]
	return []


## 얼굴 위에 얹히는 머리카락.
func _front_hair_blocks() -> Array[Rect2]:
	match String(appearance["hairstyle"]):
		"short":
			return [Rect2(8, 3, 8, 3)]
		"bob":
			return [Rect2(7, 3, 10, 3), Rect2(7, 6, 1, 6), Rect2(16, 6, 1, 6)]
		"long":
			return [Rect2(7, 3, 10, 3), Rect2(7, 6, 1, 7), Rect2(16, 6, 1, 7)]
		"ponytail":
			return [Rect2(8, 3, 8, 3)]
	return []


## 칸 좌표 사각형 하나를 채우고 어두운 외곽선을 두른다 (UI 버튼 테두리와 같은 색).
func _block(cells: Rect2, color: Color, unit: float, origin: Vector2) -> void:
	var rect := Rect2(origin + cells.position * unit, cells.size * unit)
	draw_rect(rect, color)
	draw_rect(rect, OUTLINE, false, maxf(1.0, unit * 0.25))
