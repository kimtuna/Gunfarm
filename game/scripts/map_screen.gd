extends Control

## M 으로 여는 전체 맵 (docs/DESIGN.md 「맵 (M)」).
##
## **씬 전환이 아니라 월드 위에 겹쳐서 뜬다** — 씬을 바꾸면 월드가 통째로 내려가서
## "월드는 멈추지 않는다"가 애초에 성립하지 않는다(설정 화면과 같은 이유,
## docs/DESIGN.md 「조작」 Esc 항목).
##
## **이 화면은 자기 M/Esc 를 처리하지 않는다.** 닫는 것은 띄운 쪽(`world.gd`)이다 —
## 양쪽이 다 처리하면 어느 쪽이 먼저 받느냐에 동작이 달리고, 키 한 번에 두 창이 닫힌다.
## **마우스 휠(줌)은 반대로 여기서 처리한다** — 닫는 키와 달리 지도 안에서만 뜻이 있고,
## 지도가 떠 있는 동안에만 이 노드가 트리에 있어서 "열려 있을 때만" 이 저절로 성립한다.
##
## 그림은 `map_canvas.gd` 가 그린다. 여기서는 띄우고 글자를 갱신하는 일만 한다.

const ExploredMap := preload("res://scripts/explored_map.gd")

var _explored: RefCounted = null
var _player: Node2D = null
var _shown_version := -1
var _shown_tile := Vector2i(-2147483648, 0)
var _shown_zoom := -1


## 월드가 띄우면서 한 번 부른다.
func setup(world: RefCounted, explored: RefCounted, player: Node2D) -> void:
	_explored = explored
	_player = player
	(%Canvas as Control).setup(world, explored, player)
	_refresh()


## 마우스 휠 = 줌 (docs/DESIGN.md 「맵 줌 (마우스 휠)」).
##
## **받은 휠은 반드시 소비한다** — 안 그러면 같은 휠이 뒤(나중에 붙을 핫바 스크롤 등)로도
## 흘러가서 지도를 보는 동안 손에 든 것까지 바뀐다. `_gui_input` 이 아니라 `_input` 인
## 이유는 마우스가 지도 창 밖(어두운 배경)에 있어도 휠이 먹어야 하기 때문이다.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null:
		return
	var steps := 0
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			steps = 1
		MOUSE_BUTTON_WHEEL_DOWN:
			steps = -1
		_:
			return
	# 눌림/뗌 둘 다 먹는다 — 한쪽만 먹으면 나머지 반이 뒤로 새어 나간다.
	get_viewport().set_input_as_handled()
	if button.pressed and (%Canvas as Control).zoom_by(steps):
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
	_shown_zoom = (%Canvas as Control).zoom_scale()
	var total := float(ExploredMap.TILES * ExploredMap.TILES)
	var ratio := float(_explored.explored_count()) / total * 100.0
	(%InfoLabel as Label).text = "내 위치 (%d, %d)   ·   탐험한 곳 %.1f%%" % [
		_shown_tile.x, _shown_tile.y, ratio,
	]
	(%Hint as Label).text = "M 또는 Esc — 닫기   ·   휠 — 확대/축소 (%d배)" % _shown_zoom


func _tile() -> Vector2i:
	return Vector2i.ZERO if _player == null else _player.tile()
