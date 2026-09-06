extends Control

## 아직 내용이 없는 화면(캐릭터 슬롯=INBOX #2, 설정=INBOX #3)의 자리만 잡아두는 스크립트.
## 제목만 보여주고 메인 메뉴로 돌아가는 길만 열어둔다 — 실제 내용은 각 항목에서 채운다.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	(%BackButton as Button).grab_focus()


func _on_back_pressed() -> void:
	_return_to_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_return_to_main_menu()


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
