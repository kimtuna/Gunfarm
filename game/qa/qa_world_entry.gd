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
##   5) 뒤로 버튼으로 슬롯 화면에 돌아갈 수 있다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"

const COLOR_SEA := Color(0.121569, 0.223529, 0.294118)
const COLOR_LAND := Color(0.286275, 0.415686, 0.243137)

## 논리 해상도가 곧 시야다.
const EXPECTED_RANGE := Rect2(-640, -360, 1280, 720)

const SEED_A := 20260906
const SEED_B := 31337

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _fails: Array[String] = []
var _shot_a := PackedByteArray()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# 이전 실행의 슬롯이 남아 거짓 실패를 내지 않게 지우고 시작한다 (docs/GOTCHAS.md).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))
	# 첫 씬은 여기서 올린다 — _process 가 current_scene 이 생길 때까지 기다리므로
	# 첫 단계를 _steps 에 넣어두면 영영 실행되지 않는다 (docs/GOTCHAS.md).
	_enter_world_with_seed(SEED_A)

	_steps = [
		_check_first_entry,
		_check_view_range,
		_check_spawn_is_land,
		func(): _look_at_coast(),
		_check_coast_shows_both,
		func(): _enter_world_with_seed(SEED_B),
		_check_other_seed_differs,
		func(): _enter_world_with_seed(SEED_A),
		_check_same_seed_repeats,
		_check_seed_saved_on_old_slot,
		func(): _overview_shot(),
		_check_back_button,
	]


func _process(_delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
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


func _check_back_button() -> void:
	var button := current_scene.get_node_or_null("HUD/Layout/BackButton") as Button
	if button == null:
		_fails.append("뒤로 버튼을 못 찾음")
		return
	button.emit_signal("pressed")
	_steps.append(_check_returned_to_slots)


func _check_returned_to_slots() -> void:
	if not _find_text("캐릭터 선택"):
		_fails.append("뒤로 버튼을 눌렀는데 슬롯 화면으로 안 갔다")
	_shoot("45_back_to_slots")


# --- 도구 -------------------------------------------------------------------

func _visible_world_rect() -> Rect2:
	return root.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, root.get_visible_rect().size)


func _nearest(color: Color) -> String:
	var to_land := Vector3(color.r - COLOR_LAND.r, color.g - COLOR_LAND.g, color.b - COLOR_LAND.b).length()
	var to_sea := Vector3(color.r - COLOR_SEA.r, color.g - COLOR_SEA.g, color.b - COLOR_SEA.b).length()
	if minf(to_land, to_sea) > 0.12:
		return "그 외"  # HUD/플레이어처럼 지형이 아닌 것.
	return "land" if to_land < to_sea else "sea"


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
