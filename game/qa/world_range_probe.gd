extends Node2D

## 자체 QA 전용 — "카메라가 보여주는 월드 범위"를 눈으로 볼 수 있게 만든 시험용 월드.
## 실제 게임 씬이 아니다. (docs/DESIGN.md "카메라 / 해상도" PvP 공정성 규칙 검증용)
##
## 논리 해상도 경계(±640, ±360) 바로 안쪽에 초록 표식을, 바로 바깥에 빨간 표식을 둔다.
## **빨간 표식이 화면에 보이면 그 해상도에서 시야가 넓어진 것 = 불합격**이다.
## 해상도가 달라져도 초록 표식만 보이고 빨간 표식은 안 보여야 한다.

const BASE_HALF := Vector2(640, 360)  # 논리 해상도 1280x720 의 절반
const GRID := 80.0
const MARGIN := 24.0  # 경계에서 표식까지의 거리

const COLOR_BG := Color(0.105882, 0.121569, 0.101961)
const COLOR_GRID := Color(0.227451, 0.266667, 0.211765)
const COLOR_AXIS := Color(0.462745, 0.505882, 0.415686)
const COLOR_INSIDE := Color(0.443137, 0.752941, 0.376471)
const COLOR_OUTSIDE := Color(0.847059, 0.301961, 0.278431)


func _draw() -> void:
	var far := BASE_HALF * 3.0
	draw_rect(Rect2(-far, far * 2.0), COLOR_BG)

	var x := -far.x
	while x <= far.x:
		draw_line(Vector2(x, -far.y), Vector2(x, far.y), COLOR_GRID, 2.0)
		x += GRID
	var y := -far.y
	while y <= far.y:
		draw_line(Vector2(-far.x, y), Vector2(far.x, y), COLOR_GRID, 2.0)
		y += GRID

	draw_line(Vector2(-far.x, 0), Vector2(far.x, 0), COLOR_AXIS, 3.0)
	draw_line(Vector2(0, -far.y), Vector2(0, far.y), COLOR_AXIS, 3.0)

	# 논리 해상도 경계선.
	draw_rect(Rect2(-BASE_HALF, BASE_HALF * 2.0), COLOR_INSIDE, false, 4.0)

	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(BASE_HALF.x * sx, BASE_HALF.y * sy)
			_marker(corner - Vector2(sx, sy) * MARGIN, COLOR_INSIDE)
			_marker(corner + Vector2(sx, sy) * MARGIN, COLOR_OUTSIDE)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-BASE_HALF.x + 40, -BASE_HALF.y + 70),
			"초록 = 시야 안 (모든 해상도에서 보여야 함)", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLOR_INSIDE)
	draw_string(font, Vector2(-BASE_HALF.x + 40, -BASE_HALF.y + 110),
			"빨강 = 시야 밖 (보이면 불합격)", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLOR_OUTSIDE)


func _marker(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at - Vector2(14, 14), Vector2(28, 28)), color)
