extends SceneTree

## INBOX #1 자체 QA — 메인 메뉴의 세 버튼이 실제로 동작하는지 확인한다.
##
## 실행:
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_main_menu.gd
##   (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md 참고)
##
## 검증 순서: 메인 메뉴 캡처 → 플레이 → Esc → 설정 → Esc → 나가기(종료 확인).
## **돌아가는 길은 Esc 하나뿐이다** — 화면 안에 "뒤로" 버튼이 없는지도 같이 본다
## (INBOX #17, docs/DESIGN.md 「클라이언트 화면 흐름」).
## 스크린샷은 user:// (~/Library/Application Support/Godot/app_userdata/Gunfarm) 에 남는다.

const SHOTS := "user://qa_shots"

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _fails: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# --script 모드는 main_scene 을 자동으로 띄우지 않는다 → 진입 씬을 직접 올린다.
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene", ""))
	_steps = [
		_step_main_menu,
		func(): _press("Layout/PlayButton"),
		func(): _expect_screen("캐릭터 선택", "01_play"),
		_expect_no_back_button,
		_press_escape,
		func(): _expect_screen("GUNFARM", "02_escape_from_play"),
		func(): _press("Layout/SettingsButton"),
		func(): _expect_screen("설정", "03_settings"),
		_expect_no_back_button,
		_press_escape,
		func(): _expect_screen("GUNFARM", "04_escape_from_settings"),
		_step_quit,
	]


func _process(_delta: float) -> bool:
	# 상태를 바꾼 직후 캡처하면 한 프레임 전 화면이 찍힌다 → 스텝마다 몇 프레임 쉰다.
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 — 첫 씬이 올라온 뒤에 시작한다.
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


func _scene() -> Node:
	return current_scene


func _press(node_path: String) -> void:
	var button := _scene().get_node_or_null(node_path) as Button
	if button == null:
		_fails.append("버튼을 못 찾음: %s (현재 씬 %s)" % [node_path, _scene().name])
		return
	button.emit_signal("pressed")


## Esc 를 실제 입력으로 흘려보낸다 — 화면 스크립트의 _unhandled_input 이 받아야 한다.
func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


## 화면 안에 "뒤로" 버튼이 남아 있으면 안 된다 (INBOX #17). 이름으로도 글자로도 본다 —
## 둘 중 하나만 보면 이름만 바꿔 살아남는다.
func _expect_no_back_button() -> void:
	for button in _scene().find_children("*", "Button", true, false):
		var b := button as Button
		if b.name == "BackButton" or b.text.strip_edges() == "뒤로":
			_fails.append("%s 화면에 뒤로 버튼이 남아 있다: %s (\"%s\")" % [
				_scene().name, _scene().get_path_to(b), b.text])


func _step_main_menu() -> void:
	_expect_screen("GUNFARM", "00_main_menu")
	# 진입 씬 자체가 메인 메뉴로 바뀌었는지도 같이 확인한다.
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene != "res://scenes/main_menu.tscn":
		_fails.append("진입 씬이 메인 메뉴가 아님: %s" % main_scene)
	for name in ["Layout/PlayButton", "Layout/SettingsButton", "Layout/QuitButton"]:
		if _scene().get_node_or_null(name) == null:
			_fails.append("메인 메뉴에 %s 가 없음" % name)


## 화면 안에 기대한 문구가 있는지(= 그 화면으로 넘어갔는지) 보고 스크린샷을 남긴다.
func _expect_screen(expect_text: String, shot_name: String) -> void:
	var found := false
	for label in _scene().find_children("*", "Label", true, false):
		if (label as Label).text.findn(expect_text) != -1:
			found = true
			break
	if not found:
		_fails.append("화면에 '%s' 가 없음 (현재 씬 %s)" % [expect_text, _scene().name])
	_shoot(shot_name)


func _shoot(shot_name: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		_fails.append("캡처 실패(%s): 뷰포트 텍스처 없음 — --headless 로 돌린 건 아닌지 확인" % shot_name)
		return
	var image := texture.get_image()
	var path := "%s/%s.png" % [SHOTS, shot_name]
	image.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, image.get_width(), image.get_height()])


## 나가기 버튼은 실제로 앱을 종료해야 한다 — 눌러도 안 죽으면 다음 프레임에 잡힌다.
func _step_quit() -> void:
	if not _fails.is_empty():
		_report()
		quit(1)
		return
	print("[qa] 나가기 버튼 누름 — 여기서 프로세스가 끝나야 정상")
	_report()
	_press("Layout/QuitButton")
	_steps.append(func(): _fails.append("나가기를 눌렀는데 앱이 종료되지 않음"))
	_steps.append(_report)


func _finish() -> bool:
	_report()
	if not _fails.is_empty():
		quit(1)
	return true


func _report() -> void:
	if _fails.is_empty():
		print("[qa] PASS — 메인 메뉴 3버튼 모두 정상")
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
