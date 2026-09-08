extends Node2D

## 월드에 놓인 나무·바위·덤불을 그린다 (docs/DESIGN.md 「월드 오브젝트」, INBOX #63).
##
## **이 노드는 `world_gen.gd` 가 들고 있는 배치를 비추기만 한다** — 무엇이 어디에
## 있는지는 전부 그쪽이 시드에서 정한다(「시뮬레이션 구조」/「서버 권위」).
##
## 지도는 65,536칸이라 전부 노드로 만들 수 없다. **지형(`terrain_view.gd`)이 화면에
## 들어오는 칸만 그리는 것과 같은 방식**으로, 보이는 범위가 달라졌을 때만 노드를
## 다시 맞춘다. 다만 지형과 달리 오브젝트는 **노드가 하나씩 있어야 한다** —
## 플레이어와 앞뒤가 갈려야 하기 때문이다(`world_object_node.gd`).

const WorldGen := preload("res://scripts/world_gen.gd")
const WorldObjects := preload("res://scripts/world_objects.gd")
const WorldObjectNode := preload("res://scripts/world_object_node.gd")

## 보이는 사각형을 이만큼(타일) 넓혀서 훑는다. **나무가 세 칸 높이라** 밑동이
## 화면 아래로 벗어난 나무도 잎은 아직 보인다 — 딱 맞게 자르면 화면 가장자리에서
## 나무가 통째로 깜빡인다.
const MARGIN_TILES := 4

var world: RefCounted = null

## 마지막으로 훑은 **타일 범위**. 픽셀 사각형이 아니라 타일 범위로 견주는 것이
## 중요하다 — 카메라는 매 프레임 조금씩 움직이지만 보이는 칸은 48px 마다 한 번
## 바뀐다. 픽셀로 견주면 걷는 내내 매 프레임 1,200칸을 다시 훑게 되고, 그 무게가
## 그대로 프레임 시간이 되어 **마우스로 방향을 정하는 자체 QA 가 흔들린다**
## (2026-09-08, INBOX #63 에 실제로 `qa_player_world` 가 한 번 거짓 실패했다).
var _last_range := Rect2i(0, 0, -1, -1)
## 지금 노드가 있는 칸 → 노드. 매번 지웠다 다시 만들지 않는다(그러면 카메라가
## 움직일 때마다 숲 전체가 깜빡인다).
var _nodes := {}


func set_world(new_world: RefCounted) -> void:
	world = new_world
	for node in _nodes.values():
		(node as Node).queue_free()
	_nodes.clear()
	_last_range = Rect2i(0, 0, -1, -1)
	_sync()


func _process(_delta: float) -> void:
	_sync()


## 카메라가 실제로 덮는 월드 사각형. 창 크기로 계산하면 틀린다 (docs/GOTCHAS.md).
func _visible_world_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	return viewport.get_canvas_transform().affine_inverse() \
			* Rect2(Vector2.ZERO, viewport.get_visible_rect().size)


func _sync() -> void:
	if world == null:
		return
	var view := _visible_world_rect().grow(WorldGen.TILE_SIZE * MARGIN_TILES)
	if view.size == Vector2.ZERO:
		return
	var from := WorldGen.world_to_tile(view.position)
	var to := WorldGen.world_to_tile(view.end)
	var range := Rect2i(from, to - from)
	if range == _last_range:
		return
	_last_range = range

	var want := {}
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var kind: int = world.object_at(x, y)
			if kind != WorldObjects.NONE:
				want[Vector2i(x, y)] = kind

	for tile: Vector2i in _nodes.keys():
		if not want.has(tile):
			(_nodes[tile] as Node).queue_free()
			_nodes.erase(tile)
	for tile: Vector2i in want:
		if _nodes.has(tile):
			continue
		var node := WorldObjectNode.new()
		add_child(node)
		_nodes[tile] = node
		node.show_object(want[tile], world.object_variant_at(tile.x, tile.y),
				WorldGen.tile_center(tile))


## 지금 화면에 노드가 몇 개 떠 있는가 — 자체 QA 가 본다.
func shown_count() -> int:
	return _nodes.size()
