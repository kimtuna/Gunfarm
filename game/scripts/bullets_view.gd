extends Node2D

## 날아가는 총알을 그린다 (docs/DESIGN.md 「전투」).
##
## **이 노드는 `bullets.gd`(순수 클래스)가 들고 있는 목록을 비추기만 한다** — 어디까지
## 날아갔는지, 무엇에 막혔는지는 전부 그쪽이 정한다(DESIGN.md 「시뮬레이션 구조」).
## 여기서 목록을 고치면 안 된다.
##
## **바닥 아이템과 달리 총알마다 노드를 두지 않는다.** 그건 Y정렬 묶음에 들어가려고
## 그랬던 것인데(`ground_items_view.gd`), 총알은 지면에 놓인 물건이 아니라 **머리 위로
## 지나가는 것**이라 앞뒤를 가릴 것이 없다 — `Entities`(Y정렬) 밖에 두고 한 노드가
## 전부 그린다. 그래서 여기서는 `z_index` 가 정상으로 먹는다(docs/GOTCHAS.md 의
## "YSort 안에서는 z_index 가 무시된다"는 함정을 피한 자리다).

const Bullets := preload("res://scripts/bullets.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")

## 지면 좌표를 그림에서 얼마나 올리는가. **`player.gd` 의 `aim_origin()` 과 같은 값**
## (몸 한가운데 = 가슴 높이)이라 총알이 조준선과 같은 자리에서 나가는 것으로 보인다.
##
## **2026-09-10 (INBOX #76): `CELL * SCALE * 0.5`(=48) 에서 `BODY_CENTER`(=36) 로 고쳤다.**
## 인물이 칸(96)을 꽉 채우지 않게 된 뒤로 「칸의 절반」이 몸 한가운데가 아니게 됐고,
## 예광탄이 총이 아니라 **머리 옆에서** 날아갔다 — 근거는 `player_frames.BODY_CENTER`.
const LIFT := PlayerFrames.BODY_CENTER

## 꼬리 길이(월드 단위). 한 틱 이동량(15)보다 길어야 프레임 사이가 점선으로 끊겨
## 보이지 않는다.
const TRAIL := 22.0

## 굵기는 **도트 하나(아트 1px × 씬 스케일 3)** 를 단위로 잡는다 — 지형·캐릭터와
## 같은 도트 크기 단위라 총알만 매끈해 보이지 않는다.
const DOT := float(PlayerFrames.SCALE)
const CORE_WIDTH := DOT
const GLOW_WIDTH := DOT * 2.0

## 예광탄 색. 심지는 거의 흰 노랑, 번짐은 주황이다.
const CORE_COLOR := Color(1.0, 0.96, 0.76)
const GLOW_COLOR := Color(1.0, 0.66, 0.24, 0.42)

var bullets: RefCounted = null

## 지난 프레임에 몇 개를 그렸는가 — 0 이 된 프레임에 한 번 더 다시 그려야 마지막
## 총알이 화면에서 지워진다.
var _drawn := 0


func setup(new_bullets: RefCounted) -> void:
	bullets = new_bullets
	_drawn = 0
	queue_redraw()


func _process(_delta: float) -> void:
	if bullets == null:
		return
	var live: int = bullets.size()
	if live == 0 and _drawn == 0:
		return
	_drawn = live
	queue_redraw()


func _draw() -> void:
	if bullets == null:
		return
	for entry: Dictionary in bullets.bullets:
		var head: Vector2 = (entry[Bullets.KEY_POSITION] as Vector2) - Vector2(0.0, LIFT)
		var direction: Vector2 = entry[Bullets.KEY_DIRECTION]
		# 갓 나간 총알의 꼬리는 총구 뒤로 나가지 않는다 — 날아온 만큼까지만이다.
		var back := minf(TRAIL, float(entry[Bullets.KEY_TRAVELLED]))
		if back > DOT:
			draw_line(head - direction * back, head, GLOW_COLOR, GLOW_WIDTH)
			draw_line(head - direction * (back * 0.5), head, CORE_COLOR, CORE_WIDTH)
		draw_circle(head, DOT * 0.7, CORE_COLOR)
