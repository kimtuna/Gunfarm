extends SceneTree

## INBOX #34 자체 QA — 총알(투사체)과 조준선.
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_bullets.gd
##
## 확인하는 것:
##   A. 코어(`bullets.gd` / `player_motion.gd` — 화면 없이 도는 순수 클래스)
##      1) **즉시판정이 아니다** — 쏜 순간에는 총구에 있고, 한 틱에 정해진 만큼만 간다.
##      2) 사거리(800)를 다 날아가면 사라진다 — 그 자리에서 딱 멈춘다.
##      3) **물은 총알을 막지 않는다** — 같은 지도 같은 칸에서 사람은 못 들어가고
##         총알은 지나간다. 그리고 **총알을 막는 것을 꽂으면** 거기서 사라지되
##         한 칸짜리 벽을 통째로 건너뛰지 않는다.
##      4) 각도는 스냅된 4방향이 아니라 **원본 조준 각도**다.
##      5) 정조준 — 서 있으면 모이고, 움직이면 흩어지고, 쏘면 반동으로 깎이고, 0~1 을 안 넘는다.
##      6) **탄퍼짐은 정조준 하나에서 나온다**(조준선 선명도와 같은 값). 씨앗을 주면 재현된다.
##      7) 대상 명중 판정의 **자리(`hit_test`)가 실제로 불린다** — 한 걸음짜리 선분으로.
##   B. 화면(실제 월드 씬에서)
##      8) 총을 들면 조준선이 보이고, **다른 도구를 들면 사라진다.**
##      9) **정조준이 풀릴수록 선이 넓게 번진다** — 같은 자리에서 찍은 세 장을 픽셀로 견준다.
##     10) 창(일시정지)이 열리면 조준선이 꺼진다.
##     11) 좌클릭하면 총알이 실제로 나가고 **화면에 보이며 날아간다** — 쏜 직후에는 총구
##         근처에 있고(즉시판정이면 이 검사가 실패한다), 잠시 뒤 더 멀리 가 있다.
##     12) 쏘면 반동으로 정조준이 깎인다.
##     13) **물가에서 물 건너로 쏘면 총알이 바다를 지나가고**, 같은 자리에서
##         **사람은 여전히 물에 못 들어간다**(이동 판정을 안 건드렸다는 확인).

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const Inventory := preload("res://scripts/inventory.gd")
const Bullets := preload("res://scripts/bullets.gd")
const BulletsView := preload("res://scripts/bullets_view.gd")
const PlayerMotion := preload("res://scripts/player_motion.gd")
const PlayerInput := preload("res://scripts/player_input.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260907

## 프레임 수가 아니라 **시간**으로 기다린다 (docs/GOTCHAS.md).
const SETTLE_SECONDS := 0.2

## 픽셀이 "달라졌다"고 보는 문턱. 캡처는 손실 없이 나오므로 아주 작아도 된다 —
## 부챗살 한 줄이 풀밭 위에 남기는 변화(0.05 남짓)보다 훨씬 작게 잡는다.
const DIFF_EPSILON := 0.008

## 조준선의 넓이를 재는 자리 — 플레이어에서 오른쪽으로 이만큼 떨어진 세로 한 줄을
## 훑는다. 캐릭터 그림에서 충분히 멀어 풀밭만 보이는 거리다.
const SAMPLE_DISTANCE := 150.0
const SAMPLE_HALF := 70.0

## 마우스를 화면에서 이만큼 오른쪽에 둔다 = 오른쪽 조준.
const AIM_SCREEN_DISTANCE := 300.0

## 총알이 날아가는 것을 견주는 간격(초). 900단위/초라 0.12초면 108단위를 간다 —
## 아래 `_stand_on_open_land` 이 확보하는 육지 안에서 끝나야 지형에 막히지 않는다.
const FLIGHT_SECONDS := 0.12

## 쏘고 나서 첫 캡처까지 기다리는 시간(초). 틱(1/60)보다 넉넉히 길어야 총알이 실제로
## 생기고, 짧아야 총구 근처에서 잡힌다.
const MUZZLE_SECONDS := 0.06

## 물 통과 검사 — 물가에서 동쪽으로 이만큼까지 훑어서 바다를 찾고, 이어진 바다가
## 그만큼은 돼야 "물 위로 쐈다"고 할 수 있다.
const SEA_SCAN_TILES := 6
const SEA_MIN_TILES := 2

## 물 위로 쏜 총알을 견주기까지 기다리는 시간(초). 바다의 끝(최대 6.5칸 = 312단위)을
## 넘기고도 사거리(800 = 0.89초)에는 한참 못 미치는 값이다.
const WATER_FLIGHT_SECONDS := 0.55

## 예광탄 색을 알아보는 문턱. 픽셀 비교(`DIFF_EPSILON`)보다 느슨하다 — 총알은 배경
## 위에 그려지고 선 끝이 살짝 섞이지만, 풀밭과는 애초에 색이 한참 멀다.
const TRACER_EPSILON := 0.03

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

var _shots := {}
var _line_width := {}
var _focus_before_shot := 1.0
var _muzzle := Vector2.ZERO
var _travelled_first := 0.0
var _shore_tile := Vector2i.ZERO
var _shore_sea_far := 0


## 이동 코어(`player_motion.gd`) 검사용 가짜 월드 — `is_land()` 하나만 본다. 지형 생성
## 전체를 끌고 오지 않아야 "바다 한 줄"처럼 원하는 모양을 정확히 만들 수 있다.
##
## **총알 코어는 여기에 안 나온다** — `bullets.gd` 는 이제 월드를 받지 않는다(물은
## 걸어서 못 건너지만 총알은 통과한다, docs/DESIGN.md 「전투」).
class SeaWorld extends RefCounted:
	## 이 x 타일 한 줄만 바다다. -1 이면 전부 땅이다.
	var sea_tile := -1

	func is_land(x: int, _y: int) -> bool:
		return x != sea_tile


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(SHOTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))

	_check_core()

	_enter_world()
	_steps = [
		_settle,
		_stand_on_open_land,
		_aim_right,
		_settle,
		_settle,
		_check_aimed_right,
		# 8~9) 조준선 — 같은 자리에서 세 장을 찍어 픽셀로 견준다.
		func(): _show_line(false),
		_settle,
		func(): _remember_shot("no_line"),
		func(): _show_line(true),
		_settle,
		func(): _set_focus(1.0),
		_settle,
		func(): _measure_line("focused"),
		func(): _shoot("80_aim_line_focused"),
		func(): _set_focus(0.0),
		_settle,
		func(): _measure_line("blurred"),
		func(): _shoot("81_aim_line_blurred"),
		_check_line_sharpens_with_focus,
		# 8) 다른 도구를 들면 사라진다
		_hold_axe,
		_settle,
		func(): _measure_line("axe"),
		func(): _shoot("82_aim_line_axe"),
		_check_line_gone_with_axe,
		_hold_gun,
		_settle,
		# 10) 창이 열리면 꺼진다
		func(): _send_action("ui_cancel"),
		_settle,
		_check_line_off_while_paused,
		func(): _send_action("ui_cancel"),
		_settle,
		_check_line_back_after_close,
		# 11~12) 좌클릭 → 총알이 나가고 날아간다
		func(): _set_focus(1.0),
		_settle,
		_fire_once,
		func(): _wait_time = MUZZLE_SECONDS,
		func(): _shoot("83_bullet_fired"),
		_check_bullet_left_muzzle,
		func(): _wait_time = FLIGHT_SECONDS,
		func(): _shoot("84_bullet_flying"),
		_check_bullet_flew_further,
		# 13) 물 위로 쏘면 지나간다 / 그 자리에서 사람은 여전히 물에 못 들어간다
		_stand_on_shore,
		_aim_right,
		_settle,
		func(): _set_focus(1.0),
		_wait_for_empty_sky,
		_check_sky_empty,
		_fire_over_water,
		func(): _wait_time = WATER_FLIGHT_SECONDS,
		func(): _shoot("85_bullet_over_water"),
		_check_bullet_crossed_water,
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
		if _fails.is_empty():
			print("[qa] PASS — 총알(투사체) + 조준선")
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


# =============================================================================
# A. 코어 — 화면 없이 도는 부분
# =============================================================================

func _check_core() -> void:
	_check_step_smaller_than_tile()
	_check_not_hitscan()
	_check_range()
	_check_water_does_not_block()
	_check_blocker_seam()
	_check_raw_angle()
	_check_focus()
	_check_spread()
	_check_hit_test_seam()


## 3-1) **한 틱/한 걸음 이동량이 타일(48)보다 훨씬 작다.** 이게 깨지면 아래 벽 검사가
## 우연히 통과할 수도 있으므로 값 자체를 먼저 못 박는다 (docs/GOTCHAS.md).
func _check_step_smaller_than_tile() -> void:
	var per_tick := Bullets.SPEED * Bullets.TICK_DELTA
	if per_tick >= float(WorldGen.TILE_SIZE):
		_fails.append("코어: 한 틱 이동량(%.1f)이 타일(%d)보다 크다 — 벽을 건너뛴다"
				% [per_tick, WorldGen.TILE_SIZE])
	if Bullets.MAX_STEP > float(WorldGen.TILE_SIZE) * 0.5:
		_fails.append("코어: 한 걸음(%.1f)이 타일 절반보다 크다" % Bullets.MAX_STEP)


## 1) **즉시판정이 아니다** — 쏜 순간에는 총구에 있고, 틱마다 정해진 만큼만 간다.
func _check_not_hitscan() -> void:
	var bullets := Bullets.new()
	var origin := Vector2(1000.0, 1000.0)
	var entry := bullets.fire(origin, 0.0)
	if bullets.size() != 1:
		_fails.append("코어: 쐈는데 총알이 안 생겼다")
		return
	if (entry[Bullets.KEY_POSITION] as Vector2) != origin:
		_fails.append("코어: 쏜 순간 총알이 이미 총구를 떠나 있다 — 즉시판정이다")
	var per_tick := Bullets.SPEED * Bullets.TICK_DELTA
	bullets.tick()
	var moved := (entry[Bullets.KEY_POSITION] as Vector2).distance_to(origin)
	if absf(moved - per_tick) > 0.01:
		_fails.append("코어: 한 틱에 %.2f 를 갔다 — %.2f 여야 한다" % [moved, per_tick])
	# 400 떨어진 자리는 한 틱에 닿을 수 없다(즉시판정이면 닿는다).
	var ticks := 1
	while bullets.size() > 0 and (entry[Bullets.KEY_POSITION] as Vector2).x < origin.x + 400.0:
		bullets.tick()
		ticks += 1
	if ticks < 20:
		_fails.append("코어: 400 을 %d틱 만에 갔다 — 투사체라기엔 너무 빠르다" % ticks)


## 2) 사거리를 다 날아가면 그 자리에서 사라진다.
func _check_range() -> void:
	var bullets := Bullets.new()
	var origin := Vector2(1000.0, 1000.0)
	var entry := bullets.fire(origin, 0.0)
	var ticks := 0
	while bullets.size() > 0 and ticks < 1000:
		bullets.tick()
		ticks += 1
	if bullets.size() != 0:
		_fails.append("코어: 사거리를 넘겨도 총알이 안 사라진다")
		return
	var flown := (entry[Bullets.KEY_POSITION] as Vector2).distance_to(origin)
	if absf(flown - Bullets.RANGE) > 0.01:
		_fails.append("코어: 사거리 %.0f 를 지나 %.1f 까지 날아갔다" % [Bullets.RANGE, flown])
	var expected := int(ceil(Bullets.RANGE / (Bullets.SPEED * Bullets.TICK_DELTA)))
	if ticks != expected:
		_fails.append("코어: 사거리를 %d틱에 갔다 — %d틱이어야 한다" % [ticks, expected])


## 3-1) **물은 총알을 막지 않는다** (docs/DESIGN.md 「전투」 2026-09-07 사람 결정 —
## *"한 칸 물이 있다고 해서 거기에 막히면 안 되잖아"*). **같은 지도 · 같은 칸**에 둘을
## 나란히 물어본다: 사람은 못 들어가고 총알은 지나간다. 두 판정이 도로 하나로 붙으면
## 둘 중 하나가 반드시 어긋난다.
func _check_water_does_not_block() -> void:
	var world := SeaWorld.new()
	world.sea_tile = 10
	var sea := WorldGen.tile_center(Vector2i(world.sea_tile, 5))

	# 사람 — 이동 판정은 이번 바퀴가 건드리지 않았다.
	var motion := PlayerMotion.new(world)
	if not motion.blocked_at(sea):
		_fails.append("코어: 바다 칸 %d 인데 사람이 걸어 들어갈 수 있다 — 이동 판정이 바뀌었다"
				% world.sea_tile)

	# 총알 — 같은 칸을 지나가고, 사거리를 다 쓰고 나서야 사라진다.
	var bullets := Bullets.new()
	var origin := WorldGen.tile_center(Vector2i(2, 5))
	var entry := bullets.fire(origin, 0.0)
	var ticks := 0
	while bullets.size() > 0 and ticks < 1000:
		bullets.tick()
		ticks += 1
	var at: Vector2 = entry[Bullets.KEY_POSITION]
	if at.x <= sea.x:
		_fails.append("코어: 총알이 바다 칸(x=%.0f) 앞 %.0f 에서 멈췄다 — 물에 막혔다"
				% [sea.x, at.x])
	if absf(float(entry[Bullets.KEY_TRAVELLED]) - Bullets.RANGE) > 0.01:
		_fails.append("코어: 막는 것이 없는데 총알이 %.1f 만에 사라졌다 — 사거리(%.0f)를 다 써야 한다"
				% [entry[Bullets.KEY_TRAVELLED], Bullets.RANGE])


## 3-2) **총알을 막는 것이 들어올 자리**(`blocks_bullet`)가 실제로 동작하고, 막는 것이
## **한 칸짜리여도 통째로 건너뛰지 않는다.**
##
## **지금 게임 안에는 총알을 막는 것이 하나도 없다** — 벽도 나무도 아직 없기 때문이다
## (docs/DESIGN.md 「전투」). 그래서 검사가 벽을 직접 꽂아 넣는다. 나무·벽을 만드는
## 바퀴는 여기에 그 오브젝트를 꽂아 같은 검사를 다시 쓰면 된다.
func _check_blocker_seam() -> void:
	var wall := 10
	var bullets := Bullets.new()
	bullets.blocks_bullet = func(point: Vector2) -> bool:
		return WorldGen.world_to_tile(point).x == wall
	# 벽에서 8칸 앞에서 벽을 향해 쏜다.
	var origin := WorldGen.tile_center(Vector2i(2, 5))
	var entry := bullets.fire(origin, 0.0)
	var ticks := 0
	while bullets.size() > 0 and ticks < 1000:
		bullets.tick()
		ticks += 1
	if bullets.size() != 0:
		_fails.append("코어: 벽에 닿았는데 총알이 안 사라졌다")
		return
	var tile := WorldGen.world_to_tile(entry[Bullets.KEY_POSITION] as Vector2)
	if tile.x != wall:
		_fails.append("코어: 총알이 벽 칸(%d)이 아니라 %d 칸에서 사라졌다 — 벽을 건너뛰었다"
				% [wall, tile.x])
	if float(entry[Bullets.KEY_TRAVELLED]) >= Bullets.RANGE:
		_fails.append("코어: 벽에 안 막히고 사거리를 다 썼다")
	# 검사에 이가 있는지 — 아무것도 안 꽂으면 같은 총알이 사거리까지 간다.
	var open_bullets := Bullets.new()
	var open_entry := open_bullets.fire(origin, 0.0)
	for i in 1000:
		if open_bullets.size() == 0:
			break
		open_bullets.tick()
	if absf(float(open_entry[Bullets.KEY_TRAVELLED]) - Bullets.RANGE) > 0.01:
		_fails.append("코어: 막는 것을 안 꽂았는데도 총알이 사거리 전에 사라졌다")


## 4) 각도는 스냅된 4방향이 아니라 **원본 조준 각도**다 (docs/DESIGN.md 「조작」).
func _check_raw_angle() -> void:
	var world := SeaWorld.new()
	var motion := PlayerMotion.new(world)
	var raw := 0.35  # 오른쪽으로 스냅되지만 정확히 오른쪽은 아닌 각도
	motion.tick(PlayerInput.new(Vector2i.ZERO, raw))
	if motion.facing != PlayerMotion.RIGHT:
		_fails.append("코어: %.2f 라디안이 오른쪽으로 안 스냅됐다" % raw)
	if absf(motion.aim_angle - raw) > 0.0001:
		_fails.append("코어: 조준 각도가 스냅돼 버렸다 (%.3f)" % motion.aim_angle)
	var bullets := Bullets.new()
	var entry := bullets.fire(Vector2.ZERO, motion.aim_angle)
	var fired := (entry[Bullets.KEY_DIRECTION] as Vector2).angle()
	if absf(angle_difference(fired, raw)) > 0.0001:
		_fails.append("코어: 총알이 %.3f 로 나갔다 — %.3f 여야 한다 (4방향으로 뭉갰다)"
				% [fired, raw])


## 5) 정조준 — 서 있으면 모이고, 움직이면 흩어지고, 반동으로 깎이고, 0~1 을 안 넘는다.
func _check_focus() -> void:
	var motion := PlayerMotion.new(SeaWorld.new())
	var standing := PlayerInput.new(Vector2i.ZERO, 0.0)
	var walking := PlayerInput.new(Vector2i(1, 0), 0.0)

	motion.aim_focus = 0.0
	for i in PlayerMotion.TICK_RATE:
		motion.tick(standing)
	if absf(motion.aim_focus - PlayerMotion.FOCUS_GAIN) > 0.01:
		_fails.append("코어: 1초 서 있었더니 정조준이 %.2f 다 — %.2f 여야 한다"
				% [motion.aim_focus, PlayerMotion.FOCUS_GAIN])

	motion.aim_focus = 1.0
	for i in PlayerMotion.TICK_RATE / 2:
		motion.tick(walking)
	var expected := 1.0 - PlayerMotion.FOCUS_LOSS * 0.5
	if absf(motion.aim_focus - expected) > 0.01:
		_fails.append("코어: 0.5초 걸었더니 정조준이 %.2f 다 — %.2f 여야 한다"
				% [motion.aim_focus, expected])

	# 오래 서 있어도 1 을 안 넘고, 오래 걸어도 0 밑으로 안 간다.
	for i in PlayerMotion.TICK_RATE * 5:
		motion.tick(standing)
	if motion.aim_focus != 1.0:
		_fails.append("코어: 오래 서 있었는데 정조준이 %.3f 다 — 1.0 이어야 한다" % motion.aim_focus)
	for i in PlayerMotion.TICK_RATE * 5:
		motion.tick(walking)
	if motion.aim_focus != 0.0:
		_fails.append("코어: 오래 걸었는데 정조준이 %.3f 다 — 0.0 이어야 한다" % motion.aim_focus)

	# 반동 — 한 발 쏘면 그만큼 깎이고, 바닥 아래로는 안 내려간다.
	motion.aim_focus = 1.0
	motion.apply_recoil()
	if absf(motion.aim_focus - (1.0 - PlayerMotion.RECOIL_KICK)) > 0.0001:
		_fails.append("코어: 반동으로 정조준이 %.2f 가 됐다" % motion.aim_focus)
	motion.apply_recoil()
	motion.apply_recoil()
	if motion.aim_focus != 0.0:
		_fails.append("코어: 반동이 0 밑으로 내려갔다 (%.2f)" % motion.aim_focus)

	# 좌클릭 한 번에 `use_started` 는 그 틱 하나에만 참이다(= 한 발).
	motion.aim_focus = 1.0
	var clicking := PlayerInput.new(Vector2i.ZERO, 0.0, 0, true)
	var starts := 0
	for i in PlayerMotion.USE_TICKS:
		motion.tick(clicking)
		if motion.use_started:
			starts += 1
	if starts != 1:
		_fails.append("코어: 좌클릭을 누르고 있는 %d틱 동안 %d발이 시작됐다 — 1발이어야 한다"
				% [PlayerMotion.USE_TICKS, starts])


## 6) **탄퍼짐은 정조준 하나에서 나온다** — 조준선 선명도와 같은 값이다.
func _check_spread() -> void:
	var motion := PlayerMotion.new(SeaWorld.new())
	motion.aim_focus = 1.0
	if motion.spread_angle() != 0.0:
		_fails.append("코어: 완전히 조준했는데 탄퍼짐이 %.4f 다" % motion.spread_angle())
	motion.aim_focus = 0.0
	var full := deg_to_rad(PlayerMotion.MAX_SPREAD_DEGREES)
	if absf(motion.spread_angle() - full) > 0.0001:
		_fails.append("코어: 조준이 풀렸는데 탄퍼짐이 %.4f 다 — %.4f 여야 한다"
				% [motion.spread_angle(), full])
	motion.aim_focus = 0.5
	if absf(motion.spread_angle() - full * 0.5) > 0.0001:
		_fails.append("코어: 탄퍼짐이 정조준에 비례하지 않는다")

	# 실제로 굴려본다 — 전부 퍼짐 안이고, 한 각도에 몰려 있지 않다.
	var bullets := Bullets.new()
	bullets.set_random_seed(12345)
	var angles: Array[float] = []
	for i in 40:
		var entry := bullets.fire(Vector2.ZERO, 0.0, full)
		angles.append((entry[Bullets.KEY_DIRECTION] as Vector2).angle())
	var spread_seen := 0.0
	for a in angles:
		if absf(a) > full + 0.0001:
			_fails.append("코어: 총알이 탄퍼짐(%.4f) 밖인 %.4f 로 나갔다" % [full, a])
			break
		spread_seen = maxf(spread_seen, absf(a))
	if spread_seen < full * 0.5:
		_fails.append("코어: 40발이 전부 퍼짐의 절반 안에 몰렸다 — 퍼짐이 안 굴러갔다")
	# 씨앗이 같으면 같은 결과 — 나중에 서버가 판정을 재현할 수 있어야 한다.
	var again := Bullets.new()
	again.set_random_seed(12345)
	for i in angles.size():
		var entry := again.fire(Vector2.ZERO, 0.0, full)
		if absf((entry[Bullets.KEY_DIRECTION] as Vector2).angle() - angles[i]) > 0.0001:
			_fails.append("코어: 같은 씨앗인데 탄퍼짐이 다르게 굴렀다")
			break
	# 탄퍼짐이 0 이면 조준 각도 그대로다.
	var straight := Bullets.new()
	var one := straight.fire(Vector2.ZERO, 0.0, 0.0)
	if (one[Bullets.KEY_DIRECTION] as Vector2).angle() != 0.0:
		_fails.append("코어: 퍼짐이 0 인데 총알이 빗나갔다")


## 7) 대상 명중 판정의 **자리**가 실제로 불린다 — 한 걸음짜리 선분으로.
## (지금은 맞을 대상이 없으므로 이 자리만 검증한다 — 동물이 오는 바퀴가 채운다.)
func _check_hit_test_seam() -> void:
	var bullets := Bullets.new()
	var hits: Array = []
	var lengths: Array = []
	# 람다는 바깥 지역변수를 값으로 캡처한다 — 배열에 담아 우회한다 (docs/GOTCHAS.md).
	bullets.hit_test = func(from: Vector2, to: Vector2) -> Variant:
		lengths.append(from.distance_to(to))
		if to.x >= 300.0:
			hits.append(to)
			return "표적"
		return null
	var entry := bullets.fire(Vector2(100.0, 100.0), 0.0)
	for i in 100:
		if bullets.size() == 0:
			break
		bullets.tick()
	if hits.size() != 1:
		_fails.append("코어: 명중 판정이 %d번 맞췄다고 했다 — 1번이어야 한다" % hits.size())
	if bullets.size() != 0:
		_fails.append("코어: 대상에 맞았는데 총알이 안 사라졌다")
	var at: Vector2 = entry[Bullets.KEY_POSITION]
	if at.x < 300.0 or at.x > 300.0 + Bullets.MAX_STEP:
		_fails.append("코어: 총알이 맞은 자리(x=%.1f)가 표적(300)에서 한 걸음 넘게 떨어졌다" % at.x)
	if lengths.is_empty():
		_fails.append("코어: 명중 판정이 한 번도 안 불렸다")
		return
	for length: float in lengths:
		if length > Bullets.MAX_STEP + 0.0001:
			_fails.append("코어: 명중 판정에 %.1f 짜리 선분이 넘어왔다 — 한 걸음(%.1f) 이하여야 한다"
					% [length, Bullets.MAX_STEP])
			break


# =============================================================================
# B. 화면 — 실제 월드 씬에서
# =============================================================================

## 9) 정조준이 풀릴수록 선이 넓게 번진다.
func _check_line_sharpens_with_focus() -> void:
	var focused: int = _line_width.get("focused", 0)
	var blurred: int = _line_width.get("blurred", 0)
	if focused < 2:
		_fails.append("정조준했는데 조준선이 화면에 %d px 밖에 안 보인다" % focused)
		return
	if blurred < focused * 3:
		_fails.append("조준이 풀렸는데 선이 안 번졌다 (선명 %d px ↔ 흐림 %d px)"
				% [focused, blurred])


## 8) 다른 도구를 들면 조준선이 사라진다.
func _check_line_gone_with_axe() -> void:
	if bool(_aim_line().get("armed")):
		_fails.append("도끼를 들었는데 조준선이 켜져 있다")
	var axe: int = _line_width.get("axe", -1)
	if axe != 0:
		_fails.append("도끼를 들었는데 조준선 자리에 %d px 이 남아 있다" % axe)


func _check_line_off_while_paused() -> void:
	if bool(_aim_line().get("armed")):
		_fails.append("일시정지 메뉴가 열렸는데 조준선이 켜져 있다")


func _check_line_back_after_close() -> void:
	if not bool(_aim_line().get("armed")):
		_fails.append("메뉴를 닫았는데 조준선이 안 돌아왔다")


## 11) 쏜 직후 — 총알이 하나 생겼고 **아직 총구 근처에 있다**(즉시판정이면 실패한다).
## 12) 그리고 반동으로 정조준이 깎였다.
func _check_bullet_left_muzzle() -> void:
	var bullets := _bullets()
	if bullets == null or bullets.size() != 1:
		_fails.append("좌클릭했는데 총알이 %d개다 — 1개여야 한다"
				% (0 if bullets == null else bullets.size()))
		return
	var entry: Dictionary = bullets.bullets[0]
	_travelled_first = float(entry[Bullets.KEY_TRAVELLED])
	if _travelled_first <= 0.0:
		_fails.append("총알이 아직 총구에 붙어 있다")
	if _travelled_first > Bullets.RANGE * 0.5:
		_fails.append("쏜 직후에 총알이 벌써 %.0f 를 갔다 — 사실상 즉시판정이다" % _travelled_first)
	# 총알이 조준 방향(오른쪽)으로 나갔는가.
	var at: Vector2 = entry[Bullets.KEY_POSITION]
	if at.x <= _muzzle.x or absf(at.y - _muzzle.y) > 20.0:
		_fails.append("총알이 조준 방향으로 안 나갔다 (총구 %s → %s)" % [_muzzle, at])
	# 화면에 실제로 보이는가 — 예광탄 심지 색을 총구 높이에서 찾는다.
	if _tracer_max_x(_capture()) < 0:
		_fails.append("총알이 화면에 안 보인다")
	# 12) 반동으로 정조준이 깎였다.
	var now: float = _player().motion.aim_focus
	if now > _focus_before_shot - PlayerMotion.RECOIL_KICK * 0.5:
		_fails.append("쏘고 나서 정조준이 %.2f 다 — 쏘기 전 %.2f 에서 깎였어야 한다"
				% [now, _focus_before_shot])


## 11) 잠시 뒤 — 같은 총알이 더 멀리 가 있다(그리고 화면에서도 오른쪽으로 옮겨졌다).
func _check_bullet_flew_further() -> void:
	var bullets := _bullets()
	if bullets == null or bullets.size() != 1:
		_fails.append("날아가던 총알이 %.2f초 만에 사라졌다"
				% FLIGHT_SECONDS)
		return
	var travelled := float((bullets.bullets[0] as Dictionary)[Bullets.KEY_TRAVELLED])
	var expected := Bullets.SPEED * FLIGHT_SECONDS
	if travelled - _travelled_first < expected * 0.6:
		_fails.append("총알이 %.2f초 동안 %.0f 밖에 안 갔다 — %.0f 쯤 가야 한다"
				% [FLIGHT_SECONDS, travelled - _travelled_first, expected])
	var tracer := _tracer_max_x(_capture())
	if tracer < 0:
		_fails.append("날아가는 총알이 화면에 안 보인다")


## 13) 물가에서 물 건너로 쏜 총알이 **바다를 지나갔다.**
func _check_bullet_crossed_water() -> void:
	if _shore_sea_far <= 0:
		return
	var bullets := _bullets()
	if bullets == null or bullets.size() != 1:
		_fails.append("물 위로 쏜 총알이 %.2f초 만에 사라졌다 — 물에 막혔다"
				% WATER_FLIGHT_SECONDS)
		return
	# 바다의 **먼 쪽 끝**까지의 거리. 총구는 물가 칸의 한가운데다.
	var across := (float(_shore_sea_far) + 0.5) * float(WorldGen.TILE_SIZE)
	var travelled := float((bullets.bullets[0] as Dictionary)[Bullets.KEY_TRAVELLED])
	if travelled < across:
		_fails.append("총알이 %.2f초 동안 %.0f 밖에 안 갔다 — 바다 끝(%.0f)을 지나가야 한다"
				% [WATER_FLIGHT_SECONDS, travelled, across])
		return
	var at: Vector2 = (bullets.bullets[0] as Dictionary)[Bullets.KEY_POSITION]
	print("[qa] 물가 %s 에서 바다 %d칸 너머로 총알이 지나갔다 (%.0f 단위, 지금 %s)"
			% [_shore_tile, _shore_sea_far, travelled, at])


## 13) **같은 자리에서 사람은 여전히 물에 못 들어간다** — 이동 판정을 안 건드렸다는
## 확인이다(INBOX #39 의 *"`player_motion.gd` 의 이동 판정은 건드리지 말 것"*).
func _check_stopped_on_land() -> void:
	_release_all()
	if _shore_sea_far <= 0:
		return
	var player := _player()
	var tile: Vector2i = player.tile()
	if not _world().is_land(tile.x, tile.y):
		_fails.append("총알이 지나간 바다로 사람도 걸어 들어갔다 (칸 %s)" % tile)
	elif player.motion.blocked_at(player.position):
		_fails.append("몸통이 바다에 걸친 채로 멈췄다: %s" % player.position)
	else:
		print("[qa] 같은 물가에서 사람은 땅 칸 %s 에서 멈춘다" % tile)
	_shoot("86_player_stopped_at_shore")


# =============================================================================
# 도우미
# =============================================================================

func _enter_world() -> void:
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("총잡이", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)


func _settle() -> void:
	_wait_time = SETTLE_SECONDS


## 사방이 육지인 자리에 세운다 — 총알이 검사 내내(약 160단위 = 3.4칸) 지형에 막히지
## 않아야 한다. **넓은 곳부터 찾고 없으면 좁혀 간다** — 시드에 따라 아주 넓은 빈터가
## 없을 수도 있는데, 못 찾았다고 검사를 접는 것보다 5칸짜리라도 쓰는 쪽이 낫다.
func _stand_on_open_land() -> void:
	var world := _world()
	var spawn: Vector2i = world.spawn_tile
	for clearing: int in [8, 6, 5]:
		for radius in range(0, 40):
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var tile := spawn + Vector2i(dx, dy)
					if _land_around(world, tile, clearing):
						_player().place_at(WorldGen.tile_center(tile))
						return
	_fails.append("사방이 육지인 자리를 못 찾았다")


## 물 건너로 쏠 수 있는 물가에 세운다 — **동쪽에 바다가 이어진 땅 칸**이다.
## 못 찾으면 뒤따르는 검사들을 통째로 건너뛴다(시드가 그런 자리를 안 만들 수도 있다).
func _stand_on_shore() -> void:
	var world := _world()
	var spawn: Vector2i = world.spawn_tile
	for radius in range(0, 60):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := spawn + Vector2i(dx, dy)
				var far := _sea_run_east(world, tile)
				if far > 0:
					_shore_tile = tile
					_shore_sea_far = far
					_player().place_at(WorldGen.tile_center(tile))
					return
	print("[qa] 동쪽에 바다가 이어진 물가를 못 찾아 물 통과 검사를 건너뛴다")


## `tile` 이 땅이고 그 **동쪽**으로 `SEA_MIN_TILES` 칸 이상 바다가 이어지면, 그 바다의
## 마지막 칸까지의 거리(타일 수)를 돌려준다. 아니면 0.
func _sea_run_east(world: RefCounted, tile: Vector2i) -> int:
	if not world.is_land(tile.x, tile.y):
		return 0
	var first := 1
	while first <= SEA_SCAN_TILES and world.is_land(tile.x + first, tile.y):
		first += 1
	if first > SEA_SCAN_TILES:
		return 0  # 앞이 전부 땅이다
	var last := first
	while last < SEA_SCAN_TILES and not world.is_land(tile.x + last + 1, tile.y):
		last += 1
	return last if last - first + 1 >= SEA_MIN_TILES else 0


## 앞서 쏜 총알이 사거리를 다 쓰고 사라질 때까지 기다린다 — 다음 한 발만 남겨두려는
## 것이다(사거리 0.89초보다 넉넉히 길게 잡는다).
func _wait_for_empty_sky() -> void:
	_wait_time = 1.2


## 그 기다림이 실제로 비웠는가 — **사거리를 다 쓰면 사라진다**를 화면 쪽에서도 본다.
func _check_sky_empty() -> void:
	var bullets := _bullets()
	if bullets != null and bullets.size() != 0:
		_fails.append("사거리를 다 쓰고도 총알 %d개가 남아 있다" % bullets.size())


func _fire_over_water() -> void:
	if _shore_sea_far <= 0:
		return
	_send_action("use_tool")


## 총알이 지나간 그 바다로 **걸어서** 들어가 본다 — 초당 5칸이라 2초면 바다까지
## 한참 남는다.
func _walk_into_the_sea() -> void:
	if _shore_sea_far <= 0:
		return
	_release_all()
	Input.action_press("move_right")
	_wait_time = 2.0


func _release_all() -> void:
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)


func _land_around(world: RefCounted, tile: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if not world.is_land(tile.x + dx, tile.y + dy):
				return false
	return true


## 마우스를 화면 오른쪽에 둬서 **정확히 수평으로** 오른쪽을 겨눈다.
## **각도를 코드로 밀어넣지 않는다** — 실제 마우스 경로를 지나가야 조준 계산까지 같이
## 검증된다 (docs/GOTCHAS.md).
##
## 화면 한가운데는 플레이어 **발밑**이고(카메라가 플레이어의 자식이다) 조준을 재는
## 기준점은 그보다 가슴 높이만큼 위다 — 그 차이를 빼주지 않으면 조금 아래로 겨누게
## 되고, 날아가는 총알이 아래 가로 띠 검사에서 빠져나간다.
func _aim_right() -> void:
	var size := root.get_visible_rect().size
	Input.warp_mouse(Vector2(size.x * 0.5 + AIM_SCREEN_DISTANCE, size.y * 0.5 - BulletsView.LIFT))


## 위 조준이 실제로 수평으로 들어갔는지 — 안 그러면 아래 검사들이 엉뚱한 자리를 본다.
func _check_aimed_right() -> void:
	var angle: float = _player().motion.aim_angle
	if absf(angle) > 0.02:
		_fails.append("오른쪽을 겨누려 했는데 조준 각도가 %.3f 라디안이다" % angle)


## 정조준을 원하는 값으로 놓는다. **움직임이 이 값을 바꾼다는 것은 코어 검사가 보고**,
## 여기서는 "이 값이 화면의 선을 얼마나 번지게 하는가"만 본다 — 화면을 견주려면
## 플레이어가 같은 자리에 서 있어야 하는데 걸으면 배경이 통째로 달라진다.
func _set_focus(value: float) -> void:
	var motion: RefCounted = _player().motion
	if motion == null:
		_fails.append("플레이어 코어가 없다")
		return
	motion.aim_focus = value


func _show_line(visible: bool) -> void:
	_aim_line().visible = visible


func _hold_axe() -> void:
	_send_action("hotbar_2")


func _hold_gun() -> void:
	_send_action("hotbar_1")


func _fire_once() -> void:
	_muzzle = _player().muzzle_position()
	_focus_before_shot = _player().motion.aim_focus
	_send_action("use_tool")


## 액션을 실제 입력으로 흘려보낸다 — 겹쳐 뜬 Control 이 마우스 버튼을 먼저 먹어도
## `InputEventAction` 은 `_unhandled_input()` 까지 간다 (docs/GOTCHAS.md).
func _send_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


## 조준선이 화면에서 차지하는 세로 폭(픽셀). **선이 없는 화면과 견줘서** 잰다 —
## 부챗살은 옅어서 "빨간가"로 세면 놓치지만, 안 그리던 자리를 칠했는지는 확실하다.
func _measure_line(key: String) -> void:
	var baseline: Image = _shots.get("no_line")
	var image := _capture()
	if baseline == null or image == null:
		_fails.append("조준선을 잴 캡처가 없다")
		return
	var player := _player()
	var top := _image_point(image, player.aim_origin() + Vector2(SAMPLE_DISTANCE, -SAMPLE_HALF))
	var bottom := _image_point(image, player.aim_origin() + Vector2(SAMPLE_DISTANCE, SAMPLE_HALF))
	var x := clampi(top.x, 0, image.get_width() - 1)
	var found := 0
	for y in range(maxi(0, top.y), mini(image.get_height(), bottom.y + 1)):
		if not _same(image.get_pixel(x, y), baseline.get_pixel(x, y)):
			found += 1
	_line_width[key] = found


## 예광탄 심지 색이 보이는 가장 오른쪽 픽셀의 x. 없으면 -1.
## 총구 높이의 가로 띠만 훑는다 — 총알은 지면이 아니라 가슴 높이에 그려진다.
func _tracer_max_x(image: Image) -> int:
	if image == null:
		return -1
	var player := _player()
	var band := BulletsView.DOT * 4.0
	var left := _image_point(image, player.muzzle_position() + Vector2(0.0, -BulletsView.LIFT - band))
	var right := _image_point(image, player.muzzle_position()
			+ Vector2(Bullets.RANGE, -BulletsView.LIFT + band))
	var best := -1
	for y in range(maxi(0, left.y), mini(image.get_height(), right.y + 1)):
		for x in range(maxi(0, left.x), mini(image.get_width(), right.x + 1)):
			if _close(image.get_pixel(x, y), BulletsView.CORE_COLOR, TRACER_EPSILON):
				best = maxi(best, x)
	return best


func _remember_shot(key: String) -> void:
	_shots[key] = _capture()


func _shoot(shot_name: String) -> void:
	var image := _capture()
	if image == null:
		return
	var path := "%s/%s.png" % [SHOTS, shot_name]
	image.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _capture() -> Image:
	var texture := root.get_texture()
	if texture == null:
		_fails.append("캡처 실패: 뷰포트 텍스처 없음 — --headless 로 돌린 건 아닌지 확인")
		return null
	return texture.get_image()


## 월드 좌표 → 캡처 이미지의 픽셀 좌표. **논리 해상도와 실제 캡처 크기가 다를 수
## 있으므로** 배율을 캡처에서 구한다 (docs/GOTCHAS.md).
func _image_point(image: Image, world_point: Vector2) -> Vector2i:
	var screen := root.get_canvas_transform() * world_point
	var zoom := float(image.get_width()) / root.get_visible_rect().size.x
	return Vector2i((screen * zoom).round())


func _same(a: Color, b: Color) -> bool:
	return _close(a, b, DIFF_EPSILON)


func _close(a: Color, b: Color, epsilon: float) -> bool:
	return absf(a.r - b.r) <= epsilon and absf(a.g - b.g) <= epsilon \
			and absf(a.b - b.b) <= epsilon


func _world() -> RefCounted:
	return current_scene.get("world")


func _bullets() -> RefCounted:
	return current_scene.get("bullets")


func _player() -> Node2D:
	return current_scene.get_node("%Player") as Node2D


func _aim_line() -> Node2D:
	return current_scene.get_node("%AimLine") as Node2D
