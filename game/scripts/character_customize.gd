extends Control

## 캐릭터 커스터마이징 화면 (docs/DESIGN.md "캐릭터 커스터마이징 항목").
##
## 이름 입력 + 피부색/머리색/옷색(고정 팔레트) + 머리모양 3~4종을 고르고 확정하면
## 고른 슬롯에 저장되고 월드로 들어간다. 실제 캐릭터 그림은 아직 없어서 미리보기는
## 색 사각형이다 (scripts/appearance_preview.gd).

const SlotStore := preload("res://scripts/slot_store.gd")
const Appearance := preload("res://scripts/character_appearance.gd")
const AppearancePreview := preload("res://scripts/appearance_preview.gd")

const SLOTS_SCENE := "res://scenes/character_slots.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"

var _appearance := Appearance.default_appearance()


func _ready() -> void:
	for field in Appearance.FIELDS:
		var row := _row(field)
		(row.get_node("Name") as Label).text = Appearance.FIELD_LABELS[field]
		(row.get_node("Prev") as Button).pressed.connect(_on_step.bind(field, -1))
		(row.get_node("Next") as Button).pressed.connect(_on_step.bind(field, 1))
		# 머리모양은 색이 아니라 모양이라 색 견본이 없다.
		(row.get_node("Swatch") as ColorRect).visible = field != "hairstyle"

	var name_edit := %NameEdit as LineEdit
	name_edit.max_length = Appearance.MAX_NAME_LENGTH
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(_on_name_submitted)

	var index := SlotStore.selected_slot
	if index >= 0:
		(%SlotLabel as Label).text = "슬롯 %d 에 새 캐릭터를 만든다" % (index + 1)
		name_edit.grab_focus()
	else:
		# 슬롯 화면을 거치지 않고 들어온 경우 — 저장할 곳이 없으니 만들 수 없다.
		(%SlotLabel as Label).text = "고른 슬롯이 없다 — 슬롯 화면에서 다시 고르세요"
		name_edit.editable = false
		(%BackButton as Button).grab_focus()
	_refresh()


func _row(field: String) -> HBoxContainer:
	return %Rows.get_node(field) as HBoxContainer


func _refresh() -> void:
	for field in Appearance.FIELDS:
		var id := String(_appearance[field])
		var row := _row(field)
		(row.get_node("Value") as Label).text = Appearance.label_of(field, id)
		if field != "hairstyle":
			(row.get_node("Swatch") as ColorRect).color = Appearance.color_of(field, id)
	(%Preview as AppearancePreview).appearance = _appearance

	var can_confirm := SlotStore.selected_slot >= 0 and Appearance.is_valid_name((%NameEdit as LineEdit).text)
	(%ConfirmButton as Button).disabled = not can_confirm
	if SlotStore.selected_slot < 0:
		(%Hint as Label).text = "저장할 슬롯이 없습니다."
	elif can_confirm:
		(%Hint as Label).text = "확정하면 이 슬롯에 저장되고 월드로 들어갑니다."
	else:
		(%Hint as Label).text = "이름을 입력해야 확정할 수 있습니다. (최대 %d자)" % Appearance.MAX_NAME_LENGTH


func _on_step(field: String, delta: int) -> void:
	var index := Appearance.index_of(field, String(_appearance[field]))
	_appearance[field] = Appearance.id_at(field, index + delta)
	_refresh()


func _on_name_changed(_text: String) -> void:
	_refresh()


## 이름 칸에서 Enter — 이름이 다 됐으면 바로 확정한다.
func _on_name_submitted(_text: String) -> void:
	if not (%ConfirmButton as Button).disabled:
		_on_confirm_pressed()


func _on_confirm_pressed() -> void:
	var index := SlotStore.selected_slot
	if index < 0:
		return
	var character_name := Appearance.sanitize_name((%NameEdit as LineEdit).text)
	if character_name.is_empty():
		(%NameEdit as LineEdit).grab_focus()
		return
	var slots := SlotStore.load_slots()
	slots[index] = SlotStore.make_character(character_name, _appearance)
	if not SlotStore.save_slots(slots):
		(%Hint as Label).text = "저장에 실패했습니다 — 다시 시도하세요."
		return
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_back_pressed() -> void:
	_back_to_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back_to_slots()


func _back_to_slots() -> void:
	get_tree().change_scene_to_file(SLOTS_SCENE)
