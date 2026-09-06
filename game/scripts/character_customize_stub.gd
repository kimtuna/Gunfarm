extends Control

## 캐릭터 커스터마이징 화면(INBOX #4)의 자리.
##
## #4 가 이름 입력 + 피부/머리/옷색 + 머리모양을 채운다. 그 전에도 슬롯 저장/불러오기/
## 삭제가 실제로 도는지 확인할 수 있어야 해서, 지금은 "기본값 캐릭터를 골라둔 슬롯에
## 저장"하는 임시 버튼 하나만 둔다 — #4 는 이 스크립트를 통째로 갈아끼우면 된다.

const SlotStore := preload("res://scripts/slot_store.gd")

const SLOTS_SCENE := "res://scenes/character_slots.tscn"


func _ready() -> void:
	var index := SlotStore.selected_slot
	if index >= 0:
		(%SlotLabel as Label).text = "슬롯 %d 에 새 캐릭터를 만든다" % (index + 1)
	else:
		(%SlotLabel as Label).text = "고른 슬롯이 없다"
	(%CreateButton as Button).disabled = index < 0
	(%CreateButton as Button).grab_focus()


func _on_create_pressed() -> void:
	var index := SlotStore.selected_slot
	if index < 0:
		return
	var slots := SlotStore.load_slots()
	slots[index] = SlotStore.make_character("모험가 %d" % (index + 1))
	SlotStore.save_slots(slots)
	_back_to_slots()


func _on_back_pressed() -> void:
	_back_to_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back_to_slots()


func _back_to_slots() -> void:
	get_tree().change_scene_to_file(SLOTS_SCENE)
