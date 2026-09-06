extends SceneTree

## INBOX #2 자체 QA — 캐릭터 슬롯 화면.
##
## 실행:
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_character_slots.gd
##   (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md 참고)
##
## 검증: 빈 슬롯 3개 → 빈 슬롯 고르기 → 캐릭터 생성 → 슬롯에 표시 → 저장 파일 확인 →
##       (재시작 흉내) 다시 불러도 남아있음 → 캐릭터 슬롯 고르면 월드 입장 →
##       삭제 확인창 취소 → 삭제 확인창 삭제 → 다시 빈 슬롯 + 저장 파일도 비어있음.

const SlotStore := preload("res://scripts/slot_store.gd")

const SHOTS := "user://qa_shots"
const SLOTS_SCENE := "res://scenes/character_slots.tscn"

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _fails: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# 이전 실행의 저장 상태가 남으면 거짓 실패가 난다 (docs/GOTCHAS.md).
	DirAccess.remove_absolute(SlotStore.SAVE_PATH)
	SlotStore.selected_slot = -1
	# --script 모드는 main_scene 을 자동으로 안 띄운다 → 진입 씬을 직접 올린다.
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene", ""))
	_steps = [
		func(): _press("Layout/PlayButton"),
		_check_all_empty,
		func(): _press_slot(1),
		_check_customize,
		func(): _press("Layout/CreateButton"),
		_check_slot_filled,
		func(): change_scene_to_file(SLOTS_SCENE),
		_check_reloaded,
		func(): _press_slot(1),
		_check_world,
		func(): _press("Layout/BackButton"),
		_check_back_from_world,
		# Esc 로도 메인 메뉴로 나갈 수 있어야 한다 (DESIGN.md "클라이언트 화면 흐름").
		_press_escape,
		_check_escaped_to_main_menu,
		func(): _press("Layout/PlayButton"),
		_check_still_there,
		# 삭제 확인창은 Esc 로도, 그만두기 버튼으로도 닫혀야 하고 둘 다 캐릭터를 남긴다.
		func(): _press_delete(1),
		_check_confirm_open,
		_press_escape,
		_check_delete_canceled,
		func(): _press_delete(1),
		func(): _press("DeleteConfirm/Box/BoxLayout/Buttons/DeleteNoButton"),
		_check_delete_canceled_by_button,
		func(): _press_delete(1),
		func(): _press("DeleteConfirm/Box/BoxLayout/Buttons/DeleteYesButton"),
		_check_deleted,
		func(): _press("Layout/BackButton"),
		_check_back_to_main_menu,
	]


# --- 각 단계의 확인 ---------------------------------------------------------

## 처음엔 슬롯 3개가 전부 비어 있고 삭제 버튼도 눌리지 않아야 한다.
func _check_all_empty() -> void:
	_expect_screen("캐릭터 선택", "10_slots_empty")
	for i in 3:
		_expect_slot_text(i, "비어 있음")
		_expect_delete_disabled(i, true)


## 빈 슬롯을 고르면 커스터마이징 화면으로 가고, 고른 슬롯 번호가 같이 넘어간다.
func _check_customize() -> void:
	_expect_screen("캐릭터 만들기", "11_customize_stub")
	_expect_text_on_screen("슬롯 2")
	_expect(SlotStore.selected_slot == 1, "고른 슬롯이 안 넘어갔다: %d" % SlotStore.selected_slot)


## 캐릭터를 만들면 슬롯 화면으로 돌아오고, 화면과 저장 파일 양쪽에 이름이 남는다.
func _check_slot_filled() -> void:
	_expect_screen("캐릭터 선택", "12_slot_filled")
	_expect_slot_text(1, "모험가 2")
	_expect_slot_text(0, "비어 있음")
	_expect_delete_disabled(1, false)
	_expect_saved_name(1, "모험가 2")


## 재시작 흉내 — 씬을 새로 올려도 user:// 에서 다시 읽어온다.
func _check_reloaded() -> void:
	_expect_screen("캐릭터 선택", "13_reloaded")
	_expect_slot_text(1, "모험가 2")


## 캐릭터가 있는 슬롯을 고르면 월드 입장으로 가고, 그 캐릭터가 넘어간다.
func _check_world() -> void:
	_expect_screen("월드 입장", "14_world_stub")
	_expect_text_on_screen("모험가 2")


func _check_back_from_world() -> void:
	_expect_screen("캐릭터 선택", "15_back_from_world")


func _check_escaped_to_main_menu() -> void:
	_expect_screen("GUNFARM", "15b_escaped_to_main_menu")


## 메인 메뉴를 거쳐 다시 들어와도 캐릭터가 그대로다.
func _check_still_there() -> void:
	_expect_screen("캐릭터 선택", "15c_reentered")
	_expect_slot_text(1, "모험가 2")


func _check_confirm_open() -> void:
	_expect_screen("지울까요", "16_delete_confirm")
	_expect_text_on_screen("모험가 2")


## 확인창을 Esc 로 닫으면 캐릭터가 그대로 남아야 한다.
func _check_delete_canceled() -> void:
	_shoot("17_delete_canceled_by_esc")
	_expect_slot_text(1, "모험가 2")
	_expect_saved_name(1, "모험가 2")
	_expect(not _confirm_visible(), "Esc 를 눌렀는데 확인창이 안 닫혔다")


## "그만둔다" 버튼으로 닫아도 마찬가지다.
func _check_delete_canceled_by_button() -> void:
	_shoot("17b_delete_canceled_by_button")
	_expect_slot_text(1, "모험가 2")
	_expect_saved_name(1, "모험가 2")
	_expect(not _confirm_visible(), "취소했는데 확인창이 안 닫혔다")


## 확인하면 빈 슬롯으로 돌아가고 저장 파일에서도 사라진다.
func _check_deleted() -> void:
	_shoot("18_deleted")
	_expect_slot_text(1, "비어 있음")
	_expect_delete_disabled(1, true)
	_expect_saved_name(1, "")
	_expect(not _confirm_visible(), "삭제 후 확인창이 안 닫혔다")


func _check_back_to_main_menu() -> void:
	_expect_screen("GUNFARM", "19_back_to_main_menu")


func _process(_delta: float) -> bool:
	# 상태를 바꾼 직후 캡처하면 한 프레임 전 화면이 찍힌다 → 스텝마다 몇 프레임 쉰다.
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다.
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size():
		return _finish()
	var step: Callable = _steps[_step]
	_step += 1
	_wait = 3
	step.call()
	return false


# --- 조작 -------------------------------------------------------------------

func _press(node_path: String) -> void:
	var button := current_scene.get_node_or_null(node_path) as Button
	if button == null:
		_fails.append("버튼을 못 찾음: %s (현재 씬 %s)" % [node_path, current_scene.name])
		return
	button.emit_signal("pressed")


func _press_slot(index: int) -> void:
	_press("Layout/Slots/Slot%d/Choose" % index)


func _press_delete(index: int) -> void:
	_press("Layout/Slots/Slot%d/Delete" % index)


## Esc 를 실제 입력으로 흘려보낸다 — 화면 스크립트의 _unhandled_input 이 받아야 한다.
func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


func _slot_button(index: int) -> Button:
	return current_scene.get_node_or_null("Layout/Slots/Slot%d/Choose" % index) as Button


func _confirm_visible() -> bool:
	var confirm := current_scene.get_node_or_null("DeleteConfirm") as Control
	return confirm != null and confirm.visible


# --- 검증 -------------------------------------------------------------------

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_fails.append(message)


func _expect_slot_text(index: int, expect_text: String) -> void:
	var button := _slot_button(index)
	if button == null:
		_fails.append("슬롯 %d 버튼이 없다" % (index + 1))
		return
	_expect(button.text.findn(expect_text) != -1,
		"슬롯 %d 에 '%s' 가 아니라 '%s' 가 있다" % [index + 1, expect_text, button.text])


func _expect_delete_disabled(index: int, expected: bool) -> void:
	var button := current_scene.get_node_or_null("Layout/Slots/Slot%d/Delete" % index) as Button
	if button == null:
		_fails.append("슬롯 %d 삭제 버튼이 없다" % (index + 1))
		return
	_expect(button.disabled == expected,
		"슬롯 %d 삭제 버튼 disabled 가 %s 여야 하는데 %s" % [index + 1, expected, button.disabled])


## 화면이 아니라 저장 파일(user://)을 직접 다시 읽어서 확인한다.
## expect_name 이 빈 문자열이면 "그 슬롯은 비어 있어야 한다"는 뜻.
func _expect_saved_name(index: int, expect_name: String) -> void:
	var slots := SlotStore.load_slots()
	var actual: String = slots[index].get("name", "")
	_expect(actual == expect_name,
		"저장 파일의 슬롯 %d 이름이 '%s' 여야 하는데 '%s'" % [index + 1, expect_name, actual])


func _expect_text_on_screen(expect_text: String) -> void:
	_expect(_find_text(expect_text), "화면에 '%s' 가 없음 (현재 씬 %s)" % [expect_text, current_scene.name])


## 화면 안에 기대한 문구가 있는지(= 그 화면으로 넘어갔는지) 보고 스크린샷을 남긴다.
func _expect_screen(expect_text: String, shot_name: String) -> void:
	_expect_text_on_screen(expect_text)
	_shoot(shot_name)


func _find_text(expect_text: String) -> bool:
	for label in current_scene.find_children("*", "Label", true, false):
		if (label as Label).text.findn(expect_text) != -1:
			return true
	for button in current_scene.find_children("*", "Button", true, false):
		if (button as Button).text.findn(expect_text) != -1:
			return true
	return false


func _shoot(shot_name: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		_fails.append("캡처 실패(%s): 뷰포트 텍스처 없음 — --headless 로 돌린 건 아닌지 확인" % shot_name)
		return
	var image := texture.get_image()
	var path := "%s/%s.png" % [SHOTS, shot_name]
	image.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _finish() -> bool:
	if _fails.is_empty():
		print("[qa] PASS — 캐릭터 슬롯 화면 정상")
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)
		return true
	quit(0)
	return true
