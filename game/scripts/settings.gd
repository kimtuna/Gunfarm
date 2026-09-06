extends Control

## 설정 화면 — 지금은 해상도 하나만 있다 (docs/DESIGN.md "카메라 / 해상도").
##
## 좌/우 버튼으로 해상도를 고르면 그 자리에서 창에 적용되고 user:// 에 저장된다.
## 해상도를 바꿔도 보이는 월드 범위는 변하지 않는다 — PvP 공정성 규칙이라
## 화면에도 그렇게 적어둔다.

const SettingsStore := preload("res://scripts/settings_store.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var _options: Array[Vector2i] = []
var _index := 0


func _ready() -> void:
	var current: Vector2i = SettingsStore.load_settings().get("resolution", SettingsStore.BASE_SIZE)
	_options = SettingsStore.available_resolutions(current)
	_index = maxi(_options.find(current), 0)
	_refresh()
	(%NextButton as Button).grab_focus()


func _refresh() -> void:
	var size := _options[_index]
	(%ResolutionValue as Label).text = "%d × %d" % [size.x, size.y]
	# 고를 게 하나뿐이면(작은 화면) 화살표는 눌러도 의미가 없다.
	var many := _options.size() > 1
	(%PrevButton as Button).disabled = not many
	(%NextButton as Button).disabled = not many
	(%RangeNote as Label).text = "보이는 월드 범위: 항상 %d × %d (해상도와 무관)" % [
		SettingsStore.BASE_SIZE.x, SettingsStore.BASE_SIZE.y
	]


func _on_prev_pressed() -> void:
	_step(-1)


func _on_next_pressed() -> void:
	_step(1)


func _step(delta: int) -> void:
	if _options.size() <= 1:
		return
	_index = wrapi(_index + delta, 0, _options.size())
	var size := _options[_index]
	SettingsStore.apply_resolution(size)
	SettingsStore.save_settings({"resolution": size})
	_refresh()


func _on_back_pressed() -> void:
	_return_to_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_return_to_main_menu()


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
