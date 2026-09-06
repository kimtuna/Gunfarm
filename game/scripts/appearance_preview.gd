extends Control

## 커스터마이징 화면의 외형 미리보기 — **실제 게임에 들어가는 스프라이트를 그대로
## 띄운다** (2026-09-06, INBOX #11). 예전에는 색 사각형을 쌓아 사람 형태를 흉내냈는데,
## 그건 그림이 없던 시절의 임시방편이었다.
##
## 고른 색은 `character_sprite.gd` 가 **팔레트 교체**로 반영한다(형태를 다시 그리지
## 않는다 — `docs/STYLE_GUIDE.md` 2번). 머리모양은 색으로 못 만들므로 시트가 따로다.
##
## 앞모습을 크게 하나, 그 아래에 나머지 세 방향을 작게 늘어놓는다. 뒷모습이 없으면
## 묶은머리처럼 **뒤에서만 보이는 차이**를 확인할 수 없다.

const Appearance := preload("res://scripts/character_appearance.gd")
const CharacterSprite := preload("res://scripts/character_sprite.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")

const BACKDROP := Color(0.164706, 0.192157, 0.14902)

## 아트 픽셀이 화면에서 균일하려면 **배율이 정수여야 한다**(STYLE_GUIDE 1번).
## **2026-09-07 (INBOX #19) 에 캔버스가 34 → 17px 로 절반이 되면서 두 배가 됐다** —
## 미리보기가 화면에서 차지하는 크기(204px / 68px)는 그대로 두고 배율만 올린다.
const MAIN_SCALE := 12
const SIDE_SCALE := 4
const ROW_GAP := 10.0

## 아래 작은 줄에 늘어놓는 방향. 앞모습은 위에 크게 있으므로 뺀다.
const SIDE_DIRS := ["left", "up", "right"]

var appearance: Dictionary = Appearance.default_appearance():
	set(value):
		# 이름 칸을 한 글자 칠 때마다 화면 전체가 새로고침되므로, 정말 바뀐
		# 때만 시트를 다시 칠한다(픽셀 1만 8천 개를 도는 작업이다).
		var next := Appearance.normalize(value)
		if next == appearance and _texture != null:
			return
		appearance = next
		_texture = CharacterSprite.idle_texture(appearance)
		queue_redraw()

var _texture: Texture2D = null


func _ready() -> void:
	if _texture == null:
		_texture = CharacterSprite.idle_texture(appearance)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	if _texture == null:
		return
	var cell := float(PlayerFrames.CELL)
	var main := cell * MAIN_SCALE
	var small := cell * SIDE_SCALE
	var total := main + ROW_GAP + small
	var top := (size.y - total) * 0.5

	_frame("down", Rect2(Vector2((size.x - main) * 0.5, top), Vector2(main, main)))

	var row := small * SIDE_DIRS.size() + ROW_GAP * (SIDE_DIRS.size() - 1)
	var x := (size.x - row) * 0.5
	for dir in SIDE_DIRS:
		_frame(dir, Rect2(Vector2(x, top + main + ROW_GAP), Vector2(small, small)))
		x += small + ROW_GAP


## 시트에서 한 방향(= 한 행)의 첫 프레임만 잘라 그린다.
func _frame(dir: String, into: Rect2) -> void:
	var row := PlayerFrames.DIR_NAMES.find(dir)
	if row < 0:
		return
	var cell := float(PlayerFrames.CELL)
	draw_texture_rect_region(_texture, into, Rect2(0.0, row * cell, cell, cell))
