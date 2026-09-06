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

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

## 멀리 다녀온 뒤에 "저장했다 불러와도 남는지" 볼 칸, 그리고 끝까지 안 가본 대조 칸.
var _far_tile := Vector2i(-1, -1)
var _never_tile := Vector2i(-1, -1)
var _count_before_exit := 0


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


## 논리 좌표(1280×720) → 캡처 이미지의 픽셀. 창 크기가 달라도 맞게 옮긴다.
func _to_pixels(point: Vector2) -> Vector2:
	var logical := root.get_visible_rect().size
	var pixels := Vector2(root.get_texture().get_size())
	return point * (pixels / logical)


## 지도에서 그 타일이 그려진 픽셀 하나.
func _map_pixel(image: Image, tile: Vector2i) -> Color:
	var canvas := _canvas()
	if canvas == null:
		return Color.MAGENTA
	var rect := canvas.get_global_rect()
	var per_tile := rect.size / float(WorldGen.MAP_TILES)
	var point := _to_pixels(rect.position + (Vector2(tile) + Vector2(0.5, 0.5)) * per_tile)
	return image.get_pixelv(Vector2i(point).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE))


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
