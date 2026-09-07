extends Node2D

## 데스드롭 상자 **한 개**의 그림 (docs/DESIGN.md 「데스드롭 상자」).
## `death_boxes_view.gd` 가 하나씩 만든다.
##
## 원점은 **밑동(땅에 닿는 점)** 이라 그림이 그 위로 올라간다 — 플레이어 노드의 원점이
## 발밑인 것, 바닥 아이템(`ground_item_node.gd`)이 놓인 자리인 것과 같은 약속이다.
## 짚히는 사각형은 `death_boxes.gd` 의 `box_rect()` 한 곳에서 나오므로 **보이는 자리와
## 클릭이 먹는 자리가 어긋날 수 없다.**
##
## **이건 [BUILD] 바퀴가 코드로 그린 자리표시다** — 바닥 아이템의 자리표시
## (`ground_item_node.gd`)와 같은 성격이고, 제대로 된 도트 스프라이트는 [DESIGN]
## 바퀴가 만든다(INBOX 에 항목을 남겼다). 그래도 **도트 단위는 지킨다**: 모든 치수가
## `DOT`(=씬 스케일 3배) 의 배수라 화면에서 도트 하나가 캐릭터·지형과 똑같이 3px 이다
## (docs/DESIGN.md 「아이템/오브젝트 크기 표준」).

const DeathBoxes := preload("res://scripts/death_boxes.gd")

## 아트 픽셀 하나가 화면에서 차지하는 크기. 캐릭터·타일과 같은 3배다.
const DOT := 3.0

## 궤짝 몸통/뚜껑의 높이(도트). 뚜껑 4 + 몸통 9 + 사이 띠 1 = 14 도트 = 42px
## (`death_boxes.gd` 의 `BOX_SIZE.y`).
const LID_DOTS := 4
const SEAM_DOTS := 1

## 남은 시간 막대 — 궤짝 위에 한 도트 띄우고 한 도트 두께로 긋는다.
const BAR_GAP_DOTS := 2
const BAR_DOTS := 1

## 나무/쇠 색. **바닥 아이템 자리표시와 같은 결**(밝은 띠 + 그림자 + 어두운 테두리)이라
## 나란히 놓여도 이질감이 없다.
const WOOD := Color(0.42, 0.28, 0.16)
const WOOD_LID := Color(0.52, 0.35, 0.20)
const IRON := Color(0.36, 0.38, 0.41)
const LATCH := Color(0.72, 0.62, 0.30)
const OUTLINE := Color(0.13, 0.09, 0.05)

const SHADOW_RX := 20.0
const SHADOW_RY := 7.0
const SHADOW_COLOR := Color(0.03, 0.05, 0.02, 0.32)

## 남은 시간 막대 색. 창틀·핫바와 같은 금색이라 UI 와 한 벌로 읽힌다.
const BAR_BG := Color(0.09, 0.10, 0.08, 0.85)
const BAR_FILL := Color(0.851, 0.761, 0.478)
## 얼마 안 남았을 때의 색 — 서두르라는 신호다.
const BAR_LOW := Color(0.83, 0.42, 0.28)
const BAR_LOW_RATIO := 0.2

## 열려 있는 동안의 테두리 빛. **타이머가 멈춰 있다는 것이 월드에서도 보여야 한다.**
const OPEN_GLOW := Color(0.976, 0.882, 0.522)

## 막대를 다시 그리는 최소 변화(비율). 매 프레임 다시 그리지 않으려는 것뿐이다.
const BAR_STEP := 0.005

var _ratio := -2.0
var _opened := false


## 이 노드가 그릴 상자를 정한다. `death_boxes_view.gd` 만 부른다.
func show_box(entry: Dictionary) -> void:
	var at: Vector2 = entry[DeathBoxes.KEY_POSITION]
	var ratio: float = DeathBoxes.remaining_ratio(entry)
	var opened: bool = bool(entry[DeathBoxes.KEY_OPENED])
	if position == at and opened == _opened and absf(ratio - _ratio) < BAR_STEP:
		return
	position = at
	_ratio = ratio
	_opened = opened
	queue_redraw()


func _draw() -> void:
	_draw_shadow()
	var size := DeathBoxes.BOX_SIZE
	var left := -size.x * 0.5
	var top := -size.y
	var lid_h := float(LID_DOTS) * DOT
	var seam_h := float(SEAM_DOTS) * DOT

	# 뚜껑 — 위쪽이 밝다(광원은 위, 바닥 아이템 자리표시와 같은 규칙).
	draw_rect(Rect2(left, top, size.x, lid_h), WOOD_LID)
	draw_rect(Rect2(left, top, size.x, DOT), WOOD_LID.lightened(0.22))
	# 뚜껑과 몸통 사이의 어두운 틈 — 이게 있어야 궤짝이 나무상자로 읽힌다.
	draw_rect(Rect2(left, top + lid_h, size.x, seam_h), OUTLINE)
	# 몸통.
	var body_top := top + lid_h + seam_h
	var body_h := size.y - lid_h - seam_h
	draw_rect(Rect2(left, body_top, size.x, body_h), WOOD)
	draw_rect(Rect2(left, -DOT, size.x, DOT), WOOD.darkened(0.35))

	# 쇠 띠 두 줄(세로) — 궤짝의 실루엣을 가르는 것이 이 두 줄이다.
	for offset: float in [-4.0, 2.0]:
		draw_rect(Rect2(left + (offset + 8.0) * DOT, top, 2.0 * DOT, size.y), IRON)
	# 자물쇠 — 뚜껑과 몸통에 걸친 두 도트짜리 금색.
	draw_rect(Rect2(-DOT, top + lid_h - DOT, 2.0 * DOT, 3.0 * DOT), LATCH)
	draw_rect(Rect2(left, top, size.x, size.y), OUTLINE, false, DOT)
	if _opened:
		# 열려 있는 동안은 테두리가 밝다 — 타이머가 멈춰 있다는 표시다.
		draw_rect(Rect2(left, top, size.x, size.y).grow(DOT), OPEN_GLOW, false, DOT)
	_draw_bar(left, top, size.x)


## 남은 시간 막대. **「사라지지 않음」이면 아예 안 그린다** — 줄지 않는 막대는
## 거짓말이다.
func _draw_bar(left: float, top: float, width: float) -> void:
	if _ratio < 0.0:
		return
	var y := top - float(BAR_GAP_DOTS + BAR_DOTS) * DOT
	var height := float(BAR_DOTS) * DOT
	draw_rect(Rect2(left, y, width, height), BAR_BG)
	var fill := BAR_LOW if _ratio <= BAR_LOW_RATIO else BAR_FILL
	# 칸 수를 도트로 끊는다 — 반 도트짜리 막대는 이 그림체에서 뭉개진다.
	var dots := roundi(_ratio * width / DOT)
	if dots > 0:
		draw_rect(Rect2(left, y, float(dots) * DOT, height), fill)


## 땅에 닿는 점의 납작한 그림자 (`ground_item_node.gd` 와 같은 방식).
func _draw_shadow() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_RY / SHADOW_RX))
	draw_circle(Vector2.ZERO, SHADOW_RX, SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
