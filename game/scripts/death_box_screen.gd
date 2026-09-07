extends Control

## 데스드롭 상자를 연 창 (docs/DESIGN.md 「데스드롭 상자」).
##
## **씬 전환이 아니라 월드 위에 겹쳐서 뜬다** — 인벤토리/지도/설정과 같은 자리, 같은
## 이유다(씬을 바꾸면 월드가 통째로 내려가서 "월드는 멈추지 않는다"가 성립하지 않는다).
##
## **이 화면은 자기 Esc 를 처리하지 않는다.** 닫는 것은 띄운 쪽(`world.gd`)이다 —
## 「조작」 Esc 항목의 "가장 안쪽 창부터" 규칙이 한 곳에만 있어야 한다.
## **마우스는 반대로 여기서 처리하고 반드시 소비한다** — 안 그러면 칸을 누른 좌클릭이
## 그대로 월드로 새어 나가 손에 든 도구가 발사된다(인벤토리 창과 같은 규칙).
##
## **꺼내는 규칙은 하나도 여기 없다** — 전부 `death_boxes.gd` 의 `take()` /
## `take_all()` 이고, 그 함수들이 `inventory.take_in()` 을 지나가므로 못 들어간 몫은
## 상자에 그대로 남는다 (docs/DESIGN.md 「인벤토리 안전」).
##
## **넣는 길은 없다 — 꺼내기만 되는 상자다.** 30분 뒤 내용물과 함께 사라지는 상자에
## 물건을 넣게 두면 「인벤토리 안전」과 정면으로 부딪힌다(근거는 DESIGN.md).

const DeathBoxes := preload("res://scripts/death_boxes.gd")
const ItemTypes := preload("res://scripts/item_types.gd")

var boxes: RefCounted = null
var inventory: RefCounted = null
var box: Dictionary = {}

var _shown_version := -1
var _shown_seconds := -1


func setup(new_boxes: RefCounted, entry: Dictionary, new_inventory: RefCounted) -> void:
	boxes = new_boxes
	inventory = new_inventory
	box = entry
	(%Panel as Control).box = entry
	(%Panel as Control).custom_minimum_size = (%Panel as Control).panel_size()
	(%Panel as Control).queue_redraw()
	_refresh()


func _process(_delta: float) -> void:
	if boxes != null and boxes.version != _shown_version:
		(%Panel as Control).queue_redraw()
		_shown_version = boxes.version
	_refresh_time()


func _refresh() -> void:
	if boxes != null:
		_shown_version = boxes.version
	_refresh_time()


## **남은 시간은 열려 있는 동안 멈춘다** (docs/DESIGN.md 「데스드롭 상자」 —
## *"정해진 시간은 「찾아올 시간」이지 「꺼낼 시간」이 아니다"*). 그래서 이 줄은
## 창이 떠 있는 내내 같은 값에 멈춰 있어야 한다 — 그게 규칙이 지켜지고 있다는 표시다.
func _refresh_time() -> void:
	if box.is_empty():
		return
	var remaining: float = box[DeathBoxes.KEY_REMAINING]
	if remaining < 0.0:
		(%TimeLabel as Label).text = "남은 시간: 사라지지 않음 (월드 설정)"
		return
	var seconds := maxi(0, ceili(remaining))
	if seconds == _shown_seconds:
		return
	_shown_seconds = seconds
	@warning_ignore("integer_division")
	(%TimeLabel as Label).text = "남은 시간 %d:%02d — 창이 열려 있는 동안 멈춰 있습니다" % [
		seconds / 60, seconds % 60,
	]


# --- 마우스 = 칸 하나 꺼내기 ----------------------------------------------------

func _input(event: InputEvent) -> void:
	if boxes == null or box.is_empty():
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
	if not button.pressed:
		return
	var index: int = (%Panel as Control).slot_at(get_viewport().get_mouse_position())
	if index >= 0:
		boxes.take(box, index, inventory)
		_update_hover()


func _on_take_all_pressed() -> void:
	if boxes == null or box.is_empty():
		return
	boxes.take_all(box, inventory)
	_update_hover()


func _update_hover() -> void:
	var panel := %Panel as Control
	var index: int = panel.slot_at(get_viewport().get_mouse_position())
	if index != panel.hovered:
		panel.hovered = index
		panel.queue_redraw()
	var stack: RefCounted = panel.stack_at(index)
	if stack == null:
		(%DescLabel as Label).text = " "
		return
	(%DescLabel as Label).text = "%s   ·   %s   ·   %d개" % [
		ItemTypes.name_of(stack.id), ItemTypes.category_of(stack.id), stack.count,
	]
