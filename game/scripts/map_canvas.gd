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

## 화살표 크기(화면 px). 지도 한 칸이 2px 이라 이 정도면 방향이 읽힌다.
const MARKER_LENGTH := 11.0
const MARKER_HALF_WIDTH := 6.0

var world: RefCounted = null
var explored: RefCounted = null
var player: Node2D = null

var _texture: ImageTexture = null
var _drawn_version := -1
var _drawn_position := Vector2.INF
var _drawn_angle := INF


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
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	_draw_marker()


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


## 월드 좌표 → 지도 안의 화면 좌표.
func map_position(world_position: Vector2) -> Vector2:
	return world_position / WorldGen.world_size() * size


func _aim_angle() -> float:
	if player == null or player.motion == null:
		return 0.0
	return player.motion.aim_angle


func _grown(points: PackedVector2Array, center: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + (point - center).normalized() * by)
	return out
