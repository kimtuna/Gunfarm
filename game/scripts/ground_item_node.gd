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

## **월드의 도트 배율은 1배 하나뿐이다** (2026-09-08, INBOX #67 — 전에는 3배였다).
## 캐릭터(아트 96px 칸)도 타일(아트 48px 칸)도 배율 1이라 아트 픽셀 하나가 화면에서
## 1px 인데, 바닥 아이템만 3배면 **그 하나만 도트 결이 다르다**
## (`docs/STYLE_GUIDE.md` 1번 — *"배율이 이웃과 다르면 정수여도 어긋난다"*).
## **화면 크기는 안 바뀐다**(36px 그대로): 배율을 내린 만큼 그림 쪽 칸을 12 → 36px 로
## 키웠다(`gen_character.py` 의 `GROUND_N`). 「크기를 맞출 때 배율을 손대지 말고
## 캔버스를 손댄다」는 INBOX #38 의 판단이 반대 방향으로 한 번 더 쓰인 것이다.
const ZOOM := 1

## 바닥용 그림 한 칸(= `gen_character.py` 의 `GROUND_N`)과 그 화면 크기.
## `BOX` 는 자체 QA 가 "이 자리에 아이템이 그려졌는가"를 짚을 때 쓰는 사각형이다.
const ART := 36
const BOX := ART * ZOOM

## 그림을 원점보다 얼마나 내려 그리는가 — 물건 밑동이 그림자에 살짝 잠겨야 떠 있지 않다.
const SINK := 4.0

const SHADOW_RX := 13.0
const SHADOW_RY := 5.0
const SHADOW_COLOR := Color(0.03, 0.05, 0.02, 0.30)

# ── 그림이 아직 없는 아이템의 자리표시 ─────────────────────────────────────
# **인벤토리 칸의 자리표시(색 사각형 + 두 글자)를 풀밭에 그대로 놓을 수 없다**
# (2026-09-07, INBOX #38). 칸 안에서는 자연스럽지만 월드에 놓으면 **띠와 테두리를
# 두른 34px 짜리 정사각형**이라 아이템이 아니라 **떠 있는 궤짝**으로 읽히고,
# 글자는 풀밭 위에 뜬 UI 로 보인다.
#
# 그래서 바닥에서는 **덩어리를 쌓은 더미 하나**로 그린다 — 무엇이라고 주장하지
# 않아서 어떤 원재료에 붙어도 거짓말을 하지 않는다(목이 달린 자루 모양도 그려봤는데
# **밤톨**로 읽혔다).
# 지키는 것 셋:
#   1) 도트 결 — 한 칸이 화면 `ZOOM`(1)px 이라 캐릭터·지형·도구 그림과 결이 같다.
#   2) 외곽선은 공통 잉크색 `#261C2C` — 순검정을 쓰지 않는다(STYLE_GUIDE 2번).
#   3) 광원은 왼쪽 위 — 아래 표의 밝은 칸이 전부 왼쪽 위에 몰려 있다.
# **아이템을 가르는 것은 여전히 색 하나다**(`item_types.gd` 의 `color`) — 창 안팎에서
# 같은 아이템이 같은 색으로 보인다. 두 글자를 잃는 대신 얻는 것이 "궤짝이 아닌 것"이다.
#
# **무늬는 손으로 찍지 않는다** (2026-09-08, INBOX #70 — 그전에는 손으로 찍은 10 × 8
# 무늬를 화면에서 3배로 그렸고, INBOX #67 이 나머지를 전부 배율 1로 맞춘 뒤 **이것만
# 도트가 세 배 굵게 남아** 있었다). 아래 표는 `game/tools/gen_ground_placeholder.py`
# 가 굽는다 — 덩어리 → 조명 → 축소 → 양자화 → 내부선 → 외곽선까지 도구·상자와
# **같은 파이프라인**이고, 램프 색만 안 정해진 채로 나온다(색은 아이템마다 다르므로
# 실행 중에 만든다). **손으로 고치지 말고 그 스크립트를 다시 돌릴 것.**
#
# 글자: `.` 빈 칸 / `k` 잉크 / `0`~`3` 그 아이템 색 램프(밝은면 → 가장 어두움).
#
# **이건 여전히 자리표시다.** 원재료 아이콘이 생기는 바퀴가 그 아이템에 `ground`
# 한 줄을 붙이면 이 그림은 저절로 안 쓰인다.
const PLACEHOLDER_ART := [
	".................kkkkkk.............",
	"...............kk000000kk...........",
	"..............k0000000001k..........",
	".............k000000000001k.........",
	"............k00000000000011k........",
	"...........k0000000000001112k.......",
	"...........k0000000000011112k.......",
	"...........k0000000000111112k.......",
	"..........k000000000011111122k......",
	"...........k0000000111111122k.......",
	".........kk03000011111111122k.......",
	"........k0003111111111111222k.......",
	".......k0000331111111112222k........",
	"......k0000003311111122222k.........",
	".....k00000000332222222223k.........",
	".....k00000000033322221332k.........",
	".....k00000000011333333112kkk.......",
	".....k10000011111111111121300kk.....",
	".....k3311111111111111222300001k....",
	"...kk003311111111111222230000001k...",
	"..k000003311111112222223000000011k..",
	".k00000003332222222213300000001111k.",
	"k000000000033333333330000000011111k.",
	"k0000000000000133000000000011111122k",
	"k0000000000011113000000001111111122k",
	"k000000001111111300000111111111122k.",
	"k111111111111111311111111111111222k.",
	".k1111111111111133111111111112222k..",
	"..k21111111111222331111111122222k...",
	"...kk222222222222kk222222222222k....",
	".....kk22222222kk..kk22222222kk.....",
	".......kkkkkkkk......kkkkkkkk.......",
]

## 자리표시가 화면에서 차지하는 크기 (위 표의 칸 수 × `ZOOM`).
## 가로 36 은 도구의 바닥 그림(`ART`)과 같은 값이고, 세로 32 는 「아이템/오브젝트
## 크기 표준」의 **짧은 쪽 하한**이다 — 배율이 1이라 표의 줄 수가 곧 그 판정이다.
## (옛 자리표시는 화면 30 × 24px 이라 세로에서 그 하한을 8px 어기고 있었다.)
const PLACEHOLDER_COLS := 36
const PLACEHOLDER_ROWS := 32
const PLACEHOLDER := Vector2i(PLACEHOLDER_COLS, PLACEHOLDER_ROWS) * ZOOM

## 공통 잉크색. `gen_character.py` 의 `INK`(#261C2C)와 같은 값이어야 한다.
const INK := Color8(38, 28, 44)

## 자리표시 램프 4단계 — 아이템 색 하나에서 만든다(밝은면 → 기본 → 그늘 → 가장 어두움).
const LIGHTEN := 0.28
const DARKEN := 0.28
const DARKEST := 0.50

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
	var art := ItemTypes.ground_of(_stack.id)
	if art != null:
		var size := Vector2(art.get_size()) * float(ZOOM)
		# 자리도 정수로 반올림한다 — 반 픽셀에 놓으면 도트가 뭉개진다(STYLE_GUIDE 1번).
		var at := Vector2(-size.x * 0.5, SINK - size.y).round()
		draw_texture_rect(art, Rect2(at, size), false)
	else:
		_draw_placeholder()


## 땅에 닿는 점의 납작한 그림자. `draw_circle` 을 눌러 타원으로 만든다.
func _draw_shadow() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_RY / SHADOW_RX))
	draw_circle(Vector2.ZERO, SHADOW_RX, SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 자리표시 더미를 한 칸 = 화면 `ZOOM` px 로 찍는다 — 구워진 그림과 같은 격자다.
func _draw_placeholder() -> void:
	var base: Color = ItemTypes.color_of(_stack.id)
	var ramp := [base.lightened(LIGHTEN), base, base.darkened(DARKEN),
			base.darkened(DARKEST)]
	var rows: int = PLACEHOLDER_ART.size()
	var cols: int = (PLACEHOLDER_ART[0] as String).length()
	# 밑동이 원점 언저리에 오도록 왼쪽 위 모서리를 잡는다(그림과 같은 규칙).
	var dot := float(ZOOM)
	var origin := Vector2(-cols * dot * 0.5, SINK - rows * dot).round()
	for y in rows:
		var row: String = PLACEHOLDER_ART[y]
		for x in cols:
			var cell := row[x]
			if cell == ".":
				continue
			var color: Color = INK if cell == "k" else ramp[cell.to_int()]
			draw_rect(Rect2(origin + Vector2(x, y) * dot, Vector2(dot, dot)), color)
