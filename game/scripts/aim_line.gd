extends Node2D

## 조준선 — **총을 들고 있을 때만** 조준 방향으로 뻗는 빨간 선
## (docs/DESIGN.md 「전투」).
##
## **가만히 있으면 선명해지고 움직이면 흐려진다. 그 선명도가 곧 정조준이고 탄퍼짐과
## 같은 값이다** — 그래서 여기서 퍼짐을 따로 계산하지 않고 `player_motion.gd` 의
## `spread_angle()` 하나를 부른다. 총알(`bullets.gd` 의 `fire`)도 같은 함수를 부르므로
## **보이는 흐릿함과 실제로 빗나가는 정도가 어긋날 수 없다.**
##
## 그림은 두 겹이다 — **심지 한 줄 + 퍼짐 부채꼴**:
## - **심지**는 정조준한 딱 그 각도의 선이고, 진하기가 정조준에 그대로 비례한다.
##   완전히 모이면 또렷한 한 줄, 풀리면 사라진다.
## - **부채꼴**은 탄퍼짐 반각만큼 벌어진 옅은 띠다. 모이면 폭이 0 이라 안 보이고,
##   풀릴수록 넓게 번진다.
##
## 부챗살을 여러 줄 긋는 방식으로 만들어 봤다가 버렸다 — **살이 낱낱이 보여서 흐린
## 선이 아니라 "빨간 선 일곱 개"로 읽혔다.** 살을 겹칠 만큼 늘리면 낱낱이 옅어져서
## 이번에는 아무것도 안 보인다. 진하기(심지)와 폭(부채꼴)을 나눠 맡기면 두 문제가
## 같이 없어진다.
##
## **`Entities`(Y정렬) 밖에 둔다** — 조준선은 지면에 놓인 물건이 아니라 캐릭터 위에
## 늘 보여야 하는 것이라 앞뒤를 가릴 것이 없고, YSort 안에서는 `z_index` 도 안 먹는다
## (docs/GOTCHAS.md).

## 선이 뻗는 길이(월드 단위). 사거리(800)를 그대로 그리면 화면 세로(810)의 절반인
## 405 를 훌쩍 넘겨(카메라가 캐릭터에 붙어 있다) 화면을 통째로 가로지른다 —
## 겨누는 방향을 읽는 데 필요한 만큼만 그린다. **월드 단위 값이라 논리 해상도를
## 넓혀도 그대로 둔다** — 조준선은 화면의 몇 %가 아니라 "몇 타일 앞"이다.
const LENGTH := 260.0

## 캐릭터에서 얼마나 떨어져서 시작하는가. 0 이면 선이 몸 위에 얹혀서 도트를 덮는다.
const START := 20.0

## 완전히 정조준했을 때 심지의 진하기.
const LINE_ALPHA := 0.85

## 부채꼴 한 겹의 진하기(뿌리 쪽). 심지보다 한참 옅어야 "번진 것"으로 읽힌다.
const CONE_ALPHA := 0.18

## 부채꼴을 몇 겹으로 겹쳐 그리는가 — 퍼짐 반각의 몇 배씩인지의 목록이다.
## **한 겹만 그리면 가장자리가 칼로 자른 듯 딱 끊겨서 흐린 게 아니라 손전등 불빛으로
## 읽힌다.** 좁은 겹을 안쪽에 포개면 가운데가 진하고 가장자리로 옅어져 번짐이 된다.
const CONE_LAYERS := [1.0, 0.66, 0.33]

## 길이를 몇 토막으로 나눠 그리는가 — 토막마다 알파를 낮춰 끝으로 갈수록 사라지게 한다.
const SEGMENTS := 10

const WIDTH := 2.0
const LINE_COLOR := Color(0.93, 0.22, 0.18)

## 부채꼴을 아예 안 그리는 폭(월드 단위). 정조준이 거의 다 모이면 부채꼴이 심지보다
## 얇아져 보이지도 않는데, **꼭짓점이 겹친 사각형은 엔진이 삼각형으로 못 쪼갠다**
## ("Invalid polygon data, triangulation failed"). 그 아래는 심지만 그린다.
const MIN_CONE_WIDTH := 1.0

## 총을 들고 있는가. **여기서 직접 판정하지 않는다** — 든 칸에 무엇이 있는지는
## 인벤토리를 가진 쪽(`world.gd`)이 본다 (docs/DESIGN.md 「서버 권위」).
var armed := false:
	set(value):
		if armed == value:
			return
		armed = value
		queue_redraw()

var _player: Node2D = null


func setup(player: Node2D) -> void:
	_player = player
	queue_redraw()


func _process(_delta: float) -> void:
	# 조준 각도도 정조준도 매 틱 바뀐다 — 총을 들고 있는 동안은 계속 다시 그린다.
	if armed:
		queue_redraw()


func _draw() -> void:
	if not armed or _player == null or _player.motion == null:
		return
	var origin := to_local(_player.aim_origin())
	var direction: Vector2 = _player.motion.aim_direction()
	var focus: float = _player.motion.aim_focus
	var spread: float = _player.motion.spread_angle()
	var slope := tan(spread)
	for layer: float in CONE_LAYERS:
		# 정조준이 모일수록 좁은 겹부터 하나씩 사라진다 — 부채꼴이 저절로 오므라든다.
		if slope * layer * LENGTH >= MIN_CONE_WIDTH:
			_draw_cone(origin, direction, slope * layer)
	if focus > 0.0:
		_draw_core(origin, direction, focus)


## 탄퍼짐만큼 벌어진 옅은 띠. 토막마다 사각형 하나씩 그린다 — 볼록 다각형 하나에
## 꼭짓점 색을 주면 엔진이 안에서 어떻게 쪼개느냐에 따라 그라데이션이 들쭉날쭉해진다.
func _draw_cone(origin: Vector2, direction: Vector2, slope: float) -> void:
	var perpendicular := direction.orthogonal()
	for segment in SEGMENTS:
		var near := _at(segment)
		var far := _at(segment + 1)
		var near_point := origin + direction * near
		var far_point := origin + direction * far
		var near_half := perpendicular * (slope * near)
		var far_half := perpendicular * (slope * far)
		var points := PackedVector2Array([
			near_point + near_half, far_point + far_half,
			far_point - far_half, near_point - near_half,
		])
		var near_color := _fade(CONE_ALPHA, segment)
		var far_color := _fade(CONE_ALPHA, segment + 1)
		draw_polygon(points, PackedColorArray([near_color, far_color, far_color, near_color]))


## 정조준한 각도 그대로의 심지 한 줄. 진하기가 곧 정조준이다.
func _draw_core(origin: Vector2, direction: Vector2, focus: float) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for segment in SEGMENTS + 1:
		points.append(origin + direction * _at(segment))
		colors.append(_fade(LINE_ALPHA * focus, segment))
	draw_polyline_colors(points, colors, WIDTH)


## 토막 번호 → 총구에서의 거리.
func _at(segment: int) -> float:
	return START + (LENGTH - START) * (float(segment) / float(SEGMENTS))


## 토막 번호 → 그 자리의 색. 끝으로 갈수록 사라진다 — 처음에는 천천히, 끝에서 빠르게.
func _fade(alpha: float, segment: int) -> Color:
	var f := float(segment) / float(SEGMENTS)
	return Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, alpha * (1.0 - f * f))
