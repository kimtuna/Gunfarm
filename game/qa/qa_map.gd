extends SceneTree

## INBOX #18 자체 QA — M 으로 여는 전체 맵과 "가본 곳" 기록.
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_map.gd
##
## 확인하는 것:
##   1) 기록 코어(`explored_map.gd`) — 처음엔 비어 있고, 반경만큼만 적히고, base64 로
##      저장했다 불러오면 비트가 그대로다. 깨진 문자열은 빈 지도로 떨어진다.
##   2) M 으로 지도가 열리고 다시 M 으로 닫힌다. **지도가 열려 있을 때 Esc 는 일시정지
##      메뉴가 아니라 지도 닫기다** (가장 안쪽 창부터 — docs/DESIGN.md 「맵 (M)」).
##   3) **안 가본 곳은 실제로 화면에 안 보인다** — 캡처의 픽셀로 판정한다.
##   4) 보이는 칸의 지형이 같은 시드의 월드와 일치한다(땅/바다).
##   5) 돌아다니면 채워진다.
##   6) **저장했다 불러와도 기록이 남는다** — 메인 메뉴로 나갔다 같은 슬롯으로 다시
##      들어와서 확인한다(슬롯 파일을 거치는 진짜 경로다).
##   7) **마우스 휠 줌**(docs/DESIGN.md 「맵 줌」) — 1/2/4/8배가 **화면 픽셀로 재서**
##      정말 그 배율인지, 확대하면 내가 화면 한가운데에 오는지, **지도 귀퉁이에서
##      지도 밖이 안 보이는지**, 배율을 바꿔도 안 가본 칸은 여전히 안 보이는지,
##      휠이 지도 뒤로 새지 않는지, 닫았다 열어도 배율이 남는지.

const SettingsStore := preload("res://scripts/settings_store.gd")
const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const ExploredMap := preload("res://scripts/explored_map.gd")
const MapCanvas := preload("res://scripts/map_canvas.gd")
const TerrainPalettes := preload("res://scripts/terrain_palettes.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260907

## 프레임 수가 아니라 **시간**으로 기다린다 (docs/GOTCHAS.md) — 이 창은 수직동기화가
## 없어서 몇 프레임이 몇 ms 밖에 안 되고, 그러면 고정 틱(1/60초)이 한 번도 안 돈다.
const SETTLE_SECONDS := 0.35

const PAUSE := "HUD/PauseMenu"
const PAUSE_BOX := "HUD/PauseMenu/Box/BoxLayout"

## 화면 픽셀을 색으로 판정할 때의 허용 오차.
const COLOR_EPSILON := 0.02

## 줌 검사에서 지도 밖이 보이는지 확인할 네 귀퉁이(테두리는 언제나 바다다).
const CORNER_TILES: Array[Vector2i] = [Vector2i(1, 1), Vector2i(254, 1),
		Vector2i(1, 254), Vector2i(254, 254)]

## 줌 검사 동안 화살표가 가리킬 방향(위). 픽셀로 크기를 잴 때 **가로로 훑는 자리에
## 화살표가 끼어들지 않게** 세로로 세워둔다.
const ZOOM_AIM_ANGLE := -PI * 0.5

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

## 멀리 다녀온 뒤에 "저장했다 불러와도 남는지" 볼 칸, 그리고 끝까지 안 가본 대조 칸.
var _far_tile := Vector2i(-1, -1)
var _never_tile := Vector2i(-1, -1)
var _count_before_exit := 0

## 줌 검사를 서서 할 자리(지도 한가운데 근처)와 휠 감시자.
var _center_tile := Vector2i(-1, -1)
var _spy: Node = null


## 지도가 먹어야 할 휠이 **그 뒤로 새어 나가는지** 보는 감시자 (docs/DESIGN.md 「맵 줌」의
## "휠 입력이 다른 곳으로 새지 않게"). 나중에 핫바 스크롤이 붙을 자리를 미리 흉내낸다.
class WheelSpy extends Node:
	var seen := 0

	func _unhandled_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button == null:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP \
				or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			seen += 1


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))

	_check_core()

	_enter_world()
	_steps = [
		_settle,
		_check_map_closed_at_start,
		_press_map_key,
		_check_map_opens,
		_check_unexplored_is_hidden,
		_check_marker_points_at_aim,
		_press_escape,
		_check_escape_closes_map_not_into_pause,
		_press_map_key,
		_press_map_key,
		_check_map_closed_by_m,
		func(): _walk_far(),
		_settle,
		_press_map_key,
		_check_walking_fills_map,
		# 지형 대조는 **멀리 간 뒤에** 한다 — 스폰 주변에는 이제 화살표가 없어서
		# 기록된 칸을 가리지 않는다.
		_check_visible_terrain_matches_world,
		_press_map_key,
		func(): _press(PAUSE_BOX + "/ExitButton"),
		_check_left_to_main_menu,
		func(): change_scene_to_file(WORLD_SCENE),
		_settle,
		_check_record_survives_save_load,
		_press_map_key,
		_check_reloaded_map_draws,
	]
	_steps.append_array(_zoom_steps())


## 7) 줌. 여기 들어올 때 지도는 열려 있고 배율은 아직 기본(2배)이다.
func _zoom_steps() -> Array[Callable]:
	var steps: Array[Callable] = [
		_check_zoom_default,
		_stand_at_center,
		_settle,
		_add_wheel_spy,
		func(): _wheel(-1),                       # 2 → 1
		func(): _check_zoom(1, "54_zoom_1x"),
		_check_wheel_did_not_leak,
		func(): _wheel(-1),                       # 1 에서 더 내려도 1
		func(): _check_zoom_clamped(1, "가장 작은"),
		func(): _wheel(1),                        # 1 → 2
		func(): _check_zoom(2, "55_zoom_2x"),
		func(): _wheel(1),                        # 2 → 4
		func(): _check_zoom(4, "56_zoom_4x"),
		func(): _wheel(1),                        # 4 → 8
		func(): _check_zoom(8, "57_zoom_8x"),
		func(): _wheel(1),                        # 8 에서 더 올려도 8
		func(): _check_zoom_clamped(8, "가장 큰"),
		_press_map_key,                           # 닫고
		func(): _wheel(-1),                       # 닫힌 채로 휠을 돌려본다
		_check_wheel_only_while_map_open,
		_press_map_key,                           # 다시 열기
		_settle,
		_check_zoom_kept_after_reopen,
	]
	# 네 귀퉁이 — 가장 확대한 8배에서 지도 밖이 한 점도 안 보여야 한다.
	for index in CORNER_TILES.size():
		steps.append(func(): _stand_at_corner(index))
		steps.append(_settle)
		steps.append(func(): _check_corner_stays_inside(index))
	return steps


func _process(delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
	if _resize_window_if_needed():
		return false
	if _wait_time > 0.0:
		_wait_time -= delta
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size():
		if _fails.is_empty():
			print("[qa] PASS — 전체 맵 / 탐험 기록 정상")
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


# --- 1) 기록 코어 -------------------------------------------------------------

func _check_core() -> void:
	var map := ExploredMap.new()
	if map.bits.size() != ExploredMap.BYTES or ExploredMap.BYTES != 8192:
		_fails.append("비트 배열이 %d바이트다 — 256×256 타일 ÷ 8 = 8192여야 한다" % map.bits.size())
	if not map.is_empty() or map.explored_count() != 0:
		_fails.append("새로 만든 기록이 비어 있지 않다")

	var center := Vector2i(100, 120)
	var radius := 6
	var added := map.mark_around(center, radius)
	var expected := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				expected += 1
	if added != expected or map.explored_count() != expected:
		_fails.append("반경 %d 을 적었더니 %d칸(다시 세니 %d칸) — %d칸이어야 한다"
				% [radius, added, map.explored_count(), expected])
	if not map.is_explored(center.x, center.y) or not map.is_explored(center.x + radius, center.y):
		_fails.append("반경 안인데 안 적혔다")
	if map.is_explored(center.x + radius + 1, center.y) or map.is_explored(center.x + 5, center.y + 5):
		_fails.append("반경 밖인데 적혔다 — 원이 아니라 사각형으로 적고 있다")
	if map.mark_around(center, radius) != 0:
		_fails.append("같은 자리를 다시 적었는데 새 칸이 생겼다")

	# 저장 → 불러오기 왕복. 실제로 슬롯 파일(JSON)에 들어갈 문자열 그대로다.
	var encoded := map.to_base64()
	print("[qa] %d칸 기록 = base64 %d자 (원본 %d바이트)" % [expected, encoded.length(), ExploredMap.BYTES])
	var loaded := ExploredMap.new()
	if not loaded.load_base64(encoded) or loaded.bits != map.bits:
		_fails.append("base64 로 저장했다 불러왔더니 비트가 달라졌다")

	# 전부 탐험한 최악의 경우에도 슬롯 파일이 감당할 크기여야 한다.
	var full := ExploredMap.new()
	full.mark_around(Vector2i(128, 128), 400)
	print("[qa] 전부 탐험 = base64 %d자" % full.to_base64().length())

	print("[qa] 아래 두 줄의 압축 해제 에러는 일부러 깨뜨린 입력이다 (실패가 아니다)")
	var broken := ExploredMap.new()
	if broken.load_base64("") or broken.load_base64("이건base64가아니다!!") or not broken.is_empty():
		_fails.append("깨진 저장 문자열을 읽고도 성공이라고 답했다 — 빈 지도로 떨어져야 한다")


# --- 2) 열기 / 닫기 -----------------------------------------------------------

func _check_map_closed_at_start() -> void:
	if _map() != null:
		_fails.append("월드에 들어오자마자 지도가 열려 있다")


func _check_map_opens() -> void:
	var map := _map()
	if map == null:
		_fails.append("M 을 눌렀는데 지도가 안 열렸다")
		return
	if _world() == null:
		_fails.append("지도를 열었더니 월드 씬이 통째로 바뀌었다 — 겹쳐서 띄워야 한다")
	if paused:
		_fails.append("지도를 열면서 get_tree().paused 로 세계를 세웠다")
	var player := _player()
	if player != null and player.input_enabled:
		_fails.append("지도가 열려 있는데 플레이어 입력이 살아 있다")
	_shoot("50_map_open")


## 지도가 열려 있을 때 Esc 는 **일시정지 메뉴가 아니라 지도 닫기**다.
func _check_escape_closes_map_not_into_pause() -> void:
	if _map() != null:
		_fails.append("지도가 열린 채로 Esc 를 눌렀는데 안 닫혔다")
	var menu := current_scene.get_node_or_null(PAUSE) as Control
	if menu != null and menu.visible:
		_fails.append("지도를 Esc 로 닫았는데 일시정지 메뉴까지 열렸다 — 가장 안쪽 창 하나만 닫아야 한다")
	var player := _player()
	if player != null and not player.input_enabled:
		_fails.append("지도를 닫았는데 플레이어 입력이 안 돌아왔다")


func _check_map_closed_by_m() -> void:
	if _map() != null:
		_fails.append("M 을 한 번 더 눌렀는데 지도가 안 닫혔다")


# --- 3~4) 화면에 무엇이 보이는가 ------------------------------------------------

## 안 가본 곳은 지형색이 아니라 "안 가봄" 색이어야 한다. 지도 네 귀퉁이(테두리 4칸은
## 언제나 바다이고 스폰에서 멀다)와 스폰 반대편을 본다.
func _check_unexplored_is_hidden() -> void:
	var image := _capture()
	if image == null:
		return
	var world := _world()
	var spawn: Vector2i = world.spawn_tile
	var samples: Array[Vector2i] = [Vector2i(2, 2), Vector2i(253, 2), Vector2i(2, 253),
			Vector2i(253, 253), spawn + Vector2i(40, 40), spawn - Vector2i(40, 40)]
	for tile in samples:
		if _explored().is_explored(tile.x, tile.y):
			_fails.append("아직 안 가본 칸 %s 가 기록에 적혀 있다" % tile)
			continue
		var color := _map_pixel(image, tile)
		if not _is_color(color, MapCanvas.UNEXPLORED_COLOR):
			_fails.append("안 가본 칸 %s 가 지도에 %s 로 그려졌다 — 안 보여야 한다" % [tile, color])


## 보이는 칸의 지형은 같은 시드의 월드와 일치해야 한다(기록에는 지형이 없고 시드로
## 다시 계산해서 그린다 — docs/DESIGN.md 「맵 (M)」).
func _check_visible_terrain_matches_world() -> void:
	var image := _capture()
	if image == null:
		return
	var world := _world()
	var explored: RefCounted = _explored()
	var seen := 0
	var checked := 0
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var tile: Vector2i = world.spawn_tile + Vector2i(dx, dy)
			if not explored.is_explored(tile.x, tile.y):
				continue
			seen += 1
			checked += 1
			var want := "land" if world.is_land(tile.x, tile.y) else "sea"
			var got := _terrain_of(_map_pixel(image, tile))
			if got != want:
				_fails.append("지도의 %s 가 %s 로 그려졌다 — 월드는 %s 다" % [tile, got, want])
	print("[qa] 스폰 주변 기록된 칸 %d개 중 %d개의 지형을 화면에서 대조" % [seen, checked])
	if checked < 60:
		_fails.append("대조한 칸이 %d개뿐이다 — 기록이 거의 안 채워졌다" % checked)


## 위치 점이 아니라 **조준 방향을 가리키는 화살표**여야 한다 (docs/DESIGN.md 「맵 (M)」).
## 조준을 위로 돌려놓고, 화살표 픽셀이 위쪽에 더 많은지 본다.
func _check_marker_points_at_aim() -> void:
	var player := _player()
	if player == null or player.motion == null:
		_fails.append("플레이어를 못 찾아 화살표를 못 본다")
		return
	player.motion.aim_angle = -PI * 0.5  # 위쪽
	_steps.insert(_step, _check_marker_shape)
	_wait_time = SETTLE_SECONDS


func _check_marker_shape() -> void:
	var image := _capture()
	if image == null:
		return
	var canvas := _canvas()
	var at := _to_pixels(canvas.get_global_transform()
			* canvas.map_position(_player().global_position))
	var up := 0
	var down := 0
	for dy in range(-16, 17):
		for dx in range(-16, 17):
			var point := Vector2i(at) + Vector2i(dx, dy)
			if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(point):
				continue
			if not _is_color(image.get_pixelv(point), MapCanvas.MARKER_COLOR):
				continue
			if dy < 0:
				up += 1
			elif dy > 0:
				down += 1
	print("[qa] 내 위치 화살표 픽셀: 위 %d / 아래 %d (조준은 위쪽)" % [up, down])
	if up + down == 0:
		_fails.append("지도에 내 위치 화살표가 안 보인다")
	elif up <= down:
		_fails.append("조준은 위쪽인데 화살표가 위 %d / 아래 %d 다 — 방향을 안 가리킨다" % [up, down])
	_shoot("51_map_marker_up")


# --- 5) 돌아다니면 채워진다 ----------------------------------------------------

## 스폰에서 멀리 떨어진 육지로 옮긴다(카메라와 기록이 따라간다). 옮긴 칸은 나중에
## "저장했다 불러와도 남는지" 볼 표식이 된다.
func _walk_far() -> void:
	var world := _world()
	var spawn: Vector2i = world.spawn_tile
	var best := Vector2i(-1, -1)
	var best_distance := 0.0
	for y in range(8, WorldGen.MAP_TILES - 8, 3):
		for x in range(8, WorldGen.MAP_TILES - 8, 3):
			if not world.is_land(x, y):
				continue
			var distance: float = Vector2(Vector2i(x, y) - spawn).length()
			if distance > best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	if best.x < 0:
		_fails.append("멀리 갈 육지 칸을 못 찾았다")
		return
	_far_tile = best
	var explored: RefCounted = _explored()
	_count_before_exit = explored.explored_count()
	_player().place_at(WorldGen.tile_center(best))
	# 끝까지 안 가볼 대조 칸 — 스폰에서도 방금 옮긴 자리에서도 기록 반경(6칸) 밖으로
	# 한참 떨어진, 지금 시점에 아직 안 적힌 칸.
	_never_tile = Vector2i(-1, -1)
	for y in range(6, WorldGen.MAP_TILES - 6, 5):
		for x in range(6, WorldGen.MAP_TILES - 6, 5):
			var tile := Vector2i(x, y)
			if explored.is_explored(x, y):
				continue
			if Vector2(tile - best).length() < 30.0 or Vector2(tile - spawn).length() < 30.0:
				continue
			_never_tile = tile
			break
		if _never_tile.x >= 0:
			break
	if _never_tile.x < 0:
		_fails.append("대조용으로 쓸 '안 가본 칸' 을 못 찾았다")
	print("[qa] 스폰 %s → 먼 육지 %s (%.0f칸), 대조 칸 %s" % [spawn, best, best_distance, _never_tile])


func _check_walking_fills_map() -> void:
	var explored: RefCounted = _explored()
	var count: int = explored.explored_count()
	print("[qa] 이동 전 %d칸 → 이동 후 %d칸" % [_count_before_exit, count])
	if count <= _count_before_exit:
		_fails.append("멀리 이동했는데 기록이 안 늘었다 (%d → %d)" % [_count_before_exit, count])
	if not explored.is_explored(_far_tile.x, _far_tile.y):
		_fails.append("서 있는 칸 %s 가 기록에 없다" % _far_tile)
	# 새로 채워진 자리가 실제로 화면에 그려졌는지 본다. **서 있는 칸 자체는 화살표가
	# 덮으므로** 한 칸만 보면 안 된다 — 주변 기록된 칸을 세어서 대부분이 지형으로
	# 그려졌는지, 그리고 그려진 것이 월드와 맞는지 함께 본다.
	var image := _capture()
	if image == null:
		return
	var world := _world()
	var drawn := 0
	var total := 0
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var tile: Vector2i = _far_tile + Vector2i(dx, dy)
			if not explored.is_explored(tile.x, tile.y):
				continue
			total += 1
			var got := _terrain_of(_map_pixel(image, tile))
			if got == "그 외":
				continue  # 화살표가 덮은 칸.
			drawn += 1
			var want := "land" if world.is_land(tile.x, tile.y) else "sea"
			if got != want:
				_fails.append("새로 다녀온 %s 가 %s 로 그려졌다 — 월드는 %s 다" % [tile, got, want])
	print("[qa] 새로 다녀온 자리 기록 %d칸 중 %d칸이 지도에 그려졌다 (나머지는 화살표가 덮은 칸)"
			% [total, drawn])
	if drawn < total / 2:
		_fails.append("새로 다녀온 자리 %d칸 중 %d칸만 지도에 그려졌다" % [total, drawn])
	_count_before_exit = count
	_shoot("52_map_after_walk")


# --- 6) 저장 / 불러오기 --------------------------------------------------------

func _check_left_to_main_menu() -> void:
	if not _find_text("GUNFARM"):
		_fails.append("메인 메뉴로 못 나갔다 — 저장 경로를 확인할 수 없다")
	var encoded := SlotStore.explored_of(SlotStore.load_slots()[0])
	if encoded.is_empty():
		_fails.append("월드를 나갔는데 슬롯에 탐험 기록이 저장되지 않았다")


func _check_record_survives_save_load() -> void:
	var explored: RefCounted = _explored()
	if explored == null:
		_fails.append("다시 들어온 월드에 탐험 기록이 없다")
		return
	if not explored.is_explored(_far_tile.x, _far_tile.y):
		_fails.append("나갔다 다시 들어왔더니 다녀온 칸 %s 의 기록이 사라졌다" % _far_tile)
	if explored.is_explored(_never_tile.x, _never_tile.y):
		_fails.append("한 번도 안 간 칸 %s 이 기록에 있다 — 저장이 통째로 채워졌다" % _never_tile)
	var count: int = explored.explored_count()
	print("[qa] 나가기 전 %d칸 → 다시 들어와서 %d칸" % [_count_before_exit, count])
	if count < _count_before_exit:
		_fails.append("다시 들어왔더니 기록이 %d → %d 로 줄었다" % [_count_before_exit, count])


func _check_reloaded_map_draws() -> void:
	var image := _capture()
	if image == null:
		return
	if _terrain_of(_map_pixel(image, _far_tile)) == "그 외":
		_fails.append("불러온 기록의 칸 %s 이 지도에 안 그려졌다" % _far_tile)
	if not _is_color(_map_pixel(image, _never_tile), MapCanvas.UNEXPLORED_COLOR):
		_fails.append("한 번도 안 간 칸 %s 이 지도에 보인다" % _never_tile)
	_shoot("53_map_after_reload")


# --- 7) 줌 (docs/DESIGN.md 「맵 줌 (마우스 휠)」) -------------------------------
#
# **판정을 API 값에만 기대지 않는다** — `map_rect()` 가 뭘 돌려주든 실제로 칠해진
# 화면 픽셀을 재서 1/2/4/8배인지 본다. 그래서 줌 검사는 지도 한가운데 근처의
# **아직 아무것도 안 적힌 육지**에 서서 한다: 기록 반경이 지도 위에 지름 13칸짜리
# 동그라미 하나로 홀로 찍혀서, 그 동그라미의 픽셀 크기가 곧 배율이 된다.

func _check_zoom_default() -> void:
	var canvas := _canvas()
	if canvas == null:
		_fails.append("줌 검사를 시작하는데 지도가 닫혀 있다")
		return
	if canvas.zoom_scale() != 2:
		_fails.append("지도를 열었을 때 배율이 %d배다 — 기본은 2배여야 한다" % canvas.zoom_scale())


## 지도 한가운데 근처의 육지 중 **주변에 이미 적힌 칸이 하나도 없는** 자리로 옮긴다.
func _stand_at_center() -> void:
	var world := _world()
	var center := Vector2i(WorldGen.MAP_TILES / 2, WorldGen.MAP_TILES / 2)
	var candidates: Array[Vector2i] = []
	for y in range(center.y - 40, center.y + 41):
		for x in range(center.x - 40, center.x + 41):
			if world.is_land(x, y):
				candidates.append(Vector2i(x, y))
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - center).length_squared() < Vector2(b - center).length_squared())
	var clear := _explore_radius() + 3
	for tile in candidates:
		if _is_untouched(tile, clear):
			_center_tile = tile
			break
	if _center_tile.x < 0:
		_fails.append("지도 한가운데 근처에서 '아직 아무것도 안 적힌 육지'를 못 찾았다")
		return
	print("[qa] 줌 검사 자리 %s (한가운데에서 %.0f칸)"
			% [_center_tile, Vector2(_center_tile - center).length()])
	_stand_at(_center_tile)


func _is_untouched(tile: Vector2i, radius: int) -> bool:
	var explored: RefCounted = _explored()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if explored.is_explored(tile.x + dx, tile.y + dy):
				return false
	return true


## 그 칸으로 옮기고 조준을 위로 세운다. 지도가 열려 있는 동안은 플레이어 입력이 끊겨
## 있어서(`input_enabled`) 여기 넣은 각도가 마우스에 덮이지 않는다.
func _stand_at(tile: Vector2i) -> void:
	var player := _player()
	if player == null:
		_fails.append("플레이어를 못 찾아 %s 로 못 옮긴다" % tile)
		return
	player.place_at(WorldGen.tile_center(tile))
	if player.motion != null:
		player.motion.aim_angle = ZOOM_AIM_ANGLE


## `world.gd` 의 기록 반경. 같은 숫자를 여기 또 적지 않으려고 스크립트에서 직접 읽는다.
func _explore_radius() -> int:
	return int(current_scene.get_script().get_script_constant_map()
			.get("EXPLORE_RADIUS_TILES", 6))


func _add_wheel_spy() -> void:
	_spy = WheelSpy.new()
	_spy.name = "WheelSpy"
	current_scene.add_child(_spy)


## 마우스 휠 한 칸을 **실제 입력 경로로** 흘려보낸다 — 지도의 `_input` 이 이걸 받는다.
func _wheel(steps: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if steps > 0 else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = _to_window(root.get_visible_rect().get_center())
	Input.parse_input_event(event)


## 한 배율에서 볼 것을 한 번에 본다.
func _check_zoom(zoom: int, shot_name: String) -> void:
	var canvas := _canvas()
	if canvas == null:
		_fails.append("%d배 검사 중인데 지도가 닫혀 있다" % zoom)
		return
	if canvas.zoom_scale() != zoom:
		_fails.append("휠을 돌렸더니 %d배다 — %d배여야 한다" % [canvas.zoom_scale(), zoom])
		return
	var rect: Rect2 = canvas.map_rect()
	var want := float(WorldGen.MAP_TILES * zoom)
	if not is_equal_approx(rect.size.x, want) or not is_equal_approx(rect.size.y, want):
		_fails.append("%d배인데 지도를 %s 크기로 그린다 — %.0f×%.0f 여야 한다"
				% [zoom, rect.size, want, want])
	var image := _capture()
	if image == null:
		return
	_check_map_edge_not_shown(image, zoom)
	_check_map_stays_in_window(image, zoom)
	_check_drawn_scale_in_pixels(image, zoom)
	_check_tiles_at_zoom(image, zoom)
	_check_player_centered(canvas, zoom)
	_shoot(shot_name)


func _check_zoom_clamped(zoom: int, label: String) -> void:
	var canvas := _canvas()
	if canvas != null and canvas.zoom_scale() != zoom:
		_fails.append("%s 배율(%d배)에서 휠을 더 돌렸더니 %d배가 됐다"
				% [label, zoom, canvas.zoom_scale()])


## **확대한 상태에서는 지도 밖(여백색)이 한 점도 보이면 안 된다** — 가장자리에서 중심을
## 안쪽으로 물리고 있다는 뜻이다. 1배는 반대로 지도(256px)가 창(512px)보다 작아서
## 여백이 보이는 게 맞다.
func _check_map_edge_not_shown(image: Image, zoom: int) -> void:
	var rect := _canvas().get_global_rect()
	var outside := 0
	var samples := 0
	for iy in 33:
		for ix in 33:
			var point := rect.position + Vector2(
					lerpf(1.0, rect.size.x - 1.0, ix / 32.0),
					lerpf(1.0, rect.size.y - 1.0, iy / 32.0))
			samples += 1
			if _is_color(_pixel(image, point), MapCanvas.BACKDROP_COLOR):
				outside += 1
	if zoom == 1:
		if outside == 0:
			_fails.append("1배인데 지도 밖 여백이 한 점도 안 보인다 — 지도가 창을 꽉 채우고 있다")
	elif outside > 0:
		_fails.append("%d배에서 짚어본 %d자리 중 %d자리가 지도 밖이다 — 지도 밖이 보이면 안 된다"
				% [zoom, samples, outside])


## **확대한 지도가 자기 창 밖으로 넘쳐 그려지면 안 된다.** Control 은 `_draw` 가 자기
## 사각형을 벗어나도 잘라주지 않아서, 8배(2048px)면 지도가 창틀·제목·월드 화면까지
## 통째로 덮어버린다. 창 바로 바깥(지도 상자 안쪽 여백)을 짚어서 지도 색이 나오는지 본다.
func _check_map_stays_in_window(image: Image, zoom: int) -> void:
	var rect := _canvas().get_global_rect()
	var spilled := 0
	for i in 17:
		var along := lerpf(2.0, rect.size.x - 2.0, i / 16.0)
		var down := lerpf(2.0, rect.size.y - 2.0, i / 16.0)
		for point: Vector2 in [
			Vector2(rect.position.x + along, rect.position.y - 5.0),
			Vector2(rect.position.x + along, rect.end.y + 5.0),
			Vector2(rect.position.x - 8.0, rect.position.y + down),
			Vector2(rect.end.x + 8.0, rect.position.y + down),
		]:
			var color := _pixel(image, point)
			if _is_color(color, MapCanvas.UNEXPLORED_COLOR) \
					or _is_color(color, MapCanvas.BACKDROP_COLOR):
				spilled += 1
	if spilled > 0:
		_fails.append("%d배에서 지도가 자기 창 밖으로 %d자리나 넘쳐 그려졌다 (clip_contents 확인)"
				% [zoom, spilled])


## **배율을 화면 픽셀로 잰다.**
##  - 1배: 지도가 창보다 작으니 여백과의 경계까지 재면 지도 가로폭이 그대로 나온다.
##  - 2배 이상: 창이 꽉 차서 경계가 없다. 대신 홀로 찍힌 방문 동그라미의 **세로 길이**를
##    잰다 — 화살표에 안 걸리게 중심에서 10px 이상 옆으로 비킨 세로줄에서 잰다.
func _check_drawn_scale_in_pixels(image: Image, zoom: int) -> void:
	var rect := _canvas().get_global_rect()
	if zoom == 1:
		var left := -1.0
		var right := -1.0
		var y := rect.get_center().y
		for i in int(rect.size.x):
			var x := rect.position.x + i + 0.5
			# **지도 그림인 픽셀**만 센다 — 여백도, 가장자리 선도 지도 넓이가 아니다.
			if not _is_map_content(_pixel(image, Vector2(x, y))):
				continue
			if left < 0.0:
				left = x
			right = x
		var got := right - left + 1.0
		print("[qa] 1배 — 지도 가로폭이 화면에서 %.0f (논리px), %d칸이어야 한다"
				% [got, WorldGen.MAP_TILES])
		if absf(got - float(WorldGen.MAP_TILES)) > 3.0:
			_fails.append("1배인데 지도 가로폭이 %.0f px 다 — %d px 여야 한다"
					% [got, WorldGen.MAP_TILES])
		return
	if _center_tile.x < 0:
		return
	var radius := _explore_radius()
	var offset := int(ceilf(10.0 / float(zoom)))  # 화살표(반폭 8px)를 확실히 비켜난 칸 수.
	var half := floori(sqrt(float(radius * radius - offset * offset)))
	var column := _tile_point(_center_tile + Vector2i(offset, 0))
	var top := column.y
	var bottom := column.y
	for i in range(1, int(rect.size.y)):
		var point := Vector2(column.x, column.y - i)
		if not rect.has_point(point) or _is_hidden(_pixel(image, point)):
			break
		top = point.y
	for i in range(1, int(rect.size.y)):
		var point := Vector2(column.x, column.y + i)
		if not rect.has_point(point) or _is_hidden(_pixel(image, point)):
			break
		bottom = point.y
	var got := bottom - top + 1.0
	var want := float((2 * half + 1) * zoom)
	print("[qa] %d배 — 방문 동그라미의 세로 길이가 화면에서 %.0f (논리px), %.0f 여야 한다"
			% [zoom, got, want])
	if absf(got - want) > float(zoom) + 2.0:
		_fails.append("%d배인데 방문 자국이 화면에서 %.0f px 다 — %.0f px(%d칸 × %d배)여야 한다"
				% [zoom, got, want, 2 * half + 1, zoom])


## 배율이 바뀌어도 **안 가본 칸은 여전히 안 보이고**, 보이는 칸의 지형은 월드와 같다.
## 화살표가 덮는 자리는 건너뛴다.
func _check_tiles_at_zoom(image: Image, zoom: int) -> void:
	var canvas := _canvas()
	var world := _world()
	var explored: RefCounted = _explored()
	var marker := _screen_point(canvas.map_position(_player().global_position))
	var wrong_terrain := 0
	var leaked := 0
	var seen := 0
	var hidden := 0
	for ty in range(0, WorldGen.MAP_TILES, 2):
		for tx in range(0, WorldGen.MAP_TILES, 2):
			var tile := Vector2i(tx, ty)
			if not _tile_visible(tile):
				continue
			var point := _tile_point(tile)
			if point.distance_to(marker) < MapCanvas.MARKER_LENGTH + 3.0:
				continue
			var color := _pixel(image, point)
			if not explored.is_explored(tx, ty):
				hidden += 1
				if not _is_color(color, MapCanvas.UNEXPLORED_COLOR):
					leaked += 1
				continue
			var got := _terrain_of(color)
			if got == "그 외":
				continue
			seen += 1
			if got != ("land" if world.is_land(tx, ty) else "sea"):
				wrong_terrain += 1
	print("[qa] %d배 — 보이는 칸 대조: 기록된 %d칸(어긋남 %d) / 안 가본 %d칸(새어나온 것 %d)"
			% [zoom, seen, wrong_terrain, hidden, leaked])
	if leaked > 0:
		_fails.append("%d배에서 안 가본 칸 %d개가 지도에 보인다" % [zoom, leaked])
	if wrong_terrain > 0:
		_fails.append("%d배에서 %d칸의 지형이 월드와 다르게 그려졌다" % [zoom, wrong_terrain])
	if seen < 8 or hidden < 50:
		_fails.append("%d배에서 대조한 칸이 너무 적다 (기록 %d / 안 가봄 %d)" % [zoom, seen, hidden])


## 지도가 창보다 커지는 배율에서는 **내가 화면 한가운데**여야 한다(지도 가장자리가
## 아닐 때). 줌 검사 자리는 지도 한가운데라 물러날 일이 없다.
func _check_player_centered(canvas: Control, zoom: int) -> void:
	if float(WorldGen.MAP_TILES * zoom) <= canvas.size.x:
		return
	var at: Vector2 = canvas.map_position(_player().global_position)
	var center: Vector2 = canvas.size * 0.5
	if at.distance_to(center) > 2.0:
		_fails.append("%d배에서 내 위치가 창 %s 에 있다 — 한가운데(%s)여야 한다"
				% [zoom, at, center])


## 지도가 열려 있을 때의 휠은 지도가 먹는다 — 뒤로 새어 나가면 안 된다.
func _check_wheel_did_not_leak() -> void:
	if _spy != null and _spy.seen > 0:
		_fails.append("지도가 열려 있는데 휠 %d건이 지도 뒤까지 흘러갔다 — 지도가 소비해야 한다"
				% _spy.seen)


## 반대로 지도가 닫혀 있으면 휠은 그대로 뒤로 가고 배율도 안 바뀐다. 이걸 같이 봐야
## 위의 "안 샜다"가 **감시자가 고장 나서 통과한 것**이 아님을 알 수 있다.
func _check_wheel_only_while_map_open() -> void:
	if _map() != null:
		_fails.append("M 을 눌렀는데 지도가 안 닫혔다 (휠 범위 검사)")
		return
	if _spy == null:
		return
	if _spy.seen == 0:
		_fails.append("지도를 닫고 돌린 휠이 아무 데도 안 갔다 — 감시자가 고장 났거나 휠이 안 들어갔다")
	if MapCanvas.zoom_index != MapCanvas.ZOOM_STEPS.size() - 1:
		_fails.append("지도가 닫혀 있는데 휠이 배율을 %d배로 바꿨다"
				% MapCanvas.ZOOM_STEPS[MapCanvas.zoom_index])


## 닫았다 열어도 배율은 그대로다. 다만 **슬롯에 저장하지는 않는다**.
func _check_zoom_kept_after_reopen() -> void:
	var canvas := _canvas()
	if canvas == null:
		_fails.append("다시 M 을 눌렀는데 지도가 안 열렸다")
		return
	if canvas.zoom_scale() != 8:
		_fails.append("지도를 닫았다 열었더니 배율이 %d배로 돌아갔다 — 8배여야 한다"
				% canvas.zoom_scale())
	var slot: Dictionary = SlotStore.load_slots()[0]
	for key: String in slot.keys():
		if key.findn("zoom") != -1:
			_fails.append("슬롯 저장에 줌이 들어갔다 (`%s`) — 저장하지 않기로 했다" % key)
	_shoot("58_zoom_kept_after_reopen")


func _stand_at_corner(index: int) -> void:
	_stand_at(CORNER_TILES[index])


## 지도 귀퉁이에 서도 **지도 밖 빈 공간이 나오면 안 된다**.
func _check_corner_stays_inside(index: int) -> void:
	var canvas := _canvas()
	if canvas == null:
		_fails.append("귀퉁이 검사 중인데 지도가 닫혀 있다")
		return
	var tile: Vector2i = CORNER_TILES[index]
	var rect: Rect2 = canvas.map_rect()
	if rect.position.x > 0.0 or rect.position.y > 0.0 \
			or rect.end.x < canvas.size.x or rect.end.y < canvas.size.y:
		_fails.append("귀퉁이 %s 에서 지도(%s)가 창(%s)을 다 못 덮는다" % [tile, rect, canvas.size])
	var image := _capture()
	if image == null:
		return
	_check_map_edge_not_shown(image, canvas.zoom_scale())
	_check_map_stays_in_window(image, canvas.zoom_scale())
	_shoot("59_zoom_corner_%d" % index)


## 지도 그림(안 가본 칸 + 지형)인가 — 여백/가장자리 선/화살표는 아니다.
func _is_map_content(color: Color) -> bool:
	return _is_color(color, MapCanvas.UNEXPLORED_COLOR) or _terrain_of(color) != "그 외"


func _is_hidden(color: Color) -> bool:
	return _is_color(color, MapCanvas.UNEXPLORED_COLOR) \
			or _is_color(color, MapCanvas.BACKDROP_COLOR)


# --- 도구 ---------------------------------------------------------------------

func _enter_world() -> void:
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("탐험가", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)


func _world() -> RefCounted:
	return current_scene.get("world")


func _explored() -> RefCounted:
	return current_scene.get("explored")


func _player() -> Node2D:
	return current_scene.get_node_or_null("%Player") as Node2D


func _map() -> Control:
	return current_scene.get_node_or_null("HUD/MapScreen") as Control


func _canvas() -> Control:
	var map := _map()
	return null if map == null else map.get_node_or_null("Box/BoxLayout/Canvas") as Control


func _press(node_path: String) -> void:
	var button := current_scene.get_node_or_null(node_path) as Button
	if button == null:
		_fails.append("버튼을 못 찾음: %s (현재 씬 %s)" % [node_path, current_scene.name])
		return
	button.emit_signal("pressed")


func _press_escape() -> void:
	_send_action("ui_cancel")


func _press_map_key() -> void:
	_send_action("toggle_map")


func _send_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _settle() -> void:
	_wait_time = SETTLE_SECONDS


## 논리 좌표(1440×810) → 캡처 이미지의 픽셀. 창 크기가 달라도 맞게 옮긴다.
func _to_pixels(point: Vector2) -> Vector2:
	var logical := root.get_visible_rect().size
	var pixels := Vector2(root.get_texture().get_size())
	return point * (pixels / logical)


## 지도에서 그 타일이 그려진 픽셀 하나. **자리는 캔버스에게 물어본다** — 줌과 중심
## 이동이 거기 한 곳에 있으므로, 배율이 뭐든 이 함수 하나로 맞는 픽셀을 찍는다.
func _map_pixel(image: Image, tile: Vector2i) -> Color:
	var canvas := _canvas()
	if canvas == null:
		return Color.MAGENTA
	return _pixel(image, _tile_point(tile))


## 그 타일이 그려진 자리(논리 좌표, 화면 기준). 확대하면 창 밖일 수도 있다.
func _tile_point(tile: Vector2i) -> Vector2:
	return _screen_point(_canvas().map_position(WorldGen.tile_center(tile)))


## 지도 창 안의 좌표 → 화면(논리) 좌표.
func _screen_point(canvas_point: Vector2) -> Vector2:
	return _canvas().get_global_transform() * canvas_point


## 논리 좌표 한 점의 화면 픽셀.
func _pixel(image: Image, point: Vector2) -> Color:
	var at := Vector2i(_to_pixels(point))
	return image.get_pixelv(at.clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE))


## 그 타일이 지금 지도 창 안에 보이는가(확대하면 대부분은 창 밖이다).
func _tile_visible(tile: Vector2i) -> bool:
	var canvas := _canvas()
	if canvas == null:
		return false
	return canvas.get_global_rect().grow(-2.0).has_point(_tile_point(tile))


func _is_color(color: Color, want: Color) -> bool:
	return Vector3(color.r - want.r, color.g - want.g, color.b - want.b).length() <= COLOR_EPSILON


## 픽셀 하나가 땅인지 바다인지 — 지형 램프 전체와 견줘 가장 가까운 쪽
## (`qa_world_entry.gd` 와 같은 판정이다).
func _terrain_of(color: Color) -> String:
	var to_land := _distance_to(color, TerrainPalettes.LAND_MATERIALS)
	var to_sea := _distance_to(color, TerrainPalettes.SEA_MATERIALS)
	if minf(to_land, to_sea) > COLOR_EPSILON:
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


func _shoot(shot_name: String) -> void:
	var image := _capture()
	if image == null:
		return
	var path := "%s/%s.png" % [SHOTS, shot_name]
	image.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _find_text(expect_text: String) -> bool:
	for label in current_scene.find_children("*", "Label", true, false):
		if (label as Label).text.findn(expect_text) != -1:
			return true
	return false

## 논리 좌표 → 창 픽셀. `Input.warp_mouse` 와 `parse_input_event` 는 OS 가 주는 것과 같은
## **창 픽셀**을 받는데, 우리가 재는 자리(Control 의 global_rect, 카메라 변환 결과)는 전부
## **논리 좌표**다. 논리 해상도(1440x810)와 창 크기가 갈린 2026-09-08 부터 둘이 다르다 —
## 그 전에는 값이 같아서 이 변환 없이도 통했다. `get_screen_transform()` 이 stretch 배율과
## (비율이 안 맞는 창의) 검은 여백 오프셋까지 함께 처리한다.
func _to_window(point: Vector2) -> Vector2:
	return root.get_screen_transform() * point

## 창을 논리 해상도와 같게 **유지**한다. 메인 메뉴(`main_menu.gd`)는 뜰 때마다
## `SettingsStore.apply_saved()` 로 창을 저장된 해상도(기본 1280x720)로 되돌리는데,
## 그러면 배율이 0.888 이 되어 화면 픽셀을 짚는 검사가 downscale 뭉개짐으로 거짓 실패한다
## (2026-09-08, INBOX #48 — 논리 해상도 1440x810 과 기본 창 크기가 갈렸다).
##
## **되돌린 프레임에는 단계를 돌리지 않고 몇 프레임 쉰다**(true 를 돌려준다) — 크기 변경이
## 화면에 반영되기 전에 마우스를 밀면 좌표가 어긋나서 오히려 새 거짓 실패가 난다.
func _resize_window_if_needed() -> bool:
	if DisplayServer.window_get_size() == SettingsStore.BASE_SIZE:
		return false
	DisplayServer.window_set_size(SettingsStore.BASE_SIZE)
	# **프레임 수가 아니라 초로 센다** — 수직동기화가 꺼진 창은 몇 프레임이 몇 ms 밖에
	# 안 돼서 "8프레임 대기"가 사실상 대기가 아니다 (docs/GOTCHAS.md).
	_wait_time = SETTLE_SECONDS
	return true
