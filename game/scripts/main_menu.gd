extends Control

## 메인 메뉴 — 프로젝트 진입 씬 (docs/DESIGN.md "클라이언트 화면 흐름").
## 플레이 → 캐릭터 슬롯 화면(INBOX #2가 채운다)
## 설정   → 설정 화면(INBOX #3이 채운다)
## 나가기 → 애플리케이션 종료

const CHARACTER_SLOTS_SCENE := "res://scenes/character_slots.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"


func _ready() -> void:
	# 키보드/패드만으로도 바로 조작할 수 있게 첫 버튼에 포커스를 준다.
	(%PlayButton as Button).grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SLOTS_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
