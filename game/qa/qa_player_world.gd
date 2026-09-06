extends SceneTree

## INBOX #10 자체 QA — 월드에 실제로 서 있는 플레이어(WASD 이동 / 카메라 추적 / 바다 충돌).
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_player_world.gd
##
## 확인하는 것:
##   A. 이동 코어(scripts/player_motion.gd) — 씬 없이 순수 클래스만으로:
##      1) 같은 입력이면 항상 같은 결과다(서버가 같은 코드로 재현할 수 있어야 한다).
##      2) 속도 상한 — 한 틱에 `MAX_STEP` 보다 멀리 못 간다. 대각선이 더 빠르지 않다.
##      3) 바다에 못 들어간다. 물가에 닿으면 **틈 없이 붙어서** 멈춘다.
##      4) 벽을 비스듬히 밀면 미끄러진다(막힌 축만 멈추고 나머지 축은 간다).
##      5) 한 틱 이동량이 타일보다 훨씬 작다 — 바다 한 칸을 통째로 건너뛸 수 없다.
##   B. 월드 화면 — 실제 씬에서:
##      6) 스폰 칸에 플레이어가 서 있고 카메라가 그 위에 있다.
##      7) 발밑이 노드 원점이다(스프라이트가 땅에 서 있지, 공중에 뜨거나 파묻히지 않는다).
##      8) WASD 를 누르면 그 방향으로 움직이고 **카메라가 따라온다**.
##      9) 방향에 맞는 애니메이션으로 바뀐다 (움직이면 `walk_<방향>`).
##
## 눈으로 볼 몫은 `user://qa_shots/` 에 캡처로 남긴다.

const WorldGen := preload("res://scripts/world_gen.gd")
const PlayerMotion := preload("res://scripts/player_motion.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")
const SlotStore := preload("res://scripts/slot_store.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260906

## 키를 몇 **초** 누르고 있는가. 프레임 수로 세면 안 된다 — 이 창은 수직동기화가 없어서
## 20프레임이 20ms 밖에 안 될 수도 있고, 그러면 고정 틱이 한 번도 안 돌아 "안 움직였다"고
## 나온다. 0.3초면 60Hz 틱이 확실히 여러 번 돈다.
const HOLD_SECONDS := 0.35

## 물가에 얼마나 바짝 붙어야 하는가(월드 단위 = 화면 픽셀). 1px 이면 눈에 안 보인다.
const MAX_SHORE_GAP := 1.0

var _fails: Array[String] = []
var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _world: RefCounted = null
var _before := Vector2.ZERO


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	_world = WorldGen.new()
	_world.build(SEED)

	# --- A. 이동 코어 (화면이 필요 없다) ---
	_check_determinism()
	_check_speed_limit()
	_check_step_smaller_than_tile()
	_check_sea_blocks()
	_check_wall_slide()

	# 첫 씬은 여기서 올린다 (docs/GOTCHAS.md — _steps 에 넣으면 영영 실행되지 않는다).
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("걷는사람", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)

	# --- B. 월드 화면 ---
	_steps = [
		_check_spawned,
		_check_feet_on_origin,
		func(): _shoot("50_player_spawn"),
		func(): _press("move_right"),
		func(): _expect_moved("move_right", Vector2(1, 0), "right"),
		func(): _press("move_up"),
		func(): _expect_moved("move_up", Vector2(0, -1), "up"),
		func(): _press("move_left"),
		func(): _expect_moved("move_left", Vector2(-1, 0), "left"),
		func(): _press("move_down"),
		func(): _expect_moved("move_down", Vector2(0, 1), "down"),
		_walk_into_the_sea,
		_check_stopped_on_land,
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
		return _report()
	var step: Callable = _steps[_step]
	_step += 1
	_wait = 3
	step.call()
	return false


# --- A. 이동 코어 -------------------------------------------------------------

## 서버가 같은 입력으로 같은 위치를 재현할 수 있어야 한다 (DESIGN.md 「서버 권위」).
func _check_determinism() -> void:
	var inputs: Array[Vector2i] = []
	for i in 400:
		inputs.append(Vector2i((i % 7) - 3, (i % 5) - 2))
	var a := _run(inputs)
	var b := _run(inputs)
	if not a.position.is_equal_approx(b.position) or a.facing != b.facing:
		_fails.append("같은 입력 400틱인데 결과가 다르다: %s(%d) vs %s(%d)"
				% [a.position, a.facing, b.position, b.facing])
	else:
		print("[qa] 재현성 ok — 400틱 뒤 %s, 바라보는 방향 %d" % [a.position, a.facing])


## 한 틱에 갈 수 있는 거리에 상한이 있어야 입력을 빨리 밀어넣어도 속도 핵이 안 된다.
## 대각선이 더 빠르면(정규화를 빼먹으면) 대각으로만 뛰는 게 이득이 되어버린다.
func _check_speed_limit() -> void:
	var straight := _distance_per_tick(Vector2i(1, 0), 40)
	var diagonal := _distance_per_tick(Vector2i(1, 1), 40)
	var limit: float = PlayerMotion.MAX_STEP + 0.001
	if straight > limit or diagonal > limit:
		_fails.append("한 틱 이동량이 상한(%.3f)을 넘었다: 직선 %.3f / 대각 %.3f"
				% [limit, straight, diagonal])
	elif absf(straight - diagonal) > 0.001:
		_fails.append("대각선(%.3f)이 직선(%.3f)과 속도가 다르다 — 정규화가 빠졌다"
				% [diagonal, straight])
	else:
		print("[qa] 속도 상한 ok — 틱당 %.3f (직선·대각 같음, 초당 %.0f)"
				% [straight, straight * PlayerMotion.TICK_RATE])


## 한 틱 이동량이 타일보다 훨씬 작아야 바다 한 칸을 통째로 건너뛰지 않는다
## (docs/GOTCHAS.md — 큰 이동량을 한 번에 넘기면 충돌 판정을 건너뛴다).
func _check_step_smaller_than_tile() -> void:
	if PlayerMotion.MAX_STEP > WorldGen.TILE_SIZE * 0.25:
		_fails.append("한 틱 이동량 %.1f 이 타일(%d)의 1/4을 넘는다 — 바다를 건너뛸 수 있다"
				% [PlayerMotion.MAX_STEP, WorldGen.TILE_SIZE])
	else:
		print("[qa] 틱당 %.1f / 타일 %d — 바다 한 칸을 건너뛸 수 없다"
				% [PlayerMotion.MAX_STEP, WorldGen.TILE_SIZE])


## 네 방향 모두 오래 밀어도 바다에 못 들어간다. 그리고 물가에 **틈 없이** 붙는다.
func _check_sea_blocks() -> void:
	var blocked_somewhere := false
	for move: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var motion := PlayerMotion.new(_world)
		motion.place_at_tile(_world.spawn_tile)
		var last := motion.position
		var stalled := 0
		for i in 4000:
			motion.tick(move)
			if motion.position.is_equal_approx(last):
				stalled += 1
			else:
				stalled = 0
			last = motion.position
			if stalled > 2:
				break
		if motion.blocked_at(motion.position):
			_fails.append("%s 로 계속 밀었더니 몸이 바다에 걸쳤다: %s" % [move, motion.position])
			continue
		if stalled <= 2:
			print("[qa] %s: 4000틱 안에 물가를 못 만났다(내륙) — 판정은 다른 방향에서 본다" % move)
			continue
		blocked_somewhere = true
		# 물가에 붙었는지: 한 틱만 더 가면 바다여야 하고, 그 경계까지의 틈이 아주 작아야 한다.
		var gap := _gap_to_water(motion, move)
		if gap > MAX_SHORE_GAP:
			_fails.append("%s 물가에서 %.2f 만큼 떨어져 멈췄다 — 해안에 틈이 보인다" % [move, gap])
		else:
			print("[qa] %s: 타일 %s 에서 물가에 붙어 멈춤 (틈 %.3f)" % [move, motion.tile(), gap])
	if not blocked_somewhere:
		_fails.append("네 방향 어디에서도 바다에 막히지 않았다 — 충돌 검사가 헛돌았다")


## 벽에 비스듬히 밀면 막힌 축만 멈추고 나머지 축으로는 미끄러져야 한다
## (안 그러면 해안을 따라 걷다가 자꾸 붙잡힌다).
func _check_wall_slide() -> void:
	var found := _find_shore(Vector2i(0, 1))  # 남쪽이 바다인 땅 칸
	if found.x < 0:
		print("[qa] 물가를 못 찾아 미끄러짐 검사를 건너뛴다")
		return
	var motion := PlayerMotion.new(_world)
	motion.place_at_tile(found)
	# 남쪽(바다)으로 붙인 뒤, 남동쪽으로 밀어본다 — 남쪽은 막히고 동쪽으로는 가야 한다.
	for i in 40:
		motion.tick(Vector2i(0, 1))
	var before := motion.position
	for i in 20:
		motion.tick(Vector2i(1, 1))
	var moved_x: float = motion.position.x - before.x
	if motion.blocked_at(motion.position):
		_fails.append("비스듬히 밀었더니 몸이 바다에 걸쳤다: %s" % motion.position)
	elif moved_x < 1.0:
		_fails.append("물가에 붙은 채 남동쪽으로 밀었는데 동쪽으로 %.2f 밖에 못 갔다 — 미끄러지지 않는다"
				% moved_x)
	else:
		print("[qa] 물가에 붙은 채 대각 입력 → 막힌 축은 멈추고 동쪽으로 %.1f 미끄러졌다" % moved_x)


# --- B. 월드 화면 -------------------------------------------------------------

func _player() -> Node2D:
	return current_scene.get_node_or_null("%Player") as Node2D


func _camera() -> Camera2D:
	return current_scene.get_node_or_null("%Camera") as Camera2D


func _check_spawned() -> void:
	var player := _player()
	if player == null:
		_fails.append("월드에 플레이어 노드가 없다")
		return
	var world: RefCounted = current_scene.get("world")
	var spawn: Vector2 = WorldGen.tile_center(world.spawn_tile)
	if not player.position.is_equal_approx(spawn):
		_fails.append("플레이어가 %s — 스폰 %s 에 서 있어야 한다" % [player.position, spawn])
	if not _world.is_land(player.tile().x, player.tile().y):
		_fails.append("플레이어가 바다 칸 %s 에 서 있다" % player.tile())
	var camera := _camera()
	if camera == null or not camera.global_position.is_equal_approx(player.global_position):
		_fails.append("카메라가 플레이어 위에 있지 않다")
	else:
		print("[qa] 스폰 %s 에 플레이어와 카메라가 함께 있다" % spawn)


## 노드 원점이 발밑이어야 한다 — 시트에서 실제로 칠해진 맨 아랫줄이 원점(y=0)에
## 오는지 그림에서 직접 재서 본다.
func _check_feet_on_origin() -> void:
	var sprite := _player().get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		_fails.append("플레이어에 AnimatedSprite2D(SpriteFrames)가 없다")
		return
	if not sprite.sprite_frames.has_animation("idle_down"):
		_fails.append("idle_down 애니메이션이 없다 — 시트를 못 잘랐다")
		return
	var image: Image = sprite.sprite_frames.get_frame_texture("idle_down", 0).get_image()
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				bottom = y
				break
	var feet_local: float = (float(bottom + 1) - image.get_height() * 0.5 + sprite.offset.y) * sprite.scale.y
	if absf(feet_local) > 3.0:
		_fails.append("발밑이 원점에서 %.1f px 어긋났다 — 캐릭터가 뜨거나 파묻혀 보인다" % feet_local)
	var screen_height: float = image.get_height() * sprite.scale.y
	if not is_equal_approx(screen_height, 102.0):
		_fails.append("화면에서 캐릭터 칸 높이가 %.0fpx — 102px(아트 34 × 3배)여야 한다" % screen_height)
	else:
		print("[qa] 발밑이 원점 (%.1fpx 오차), 화면 높이 %.0fpx" % [feet_local, screen_height])


func _press(action: String) -> void:
	_release_all()
	_before = _player().position
	Input.action_press(action)
	_wait_time = HOLD_SECONDS


func _expect_moved(action: String, want: Vector2, dir_name: String) -> void:
	var player := _player()
	var delta := player.position - _before
	Input.action_release(action)
	if delta.dot(want) <= 0.5:
		_fails.append("%s 를 눌렀는데 %s 로 움직였다 (기대 %s)" % [action, delta, want])
	# 누른 축과 직각인 축은 그대로여야 한다.
	var across := Vector2(want.y, want.x).abs()
	if absf(delta.dot(across)) > 0.001:
		_fails.append("%s 를 눌렀는데 옆으로도 %s 움직였다" % [action, delta])
	var camera := _camera()
	if camera != null and not camera.global_position.is_equal_approx(player.global_position):
		_fails.append("%s 로 움직였는데 카메라가 안 따라왔다 (%s vs %s)"
				% [action, camera.global_position, player.global_position])
	var sprite := player.get_node_or_null("Sprite") as AnimatedSprite2D
	# 움직이는 동안은 **그 방향의 걷기**여야 한다 (INBOX #15 에서 걷기 시트가 생겼다).
	# 방향과 시트의 행이 어긋나면 옆으로 걸으면서 앞모습이 나온다.
	var want_anim := "walk_%s" % dir_name
	if sprite.animation != want_anim:
		_fails.append("%s 로 움직이는데 애니메이션이 %s 다 — %s 여야 한다"
				% [action, sprite.animation, want_anim])
	else:
		print("[qa] %s → %s 이동, 카메라 추적 ok, 애니메이션 %s" % [action, delta, want_anim])
	# 방향마다 한 장씩 남긴다 — 네 방향이 실제로 다른 그림으로 보이는지는 눈으로 봐야 한다.
	_shoot("51_walk_%s" % dir_name)


## 실제 키 입력으로 바다 쪽으로 계속 밀어본다 — 코어만이 아니라 씬에서도 막히는지.
func _walk_into_the_sea() -> void:
	var player := _player()
	var shore := _find_shore(Vector2i(0, 1))
	if shore.x < 0:
		print("[qa] 물가를 못 찾아 화면 쪽 바다 충돌 검사를 건너뛴다")
		return
	player.place_at(WorldGen.tile_center(shore))
	_release_all()
	Input.action_press("move_down")
	# 물가까지 걸어갈 시간을 넉넉히 준다(초당 5칸).
	_wait_time = 4.0


func _check_stopped_on_land() -> void:
	_release_all()
	var player := _player()
	var tile: Vector2i = player.tile()
	if not _world.is_land(tile.x, tile.y):
		_fails.append("바다 쪽으로 계속 걸었더니 바다 칸 %s 에 들어갔다" % tile)
	elif player.motion.blocked_at(player.position):
		_fails.append("몸통이 바다에 걸친 채로 멈췄다: %s" % player.position)
	else:
		print("[qa] 바다 쪽으로 계속 걸어도 땅 칸 %s 에서 멈춘다" % tile)
	_shoot("52_player_at_shore")


# --- 도구 ---------------------------------------------------------------------

func _run(inputs: Array[Vector2i]) -> RefCounted:
	var motion := PlayerMotion.new(_world)
	motion.place_at_tile(_world.spawn_tile)
	for move in inputs:
		motion.tick(move)
	return motion


## 한 틱에 실제로 움직인 거리 중 가장 큰 값.
func _distance_per_tick(move: Vector2i, ticks: int) -> float:
	var motion := PlayerMotion.new(_world)
	motion.place_at_tile(_world.spawn_tile)
	var worst := 0.0
	for i in ticks:
		var before := motion.position
		motion.tick(move)
		worst = maxf(worst, motion.position.distance_to(before))
	return worst


## 지금 선 자리에서 진행 방향으로 물가까지 남은 틈(월드 단위 = 화면 픽셀).
## 붙여서 멈추지 않으면 여기서 한 틱 이동량(4px)에 가까운 값이 나온다.
func _gap_to_water(motion: RefCounted, move: Vector2i) -> float:
	var gap := 0.0
	while gap < WorldGen.TILE_SIZE:
		if motion.blocked_at(motion.position + Vector2(move) * gap):
			return gap
		gap += 0.02
	return gap


## 그 방향 이웃이 바다인 땅 칸 중 스폰에서 가장 가까운 것.
func _find_shore(toward: Vector2i) -> Vector2i:
	var spawn: Vector2i = _world.spawn_tile
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(8, WorldGen.MAP_TILES - 8):
		for x in range(8, WorldGen.MAP_TILES - 8):
			if not _world.is_land(x, y) or _world.is_land(x + toward.x, y + toward.y):
				continue
			var distance: float = Vector2(Vector2i(x, y) - spawn).length_squared()
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	return best


func _release_all() -> void:
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)


func _shoot(shot_name: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		print("[qa] 캡처 건너뜀 — --headless 로 돌렸다(뷰포트 텍스처 없음)")
		return
	var path := "%s/%s.png" % [SHOTS, shot_name]
	texture.get_image().save_png(path)
	print("[qa] shot %s" % path)


func _report() -> bool:
	_release_all()
	if _fails.is_empty():
		print("[qa] PASS — 이동 코어(재현성/속도상한/바다충돌/미끄러짐) + 월드의 플레이어(WASD/카메라추적)")
		return true
	for f in _fails:
		printerr("[qa] FAIL — %s" % f)
	quit(1)
	return true
