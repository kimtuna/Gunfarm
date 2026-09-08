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
##      4-1) **나무·바위는 걷기를 막고 덤불은 안 막는다**(INBOX #65). 막는 것은 그
##         오브젝트가 **선 칸 하나**이고(잎 아래는 지나간다), 밑동에 틈 없이 붙고,
##         비스듬히 밀면 해안과 똑같이 미끄러진다.
##      5) 한 틱 이동량이 타일보다 훨씬 작다 — 바다 한 칸을 통째로 건너뛸 수 없다.
##      6) **바라보는 방향은 이동이 아니라 조준이 정한다**(INBOX #16) — 4방향 스냅,
##         경계에서 마우스가 떨려도 안 흔들림(히스테리시스), 스냅해도 **원본 각도는
##         각도 그대로** 남음(총알/시야 콘이 쓸 값이다).
##   B. 월드 화면 — 실제 씬에서:
##      7) 스폰 칸에 플레이어가 서 있고 카메라가 그 위에 있다.
##      8) 발밑이 노드 원점이다(스프라이트가 땅에 서 있지, 공중에 뜨거나 파묻히지 않는다).
##      9) WASD 를 누르면 그 방향으로 움직이고 **카메라가 따라온다**.
##     10) **실제 마우스 좌표**(`Input.warp_mouse`)가 애니메이션 방향을 정한다 —
##         이동과 조준을 일부러 어긋나게(왼쪽으로 걸으며 오른쪽 조준) 넣어서 확인한다.
##     11) 서 있어도 마우스만 돌리면 캐릭터가 그쪽을 본다.
##     12) **나무를 향해 실제로 걸어도 통과하지 못한다**(INBOX #65 (3) — 캡처로도 본다).
##
## 눈으로 볼 몫은 `user://qa_shots/` 에 캡처로 남긴다.

const SettingsStore := preload("res://scripts/settings_store.gd")
const _Inventory := preload("res://scripts/inventory.gd")

const WorldGen := preload("res://scripts/world_gen.gd")
const PlayerMotion := preload("res://scripts/player_motion.gd")
const WorldObjects := preload("res://scripts/world_objects.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")
const PlayerInput := preload("res://scripts/player_input.gd")
const SlotStore := preload("res://scripts/slot_store.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260906

## 키를 몇 **초** 누르고 있는가. 프레임 수로 세면 안 된다 — 이 창은 수직동기화가 없어서
## 20프레임이 20ms 밖에 안 될 수도 있고, 그러면 고정 틱이 한 번도 안 돌아 "안 움직였다"고
## 나온다. 0.3초면 60Hz 틱이 확실히 여러 번 돈다.
const HOLD_SECONDS := 0.35

## 한 단계를 끝낸 뒤 다음 단계까지 두는 여유(초). **여기가 이 검사의 핵심 상수다**
## (2026-09-07, INBOX #21) — 조준/이동은 `player.gd` 가 프레임 시간을 모아 고정 틱
## (1/60초)으로 쪼개서 돌리므로, 상태를 바꾼 뒤 **틱이 실제로 몇 번 돌 만큼의 시간**이
## 지나야 화면에 반영된다. 예전에는 여기가 "3프레임"이었는데, 수직동기화가 없는 이
## 창에서 3프레임은 수 ms 라 틱이 한 번도 안 돌아 직전 방향이 그대로 나왔다.
const SETTLE_SECONDS := 0.15

## 45도 경계에서 마우스를 몇 번, 한 자리에 몇 초씩 흔들어보는가.
## **한 자리에 머무는 시간도 프레임 수가 아니라 초다** — 매 프레임 다른 자리로
## `warp_mouse()` 하면 OS 가 커서 이동을 합쳐버려서(docs/GOTCHAS.md) 실제로는
## 마우스가 안 움직인 채 "안 떨었다"로 통과한다.
const JITTER_SAMPLES := 12
const JITTER_HOLD_SECONDS := 0.06

## 물가에 얼마나 바짝 붙어야 하는가(월드 단위 = 화면 픽셀). 1px 이면 눈에 안 보인다.
const MAX_SHORE_GAP := 1.0

## 방향 이름 → 조준 각도(라디안). `player_motion.gd` 의 `DIR_ANGLE` 과 같은 값이지만
## 일부러 여기에 따로 적는다 — 코어와 같은 상수를 쓰면 코어가 틀려도 같이 틀린다.
const AIM := {"right": 0.0, "down": PI * 0.5, "left": PI, "up": -PI * 0.5}

## 마우스를 화면 가운데(=플레이어)에서 얼마나 밀어놓는가. 창 짧은 변에 대한 비율이다.
const AIM_REACH := 0.3

var _fails: Array[String] = []
var _steps: Array[Callable] = []
var _step := 0

## 다음 단계까지 남은 **시간**(초). 프레임 수를 세는 변수는 두지 않는다 — 그게
## INBOX #21 의 거짓 실패 원인이었다.
var _wait_time := 0.0
var _world: RefCounted = null
var _before := Vector2.ZERO

## 화면 쪽에서 걸어가 볼 나무 칸. `_walk_into_a_tree` 가 정하고 다음 단계가 읽는다.
var _tree_tile := Vector2i(-1, -1)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# **일부러 수직동기화를 끈다** (2026-09-07, INBOX #21). 프레임 수로 기다리는 코드가
	# 다시 들어오면 여기서 바로 걸리게 하려는 것이다 — 켜져 있으면 한 프레임이 16ms 라
	# "3프레임 기다리기"도 우연히 통과하고, 정작 사람의 빠른 기계(120Hz 이상)에서만
	# 거짓 실패한다. 꺼두면 이 검사가 늘 최악 조건에서 돈다.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_world = WorldGen.new()
	_world.build(SEED)

	# --- A. 이동 코어 (화면이 필요 없다) ---
	_check_determinism()
	_check_speed_limit()
	_check_step_smaller_than_tile()
	_check_sea_blocks()
	_check_objects_block()
	_check_wall_slide()
	_check_facing_follows_aim()

	# 첫 씬은 여기서 올린다 (docs/GOTCHAS.md — _steps 에 넣으면 영영 실행되지 않는다).
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("걷는사람", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)

	# --- B. 월드 화면 ---
	_steps = [
		_free_hand,
		_check_spawned,
		_check_feet_on_origin,
		func(): _shoot("50_player_spawn"),
		# 이동 키와 조준을 **일부러 어긋나게** 넣는다 (INBOX #16). 첫 짝만 방향이
		# 같고 나머지 셋은 다르다 — 이동 키가 방향을 정하던 옛 동작이 남아 있으면
		# 여기서 애니메이션이 이동 쪽 이름으로 나와 걸린다.
		func(): _press("move_right", "right"),
		func(): _expect_moved("move_right", Vector2(1, 0), "right"),
		func(): _press("move_up", "down"),
		func(): _expect_moved("move_up", Vector2(0, -1), "down"),
		func(): _press("move_left", "right"),
		func(): _expect_moved("move_left", Vector2(-1, 0), "right"),
		func(): _press("move_down", "left"),
		func(): _expect_moved("move_down", Vector2(0, 1), "left"),
		func(): _aim("up"),
		_check_aim_turns_while_standing,
		_check_aim_jitter_on_screen,
		_walk_into_the_sea,
		_check_stopped_on_land,
		_walk_into_a_tree,
		_check_stopped_at_tree,
	]



## **맨손으로 만든다** — 이 검사가 보는 것은 맨손 idle/걷기 시트인데, 처음 들어온
## 캐릭터는 **든 칸(1번)에 도구가 들어 있다**(`world.gd` 의 `STARTER_ITEMS`).
## 그 도구에 그림이 생기는 순간 `hold_<도구>` 가 나오므로, 도구 이름에 기대지 않게
## 그 칸을 비운다. (2026-09-07, INBOX #28 — 총에 그림이 생기면서 걸렸다.)
func _free_hand() -> void:
	if current_scene == null:
		return
	var inv: RefCounted = current_scene.get("inventory")
	if inv == null:
		return
	inv.take_out(_Inventory.AREA_GENERAL, 0)

func _process(delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
	if _resize_window_if_needed():
		return false
	if _wait_time > 0.0:
		_wait_time -= delta
		return false
	if _step >= _steps.size():
		return _report()
	var step: Callable = _steps[_step]
	_step += 1
	# 단계 자체가 더 오래 걸리면(키를 누르고 있기 등) 그 단계가 이 값을 덮어쓴다.
	# **비동기(await) 단계는 자기가 도는 전체 시간을 반드시 여기에 적어야 한다** —
	# 안 그러면 코루틴이 아직 도는 중에 다음 단계가 시작된다.
	_wait_time = SETTLE_SECONDS
	step.call()
	return false


# --- A. 이동 코어 -------------------------------------------------------------

## 서버가 같은 입력으로 같은 위치를 재현할 수 있어야 한다 (DESIGN.md 「서버 권위」).
func _check_determinism() -> void:
	var inputs: Array[RefCounted] = []
	for i in 400:
		# 조준도 입력이라 같이 흔들어본다 — 각도가 재현에 끼어들면 여기서 걸린다.
		inputs.append(PlayerInput.new(Vector2i((i % 7) - 3, (i % 5) - 2), float(i) * 0.37 - PI))
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
##
## **출발점은 스폰이 아니라 그 방향의 물가다** (2026-09-08, INBOX #65). 나무·바위가
## 걷기를 막게 되면서 스폰에서 밀면 대개 나무에 먼저 막히는데, 그러면 이 검사는
## *"바다에 못 들어간다"* 가 아니라 *"무언가에 막힌다"* 를 재게 된다 — 나무 앞에서
## 멈춰도 초록불이라 **물가 판정이 통째로 사라져도 모른다.** 물가 칸은 이웃에 바다가
## 있어 오브젝트가 놓이지 않으므로(`world_gen.gd` 의 `_can_hold_object`), 거기서
## 밀면 막는 것은 반드시 물이다.
func _check_sea_blocks() -> void:
	var blocked_somewhere := false
	for move: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var shore := _find_shore(move)
		if shore.x < 0:
			print("[qa] %s 쪽이 바다인 물가를 못 찾았다 — 판정은 다른 방향에서 본다" % move)
			continue
		var motion := PlayerMotion.new(_world)
		motion.place_at_tile(shore)
		for i in 60:
			motion.tick(PlayerInput.new(move))
		if motion.blocked_at(motion.position):
			_fails.append("%s 로 계속 밀었더니 몸이 바다에 걸쳤다: %s" % [move, motion.position])
			continue
		var ahead: Vector2i = motion.tile() + move
		if _world.is_land(ahead.x, ahead.y):
			_fails.append("%s 물가에서 밀었는데 바다(%s)가 아니라 땅 앞에서 멈췄다" % [move, ahead])
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


## **나무·바위는 걷기를 막고 덤불은 안 막는다** (docs/DESIGN.md 「월드 오브젝트」의
## 「막는 크기」, INBOX #65). 바다와 **같은 지도 같은 코어**에 물어본다 — 막는 자리가
## `blocked_at()` 한 곳으로 모여 있다는 것이 이 검사의 요점이다.
##
## 막는 크기는 **그 오브젝트가 선 칸 하나**다. 나무 그림은 두 칸 × 세 칸이지만 잎까지
## 막으면 숲을 통째로 못 지나간다 — 그래서 **밑동 칸 바로 위 칸은 걸을 수 있어야
## 한다**(잎 아래를 지나간다). 그것까지 여기서 본다.
func _check_objects_block() -> void:
	var tree := _find_object(WorldObjects.TREE)
	var rock := _find_object(WorldObjects.ROCK)
	var bush := _find_object(WorldObjects.BUSH)
	var motion := PlayerMotion.new(_world)
	for pair: Array in [[tree, "나무"], [rock, "바위"]]:
		var t: Vector2i = pair[0]
		if t.x < 0:
			print("[qa] %s 를 못 찾아 막힘 검사를 건너뛴다" % pair[1])
			continue
		if not motion.blocked_at(WorldGen.tile_center(t)):
			_fails.append("%s 가 선 칸 %s 을 걸어서 지나갈 수 있다" % [pair[1], t])
		# 잎(나무는 위로 세 칸)까지 막으면 안 된다 — 밑동 바로 위 칸은 걸을 수 있어야 한다.
		var above := t + Vector2i(0, -1)
		if _world.is_land(above.x, above.y) and _world.object_at(above.x, above.y) == WorldObjects.NONE \
				and motion.blocked_at(WorldGen.tile_center(above)):
			_fails.append("%s 의 바로 윗칸 %s 까지 막혔다 — 막는 것은 선 칸 하나여야 한다"
					% [pair[1], above])
	if bush.x < 0:
		print("[qa] 덤불을 못 찾아 통과 검사를 건너뛴다")
	elif motion.blocked_at(WorldGen.tile_center(bush)):
		_fails.append("덤불 칸 %s 이 걷기를 막는다 — 덤불은 안 막는다" % bush)
	else:
		print("[qa] 나무 %s · 바위 %s 는 막고, 덤불 %s 은 지나갈 수 있다" % [tree, rock, bush])

	# 실제로 밀어서도 확인한다 — 판정 함수만 맞고 이동이 안 쓰면 소용이 없다.
	var open_tree := _find_object(WorldObjects.TREE, true)
	if open_tree.x < 0:
		print("[qa] 서쪽 두 칸이 비어 있는 나무를 못 찾아 밀기 검사를 건너뛴다")
		return
	tree = open_tree
	var walker := PlayerMotion.new(_world)
	walker.place_at_tile(tree + Vector2i(-2, 0))
	for i in 60:
		walker.tick(PlayerInput.new(Vector2i(1, 0)))
	if walker.tile().x >= tree.x:
		_fails.append("나무 %s 를 향해 밀었더니 %s 까지 들어갔다" % [tree, walker.tile()])
		return
	var edge := float(tree.x * WorldGen.TILE_SIZE) - PlayerMotion.BODY_HALF.x
	if absf(walker.position.x - edge) > MAX_SHORE_GAP:
		_fails.append("나무 앞에서 %.2f 만큼 떨어져 멈췄다 — 밑동에 붙지 않았다"
				% absf(walker.position.x - edge))
	# 비스듬히 밀면 막힌 축만 멈추고 나머지 축으로는 미끄러져야 한다(해안과 같은 규칙).
	var slide_dir := 1 if _world.is_walkable(tree.x - 1, tree.y + 1) else -1
	if not _world.is_walkable(tree.x - 1, tree.y + slide_dir):
		print("[qa] 나무 옆이 막혀 미끄러짐 검사를 건너뛴다")
		return
	var before := walker.position
	for i in 20:
		walker.tick(PlayerInput.new(Vector2i(1, slide_dir)))
	var moved_y := (walker.position.y - before.y) * float(slide_dir)
	if walker.blocked_at(walker.position):
		_fails.append("나무에 비스듬히 밀었더니 몸이 막힌 칸에 걸쳤다: %s" % walker.position)
	elif moved_y < 1.0:
		_fails.append("나무에 붙은 채 비스듬히 밀었는데 옆으로 %.2f 밖에 못 갔다 — 미끄러지지 않는다"
				% moved_y)
	else:
		print("[qa] 나무 %s 밑동에 붙어 멈추고, 비스듬히 밀면 옆으로 %.1f 미끄러진다" % [tree, moved_y])


## 스폰에서 가장 가까운, 그 종류의 오브젝트가 선 칸. 없으면 (-1, -1).
##
## `clear_west` 를 켜면 **서쪽 두 칸이 걸을 수 있는** 것만 고른다 — 밀어서 확인하는
## 검사는 조수를 놓을 자리와 달려올 거리가 필요하다. **이 조건을 안 걸면 옆 칸의
## 다른 나무에 먼저 막히고도 "나무에 막혔다"로 통과한다**(2026-09-08 에 실제로 그랬다).
func _find_object(kind: int, clear_west := false) -> Vector2i:
	var spawn: Vector2i = _world.spawn_tile
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(8, WorldGen.MAP_TILES - 8):
		for x in range(8, WorldGen.MAP_TILES - 8):
			if _world.object_at(x, y) != kind:
				continue
			if clear_west and not (_world.is_walkable(x - 1, y) and _world.is_walkable(x - 2, y)):
				continue
			var distance: float = Vector2(Vector2i(x, y) - spawn).length_squared()
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	return best


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
		motion.tick(PlayerInput.new(Vector2i(0, 1)))
	var before := motion.position
	for i in 20:
		motion.tick(PlayerInput.new(Vector2i(1, 1)))
	var moved_x: float = motion.position.x - before.x
	if motion.blocked_at(motion.position):
		_fails.append("비스듬히 밀었더니 몸이 바다에 걸쳤다: %s" % motion.position)
	elif moved_x < 1.0:
		_fails.append("물가에 붙은 채 남동쪽으로 밀었는데 동쪽으로 %.2f 밖에 못 갔다 — 미끄러지지 않는다"
				% moved_x)
	else:
		print("[qa] 물가에 붙은 채 대각 입력 → 막힌 축은 멈추고 동쪽으로 %.1f 미끄러졌다" % moved_x)


## **바라보는 방향은 이동이 아니라 조준이 정한다** (docs/DESIGN.md 「조작」).
## 스냅(4방향) / 경계에서의 떨림 / 원본 각도 보존 / 이동과 어긋난 조준을 함께 본다.
func _check_facing_follows_aim() -> void:
	# 1) 서 있어도(이동 0) 조준한 쪽을 본다. 네 방향 전부.
	for dir_name: String in AIM:
		var motion := PlayerMotion.new(_world)
		motion.place_at_tile(_world.spawn_tile)
		motion.tick(PlayerInput.new(Vector2i.ZERO, AIM[dir_name]))
		var got: String = PlayerFrames.DIR_NAMES[motion.facing]
		if got != dir_name:
			_fails.append("%s 를 조준했는데 %s 를 본다 — 조준이 방향을 안 정한다"
					% [dir_name, got])
		if not is_equal_approx(motion.aim_angle, AIM[dir_name]):
			_fails.append("조준 각도가 %.3f 로 바뀌었다 — 스냅된 값이 원본을 덮어썼다"
					% motion.aim_angle)

	# 2) **이동과 조준이 어긋난 경우** — 왼쪽으로 걸으면서 오른쪽을 겨눈다(게걸음).
	var side := PlayerMotion.new(_world)
	side.place_at_tile(_world.spawn_tile)
	var start := side.position
	for i in 20:
		side.tick(PlayerInput.new(Vector2i(-1, 0), AIM["right"]))
	if side.position.x >= start.x:
		_fails.append("왼쪽 입력인데 x 가 %.1f → %.1f 로 안 줄었다" % [start.x, side.position.x])
	elif PlayerFrames.DIR_NAMES[side.facing] != "right":
		_fails.append("왼쪽으로 걸으며 오른쪽을 겨눴는데 %s 를 본다 — 이동이 방향을 뺏었다"
				% PlayerFrames.DIR_NAMES[side.facing])
	else:
		print("[qa] 게걸음 ok — 왼쪽으로 %.0f 이동하면서 오른쪽을 본다"
				% (start.x - side.position.x))

	# 3) **스냅 경계에서 떨지 않는다.** 오른쪽을 보다가 45도 경계 위에서 마우스를
	#    흔들면(±0.02rad) 시트가 매 프레임 오가서는 안 된다.
	var jitter := PlayerMotion.new(_world)
	jitter.place_at_tile(_world.spawn_tile)
	jitter.tick(PlayerInput.new(Vector2i.ZERO, AIM["right"]))
	var edge := PI * 0.25
	var flips := 0
	var last := jitter.facing
	for i in 20:
		jitter.tick(PlayerInput.new(Vector2i.ZERO, edge + (0.02 if i % 2 == 0 else -0.02)))
		if jitter.facing != last:
			flips += 1
		last = jitter.facing
	if flips > 0:
		_fails.append("45도 경계에서 마우스를 조금 흔들었더니 방향이 %d번 뒤집혔다 — 캐릭터가 떤다"
				% flips)
	# 히스테리시스가 너무 세서 아예 안 넘어가면 그것대로 고장이다.
	jitter.tick(PlayerInput.new(Vector2i.ZERO, edge + 0.4))
	if PlayerFrames.DIR_NAMES[jitter.facing] != "down":
		_fails.append("경계를 확실히 넘겼는데도 %s 에 붙어 있다 — 히스테리시스가 너무 세다"
				% PlayerFrames.DIR_NAMES[jitter.facing])
	elif _fails.is_empty():
		print("[qa] 조준 스냅 ok — 경계에서 안 떨고(0번), 확실히 넘기면 down 으로 바뀐다")


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
	var want_height := float(PlayerFrames.CELL * PlayerFrames.SCALE)
	if not is_equal_approx(screen_height, want_height):
		_fails.append("화면에서 캐릭터 칸 높이가 %.0fpx — %.0fpx(아트 %d × %d배)여야 한다"
				% [screen_height, want_height, PlayerFrames.CELL, PlayerFrames.SCALE])
	else:
		print("[qa] 발밑이 원점 (%.1fpx 오차), 화면 높이 %.0fpx" % [feet_local, screen_height])


## 실제 마우스를 조준 기준점에서 `angle` 쪽으로 밀어놓는다.
## `Input.warp_mouse()` 라 노드의 "마우스 → 각도" 변환까지 그대로 지나간다 —
## 각도를 코어에 직접 넣으면 정작 이번에 만든 그 변환을 안 지나간다.
##
## 카메라가 플레이어의 자식이라 **발밑이 화면 한가운데**고, 조준 기준점은 거기서
## 몸 절반만큼 위다(`player.gd` 의 `aim_origin()`). 그 어긋남을 빼줘야 여기서
## 넣은 각도가 실제 조준 각도와 같아진다 — 45도 경계를 재는 검사에 필요하다.
func _aim_at(angle: float) -> void:
	# **논리 좌표**로 잡는다 — 아래에서 `_to_window()` 로 한 번만 창 픽셀로 옮긴다.
	# 창 크기로 잡으면 이미 창 픽셀인 값을 한 번 더 변환해서 조준 각도가 어긋난다
	# (2026-09-08, INBOX #48 — 그 전에는 논리 해상도와 창 크기가 같아서 안 드러났다).
	var size := root.get_visible_rect().size
	var origin := size * 0.5 - Vector2(0.0, PlayerFrames.CELL * PlayerFrames.SCALE * 0.5)
	Input.warp_mouse(_to_window(origin + Vector2.from_angle(angle) * minf(size.x, size.y) * AIM_REACH))


func _aim(dir_name: String) -> void:
	_aim_at(AIM[dir_name])


func _press(action: String, aim_name: String) -> void:
	_release_all()
	_aim(aim_name)
	_before = _player().position
	Input.action_press(action)
	_wait_time = HOLD_SECONDS


## `want` 는 **이동 방향**, `aim_name` 은 **조준 방향**이다 — 둘이 달라도 된다.
func _expect_moved(action: String, want: Vector2, aim_name: String) -> void:
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
	# 움직이는 동안은 걷기 시트를 쓰되(INBOX #15), **행은 조준 방향**이다(INBOX #16).
	var want_anim := "walk_%s" % aim_name
	if sprite.animation != want_anim:
		_fails.append("%s 를 누른 채 %s 를 조준했는데 애니메이션이 %s 다 — %s 여야 한다"
				% [action, aim_name, sprite.animation, want_anim])
	else:
		print("[qa] %s → %s 이동, %s 조준, 카메라 추적 ok, 애니메이션 %s"
				% [action, delta, aim_name, want_anim])
	# 이동/조준 짝마다 한 장씩 남긴다 — 어긋난 짝이 실제로 어떻게 보이는지는 눈으로 봐야 한다.
	_shoot("51_%s_aim_%s" % [action, aim_name])


## 실제 키 입력으로 바다 쪽으로 계속 밀어본다 — 코어만이 아니라 씬에서도 막히는지.
## 키를 하나도 안 눌러도 마우스만 돌리면 그쪽을 봐야 한다 — 서 있을 때 방향을
## 못 바꾸면 조준이 이동에 묶여 있는 것이다.
func _check_aim_turns_while_standing() -> void:
	var sprite := _player().get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null:
		return
	if sprite.animation != "idle_up":
		_fails.append("가만히 선 채 위를 조준했는데 애니메이션이 %s 다 — idle_up 이어야 한다"
				% sprite.animation)
	else:
		print("[qa] 서 있는 채로 마우스만 위로 → idle_up")
	_shoot("53_aim_up_standing")


## **실제 마우스를 45도 경계에서 흔들어본다** — 코어의 히스테리시스가 화면까지
## 이어지는지는 각도를 코어에 직접 넣는 검사만으로는 안 보인다. 여기서 방향이
## 오가면 플레이하는 사람 눈에는 캐릭터가 덜덜 떠는 것으로 보인다.
func _check_aim_jitter_on_screen() -> void:
	var sprite := _player().get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null:
		return
	_release_all()
	_aim_at(0.0)  # 오른쪽에서 시작해 경계로 올라간다.
	# 이 단계는 아래에서 실제로 시간을 쓰며 도는 코루틴이다 — 그 전체 시간을 여기에
	# 적어둬야 도는 중에 다음 단계가 끼어들지 않는다.
	_wait_time = SETTLE_SECONDS * 2.0 + JITTER_SAMPLES * JITTER_HOLD_SECONDS
	# 오른쪽으로 자리잡을 시간을 준다 — 여기서 바로 재면 직전 방향(위)이 섞여 들어와
	# "떨었다"고 잘못 잡는다. 고정 틱이 여러 번 돌아야 하므로 프레임이 아니라 초다.
	await _sleep(SETTLE_SECONDS)
	var seen := {}
	# 한 자리마다 **시간을 두고** 머문다 (위 JITTER_HOLD_SECONDS 주석).
	for i in JITTER_SAMPLES:
		_aim_at(PI * 0.25 + (0.02 if i % 2 == 0 else -0.02))
		await _sleep(JITTER_HOLD_SECONDS)
		seen[sprite.animation] = true
	if seen.size() > 1:
		_fails.append("45도 경계에서 마우스를 흔들었더니 화면 애니메이션이 %s 로 오갔다 — 캐릭터가 떤다"
				% [seen.keys()])
	else:
		print("[qa] 마우스를 45도 경계에서 흔들어도 %s 하나로 고정 — 안 떤다" % seen.keys()[0])


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


## 12) **나무를 향해 실제로 걸어본다** (INBOX #65 (3)). 코어만 맞고 화면 쪽 배선이
## 옛 판정을 쓰고 있으면 여기서 잡힌다 — 캐릭터가 나무 한가운데를 그냥 지나간다.
func _walk_into_a_tree() -> void:
	var tree := _find_object(WorldObjects.TREE, true)
	if tree.x < 0:
		print("[qa] 서쪽 두 칸이 비어 있는 나무를 못 찾아 화면 쪽 나무 충돌 검사를 건너뛴다")
		return
	_tree_tile = tree
	_player().place_at(WorldGen.tile_center(tree + Vector2i(-2, 0)))
	_release_all()
	_aim("right")
	Input.action_press("move_right")
	# 두 칸(96)이면 초당 5칸이라 0.4초면 닿는다 — 넉넉히 밀어붙인다.
	_wait_time = 2.0


func _check_stopped_at_tree() -> void:
	_release_all()
	if _tree_tile.x < 0:
		return
	var player := _player()
	var tile: Vector2i = player.tile()
	if tile.x >= _tree_tile.x:
		_fails.append("나무 %s 를 향해 계속 걸었더니 %s 까지 들어갔다" % [_tree_tile, tile])
	elif player.motion.blocked_at(player.position):
		_fails.append("몸통이 나무 칸에 걸친 채로 멈췄다: %s" % player.position)
	else:
		print("[qa] 나무 %s 를 향해 계속 걸어도 %s 에서 멈춘다" % [_tree_tile, tile])
	_shoot("54_player_at_tree")


# --- 도구 ---------------------------------------------------------------------

func _run(inputs: Array[RefCounted]) -> RefCounted:
	var motion := PlayerMotion.new(_world)
	motion.place_at_tile(_world.spawn_tile)
	for input in inputs:
		motion.tick(input)
	return motion


## 한 틱에 실제로 움직인 거리 중 가장 큰 값.
func _distance_per_tick(move: Vector2i, ticks: int) -> float:
	var motion := PlayerMotion.new(_world)
	motion.place_at_tile(_world.spawn_tile)
	var worst := 0.0
	for i in ticks:
		var before := motion.position
		motion.tick(PlayerInput.new(move))
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


## 실제로 `seconds` 초가 지날 때까지 프레임을 넘긴다.
## **프레임 수로 세는 대기는 이 파일에 두지 않는다** (docs/GOTCHAS.md — 수직동기화가
## 없는 창에서 N프레임은 수 ms 라 고정 틱이 한 번도 안 돌 수 있다).
func _sleep(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


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
		print("[qa] PASS — 이동 코어(재현성/속도상한/바다충돌/미끄러짐/마우스 조준) + 월드의 플레이어(WASD/카메라추적/조준 방향)")
		return true
	for f in _fails:
		printerr("[qa] FAIL — %s" % f)
	quit(1)
	return true

## 논리 좌표 → 창 픽셀. `Input.warp_mouse` 와 `parse_input_event` 는 OS 가 주는 것과 같은
## **창 픽셀**을 받는데, 우리가 재는 자리(Control 의 global_rect, 카메라 변환 결과)는 전부
## **논리 좌표**다. 논리 해상도(1440x810)와 창 크기가 갈린 2026-09-08 부터 둘이 다르다 —
## 그 전에는 값이 같아서 이 변환 없이도 통했다. `get_screen_transform()` 이 stretch 배율과
## (비율이 안 맞는 창의) 검은 여백 오프셋까지 함께 처리한다.
func _to_window(point: Vector2) -> Vector2:
	return root.get_screen_transform() * point


## 창을 논리 해상도와 같게 **유지**한다. 화면 픽셀을 짚어보고 마우스를 논리 좌표로 미는
## 검사라, 배율이 1 이 아니면 얇은 테두리가 downscale 에 뭉개지고 좌표가 어긋난다
## (2026-09-08, INBOX #48 — 논리 해상도 1440x810 과 기본 창 크기 1280x720 이 갈렸다).
##
## **되돌린 프레임에는 단계를 돌리지 않고 쉰다**(true 를 돌려준다). 창은 늘 기본 크기로
## 열리므로 이 대기는 **매 실행의 첫 프레임에 반드시 한 번 일어난다** — 없으면 크기 변경이
## 화면에 반영되기 전에 첫 단계가 마우스를 밀어 가끔 거짓 실패한다.
## 대기는 프레임 수가 아니라 **초**로 센다 (docs/GOTCHAS.md).
func _resize_window_if_needed() -> bool:
	if DisplayServer.window_get_size() == SettingsStore.BASE_SIZE:
		return false
	DisplayServer.window_set_size(SettingsStore.BASE_SIZE)
	_wait_time = SETTLE_SECONDS
	return true
