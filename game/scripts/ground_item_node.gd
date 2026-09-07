extends Node2D

## 바닥에 놓인 아이템 **한 개**의 그림. `ground_items_view.gd` 가 하나씩 만든다.
##
## **노드가 하나씩 따로 있는 이유는 앞뒤(Y) 정렬 때문이다** — 플레이어와 같은 Y정렬
## 묶음 안에 들어가야 "내 위쪽에 놓인 것은 내 뒤에, 아래쪽에 놓인 것은 내 앞에"가
## 저절로 맞는다. 한 노드가 전부 그리면 그 노드의 Y 하나로만 정렬돼서 어긋난다.
##
## 원점은 **놓인 자리(땅에 닿는 점)** 다 — 플레이어 노드의 원점이 발밑인 것과 같다.
## 그림은 그 위로 올라가고, 원점에는 납작한 그림자를 깔아 어느 칸에 놓였는지 보이게 한다.

const ItemTypes := preload("res://scripts/item_types.gd")

## 아이콘(아트 17px)을 화면에서 몇 배로 그리는가. **정수 배율이어야 한다**
## (docs/STYLE_GUIDE.md 1번). 2배 = 34px 로, DESIGN.md 「아이템/오브젝트 크기 표준」의
## 하한 16px 을 넘으면서 플레이어(51px)의 2/3 다 — 실제 도끼와 사람의 비율이 그쯤이다.
const ZOOM := 2

## 아이콘이 아직 없는 아이템의 자리표시 한 변. 아이콘(17×2=34)과 같은 크기라 둘이
## 섞여 놓여도 크기가 들쭉날쭉하지 않다.
const PLACEHOLDER := 34.0

## 그림을 원점보다 얼마나 내려 그리는가 — 물건 밑동이 그림자에 살짝 잠겨야 떠 있지 않다.
const SINK := 4.0

const SHADOW_RX := 13.0
const SHADOW_RY := 5.0
const SHADOW_COLOR := Color(0.03, 0.05, 0.02, 0.30)

## 자리표시의 결(밝은 띠 / 그림자 / 테두리)은 인벤토리 칸과 같은 값이다
## (`inventory_panel.gd` 의 `_draw_placeholder`) — 같은 아이템이 창 안팎에서 다르게
## 보이면 안 된다.
const BAND := 3.0
const BORDER := 2.0
const NAME_FONT_SIZE := 15

var _stack: RefCounted = null


## 이 노드가 그릴 뭉치와 자리를 정한다. `ground_items_view.gd` 만 부른다.
func show_stack(stack: RefCounted, world_position: Vector2) -> void:
	if _stack == stack and position == world_position:
		return
	_stack = stack
	position = world_position
	queue_redraw()


func _draw() -> void:
	if _stack == null or _stack.is_empty():
		return
	_draw_shadow()
	var icon := ItemTypes.icon_of(_stack.id)
	if icon != null:
		var size := Vector2(icon.get_size()) * float(ZOOM)
		# 자리도 정수로 반올림한다 — 반 픽셀에 놓으면 도트가 뭉개진다(STYLE_GUIDE 1번).
		var at := Vector2(-size.x * 0.5, SINK - size.y).round()
		draw_texture_rect(icon, Rect2(at, size), false)
	else:
		_draw_placeholder()


## 땅에 닿는 점의 납작한 그림자. `draw_circle` 을 눌러 타원으로 만든다.
func _draw_shadow() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_RY / SHADOW_RX))
	draw_circle(Vector2.ZERO, SHADOW_RX, SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_placeholder() -> void:
	var rect := Rect2(Vector2(-PLACEHOLDER * 0.5, SINK - PLACEHOLDER),
			Vector2(PLACEHOLDER, PLACEHOLDER))
	var base: Color = ItemTypes.color_of(_stack.id)
	draw_rect(rect, base)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, BAND)), base.lightened(0.25))
	draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - BAND), Vector2(rect.size.x, BAND)),
			base.darkened(0.35))
	draw_rect(rect, base.darkened(0.6), false, BORDER)
	# 글자는 바탕 밝기에 따라 검거나 희게 — 어느 아이템 색에서도 읽혀야 한다.
	var ink := Color(0.06, 0.07, 0.05) if base.get_luminance() > 0.42 else Color(0.95, 0.95, 0.92)
	var font := ThemeDB.fallback_font
	var text := ItemTypes.short_name(_stack.id)
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FONT_SIZE)
	var at := rect.position + Vector2((rect.size.x - measured.x) * 0.5,
			(rect.size.y + font.get_ascent(NAME_FONT_SIZE) - font.get_descent(NAME_FONT_SIZE)) * 0.5)
	draw_string(font, at.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FONT_SIZE, ink)
