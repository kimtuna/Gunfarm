extends Control

## E 로 여는 인벤토리 창 (docs/DESIGN.md 「인벤토리 / 장비」).
##
## **씬 전환이 아니라 월드 위에 겹쳐서 뜬다** — 씬을 바꾸면 월드가 통째로 내려가서
## "월드는 멈추지 않는다"가 성립하지 않는다(지도/설정과 같은 자리, 같은 이유).
##
## **이 화면은 자기 E/Esc 를 처리하지 않는다.** 닫는 것은 띄운 쪽(`world.gd`)이다 —
## 「조작」 Esc 항목의 "가장 안쪽 창부터" 규칙이 한 곳에만 있어야 하기 때문이다.
## 숫자키 1~9 도 마찬가지다(창이 닫혀 있을 때도 먹어야 하므로 `world.gd` 가 받는다).
## **마우스는 반대로 여기서 처리하고 반드시 소비한다** — 안 그러면 아이템을 끌던
## 좌클릭이 그대로 월드로 새어 나가 손에 든 도구가 발사된다.
##
## 옮기는 규칙 자체는 하나도 여기 없다 — 전부 `inventory.gd`(순수 클래스)의
## `move()` / `take_out()` 이다. 여기가 하는 일은 "어느 칸을 집어서 어디에 놓았는가"를
## 좌표에서 알아내는 것뿐이다.

const Inventory := preload("res://scripts/inventory.gd")
const ItemTypes := preload("res://scripts/item_types.gd")

## 창 **바깥**에 놓아서 버렸다 — 어느 칸이었는지 알려준다. 실제로 바닥에 놓는 일은
## 월드 좌표를 아는 `world.gd` 가 한다 (docs/DESIGN.md 「인벤토리 / 장비」의 버리기).
signal drop_outside(area: String, index: int)

var inventory: RefCounted = null

## 지금 끌고 있는 칸({"area","index"}). **끌기 시작해도 아이템은 인벤토리에 그대로 있다** —
## 손에 들고 있다가 창이 닫히면 사라지는 식으로 만들면 「인벤토리 안전」이 깨진다.
var _drag: Dictionary = {}

## 마지막으로 화면에 반영한 인벤토리 버전 — 달라졌을 때만 글자를 다시 만든다.
var _shown_version := -1


func setup(new_inventory: RefCounted) -> void:
	inventory = new_inventory
	(%Panel as Control).setup(new_inventory)
	_refresh()


func _ready() -> void:
	# 끌고 있는 그림은 창 위에 떠야 한다 — 창(Box)보다 뒤에 있는 이 노드가 그린다.
	(%DragLayer as Control).draw.connect(_draw_drag)


func _process(_delta: float) -> void:
	if inventory != null and inventory.version != _shown_version:
		_refresh()


func _refresh() -> void:
	if inventory == null:
		return
	_shown_version = inventory.version
	var held: RefCounted = inventory.held()
	var held_text := "빈손" if held == null else ItemTypes.name_of(held.id)
	(%HeldLabel as Label).text = "손에 든 것 (%d번 칸): %s" % [inventory.selected_hotbar + 1, held_text]


# --- 마우스 = 드래그 (docs/DESIGN.md 「인벤토리 / 장비」) ------------------------

func _input(event: InputEvent) -> void:
	if inventory == null:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_update_hover()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	# 창이 떠 있는 동안의 좌클릭은 전부 이 창의 것이다 — 뒤(월드)로 흘려보내지 않는다.
	get_viewport().set_input_as_handled()
	if button.pressed:
		_begin_drag(_mouse())
	else:
		_end_drag(_mouse())


func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()


func _begin_drag(at: Vector2) -> void:
	var slot: Dictionary = (%Panel as Control).slot_at(at)
	if slot.is_empty() or inventory.at(slot["area"], slot["index"]) == null:
		return
	_drag = slot
	(%Panel as Control).drag_from = slot
	(%Panel as Control).queue_redraw()
	(%DragLayer as Control).queue_redraw()


## 놓은 자리에 따라 셋 중 하나다: 다른 칸이면 옮기기(합치기/자리바꾸기),
## **창 바깥이면 버리기**, 창 안의 빈 자리면 아무 일도 없음(원래 칸에 그대로).
func _end_drag(at: Vector2) -> void:
	if _drag.is_empty():
		return
	var from := _drag
	_drag = {}
	(%Panel as Control).drag_from = {}
	(%Panel as Control).queue_redraw()
	(%DragLayer as Control).queue_redraw()
	var target: Dictionary = (%Panel as Control).slot_at(at)
	if not target.is_empty():
		inventory.move(from["area"], from["index"], target["area"], target["index"])
		_refresh()
		return
	if not _window_rect().has_point(at):
		drop_outside.emit(String(from["area"]), int(from["index"]))
		_refresh()


func _window_rect() -> Rect2:
	var box := %Box as Control
	return Rect2(box.global_position, box.size)


func _update_hover() -> void:
	var panel := %Panel as Control
	var slot: Dictionary = panel.slot_at(_mouse())
	if slot == panel.hovered:
		if not _drag.is_empty():
			(%DragLayer as Control).queue_redraw()
		return
	panel.hovered = slot
	panel.queue_redraw()
	if not _drag.is_empty():
		(%DragLayer as Control).queue_redraw()
	var stack: RefCounted = null if slot.is_empty() else inventory.at(slot["area"], slot["index"])
	if stack == null:
		(%DescLabel as Label).text = " "
		return
	(%DescLabel as Label).text = "%s   ·   %s   ·   %d개" % [
		ItemTypes.name_of(stack.id), ItemTypes.category_of(stack.id), stack.count,
	]


## 끌고 있는 아이템은 마우스를 따라다닌다. 그림은 칸 안과 **같은 함수**로 그린다
## (`inventory_panel.gd` 의 `draw_item`) — 집는 순간 모양이 달라지면 안 된다.
func _draw_drag() -> void:
	if _drag.is_empty() or inventory == null:
		return
	var stack: RefCounted = inventory.at(_drag["area"], _drag["index"])
	if stack == null:
		return
	(%Panel as Control).draw_floating(%DragLayer as Control, stack, _mouse())
