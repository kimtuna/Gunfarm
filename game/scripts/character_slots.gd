extends Control

## 캐릭터 슬롯 화면 (docs/DESIGN.md "클라이언트 화면 흐름").
## 빈 슬롯 → 캐릭터 커스터마이징(INBOX #4), 캐릭터가 있는 슬롯 → 월드 입장(INBOX #5).
## 슬롯 내용은 user:// 에 저장되고, 슬롯마다 삭제 버튼이 있다.

const SlotStore := preload("res://scripts/slot_store.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const CUSTOMIZE_SCENE := "res://scenes/character_customize.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"

var _slots: Array[Dictionary] = []
var _delete_target := -1


func _ready() -> void:
	for i in SlotStore.SLOT_COUNT:
		_choose_button(i).pressed.connect(_on_slot_pressed.bind(i))
		_delete_button(i).pressed.connect(_on_delete_pressed.bind(i))
	_slots = SlotStore.load_slots()
	_refresh()
	# 커스터마이징/월드에서 돌아왔으면 방금 만졌던 슬롯에 커서를 돌려준다.
	_choose_button(clampi(SlotStore.selected_slot, 0, SlotStore.SLOT_COUNT - 1)).grab_focus()


func _choose_button(index: int) -> Button:
	return (%Slots.get_child(index).get_node("Choose") as Button)


func _delete_button(index: int) -> Button:
	return (%Slots.get_child(index).get_node("Delete") as Button)


func _refresh() -> void:
	for i in SlotStore.SLOT_COUNT:
		var slot := _slots[i]
		if SlotStore.is_empty(slot):
			_choose_button(i).text = "슬롯 %d   ·   비어 있음" % (i + 1)
			_delete_button(i).disabled = true
		else:
			_choose_button(i).text = "슬롯 %d   ·   %s" % [i + 1, slot.get("name", "이름 없음")]
			_delete_button(i).disabled = false


func _on_slot_pressed(index: int) -> void:
	if _confirm_visible():
		return  # 삭제 확인 중에는 뒤쪽 버튼이 먹으면 안 된다.
	SlotStore.selected_slot = index
	if SlotStore.is_empty(_slots[index]):
		get_tree().change_scene_to_file(CUSTOMIZE_SCENE)
	else:
		get_tree().change_scene_to_file(WORLD_SCENE)


# --- 삭제 (되돌릴 수 없으므로 한 번 확인한다) ---------------------------------

func _confirm_visible() -> bool:
	return (%DeleteConfirm as Control).visible


func _on_delete_pressed(index: int) -> void:
	if _confirm_visible() or SlotStore.is_empty(_slots[index]):
		return
	_delete_target = index
	(%DeleteMessage as Label).text = "슬롯 %d 의 캐릭터 '%s'\n정말 지울까요? 되돌릴 수 없습니다." % [
		index + 1, _slots[index].get("name", "이름 없음")
	]
	(%DeleteConfirm as Control).visible = true
	(%DeleteNoButton as Button).grab_focus()


func _on_delete_confirmed() -> void:
	if _delete_target >= 0:
		_slots[_delete_target] = {}
		SlotStore.save_slots(_slots)
	_close_confirm()


func _on_delete_canceled() -> void:
	_close_confirm()


func _close_confirm() -> void:
	var focus_index: int = maxi(_delete_target, 0)
	_delete_target = -1
	(%DeleteConfirm as Control).visible = false
	_refresh()
	_choose_button(focus_index).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm_visible():
			_close_confirm()
		else:
			get_tree().change_scene_to_file(MAIN_MENU_SCENE)
