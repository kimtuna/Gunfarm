extends SceneTree

## INBOX #4 자체 QA — 캐릭터 커스터마이징 화면.
##
## 실행:
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_character_customize.gd
##   (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md 참고)
##
## 검증: 외형 데이터 클래스(팔레트/정규화/이름 다듬기) → 기본 상태(이름 없으면 확정 불가) →
##       이름 입력하면 확정 가능 → 색/머리모양 좌우 이동 + 양끝에서 되감김 →
##       머리모양 4종 미리보기 캡처 → 확정하면 슬롯에 외형까지 저장되고 월드 입장 →
##       Esc 로 나가면 아무것도 저장되지 않음.

const SlotStore := preload("res://scripts/slot_store.gd")
const Appearance := preload("res://scripts/character_appearance.gd")

const SHOTS := "user://qa_shots"
const CUSTOMIZE_SCENE := "res://scenes/character_customize.tscn"

const ROWS := "Layout/Content/Fields/Rows"
const NAME_EDIT := "Layout/Content/Fields/NameRow/NameEdit"
const CONFIRM := "Layout/Buttons/ConfirmButton"

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _fails: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# 이전 실행의 저장 상태가 남으면 거짓 실패가 난다 (docs/GOTCHAS.md).
	DirAccess.remove_absolute(SlotStore.SAVE_PATH)
	_check_appearance_data()
	SlotStore.selected_slot = 0
	change_scene_to_file(CUSTOMIZE_SCENE)
	_steps = [
		_check_default_state,
		func(): _type_name("  갈대  "),
		_check_name_enables_confirm,
		# 양끝에서 되감기는지 — 첫 선택지에서 왼쪽으로 가면 마지막 선택지여야 한다.
		func(): _step_field("skin", "Prev"),
		_check_skin_wrapped,
		func(): _step_field("skin", "Next"),
		_check_skin_back_to_first,
		# 실제로 골라본다: 피부 2칸, 머리색 3칸, 옷색 5칸.
		func(): _step_field("skin", "Next", 2),
		func(): _step_field("hair_color", "Next", 3),
		func(): _step_field("clothes_color", "Next", 5),
		_check_picked_values,
		# 머리모양 4종이 미리보기에서 서로 달라 보이는지 눈으로 볼 캡처를 남긴다.
		_shoot_hairstyle_short,
		func(): _step_field("hairstyle", "Next"),
		_shoot_hairstyle_bob,
		func(): _step_field("hairstyle", "Next"),
		_shoot_hairstyle_long,
		func(): _step_field("hairstyle", "Next"),
		_shoot_hairstyle_ponytail,
		func(): _step_field("hairstyle", "Next"),
		_check_hairstyle_wrapped,
		func(): _press(CONFIRM),
		_check_confirmed,
		# 확정하지 않고 Esc 로 나가면 그 슬롯은 그대로 비어 있어야 한다.
		func(): _start_second_slot(),
		func(): _type_name("버려질이름"),
		_press_escape,
		_check_escaped_without_saving,
	]


# --- 데이터 클래스 (화면 없이 확인) -----------------------------------------

func _check_appearance_data() -> void:
	var default := Appearance.default_appearance()
	for field in Appearance.FIELDS:
		_expect(Appearance.options(field).size() >= 3,
			"%s 선택지가 너무 적다: %d" % [field, Appearance.options(field).size()])
		_expect(Appearance.index_of(field, String(default[field])) == 0,
			"%s 기본값이 첫 선택지가 아니다" % field)
	_expect(Appearance.HAIRSTYLE.size() >= 3 and Appearance.HAIRSTYLE.size() <= 4,
		"머리모양은 3~4종이어야 한다 (DESIGN.md): %d" % Appearance.HAIRSTYLE.size())

	# 팔레트 안의 id 는 겹치면 안 되고, 색은 실제로 파싱돼야 한다.
	for field in Appearance.FIELDS:
		var seen := {}
		for option in Appearance.options(field):
			_expect(not seen.has(option["id"]), "%s 에 같은 id 가 두 번 있다: %s" % [field, option["id"]])
			seen[option["id"]] = true
			if field != "hairstyle":
				_expect(Appearance.color_of(field, String(option["id"])) != Color.MAGENTA,
					"%s/%s 의 색을 못 읽었다" % [field, option["id"]])

	# 깨진/옛 저장값은 기본값으로 되돌아가야 한다.
	var fixed := Appearance.normalize({"skin": "없는색", "hairstyle": "long"})
	_expect(fixed["skin"] == default["skin"], "모르는 id 가 기본값으로 안 돌아갔다: %s" % fixed["skin"])
	_expect(fixed["hairstyle"] == "long", "멀쩡한 id 까지 덮어썼다: %s" % fixed["hairstyle"])

	# 이름 다듬기 — 앞뒤 공백 제거, 길이 자르기, 공백뿐인 이름은 무효.
	_expect(Appearance.sanitize_name("  갈대  ") == "갈대", "이름 공백이 안 잘렸다")
	_expect(Appearance.sanitize_name("가".repeat(30)).length() == Appearance.MAX_NAME_LENGTH,
		"이름 길이가 안 잘렸다")
	_expect(not Appearance.is_valid_name("   "), "공백뿐인 이름이 통과됐다")
	_expect(Appearance.is_valid_name("갈대"), "멀쩡한 이름이 막혔다")


# --- 각 단계의 확인 ---------------------------------------------------------

## 처음엔 기본 외형이 보이고, 이름이 비어 있어서 확정할 수 없다.
func _check_default_state() -> void:
	_expect_screen("캐릭터 만들기", "30_customize_default")
	_expect_text_on_screen("슬롯 1")
	_expect_value("skin", "밝은")
	_expect_value("hair_color", "검정")
	_expect_value("clothes_color", "풀색")
	_expect_value("hairstyle", "짧은머리")
	_expect_swatch("skin", Appearance.color_of("skin", "light"))
	_expect_confirm_disabled(true)
	_expect_text_on_screen("이름을 입력해야")


func _check_name_enables_confirm() -> void:
	_expect_screen("캐릭터 만들기", "31_name_typed")
	_expect_confirm_disabled(false)


func _check_skin_wrapped() -> void:
	_expect_value("skin", String(Appearance.SKIN[Appearance.SKIN.size() - 1]["label"]))
	_expect_swatch("skin", Appearance.color_of("skin", String(Appearance.SKIN[Appearance.SKIN.size() - 1]["id"])))
	_shoot("32_skin_wrapped_to_last")


func _check_skin_back_to_first() -> void:
	_expect_value("skin", "밝은")


func _check_picked_values() -> void:
	_expect_screen("캐릭터 만들기", "33_picked")
	_expect_value("skin", String(Appearance.SKIN[2]["label"]))
	_expect_value("hair_color", String(Appearance.HAIR_COLOR[3]["label"]))
	_expect_value("clothes_color", String(Appearance.CLOTHES_COLOR[5]["label"]))
	_expect_swatch("skin", Appearance.color_of("skin", String(Appearance.SKIN[2]["id"])))
	_expect_swatch("hair_color", Appearance.color_of("hair_color", String(Appearance.HAIR_COLOR[3]["id"])))
	_expect_swatch("clothes_color", Appearance.color_of("clothes_color", String(Appearance.CLOTHES_COLOR[5]["id"])))
	# 머리모양 줄에는 색 견본이 없다.
	var swatch := current_scene.get_node_or_null("%s/hairstyle/Swatch" % ROWS) as ColorRect
	_expect(swatch != null and not swatch.visible, "머리모양 줄에 색 견본이 보인다")


func _shoot_hairstyle_short() -> void:
	_expect_value("hairstyle", "짧은머리")
	_shoot("34_hairstyle_short")


func _shoot_hairstyle_bob() -> void:
	_expect_value("hairstyle", "단발머리")
	_shoot("35_hairstyle_bob")


func _shoot_hairstyle_long() -> void:
	_expect_value("hairstyle", "긴머리")
	_shoot("36_hairstyle_long")


func _shoot_hairstyle_ponytail() -> void:
	_expect_value("hairstyle", "묶은머리")
	_shoot("37_hairstyle_ponytail")


func _check_hairstyle_wrapped() -> void:
	_expect_value("hairstyle", "짧은머리")


## 확정하면 월드로 들어가고, 저장 파일에 이름과 외형 id 가 그대로 들어간다.
func _check_confirmed() -> void:
	_expect_screen("시드", "38_confirmed_enters_world")
	_expect_text_on_screen("갈대")
	var slot: Dictionary = SlotStore.load_slots()[0]
	_expect(slot.get("name", "") == "갈대", "저장된 이름이 '%s'" % slot.get("name", ""))
	var saved: Dictionary = slot.get("appearance", {})
	_expect_saved_id(saved, "skin", String(Appearance.SKIN[2]["id"]))
	_expect_saved_id(saved, "hair_color", String(Appearance.HAIR_COLOR[3]["id"]))
	_expect_saved_id(saved, "clothes_color", String(Appearance.CLOTHES_COLOR[5]["id"]))
	_expect_saved_id(saved, "hairstyle", "short")


func _check_escaped_without_saving() -> void:
	_expect_screen("캐릭터 선택", "39_escaped_without_saving")
	var slot: Dictionary = SlotStore.load_slots()[1]
	_expect(SlotStore.is_empty(slot), "확정을 안 했는데 슬롯 2 에 뭔가 저장됐다: %s" % slot)


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


func _step_field(field: String, side: String, times: int = 1) -> void:
	for i in times:
		_press("%s/%s/%s" % [ROWS, field, side])


## LineEdit 은 text 를 대입해도 text_changed 를 안 쏜다 — 화면 갱신까지 흉내내려면
## 직접 쏴줘야 한다.
func _type_name(text: String) -> void:
	var edit := current_scene.get_node_or_null(NAME_EDIT) as LineEdit
	if edit == null:
		_fails.append("이름 입력칸을 못 찾음 (현재 씬 %s)" % current_scene.name)
		return
	edit.text = text
	edit.text_changed.emit(text)


func _start_second_slot() -> void:
	SlotStore.selected_slot = 1
	change_scene_to_file(CUSTOMIZE_SCENE)


func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


# --- 검증 -------------------------------------------------------------------

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_fails.append(message)


func _expect_value(field: String, expect_text: String) -> void:
	var label := current_scene.get_node_or_null("%s/%s/Value" % [ROWS, field]) as Label
	if label == null:
		_fails.append("%s 값 라벨이 없다 (현재 씬 %s)" % [field, current_scene.name])
		return
	_expect(label.text == expect_text, "%s 가 '%s' 여야 하는데 '%s'" % [field, expect_text, label.text])


func _expect_swatch(field: String, expect_color: Color) -> void:
	var swatch := current_scene.get_node_or_null("%s/%s/Swatch" % [ROWS, field]) as ColorRect
	if swatch == null:
		_fails.append("%s 색 견본이 없다" % field)
		return
	_expect(swatch.color.is_equal_approx(expect_color),
		"%s 색 견본이 %s 여야 하는데 %s" % [field, expect_color, swatch.color])


func _expect_confirm_disabled(expected: bool) -> void:
	var button := current_scene.get_node_or_null(CONFIRM) as Button
	if button == null:
		_fails.append("확정 버튼이 없다 (현재 씬 %s)" % current_scene.name)
		return
	_expect(button.disabled == expected,
		"확정 버튼 disabled 가 %s 여야 하는데 %s" % [expected, button.disabled])


func _expect_saved_id(saved: Dictionary, field: String, expect_id: String) -> void:
	_expect(String(saved.get(field, "")) == expect_id,
		"저장된 %s 가 '%s' 여야 하는데 '%s'" % [field, expect_id, saved.get(field, "")])


func _expect_text_on_screen(expect_text: String) -> void:
	_expect(_find_text(expect_text), "화면에 '%s' 가 없음 (현재 씬 %s)" % [expect_text, current_scene.name])


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
		print("[qa] PASS — 캐릭터 커스터마이징 화면 정상")
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)
		return true
	quit(0)
	return true
