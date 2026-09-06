extends SceneTree

## INBOX #5 자체 QA (2) — 만들어진 월드가 실제로 화면에 보이는지.
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_world_entry.gd
##
## 확인하는 것:
##   1) 캐릭터가 있는 슬롯으로 들어가면 그 슬롯의 시드로 만든 지형이 화면에 그려진다.
##   2) 플레이어와 카메라가 스폰 지점에 있고 스폰 주변은 땅이다(바다 한가운데서
##      시작하지 않는다). 카메라는 플레이어의 자식이라 위치를 볼 때 global 로 본다.
##   3) **보이는 월드 범위는 여전히 1280×720 고정**이다 (docs/DESIGN.md "카메라 / 해상도").
##   4) 시드가 다르면 화면도 다르고, 같은 시드로 다시 들어오면 같은 화면이다.
##   5) **월드의 Esc 는 나가는 키가 아니라 일시정지 메뉴다** (INBOX #17):
##      화면에 뒤로 버튼이 없고, Esc 로 메뉴가 열리며 씬은 그대로 월드다.
##      메뉴가 열려도 **월드는 멈추지 않고**(get_tree().paused 를 쓰지 않는다) **입력만**
##      끊긴다. 설정은 겹쳐서 열리고 Esc 로 가장 안쪽 창부터 닫힌다.
##      "메인 메뉴로 나가기"는 슬롯이 아니라 메인 메뉴로 간다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"

## 화면의 픽셀을 땅/바다로 가르는 기준색. 지형이 스프라이트가 된 뒤로는 한 지형이
## 색 하나가 아니라 **램프 4단계**라, 재질별 램프 전체와 견줘서 가장 가까운 쪽을
## 고른다 (INBOX #12). 색은 손으로 적지 않고 생성기가 내려보낸 표에서 꺼낸다.
const TerrainPalettes := preload("res://scripts/terrain_palettes.gd")

## 논리 해상도가 곧 시야다.
const EXPECTED_RANGE := Rect2(-640, -360, 1280, 720)

const SEED_A := 20260906
const SEED_B := 31337

## 캡처를 견주거나 이동을 재기 전에 시뮬레이션이 자리를 잡을 때까지 쉬는 **시간**.
## 프레임 수로 세면 안 된다 (docs/GOTCHAS.md) — 이 창은 수직동기화가 없어 몇 프레임이
## 몇 ms 밖에 안 되고, 그러면 고정 틱(1/60초)이 한 번도 안 돈다. 그때 (1) 캐릭터가 아직
## 마우스 쪽을 안 본 채로 찍혀 같은 시드 재입장 비교가 어긋나고, (2) "메뉴가 열리면 안
## 움직인다" 검사가 애초에 아무도 안 움직여서 거저 통과한다.
const SETTLE_SECONDS := 0.35

const PAUSE := "HUD/PauseMenu"
const PAUSE_BOX := "HUD/PauseMenu/Box/BoxLayout"
## 일시정지 메뉴가 열린 동안 월드가 계속 도는지 재는 시계. 세계를 `get_tree().paused` 로
## 세웠다면 기본 process_mode 인 이 타이머도 같이 멈춰서 `time_left` 가 그대로 남는다.
const CLOCK_SECONDS := 10.0

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []
var _shot_a := PackedByteArray()
## 일시정지 메뉴를 열기 직전의 플레이어 위치 — 메뉴가 열린 동안 여기서 안 움직여야 한다.
var _move_from := Vector2.ZERO


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# 이전 실행의 슬롯이 남아 거짓 실패를 내지 않게 지우고 시작한다 (docs/GOTCHAS.md).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))
	# 첫 씬은 여기서 올린다 — _process 가 current_scene 이 생길 때까지 기다리므로
	# 첫 단계를 _steps 에 넣어두면 영영 실행되지 않는다 (docs/GOTCHAS.md).
	_enter_world_with_seed(SEED_A)

	_steps = [
		_settle,
		_check_first_entry,
		_check_view_range,
		_check_spawn_is_land,
		func(): _look_at_coast(),
		_check_coast_shows_both,
		func(): _enter_world_with_seed(SEED_B),
		_settle,
		_check_other_seed_differs,
		func(): _enter_world_with_seed(SEED_A),
		_settle,
		_check_same_seed_repeats,
		_check_seed_saved_on_old_slot,
		func(): _overview_shot(),
		# 위 캡처가 카메라를 축소해뒀으므로 일시정지 메뉴는 새로 들어간 월드에서 본다.
		func(): _enter_world_with_seed(SEED_A),
		_check_no_back_button,
		_press_escape,
		_check_escape_opens_pause_menu,
		_settle,
		_check_world_keeps_running_input_cut,
		func(): _press(PAUSE_BOX + "/SettingsButton"),
		_check_settings_opens_over_world,
		_press_escape,
		_check_settings_closed_back_to_pause,
		_press_escape,
		_settle,
		_check_resumed,
		_press_escape,
		func(): _press(PAUSE_BOX + "/ExitButton"),
		_check_exit_goes_to_main_menu,
	]


func _process(delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
	if _wait_time > 0.0:
		_wait_time -= delta
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size():
		if _fails.is_empty():
			print("[qa] PASS — 월드 생성/입장 화면 정상")
			return true
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)
		return true
	var step: Callable = _steps[_step]
	_step += 1
	_wait = 4  # 상태를 바꾼 프레임에 바로 찍으면 한 프레임 전 화면이 찍힌다 (docs/GOTCHAS.md).
	step.call()
	return false


# --- 준비 -------------------------------------------------------------------

func _enter_world_with_seed(seed_value: int) -> void:
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("탐험가", {}, seed_value)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)


func _world() -> RefCounted:
	return current_scene.get("world")


# --- 확인 -------------------------------------------------------------------

func _check_first_entry() -> void:
	_expect_text("탐험가", "캐릭터 이름")
	_expect_text(str(SEED_A), "시드 표시")
	var world := _world()
	if world == null:
		_fails.append("월드가 만들어지지 않았다")
		return
	if world.world_seed != SEED_A:
		_fails.append("슬롯의 시드(%d)가 아니라 %d 로 월드를 만들었다" % [SEED_A, world.world_seed])
	_shoot("40_world_spawn")


## 해상도/창 크기와 무관하게 보이는 월드 범위는 고정이어야 한다 (PvP 공정성).
## 카메라가 스폰으로 옮겨갔으므로 그 위치 기준으로 1280×720 이어야 한다.
func _check_view_range() -> void:
	var camera := current_scene.get_node_or_null("%Camera") as Camera2D
	if camera == null:
		_fails.append("카메라를 못 찾음")
		return
	var world := _world()
	var spawn: Vector2 = WorldGen.tile_center(world.spawn_tile)
	# 카메라는 플레이어의 자식이라(따라다니게 만들 코드가 없다) 로컬 좌표는 항상 0이다.
	if not camera.global_position.is_equal_approx(spawn):
		_fails.append("카메라가 %s 인데 스폰 %s 에 있어야 한다" % [camera.global_position, spawn])
	if not camera.zoom.is_equal_approx(Vector2.ONE):
		_fails.append("카메라 zoom 이 %s 다 — 확대/축소하면 시야가 달라져 PvP 공정성이 깨진다" % camera.zoom)
	var rect := _visible_world_rect()
	var expected := Rect2(EXPECTED_RANGE.position + spawn, EXPECTED_RANGE.size)
	if not rect.position.is_equal_approx(expected.position) or not rect.size.is_equal_approx(expected.size):
		_fails.append("보이는 월드 범위가 %s — %s 여야 한다 (PvP 공정성)" % [rect, expected])


## 스폰 주변이 땅이어야 한다. 화면 한가운데는 플레이어가 덮고 있으므로 조금 비켜서 본다.
func _check_spawn_is_land() -> void:
	var image := _capture()
	if image == null:
		return
	var size := image.get_size()
	var land := 0
	var total := 0
	for dx: float in [-0.18, -0.09, 0.09, 0.18]:
		for dy: float in [-0.18, -0.09, 0.09, 0.18]:
			var at := size / 2 + Vector2i(int(size.x * dx), int(size.y * dy))
			total += 1
			if _nearest(image.get_pixelv(at)) == "land":
				land += 1
	print("[qa] 스폰 주변 표본 %d개 중 땅 %d개" % [total, land])
	if land < total:
		_fails.append("스폰 주변 %d/%d 칸이 바다다 — 바다 한가운데서 시작하면 안 된다" % [total - land, total])


## 해안으로 플레이어를 옮기면(카메라가 따라간다) 한 화면에 땅과 바다가 같이 보여야 한다
## (지형이 실제로 두 종류로 그려지는지 = 렌더러가 도는지 확인).
func _look_at_coast() -> void:
	var world := _world()
	var spawn: Vector2i = world.spawn_tile
	# 스폰에서 가장 가까운 **자연 해안**(바다에 닿은 땅 칸). 지도 테두리는 강제로 바다라
	# 직선이므로 빼고 찾는다 — 실제 해안선이 어떻게 그려지는지 봐야 의미가 있다.
	var margin := 12
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(margin, WorldGen.MAP_TILES - margin):
		for x in range(margin, WorldGen.MAP_TILES - margin):
			if not world.is_land(x, y):
				continue
			if world.is_land(x + 1, y) and world.is_land(x - 1, y) \
					and world.is_land(x, y + 1) and world.is_land(x, y - 1):
				continue
			var distance: float = Vector2(Vector2i(x, y) - spawn).length_squared()
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	if best.x < 0:
		_fails.append("자연 해안 타일을 못 찾았다 — 지도가 전부 땅이거나 전부 바다다")
		return
	var player := current_scene.get_node_or_null("%Player") as Node2D
	player.place_at(WorldGen.tile_center(best))
	print("[qa] 스폰에서 가장 가까운 해안 %s 로 플레이어 이동" % best)


func _check_coast_shows_both() -> void:
	var image := _capture()
	if image == null:
		return
	var counts := {"land": 0, "sea": 0, "그 외": 0}
	var size := image.get_size()
	for i in 400:
		var at := Vector2i((i * 37) % size.x, (i * 53) % size.y)
		counts[_nearest(image.get_pixelv(at))] += 1
	print("[qa] 해안 화면 표본 400개 → 땅 %d / 바다 %d / 그 외 %d" % [counts["land"], counts["sea"], counts["그 외"]])
	if counts["land"] < 20 or counts["sea"] < 20:
		_fails.append("해안 화면에 땅 %d / 바다 %d — 한 화면에 둘 다 보여야 한다" % [counts["land"], counts["sea"]])
	_shoot("41_world_coast")


func _check_other_seed_differs() -> void:
	_expect_text(str(SEED_B), "다른 시드 표시")
	_shot_a = _shoot("42_world_seed_b")
	var world := _world()
	if world != null and world.world_seed != SEED_B:
		_fails.append("시드 %d 로 들어갔는데 월드 시드가 %d 다" % [SEED_B, world.world_seed])


func _check_same_seed_repeats() -> void:
	var again := _shoot("43_world_seed_a_again")
	var first := FileAccess.get_file_as_bytes("%s/40_world_spawn.png" % SHOTS)
	if first.is_empty() or again.is_empty():
		_fails.append("같은 시드 재입장 비교용 캡처가 비어 있다")
		return
	if first != again:
		_fails.append("같은 시드(%d)로 다시 들어왔는데 화면이 다르다" % SEED_A)
	if first == _shot_a:
		_fails.append("시드 %d 와 %d 의 화면이 같다 — 시드가 화면에 안 먹히고 있다" % [SEED_A, SEED_B])


## 시드가 없던(옛 형식) 슬롯으로 들어가면 그 자리에서 시드를 정해 저장해야 한다 —
## 다음에 다시 들어와도 같은 월드가 나와야 하기 때문이다.
func _check_seed_saved_on_old_slot() -> void:
	var slots := SlotStore.load_slots()
	var slot: Dictionary = slots[0]
	slot["world_seed"] = 0
	slots[0] = slot
	SlotStore.save_slots(slots)
	change_scene_to_file(WORLD_SCENE)
	_steps.insert(_step, _check_seed_filled_in)


func _check_seed_filled_in() -> void:
	var saved := int(SlotStore.load_slots()[0].get("world_seed", 0))
	if saved == 0:
		_fails.append("시드가 비어 있던 슬롯에 들어갔는데 시드가 저장되지 않았다")
		return
	var world := _world()
	if world == null or world.world_seed != saved:
		_fails.append("저장된 시드(%d)와 화면의 월드 시드가 어긋난다" % saved)


## 이 캡처만 QA 전용으로 카메라를 축소해서 섬 전체 모양을 눈으로 본다
## (게임 플레이에서는 절대 축소하지 않는다 — 위 _check_view_range 참고).
func _overview_shot() -> void:
	var camera := current_scene.get_node_or_null("%Camera") as Camera2D
	# 지도 전체(12288 월드 단위)가 720px 세로 안에 들어오는 배율.
	var fit := root.get_visible_rect().size.y / WorldGen.world_size().y
	camera.zoom = Vector2(fit, fit)
	camera.global_position = WorldGen.world_size() * 0.5
	_steps.insert(_step, func(): _shoot("44_island_overview_QA만_축소"))


# --- 일시정지 메뉴 (INBOX #17) ------------------------------------------------

## 화면 안에 "뒤로" 버튼이 남아 있으면 안 된다. 이름으로도 글자로도 본다 —
## 둘 중 하나만 보면 이름만 바꿔 살아남는다.
func _check_no_back_button() -> void:
	for button in current_scene.find_children("*", "Button", true, false):
		var b := button as Button
		if b.name == "BackButton" or b.text.strip_edges() == "뒤로":
			_fails.append("월드 화면에 뒤로 버튼이 남아 있다: %s" % current_scene.get_path_to(b))


## Esc 는 **슬롯 화면으로 나가지 않는다** — 그 자리에서 일시정지 메뉴를 연다.
func _check_escape_opens_pause_menu() -> void:
	if _find_text("캐릭터 선택"):
		_fails.append("월드에서 Esc 를 눌렀더니 슬롯 화면으로 나가버렸다 — 일시정지 메뉴여야 한다")
		return
	var menu := current_scene.get_node_or_null(PAUSE) as Control
	if menu == null or not menu.visible:
		_fails.append("월드에서 Esc 를 눌렀는데 일시정지 메뉴가 안 열렸다")
		return
	for label: String in ["계속하기", "설정", "메인 메뉴로 나가기"]:
		if current_scene.get_node_or_null("%s/%s" % [PAUSE_BOX, _button_name(label)]) == null:
			_fails.append("일시정지 메뉴에 '%s' 가 없다" % label)
	if paused:
		_fails.append("get_tree().paused 로 세계를 세웠다 — 멀티플레이에서 한 사람이 세계를 멈출 수 없다")
	var player := _player()
	if player != null and not player.is_processing():
		_fails.append("메뉴를 열면서 플레이어의 _process 를 껐다 — 입력만 끊어야 한다")
	_shoot("45_pause_menu")

	# 여기서부터 "세계는 도는데 입력만 끊겼다"를 잰다: 시계를 하나 걸어두고,
	# 이동 키를 **누른 채로** 둔다.
	_start_clock()
	_move_from = player.global_position if player != null else Vector2.ZERO
	Input.action_press("move_up")


## 메뉴가 열린 동안: 시계는 계속 가고(세계가 돈다), 플레이어는 키를 눌러도 안 움직인다.
func _check_world_keeps_running_input_cut() -> void:
	var clock := _clock()
	if clock == null or clock.is_stopped():
		_fails.append("월드가 계속 도는지 잴 시계가 멈춰 있다")
	elif is_equal_approx(clock.time_left, CLOCK_SECONDS):
		_fails.append("일시정지 메뉴를 여는 동안 월드 시간이 한 틱도 안 흘렀다 — 세계를 멈추면 안 된다")
	var player := _player()
	if player == null:
		return
	var moved := player.global_position.distance_to(_move_from)
	print("[qa] 메뉴 열린 채 W 를 누른 동안 이동 %.1f / 시계 남은 %.3f초" % [moved, clock.time_left])
	if moved > 0.5:
		_fails.append("메뉴가 열려 있는데 W 로 %.1f 만큼 움직였다 — 입력은 끊겨야 한다" % moved)


## 설정은 **씬을 바꾸지 않고 월드 위에 겹쳐서** 열린다(씬을 바꾸면 월드가 내려간다).
func _check_settings_opens_over_world() -> void:
	if _world() == null:
		_fails.append("설정을 열었더니 월드 씬이 통째로 바뀌었다 — 겹쳐서 띄워야 한다")
		return
	if current_scene.get_node_or_null("HUD/Screen") == null:
		_fails.append("일시정지 메뉴의 설정을 눌렀는데 설정 화면이 안 떴다")
	_expect_text("해상도", "겹쳐 뜬 설정 화면")
	_shoot("46_pause_settings")


## 가장 안쪽 창부터 닫힌다 — Esc 로 설정만 닫히고 일시정지 메뉴는 남는다.
func _check_settings_closed_back_to_pause() -> void:
	if current_scene.get_node_or_null("HUD/Screen") != null:
		_fails.append("겹쳐 뜬 설정이 Esc 로 안 닫혔다")
	var menu := current_scene.get_node_or_null(PAUSE) as Control
	if menu == null or not menu.visible:
		_fails.append("설정을 닫았더니 일시정지 메뉴까지 같이 닫혔다 — 안쪽 창 하나만 닫혀야 한다")
	_shoot("47_pause_after_settings")


## 메뉴를 닫으면 조작이 돌아온다 — 아까부터 누르고 있던 W 가 그제서야 먹는다.
func _check_resumed() -> void:
	var menu := current_scene.get_node_or_null(PAUSE) as Control
	if menu != null and menu.visible:
		_fails.append("Esc 를 한 번 더 눌렀는데 일시정지 메뉴가 안 닫혔다")
	var player := _player()
	if player != null:
		var moved := player.global_position.distance_to(_move_from)
		print("[qa] 메뉴를 닫은 뒤 이동 %.1f" % moved)
		if moved < 1.0:
			_fails.append("메뉴를 닫았는데도 W 가 안 먹는다 (이동 %.1f)" % moved)
	Input.action_release("move_up")
	_shoot("48_resumed")


## "메인 메뉴로 나가기"는 슬롯이 아니라 메인 메뉴로 간다 (docs/DESIGN.md 「조작」).
func _check_exit_goes_to_main_menu() -> void:
	if not _find_text("GUNFARM"):
		_fails.append("일시정지 메뉴의 '메인 메뉴로 나가기' 가 메인 메뉴로 안 갔다")
	_shoot("49_exit_to_main_menu")


func _button_name(label: String) -> String:
	match label:
		"계속하기": return "ResumeButton"
		"설정": return "SettingsButton"
		_: return "ExitButton"


func _player() -> Node2D:
	return current_scene.get_node_or_null("%Player") as Node2D


func _press(node_path: String) -> void:
	var button := current_scene.get_node_or_null(node_path) as Button
	if button == null:
		_fails.append("버튼을 못 찾음: %s (현재 씬 %s)" % [node_path, current_scene.name])
		return
	button.emit_signal("pressed")


## Esc 를 실제 입력으로 흘려보낸다 — 화면 스크립트의 _unhandled_input 이 받아야 한다.
func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


## 다음 단계까지 넉넉히 쉰다 (위 SETTLE_SECONDS 주석 참고).
func _settle() -> void:
	_wait_time = SETTLE_SECONDS


func _start_clock() -> void:
	var clock := Timer.new()
	clock.name = "QaClock"
	clock.wait_time = CLOCK_SECONDS
	clock.one_shot = true
	current_scene.add_child(clock)
	clock.start()


func _clock() -> Timer:
	return current_scene.get_node_or_null("QaClock") as Timer


# --- 도구 -------------------------------------------------------------------

func _visible_world_rect() -> Rect2:
	return root.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, root.get_visible_rect().size)


func _nearest(color: Color) -> String:
	var to_land := _distance_to(color, TerrainPalettes.LAND_MATERIALS)
	var to_sea := _distance_to(color, TerrainPalettes.SEA_MATERIALS)
	# 램프 색과 정확히 맞는 픽셀만 지형으로 본다 — 나머지는 HUD/플레이어다.
	if minf(to_land, to_sea) > 0.02:
		return "그 외"
	return "land" if to_land < to_sea else "sea"


func _distance_to(color: Color, materials: Array) -> float:
	var best := INF
	for material: String in materials:
		for step in TerrainPalettes.RAMPS[material].size():
			var ramp := TerrainPalettes.color_of(material, step)
			best = minf(best, Vector3(color.r - ramp.r, color.g - ramp.g,
					color.b - ramp.b).length())
	return best


func _capture() -> Image:
	var texture := root.get_texture()
	if texture == null:
		_fails.append("캡처 실패: 뷰포트 텍스처 없음 — --headless 로 돌린 건 아닌지 확인")
		return null
	return texture.get_image()


func _shoot(shot_name: String) -> PackedByteArray:
	var image := _capture()
	if image == null:
		return PackedByteArray()
	var path := "%s/%s.png" % [SHOTS, shot_name]
	image.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	return FileAccess.get_file_as_bytes(path)


func _find_text(expect_text: String) -> bool:
	for label in current_scene.find_children("*", "Label", true, false):
		if (label as Label).text.findn(expect_text) != -1:
			return true
	return false


func _expect_text(expect_text: String, what: String) -> void:
	if not _find_text(expect_text):
		_fails.append("%s: 화면에서 '%s' 를 못 찾았다" % [what, expect_text])
