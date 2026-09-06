extends SceneTree

## INBOX #3 자체 QA — 설정 화면의 해상도 옵션과 PvP 공정성 규칙.
##
## 실행:
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_settings.gd
##   (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md 참고)
##
## 확인하는 것:
##   1) 설정 화면에서 해상도를 고르면 창 크기가 실제로 바뀌고 user:// 에 저장된다.
##   2) 다시 들어오면 저장된 값이 그대로 보이고, 진입 씬(메인 메뉴)이 그걸 창에 반영한다.
##   3) **해상도가 달라져도 카메라가 보여주는 월드 범위는 똑같다** (docs/DESIGN.md
##      "카메라 / 해상도"). 창을 16:9 아닌 비율로 늘려도 마찬가지여야 한다.
##   4) **돌아가는 길은 Esc 하나뿐이다** — 화면에 "뒤로" 버튼이 없고, Esc 로 메인 메뉴에
##      돌아간다 (INBOX #17, docs/DESIGN.md 「클라이언트 화면 흐름」).

const SettingsStore := preload("res://scripts/settings_store.gd")

const SHOTS := "user://qa_shots"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const PROBE_SCENE := "res://qa/world_range_probe.tscn"

## 논리 해상도가 그대로 월드 범위다 — 카메라가 원점에 있으므로 이 사각형이 나와야 한다.
const EXPECTED_RANGE := Rect2(-640, -360, 1280, 720)

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _fails: Array[String] = []
var _options: Array[Vector2i] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# 이전 실행의 저장 상태가 남아 거짓 실패를 내지 않게 지우고 시작한다 (docs/GOTCHAS.md).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsStore.SAVE_PATH))
	SettingsStore.apply_resolution(SettingsStore.BASE_SIZE)
	change_scene_to_file(SETTINGS_SCENE)

	_options = SettingsStore.available_resolutions()
	print("[qa] 이 화면에서 고를 수 있는 해상도: %s" % str(_options))

	_steps = [
		_step_initial,
		_expect_no_back_button,
		func(): _press("Layout/ResolutionRow/NextButton"),
		_step_after_next,
		func(): _press("Layout/ResolutionRow/PrevButton"),
		_step_after_prev,
		_step_save_then_reenter_menu,
		_step_menu_applied,
		_step_start_probe,
	]
	# 해상도마다: 적용 → 월드 범위 확인 + 캡처.
	for i in _options.size():
		var size: Vector2i = _options[i]
		_steps.append(func(): SettingsStore.apply_resolution(size))
		_steps.append(func(): _check_range("해상도 %dx%d" % [size.x, size.y], "1%d_range_%dx%d" % [i, size.x, size.y]))
	# 사용자가 창을 손으로 끌어 16:9 아닌 비율로 만든 경우에도 시야가 넓어지면 안 된다.
	_steps.append(func(): DisplayServer.window_set_size(Vector2i(1600, 720)))
	_steps.append(func(): _check_range("창을 손으로 늘린 1600x720", "20_range_dragged_1600x720"))
	# 마지막으로 설정 화면으로 돌아와 Esc 가 메인 메뉴로 나가는지 본다.
	_steps.append(func(): change_scene_to_file(SETTINGS_SCENE))
	_steps.append(_expect_no_back_button)
	_steps.append(_press_escape)
	_steps.append(_step_escaped_to_main_menu)
	_steps.append(_step_cleanup)


func _process(_delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size():
		_report()
		if not _fails.is_empty():
			quit(1)
		return true
	var step: Callable = _steps[_step]
	_step += 1
	_wait = 4  # 상태 변경(특히 창 크기)이 화면에 반영될 때까지 몇 프레임 쉰다.
	step.call()
	return false


# --- 설정 화면 -----------------------------------------------------------------

func _step_initial() -> void:
	_expect_value("1280 × 720", "저장된 설정이 없을 때 기본 해상도")
	_shoot("00_settings_default")


func _step_after_next() -> void:
	if _options.size() < 2:
		_fails.append("고를 수 있는 해상도가 %d개뿐이라 이 화면에서는 검증이 불가능하다" % _options.size())
		return
	var expected: Vector2i = _options[1]
	_expect_value("%d × %d" % [expected.x, expected.y], "다음 해상도로 넘긴 뒤")
	_expect_window(expected, "다음 해상도로 넘긴 뒤")
	var saved: Vector2i = SettingsStore.load_settings().get("resolution", Vector2i.ZERO)
	if saved != expected:
		_fails.append("저장 파일이 %s 인데 %s 여야 한다" % [saved, expected])
	_shoot("01_settings_next")


func _step_after_prev() -> void:
	_expect_value("1280 × 720", "이전 해상도로 되돌린 뒤")
	_expect_window(SettingsStore.BASE_SIZE, "이전 해상도로 되돌린 뒤")
	_shoot("02_settings_prev")


## 저장된 해상도를 메인 메뉴(진입 씬)가 창에 반영하는지.
func _step_save_then_reenter_menu() -> void:
	if _options.size() >= 2:
		SettingsStore.save_settings({"resolution": _options[1]})
	SettingsStore.apply_resolution(SettingsStore.BASE_SIZE)  # 일부러 어긋나게 해둔다.
	change_scene_to_file(MAIN_MENU_SCENE)


func _step_menu_applied() -> void:
	if _options.size() >= 2:
		_expect_window(_options[1], "메인 메뉴가 저장된 해상도를 반영")
	_shoot("03_menu_applied_saved")


# --- 월드 범위 (PvP 공정성) -------------------------------------------------------

func _step_start_probe() -> void:
	change_scene_to_file(PROBE_SCENE)


## 카메라가 실제로 덮는 월드 사각형을 계산한다.
## 캔버스 변환의 역이 곧 "화면 → 월드" 이므로, 뷰포트 전체를 월드로 되돌리면 시야가 나온다.
func _visible_world_rect() -> Rect2:
	return root.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, root.get_visible_rect().size)


func _check_range(what: String, shot_name: String) -> void:
	var rect := _visible_world_rect()
	var window := DisplayServer.window_get_size()
	print("[qa] %s → 창 %s / 보이는 월드 %s" % [what, window, rect])
	if not rect.position.is_equal_approx(EXPECTED_RANGE.position) or not rect.size.is_equal_approx(EXPECTED_RANGE.size):
		_fails.append("%s: 보이는 월드 범위가 %s — %s 여야 한다 (PvP 공정성)" % [what, rect, EXPECTED_RANGE])
	_shoot(shot_name)


## 설정 화면에서 Esc → 메인 메뉴. 뒤로 버튼이 없어졌으므로 이게 유일한 길이다.
func _step_escaped_to_main_menu() -> void:
	var found := false
	for label in current_scene.find_children("*", "Label", true, false):
		if (label as Label).text.findn("GUNFARM") != -1:
			found = true
			break
	if not found:
		_fails.append("설정 화면에서 Esc 를 눌렀는데 메인 메뉴로 안 갔다 (현재 씬 %s)" % current_scene.name)
	_shoot("30_settings_escape_to_menu")


## 화면 안에 "뒤로" 버튼이 남아 있으면 안 된다 (INBOX #17). 이름으로도 글자로도 본다.
func _expect_no_back_button() -> void:
	for button in current_scene.find_children("*", "Button", true, false):
		var b := button as Button
		if b.name == "BackButton" or b.text.strip_edges() == "뒤로":
			_fails.append("%s 화면에 뒤로 버튼이 남아 있다: %s" % [
				current_scene.name, current_scene.get_path_to(b)])


## Esc 를 실제 입력으로 흘려보낸다 — 화면 스크립트의 _unhandled_input 이 받아야 한다.
func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


func _step_cleanup() -> void:
	SettingsStore.apply_resolution(SettingsStore.BASE_SIZE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsStore.SAVE_PATH))


# --- 도구 ----------------------------------------------------------------------

func _press(node_path: String) -> void:
	var button := current_scene.get_node_or_null(node_path) as Button
	if button == null:
		_fails.append("버튼을 못 찾음: %s (현재 씬 %s)" % [node_path, current_scene.name])
		return
	if button.disabled:
		_fails.append("버튼이 비활성 상태다: %s" % node_path)
		return
	button.emit_signal("pressed")


func _expect_value(text: String, what: String) -> void:
	var label := current_scene.get_node_or_null("Layout/ResolutionRow/ResolutionValue") as Label
	if label == null:
		_fails.append("%s: 해상도 표시 라벨을 못 찾음" % what)
		return
	if label.text != text:
		_fails.append("%s: 화면에 '%s' 인데 '%s' 여야 한다" % [what, label.text, text])


func _expect_window(size: Vector2i, what: String) -> void:
	var actual := DisplayServer.window_get_size()
	if actual != size:
		_fails.append("%s: 창 크기가 %s 인데 %s 여야 한다" % [what, actual, size])


func _shoot(shot_name: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		_fails.append("캡처 실패(%s): 뷰포트 텍스처 없음 — --headless 로 돌린 건 아닌지 확인" % shot_name)
		return
	var image := texture.get_image()
	var path := "%s/%s.png" % [SHOTS, shot_name]
	image.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _report() -> void:
	if _fails.is_empty():
		print("[qa] PASS — 해상도 설정과 월드 범위 고정 모두 정상")
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
