extends Node2D

## 생성된 땅/바다 타일을 그린다. 아직 지형 스프라이트가 없어서([BUILD] 항목이라 그림을
## 만들지 않는다) 타일 색 사각형으로 그린다 — 그림이 생기면 이 스크립트만 갈아끼운다.
##
## 지도는 256×256 = 65,536칸이라 전부 그리면 낭비다. **화면에 들어오는 칸만** 그리고,
## 가로로 이어지는 같은 지형은 사각형 하나로 합쳐서 그린다.

const WorldGen := preload("res://scripts/world_gen.gd")

const COLOR_SEA := Color(0.121569, 0.223529, 0.294118)
const COLOR_LAND := Color(0.286275, 0.415686, 0.243137)
## 타일 크기가 눈에 보이게 얇게 얹는 격자선. 건축이 이 격자 위에 올라간다.
const COLOR_GRID := Color(0.0, 0.0, 0.0, 0.09)

var world: RefCounted = null

var _last_view := Rect2()


func set_world(new_world: RefCounted) -> void:
	world = new_world
	queue_redraw()


func _process(_delta: float) -> void:
	# 카메라가 움직이면 보이는 칸이 달라진다 — 달라졌을 때만 다시 그린다.
	var view := _visible_world_rect()
	if not view.is_equal_approx(_last_view):
		_last_view = view
		queue_redraw()


## 카메라가 실제로 덮는 월드 사각형. 창 크기로 계산하면 틀린다 (docs/GOTCHAS.md).
func _visible_world_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	return viewport.get_canvas_transform().affine_inverse() \
			* Rect2(Vector2.ZERO, viewport.get_visible_rect().size)


func _draw() -> void:
	if world == null:
		return
	var view := _visible_world_rect().grow(WorldGen.TILE_SIZE)
	var from := WorldGen.world_to_tile(view.position)
	var to := WorldGen.world_to_tile(view.end)
	var x0 := maxi(from.x, 0)
	var y0 := maxi(from.y, 0)
	var x1 := mini(to.x, WorldGen.MAP_TILES - 1)
	var y1 := mini(to.y, WorldGen.MAP_TILES - 1)

	# 지도 밖(창이 지도보다 클 때)도 바다로 메워서 빈 배경이 비치지 않게 한다.
	draw_rect(view, COLOR_SEA)

	var size := float(WorldGen.TILE_SIZE)
	for y in range(y0, y1 + 1):
		var x := x0
		while x <= x1:
			var kind: int = world.at(x, y)
			var run := x + 1
			while run <= x1 and world.at(run, y) == kind:
				run += 1
			if kind == WorldGen.LAND:
				draw_rect(Rect2(x * size, y * size, (run - x) * size, size), COLOR_LAND)
			x = run

	_draw_grid(x0, y0, x1, y1)


func _draw_grid(x0: int, y0: int, x1: int, y1: int) -> void:
	var size := float(WorldGen.TILE_SIZE)
	var top := y0 * size
	var bottom := (y1 + 1) * size
	var left := x0 * size
	var right := (x1 + 1) * size
	for x in range(x0, x1 + 2):
		draw_line(Vector2(x * size, top), Vector2(x * size, bottom), COLOR_GRID, 1.0)
	for y in range(y0, y1 + 2):
		draw_line(Vector2(left, y * size), Vector2(right, y * size), COLOR_GRID, 1.0)
