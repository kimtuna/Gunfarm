extends Control

## 월드 입장(INBOX #5)의 자리.
## #5 가 시드 기반 절차적 월드 생성을 채운다. 지금은 어느 슬롯/캐릭터로 들어왔는지만
## 보여줘서 "캐릭터가 있는 슬롯 → 월드 입장" 경로가 제대로 이어졌는지 확인할 수 있게 한다.

const SlotStore := preload("res://scripts/slot_store.gd")

const SLOTS_SCENE := "res://scenes/character_slots.tscn"


func _ready() -> void:
	var index := SlotStore.selected_slot
	var who := "고른 캐릭터 없음"
	if index >= 0:
		var slots := SlotStore.load_slots()
		who = "슬롯 %d   ·   %s" % [index + 1, slots[index].get("name", "이름 없음")]
	(%WhoLabel as Label).text = who
	(%BackButton as Button).grab_focus()


func _on_back_pressed() -> void:
	_back_to_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back_to_slots()


func _back_to_slots() -> void:
	get_tree().change_scene_to_file(SLOTS_SCENE)
