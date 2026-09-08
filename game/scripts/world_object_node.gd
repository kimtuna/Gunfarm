extends Node2D

## 월드 오브젝트 **한 개**의 그림. `world_objects_view.gd` 가 하나씩 만든다.
##
## **노드가 하나씩 따로 있는 이유는 앞뒤(Y) 정렬 때문이다** — 플레이어와 같은 Y정렬
## 묶음 안에 들어가야 "내 위쪽 나무는 내 뒤에, 아래쪽 나무는 내 앞에"가 저절로 맞는다
## (바닥 아이템·데스드롭 상자와 같은 자리다). 한 노드가 전부 그리면 그 노드의 Y
## 하나로만 정렬돼서 캐릭터가 언제나 숲 앞이거나 언제나 숲 뒤가 된다.
##
## 원점은 **오브젝트가 선 자리(밑동)** 다 — 플레이어 노드의 원점이 발밑인 것과 같다.
## 그림은 그 위로 올라가고(`WorldObjects.draw_offset`), 원점에는 납작한 그림자를
## 깔아 어느 칸에 서 있는지 보이게 한다.
##
## **배율이 없다**(`draw_texture_rect` 를 아트 크기 그대로 그린다). 캐릭터 96px ·
## 타일 48px 이 둘 다 배율 1이라(docs/CHARACTER.md 1절) 오브젝트도 1이어야 아트
## 픽셀 하나가 화면에서 똑같이 1px 이 된다.

const WorldObjects := preload("res://scripts/world_objects.gd")

## 종류마다 그림자 반지름(가로). 세로는 이 비율로 눌린다 — 납작해야 땅에 깔린 것으로
## 보인다(바닥 아이템의 그림자와 같은 규칙).
const SHADOW_RX := {
	WorldObjects.TREE: 26.0,
	WorldObjects.ROCK: 20.0,
	WorldObjects.BUSH: 20.0,
}
const SHADOW_FLATTEN := 0.34
const SHADOW_COLOR := Color(0.03, 0.05, 0.02, 0.30)

## 그림을 원점보다 얼마나 내려 그리는가 — 밑동이 그림자에 살짝 잠겨야 떠 있지 않다.
const SINK := 3.0

var _kind := WorldObjects.NONE
var _variant := 0
var _sheet: Texture2D = null


## 이 노드가 그릴 오브젝트와 자리를 정한다. `world_objects_view.gd` 만 부른다.
func show_object(kind: int, variant: int, world_position: Vector2) -> void:
	if _kind == kind and _variant == variant and position == world_position:
		return
	_kind = kind
	_variant = variant
	position = world_position
	_sheet = load(WorldObjects.sheet_path(kind)) if kind != WorldObjects.NONE else null
	queue_redraw()


func _draw() -> void:
	if _kind == WorldObjects.NONE:
		return
	_draw_shadow()
	if _sheet == null:
		return
	var region := WorldObjects.region(_kind, _variant)
	# 자리는 정수로 반올림한다 — 반 픽셀에 놓으면 도트가 뭉개진다(STYLE_GUIDE 1번).
	var at := (WorldObjects.draw_offset(_kind) + Vector2(0.0, SINK)).round()
	draw_texture_rect_region(_sheet, Rect2(at, region.size), region)


func _draw_shadow() -> void:
	var rx: float = SHADOW_RX[_kind]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_FLATTEN))
	draw_circle(Vector2.ZERO, rx, SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
