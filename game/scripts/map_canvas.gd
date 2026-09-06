extends Control

## 전체 맵의 그림 부분 (docs/DESIGN.md 「맵 (M)」). 띄우고 닫는 일은 `map_screen.gd` 가
## 하고, 여기서는 **가본 곳의 지형 + 내 위치/조준 방향**만 그린다.
##
## **지형은 기록에서 읽지 않고 `world_gen` 에 다시 물어본다** — 방문 기록(`explored_map.gd`)이
## 가진 것은 "어디를 봤는가" 하나뿐이다. 안 가본 칸은 지형을 알든 말든 안 그린다.
##
## 65,536칸을 매 프레임 다시 굽지 않는다 — 방문 기록의 `version` 이 달라졌을 때만
## 이미지를 새로 만들고, 평소에는 만들어둔 텍스처 한 장을 확대해서 붙인다
## (프로젝트 전역 텍스처 필터가 Nearest 라 확대해도 도트가 안 뭉개진다).
##
## **줌은 이 텍스처를 붙이는 사각형(`map_rect()`)만 바꾼다** — 이미지는 다시 굽지 않는다.

const WorldGen := preload("res://scripts/world_gen.gd")
const TerrainTiles := preload("res://scripts/terrain_tiles.gd")
const TerrainPalettes := preload("res://scripts/terrain_palettes.gd")

const TILES := WorldGen.MAP_TILES

## 아직 안 가본 칸. 어느 지형 램프와도 뚜렷이 다른 색이어야 한다 — 자체 QA 가 화면의
## 픽셀을 이 색과 지형 램프에 견줘서 "안 가본 곳이 정말 안 보이는지" 판정한다.
const UNEXPLORED_COLOR := Color(0.066, 0.078, 0.062)

## 내 위치 화살표. 지형·안 가본 칸 어느 색과도 안 겹치는 밝은 금색이다.
const MARKER_COLOR := Color(0.976, 0.882, 0.522)
const MARKER_EDGE_COLOR := Color(0.078, 0.086, 0.070)

## 화살표 크기(화면 px). 지도 한 칸이 기본 2px 이라 이 정도면 방향이 읽힌다.
## **배율을 따라 커지지 않는다** — 내 위치 표시는 지도 그림이 아니라 화면 위의 표식이다.
const MARKER_LENGTH := 11.0
const MARKER_HALF_WIDTH := 6.0

## 줌 단계 (docs/DESIGN.md 「맵 줌 (마우스 휠)」). **정수 배율만** 쓴다 — 소수 배율을
## 끼우면 지도 픽셀 하나가 화면에서 1px, 2px 로 들쭉날쭉해져 도트가 뭉개진다.
const ZOOM_STEPS := [1, 2, 4, 8]

## 기본은 2배(= 256칸이 화면 512px). 1배는 월드 전체가 한눈에 들어오는 배율이다.
const DEFAULT_ZOOM_INDEX := 1

## 지도의 가장자리를 알려주는 한 줄. **1배에서 지도(256px)가 창(512px)보다 작을 때**
## 여백과 안 가본 칸이 둘 다 어두워서 세계가 어디까지인지 안 보이기 때문에 긋는다.
## 창 테두리와 같은 금색이라 지도 그림의 일부로 안 읽힌다.
const MAP_EDGE_COLOR := Color(0.851, 0.761, 0.478, 0.45)

## 지도 그림 바깥의 여백. 1배일 때만 보인다(256px 짜리 지도가 512px 창보다 작다).
## **확대한 상태에서 이 색이 보이면 지도 밖을 보여주고 있다는 뜻**이라, 자체 QA 가
## 이 색으로 "가장자리에서 지도 밖이 안 보이는지"를 판정한다 — 지형·안 가본 칸 어느
## 색과도 뚜렷이 달라야 한다.
const BACKDROP_COLOR := Color(0.024, 0.027, 0.031)

var world: RefCounted = null
var explored: RefCounted = null
var player: Node2D = null

## 지금 배율. **지도를 닫았다 열어도 유지되지만 저장하지는 않는다**(docs/DESIGN.md
## 「맵 줌」) — 캐릭터의 진행 상황이 아니라 지금 보고 있는 방식일 뿐이라 슬롯의
## `explored` 옆에 끼워 넣지 않는다. 그래서 노드가 아니라 **스크립트에 붙은 static**
## 이다: 지도 노드는 닫을 때마다 사라지지만 이 값은 남고, 게임을 다시 켜면 기본 2배다.
static var zoom_index := DEFAULT_ZOOM_INDEX

var _texture: ImageTexture = null
var _drawn_version := -1
var _drawn_position := Vector2.INF
var _drawn_angle := INF


func _ready() -> void:
	# 확대하면 지도가 이 창보다 커진다 — 잘라내지 않으면 화면 전체로 넘쳐 그려진다.
	clip_contents = true


func setup(new_world: RefCounted, new_explored: RefCounted, new_player: Node2D) -> void:
	world = new_world
	explored = new_explored
	player = new_player
	_drawn_version = -1
	queue_redraw()


func _process(_delta: float) -> void:
	# 지도가 열려 있는 동안에도 세계는 돈다 — 기록이 늘거나 내가 움직이면 다시 그린다.
	if explored != null and explored.version != _drawn_version:
		queue_redraw()
		return
	if player == null:
		return
	if not player.global_position.is_equal_approx(_drawn_position) \
			or not is_equal_approx(_aim_angle(), _drawn_angle):
		queue_redraw()


func _draw() -> void:
	if world == null or explored == null:
		return
	if explored.version != _drawn_version:
		_texture = ImageTexture.create_from_image(_bake())
		_drawn_version = explored.version
	# 지도 밖 여백을 먼저 깔아야 1배에서 지도가 어디까지인지 눈에 보인다.
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP_COLOR)
	var rect := map_rect()
	draw_texture_rect(_texture, rect, false)
	# 지도 **바깥쪽**에 긋는다 — 안쪽에 그으면 가장자리 한 칸을 덮어버린다.
	draw_rect(rect.grow(1.0), MAP_EDGE_COLOR, false, 1.0)
	_draw_marker()


# --- 줌 (docs/DESIGN.md 「맵 줌 (마우스 휠)」) ----------------------------------

func zoom_scale() -> int:
	return ZOOM_STEPS[zoom_index]


## 휠 한 칸에 한 단계. 양 끝에서는 더 안 움직인다 — 실제로 바뀌었으면 true 다.
func zoom_by(steps: int) -> bool:
	var next := clampi(zoom_index + steps, 0, ZOOM_STEPS.size() - 1)
	if next == zoom_index:
		return false
	zoom_index = next
	queue_redraw()
	return true


## 지도 그림이 이 창의 어디에 얼마 크기로 놓이는가(창 기준 좌표).
##
## 배율이 커져 지도가 창보다 커지면 **플레이어를 중심에 두고 잘라서** 보여준다.
## 다만 지도 가장자리에서는 중심을 안쪽으로 물려 **지도 밖이 나오지 않게** 한다
## (`clampf` 가 그 일을 한다). 지도가 창보다 작으면(1배) 가운데에 놓는다.
##
## 시작 좌표를 정수로 반올림하는 것이 중요하다 — 소수 자리가 남으면 배율이 정수여도
## 지도 픽셀 하나가 화면에서 2px, 3px 로 들쭉날쭉해진다.
func map_rect() -> Rect2:
	var drawn := Vector2.ONE * float(TILES * zoom_scale())
	var origin := Vector2.ZERO
	for axis in 2:
		if drawn[axis] <= size[axis]:
			origin[axis] = roundf((size[axis] - drawn[axis]) * 0.5)
		else:
			var focus: float = _focus()[axis] * drawn[axis]
			origin[axis] = clampf(roundf(size[axis] * 0.5 - focus),
					size[axis] - drawn[axis], 0.0)
	return Rect2(origin, drawn)


## 확대했을 때 화면 한가운데에 둘 자리 — 지도 전체를 0~1 로 본 내 위치다.
func _focus() -> Vector2:
	if player == null:
		return Vector2(0.5, 0.5)
	return (player.global_position / WorldGen.world_size()).clamp(Vector2.ZERO, Vector2.ONE)


## 방문 기록 × 지형 → 지도 이미지 한 장(타일 하나 = 픽셀 하나).
func _bake() -> Image:
	var image := Image.create_empty(TILES, TILES, false, Image.FORMAT_RGBA8)
	image.fill(UNEXPLORED_COLOR)
	for y in TILES:
		for x in TILES:
			if explored.is_explored(x, y):
				image.set_pixel(x, y, _tile_color(x, y))
	return image


## 한 칸의 색. 램프 단계를 좌표 해시로 살짝 흔들어(지형 시트의 무늬 변주와 같은 해시)
## 지도가 단색 덩어리로 보이지 않게 하고, 물에 닿은 땅은 테두리색으로 해안선을 세운다.
func _tile_color(x: int, y: int) -> Color:
	var variant := TerrainTiles.variant_at(x, y)
	if not world.is_land(x, y):
		return TerrainPalettes.color_of("deep", 1 if variant % 3 == 0 else 2)
	if not (world.is_land(x + 1, y) and world.is_land(x - 1, y)
			and world.is_land(x, y + 1) and world.is_land(x, y - 1)):
		return TerrainPalettes.color_of("rim", 1)
	return TerrainPalettes.color_of("grass", 0 if variant % 3 == 0 else 1)


## 내 위치는 점이 아니라 **조준 방향을 가리키는 화살표**다 (docs/DESIGN.md 「맵 (M)」) —
## 점만 찍으면 지도에서 어느 쪽을 보고 있는지 알 수 없다. 각도는 4방향으로 스냅되기
## 전의 원본(`player_motion.gd` 의 `aim_angle`)을 그대로 쓴다.
func _draw_marker() -> void:
	if player == null:
		return
	var at := map_position(player.global_position)
	var angle := _aim_angle()
	_drawn_position = player.global_position
	_drawn_angle = angle
	var forward := Vector2.from_angle(angle)
	var side := forward.orthogonal()
	var points := PackedVector2Array([
		at + forward * MARKER_LENGTH,
		at - forward * MARKER_LENGTH * 0.45 + side * MARKER_HALF_WIDTH,
		at - forward * MARKER_LENGTH * 0.1,
		at - forward * MARKER_LENGTH * 0.45 - side * MARKER_HALF_WIDTH,
	])
	# 어두운 테두리를 먼저 깔아야 밝은 땅 위에서도 화살표가 안 묻힌다.
	draw_colored_polygon(_grown(points, at, 1.6), MARKER_EDGE_COLOR)
	draw_colored_polygon(points, MARKER_COLOR)


## 월드 좌표 → 지도 안의 화면 좌표. 줌과 중심 이동이 `map_rect()` 한 곳에만 있으므로
## 화살표도, 자체 QA 도 이 함수만 부르면 배율이 뭐든 맞는 자리를 얻는다.
func map_position(world_position: Vector2) -> Vector2:
	var rect := map_rect()
	return rect.position + world_position / WorldGen.world_size() * rect.size


func _aim_angle() -> float:
	if player == null or player.motion == null:
		return 0.0
	return player.motion.aim_angle


func _grown(points: PackedVector2Array, center: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + (point - center).normalized() * by)
	return out
