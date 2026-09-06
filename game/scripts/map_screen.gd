extends Control

## M 으로 여는 전체 맵 (docs/DESIGN.md 「맵 (M)」).
##
## **씬 전환이 아니라 월드 위에 겹쳐서 뜬다** — 씬을 바꾸면 월드가 통째로 내려가서
## "월드는 멈추지 않는다"가 애초에 성립하지 않는다(설정 화면과 같은 이유,
## docs/DESIGN.md 「조작」 Esc 항목).
##
## **이 화면은 자기 M/Esc 를 처리하지 않는다.** 닫는 것은 띄운 쪽(`world.gd`)이다 —
## 양쪽이 다 처리하면 어느 쪽이 먼저 받느냐에 동작이 달리고, 키 한 번에 두 창이 닫힌다.
##
## 그림은 `map_canvas.gd` 가 그린다. 여기서는 띄우고 글자를 갱신하는 일만 한다.

const ExploredMap := preload("res://scripts/explored_map.gd")

var _explored: RefCounted = null
var _player: Node2D = null
var _shown_version := -1
var _shown_tile := Vector2i(-2147483648, 0)


## 월드가 띄우면서 한 번 부른다.
func setup(world: RefCounted, explored: RefCounted, player: Node2D) -> void:
	_explored = explored
	_player = player
	(%Canvas as Control).setup(world, explored, player)
	_refresh()


func _process(_delta: float) -> void:
	# 지도를 보고 있는 동안에도 세계는 돈다 — 기록이나 내 칸이 달라지면 글자도 따라간다.
	if _explored == null:
		return
	if _explored.version != _shown_version or _tile() != _shown_tile:
		_refresh()


func _refresh() -> void:
	if _explored == null:
		return
	_shown_version = _explored.version
	_shown_tile = _tile()
	var total := float(ExploredMap.TILES * ExploredMap.TILES)
	var ratio := float(_explored.explored_count()) / total * 100.0
	(%InfoLabel as Label).text = "내 위치 (%d, %d)   ·   탐험한 곳 %.1f%%" % [
		_shown_tile.x, _shown_tile.y, ratio,
	]


func _tile() -> Vector2i:
	return Vector2i.ZERO if _player == null else _player.tile()
