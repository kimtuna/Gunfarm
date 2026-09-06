extends Node2D

## 스폰 지점 표식. 플레이어 캐릭터가 아직 없어서(이번 범위는 지형과 스폰 지점까지다)
## "여기서 시작한다"는 자리만 표시한다 — 캐릭터가 생기면 이 노드를 캐릭터로 갈아끼운다.

const COLOR := Color(0.85098, 0.760784, 0.478431)  # 메뉴 강조색과 같은 금색
const RADIUS := 14.0


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 8.0, Color(COLOR, 0.18))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, COLOR, 3.0)
	draw_line(Vector2(-RADIUS - 12.0, 0), Vector2(RADIUS + 12.0, 0), COLOR, 2.0)
	draw_line(Vector2(0, -RADIUS - 12.0), Vector2(0, RADIUS + 12.0), COLOR, 2.0)
