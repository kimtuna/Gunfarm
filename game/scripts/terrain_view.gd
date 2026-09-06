extends Node2D

## 생성된 땅/바다 타일을 **지형 스프라이트로** 그린다 (INBOX #12).
##
## 지도는 256×256 = 65,536칸이라 전부 그리면 낭비다 — **화면에 들어오는 칸만** 그린다.
## 칸 하나당 그리기 한 번이면 되고(밑그림과 해안이 한 장에 같이 구워져 있다,
## `terrain_tiles.gd`), 지도 밖도 그냥 같이 돈다(`WorldGen.at()` 이 바다로 답한다).
##
## 예전에는 색 사각형 + 격자선이었다. **격자선은 뺐다** — 인접한 같은 지형이 이어져
## 보여야 하는데 48px 마다 선이 그이면 그게 안 된다. 건축이 올라갈 때 필요한 격자는
## 배치 미리보기로 그때 그리는 게 맞다.

const WorldGen := preload("res://scripts/world_gen.gd")
const TerrainTiles := preload("res://scripts/terrain_tiles.gd")

var world: RefCounted = null

var _sheet: Texture2D = null
var _last_view := Rect2()


func _ready() -> void:
	_sheet = load(TerrainTiles.SHEET_PATH)
	if _sheet == null:
		push_error("지형 시트를 못 읽었다: %s — `--import` 를 안 돌렸을 수 있다"
				% TerrainTiles.SHEET_PATH)


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
	var size := float(WorldGen.TILE_SIZE)

	if _sheet == null:
		# 시트가 없을 때도 화면이 통째로 비지는 않게 — 색으로라도 지형을 보여준다.
		draw_rect(view, TerrainTiles.color_sea())
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				if world.is_land(x, y):
					draw_rect(Rect2(x * size, y * size, size, size), TerrainTiles.color_grass())
		return

	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			draw_texture_rect_region(_sheet, Rect2(x * size, y * size, size, size),
					TerrainTiles.region_at(world, x, y))
