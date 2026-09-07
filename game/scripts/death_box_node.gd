extends Node2D

## 데스드롭 상자 **한 개**의 그림 (docs/DESIGN.md 「데스드롭 상자」).
## `death_boxes_view.gd` 가 하나씩 만든다.
##
## 원점은 **밑동(땅에 닿는 점)** 이라 그림이 그 위로 올라간다 — 플레이어 노드의 원점이
## 발밑인 것, 바닥 아이템(`ground_item_node.gd`)이 놓인 자리인 것과 같은 약속이다.
## 짚히는 사각형은 `death_boxes.gd` 의 `box_rect()` 한 곳에서 나오므로 **보이는 자리와
## 클릭이 먹는 자리가 어긋날 수 없다.**
##
## **상자는 구워진 도트 스프라이트다** (2026-09-07, INBOX #40 — 그전에는 `draw_rect`
## 로 그린 자리표시였다). 만드는 코드는 `game/tools/gen_box.py` 이고, 나무·쇠 램프도
## 광원도 잉크도 도구 아이콘과 같은 것을 쓴다 — 바닥에 놓인 도끼 옆에 나란히 놓여도
## 이질감이 없어야 하기 때문이다(`docs/DESIGN.md` 「그래픽 파이프라인」 1) 어울림).
##
## **코드로 그리는 것이 둘 남아 있다.** 둘 다 그림이 아니라서다:
##   - 납작한 그림자 — 어느 칸에 놓였는지 보이게 하는 것이라 바닥 아이템과 공유한다.
##   - 남은 시간 막대 — **값에 따라 길이가 변하는 UI** 다(INBOX #40 (2)).

const DeathBoxes := preload("res://scripts/death_boxes.gd")

## 구워진 시트. 열 = 프레임이고 순서는 `gen_box.py` 의 `FRAMES` 와 같아야 한다.
const SHEET := preload("res://assets/sprites/death_box.png")
const FRAME_CLOSED := 0
const FRAME_OPEN := 1

## 아트 픽셀 하나가 화면에서 차지하는 크기. 캐릭터·타일·바닥 아이템과 같은 3배다
## (`docs/STYLE_GUIDE.md` 1번 — 월드에 놓이는 것은 전부 3배다).
const DOT := 3.0

## 그림 한 칸(아트). `death_boxes.gd` 의 `BOX_SIZE`(48 × 42) ÷ `DOT` 이고,
## `gen_box.py` 의 `BOX_W`/`BOX_H` 와 같아야 한다 — `_ready()` 가 실제로 견준다.
const ART := Vector2i(16, 14)

## 남은 시간 막대 — 상자 위에 두 도트 띄우고 한 도트 두께로 긋는다.
const BAR_GAP_DOTS := 2
const BAR_DOTS := 1

const SHADOW_RX := 20.0
const SHADOW_RY := 7.0
const SHADOW_COLOR := Color(0.03, 0.05, 0.02, 0.32)

## 남은 시간 막대 색. 창틀·핫바와 같은 금색이라 UI 와 한 벌로 읽힌다.
const BAR_BG := Color(0.09, 0.10, 0.08, 0.85)
const BAR_FILL := Color(0.851, 0.761, 0.478)
## 얼마 안 남았을 때의 색 — 서두르라는 신호다.
const BAR_LOW := Color(0.83, 0.42, 0.28)
const BAR_LOW_RATIO := 0.2

## 막대를 다시 그리는 최소 변화(비율). 매 프레임 다시 그리지 않으려는 것뿐이다.
const BAR_STEP := 0.005

var _ratio := -2.0
var _opened := false


func _ready() -> void:
	# 그림과 짚는 자리가 어긋나면 클릭이 빗나간다 — 구워진 칸이 실제로 그 크기인지
	# 여기서 한 번 본다(자체 QA 도 같은 것을 본다).
	assert(SHEET.get_size() == Vector2(ART.x * 2, ART.y),
			"death_box.png 는 %dx%d 칸 두 장이어야 한다" % [ART.x, ART.y])
	assert(Vector2(ART) * DOT == DeathBoxes.BOX_SIZE,
			"구워진 칸 × 3배가 death_boxes.gd 의 BOX_SIZE 와 다르다")


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
	# **열려 있으면 뚜껑이 젖혀진 프레임을 그린다** — 예전에는 테두리에 밝은 띠를
	# 둘러서 알렸는데, 그건 그림이 아니라 월드 위에 뜬 UI 로 보였다. 뚜껑이 열린
	# 그림 자체가 "타이머가 멈춰 있다"는 신호다(INBOX #40 (3)).
	var frame := FRAME_OPEN if _opened else FRAME_CLOSED
	draw_texture_rect_region(SHEET, Rect2(Vector2(left, top).round(), size),
			Rect2(float(frame * ART.x), 0.0, float(ART.x), float(ART.y)))
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
