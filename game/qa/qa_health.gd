extends SceneTree

## INBOX #36 자체 QA — 플레이어 체력 100 / 죽음 / 리스폰.
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_health.gd
##
## **아직 게임 안에서 죽을 방법이 없다** — 동물이 없고 이 서버는 PvE 라 사람도 서로
## 안 맞는다(docs/DESIGN.md 「전투」). 그래서 이 검사가 코드로 데미지를 준다
## (`take_damage()` 를 직접 부른다) — INBOX #36 (3) 이 정해둔 방식이다.
##
## 확인하는 것:
##   A. 코어(`player_health.gd` / `player_motion.gd` — 화면 없이 도는 순수 클래스)
##      1) 최대 체력 100 — 처음엔 가득이고 살아 있다.
##      2) 데미지는 **실제로 깎인 양**을 돌려주고 0 아래로 안 내려간다. 1 이라도
##         남아 있으면 안 죽고, 0 이 되어야 죽는다.
##      3) 죽으면 **다음 틱에** 리스폰 지점에서 되살아난다 — 자리는 리스폰 지점,
##         체력은 가득이고, `respawned` 는 **그 틱 하나에만** 참이다.
##      4) **리스폰 지점은 값 하나다** — 그 값을 바꾸면 그 자리에서 되살아난다
##         (나중에 침대가 덮어쓸 자리). 텔레포트(`place_at`)로는 안 따라간다.
##      5) 살아 있는 동안은 아무리 틱을 돌려도 리스폰하지 않는다(제자리에 있는다).
##      6) 휘두르던 도중에 죽으면 그 사용 모션은 끊긴다.
##   B. 화면(실제 월드 씬에서)
##      7) 월드에 들어오면 체력이 가득이고 **리스폰 지점 = 스폰 칸**이다.
##      8) **다쳐도 화면에 새 상시 HUD 가 생기지 않는다** — docs/DESIGN.md
##         「인벤토리 / 장비」의 "체력·허기 같은 것을 여기에 덧붙이지 말 것".
##         체력 100 일 때와 40 일 때의 화면이 같은지 픽셀로 본다.
##      9) 스폰에서 멀리 떨어지면 화면이 실제로 달라진다(9번이 있어야 10번이 뜻을 갖는다).
##     10) **죽으면 스폰 지점 화면으로 돌아온다** — 캡처가 7번 자리의 것과 다시 같아진다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const PlayerHealth := preload("res://scripts/player_health.gd")
const PlayerMotion := preload("res://scripts/player_motion.gd")
const PlayerInput := preload("res://scripts/player_input.gd")
const Inventory := preload("res://scripts/inventory.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260907

## 프레임 수가 아니라 **시간**으로 기다린다 (docs/GOTCHAS.md).
const SETTLE_SECONDS := 0.3

## 첫 캡처 전에 한 번 길게 기다린다 — 조준선은 정조준(`aim_focus`)이 다 모여야
## 진하기가 멈추므로(바닥에서 1.1초), 그 전에 찍으면 뒤의 캡처와 저절로 달라진다.
const FOCUS_SECONDS := 1.6

## 스폰에서 이만큼 떨어진 땅으로 옮긴다. 풀밭 무늬는 좌표 해시로 갈리므로
## (docs/DESIGN.md 「월드 생성」) 이 거리면 화면이 확실히 달라진다.
const FAR_TILES := 20

## 두 캡처의 표본 격자 한 변. 32 × 32 = 1024 점을 견준다.
const SAMPLE_GRID := 32

## 픽셀이 "같다"고 보는 문턱 (qa_gun_ammo.gd 와 같은 값).
const DIFF_EPSILON := 0.008

## "같은 화면"으로 볼 표본 일치율. 렌더링 흔들림 몇 점은 봐준다.
const SAME_RATIO := 0.99

## "다른 화면"으로 볼 상한. 20칸 떨어지면 무늬가 통째로 갈리므로 훨씬 아래로 떨어진다.
const DIFFERENT_RATIO := 0.95

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

## 캡처 이름 → 표본 색 배열.
var _samples := {}
var _far_position := Vector2.ZERO


## 코어 검사용 가짜 월드 — `player_motion.gd` 는 `is_land()` 하나만 본다.
class OpenWorld extends RefCounted:
	func is_land(_x: int, _y: int) -> bool:
		return true


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(SHOTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))

	_check_core()

	_enter_world()
	_steps = [
		_settle,
		_empty_inventory,
		_aim_right,
		func(): _wait_time = FOCUS_SECONDS,
		# 7) 들어오면 가득이고 리스폰 지점이 스폰 칸이다
		_check_spawn_state,
		func(): _remember_samples("spawn"),
		func(): _shoot("91_health_spawn"),
		# 8) 다쳐도 화면에 새 HUD 가 생기지 않는다
		_hurt_but_alive,
		_settle,
		_check_still_alive,
		func(): _remember_samples("hurt"),
		func(): _shoot("92_health_hurt"),
		_check_no_new_hud_when_hurt,
		# 9) 멀리 떨어지면 화면이 달라진다
		_go_far,
		_settle,
		func(): _remember_samples("far"),
		func(): _shoot("93_health_far"),
		_check_far_looks_different,
		# 10) 죽으면 스폰 지점으로 돌아온다
		_kill,
		_settle,
		_check_respawned_on_screen,
		func(): _remember_samples("respawned"),
		func(): _shoot("94_health_respawned"),
		_check_respawn_looks_like_spawn,
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
			print("[qa] PASS — 체력 100 + 죽음 + 리스폰")
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
	_check_max_health()
	_check_damage_math()
	_check_respawn_next_tick()
	_check_respawn_point_is_one_value()
	_check_alive_never_respawns()
	_check_use_motion_is_cut()


## 1) 최대 체력 100 (docs/DESIGN.md 「체력 / 죽음 / 리스폰」 — 사슴과 같은 값).
func _check_max_health() -> void:
	if PlayerHealth.MAX_HEALTH != 100:
		_fails.append("코어: 최대 체력이 %d 다 — 「체력 / 죽음 / 리스폰」은 100 이다"
				% PlayerHealth.MAX_HEALTH)
	var health := PlayerHealth.new()
	if health.current != PlayerHealth.MAX_HEALTH:
		_fails.append("코어: 처음 체력이 %d 다 — 가득이어야 한다" % health.current)
	if health.is_dead():
		_fails.append("코어: 처음부터 죽어 있다")


## 2) 데미지는 실제로 깎인 양을 돌려주고 0 아래로 안 내려간다.
func _check_damage_math() -> void:
	var health := PlayerHealth.new()
	if health.take_damage(25) != 25:
		_fails.append("코어: 25 데미지가 25 만큼 안 깎였다")
	if health.current != 75:
		_fails.append("코어: 25 맞고 체력이 %d 다 — 75 여야 한다" % health.current)
	if health.take_damage(0) != 0 or health.take_damage(-5) != 0:
		_fails.append("코어: 0/음수 데미지가 체력을 건드렸다")
	if health.current != 75:
		_fails.append("코어: 0/음수 데미지 뒤 체력이 %d 다" % health.current)
	# 1 이라도 남아 있으면 안 죽는다.
	health.take_damage(74)
	if health.current != 1:
		_fails.append("코어: 74 를 더 맞고 체력이 %d 다 — 1 이어야 한다" % health.current)
	if health.is_dead():
		_fails.append("코어: 체력 1 인데 죽었다고 한다")
	# 남은 것보다 큰 데미지는 남은 만큼만 깎인다(0 아래로 안 내려간다).
	if health.take_damage(999) != 1:
		_fails.append("코어: 체력 1 에 999 데미지가 1 이 아닌 값을 깎았다")
	if health.current != 0:
		_fails.append("코어: 죽은 뒤 체력이 %d 다 — 0 이어야 한다" % health.current)
	if not health.is_dead():
		_fails.append("코어: 체력 0 인데 안 죽었다고 한다")
	health.refill()
	if health.current != PlayerHealth.MAX_HEALTH or health.is_dead():
		_fails.append("코어: 되살렸는데 체력이 %d 다" % health.current)


## 3) 죽으면 **다음 틱에** 리스폰 지점에서 되살아난다. `respawned` 는 그 틱 하나뿐이다.
func _check_respawn_next_tick() -> void:
	var motion := PlayerMotion.new(OpenWorld.new())
	if motion.health == null:
		_fails.append("코어: 플레이어 코어가 체력을 안 들고 있다 — 화면 상태가 되어 버렸다")
		return
	var home := Vector2(1000.0, 1000.0)
	motion.set_respawn(home)
	motion.place_at(Vector2(5000.0, 2000.0))
	var idle := PlayerInput.new()
	# 아직 안 죽었다 — 틱을 돌려도 제자리다.
	motion.tick(idle)
	if motion.respawned:
		_fails.append("코어: 멀쩡한데 리스폰했다고 한다")
	if motion.take_damage(PlayerHealth.MAX_HEALTH) != PlayerHealth.MAX_HEALTH:
		_fails.append("코어: 코어를 통해 준 데미지가 체력에 안 닿았다")
	if not motion.health.is_dead():
		_fails.append("코어: 최대 체력만큼 맞았는데 안 죽었다")
	# **죽은 그 순간에는 아직 안 옮겨진다** — 리스폰은 틱 위에서 일어난다.
	if motion.position == home:
		_fails.append("코어: 데미지를 준 함수가 그 자리에서 위치를 옮겼다 — 리스폰이 틱 밖에 있다")
	motion.tick(idle)
	if not motion.respawned:
		_fails.append("코어: 죽고 한 틱 돌았는데 리스폰했다는 표시가 없다")
	if motion.position != home:
		_fails.append("코어: 리스폰했는데 자리가 %s 다 — 리스폰 지점 %s 이어야 한다"
				% [motion.position, home])
	if motion.health.current != PlayerHealth.MAX_HEALTH:
		_fails.append("코어: 되살아났는데 체력이 %d 다 — 가득이어야 한다" % motion.health.current)
	motion.tick(idle)
	if motion.respawned:
		_fails.append("코어: 리스폰 표시가 다음 틱까지 남아 있다 — 그 틱 하나여야 한다")
	if motion.position != home:
		_fails.append("코어: 리스폰한 다음 틱에 자리가 또 옮겨졌다")


## 4) **리스폰 지점은 값 하나다** — 그것만 바꾸면 그 자리에서 되살아난다(침대가 덮어쓸
## 자리). 텔레포트(`place_at`)로는 리스폰 지점이 따라가지 않는다.
func _check_respawn_point_is_one_value() -> void:
	var motion := PlayerMotion.new(OpenWorld.new())
	var home := Vector2(1000.0, 1000.0)
	motion.set_respawn(home)
	var bed := Vector2(7000.0, 3000.0)
	motion.set_respawn(bed)
	motion.place_at(Vector2(200.0, 200.0))
	if motion.respawn_position != bed:
		_fails.append("코어: 텔레포트했더니 리스폰 지점이 %s 로 따라갔다" % motion.respawn_position)
	motion.take_damage(PlayerHealth.MAX_HEALTH)
	motion.tick(PlayerInput.new())
	if motion.position != bed:
		_fails.append("코어: 리스폰 지점을 바꿨는데 %s 에서 되살아났다 — %s 여야 한다"
				% [motion.position, bed])


## 5) 살아 있는 동안은 아무리 틱을 돌려도 리스폰하지 않는다.
func _check_alive_never_respawns() -> void:
	var motion := PlayerMotion.new(OpenWorld.new())
	motion.set_respawn(Vector2.ZERO)
	var here := Vector2(4000.0, 4000.0)
	motion.place_at(here)
	motion.take_damage(PlayerHealth.MAX_HEALTH - 1)  # 체력 1 — 아슬아슬하게 살아 있다.
	var idle := PlayerInput.new()
	for i in 300:
		motion.tick(idle)
		if motion.respawned:
			_fails.append("코어: 체력 1 로 살아 있는데 %d번째 틱에 리스폰했다" % i)
			return
	if motion.position != here:
		_fails.append("코어: 가만히 서 있었는데 자리가 %s 로 옮겨졌다" % motion.position)
	if motion.health.current != 1:
		_fails.append("코어: 가만히 있었는데 체력이 %d 로 바뀌었다 — 회복 수단은 아직 없다"
				% motion.health.current)


## 6) 휘두르던 도중에 죽으면 그 사용 모션은 끊긴다 — 스폰 지점에 나타나자마자
## 죽기 전의 도끼질을 마저 하면 안 된다.
func _check_use_motion_is_cut() -> void:
	var motion := PlayerMotion.new(OpenWorld.new())
	motion.set_respawn(Vector2(1000.0, 1000.0))
	motion.tick(PlayerInput.new(Vector2i.ZERO, PlayerInput.AIM_DOWN, 0, true))
	if not motion.is_using():
		_fails.append("코어: 좌클릭했는데 사용 모션이 안 나갔다 — 검사가 무의미해진다")
		return
	motion.take_damage(PlayerHealth.MAX_HEALTH)
	motion.tick(PlayerInput.new())
	if motion.is_using():
		_fails.append("코어: 죽었다 되살아났는데 죽기 전의 사용 모션이 계속 돌고 있다")


# =============================================================================
# B. 화면 — 실제 월드 씬에서
# =============================================================================

## 7) 월드에 들어오면 체력이 가득이고 리스폰 지점이 스폰 칸이다.
func _check_spawn_state() -> void:
	var motion: RefCounted = _player().motion
	if motion == null:
		_fails.append("월드에 들어왔는데 플레이어 코어가 없다")
		return
	if motion.health.current != PlayerHealth.MAX_HEALTH:
		_fails.append("월드에 들어왔는데 체력이 %d 다 — 가득이어야 한다" % motion.health.current)
	var spawn: Vector2 = WorldGen.tile_center(_world().spawn_tile)
	if motion.respawn_position != spawn:
		_fails.append("리스폰 지점이 %s 다 — 스폰 좌표 %s 여야 한다"
				% [motion.respawn_position, spawn])


func _hurt_but_alive() -> void:
	_player().motion.take_damage(60)


func _check_still_alive() -> void:
	var health: RefCounted = _player().motion.health
	if health.current != 40:
		_fails.append("60 맞고 체력이 %d 다 — 40 이어야 한다" % health.current)
	if health.is_dead():
		_fails.append("60 만 맞았는데 죽었다")


## 8) **다쳐도 화면에 새 상시 HUD 가 생기지 않는다** (docs/DESIGN.md 「인벤토리 /
## 장비」— 지금 화면에 상시로 두는 것은 핫바 하나다).
func _check_no_new_hud_when_hurt() -> void:
	var ratio := _similarity("spawn", "hurt")
	if ratio < SAME_RATIO:
		_fails.append("체력이 100 → 40 이 되자 화면이 달라졌다(일치율 %.3f) — 체력 HUD 가 생긴 것 아닌가"
				% ratio)


## 9) 스폰에서 멀리 떨어뜨린다 — 10번의 "돌아왔다"가 뜻을 가지려면 먼저 실제로
## 떠나 있어야 한다.
func _go_far() -> void:
	var world := _world()
	var spawn: Vector2i = world.spawn_tile
	for radius in range(FAR_TILES, FAR_TILES + 30):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := spawn + Vector2i(dx, dy)
				if world.is_land(tile.x, tile.y):
					_far_position = WorldGen.tile_center(tile)
					_player().place_at(_far_position)
					return
	_fails.append("스폰에서 %d칸 떨어진 땅을 못 찾았다" % FAR_TILES)


func _check_far_looks_different() -> void:
	if _player().motion.position != _far_position:
		_fails.append("멀리 옮겼는데 자리가 %s 다" % _player().motion.position)
	var ratio := _similarity("spawn", "far")
	if ratio > DIFFERENT_RATIO:
		_fails.append("스폰에서 %d칸 떨어졌는데 화면이 그대로다(일치율 %.3f) — 10번 검사가 무의미해진다"
				% [FAR_TILES, ratio])


func _kill() -> void:
	_player().motion.take_damage(PlayerHealth.MAX_HEALTH)


## 10) 죽으면 리스폰 지점(= 스폰 칸)에서 체력 가득으로 되살아난다.
func _check_respawned_on_screen() -> void:
	var motion: RefCounted = _player().motion
	var spawn: Vector2 = WorldGen.tile_center(_world().spawn_tile)
	if motion.position != spawn:
		_fails.append("죽었는데 자리가 %s 다 — 스폰 %s 으로 돌아와야 한다" % [motion.position, spawn])
	if _player().global_position != spawn:
		_fails.append("코어는 돌아왔는데 화면의 캐릭터가 %s 에 남아 있다" % _player().global_position)
	if motion.health.current != PlayerHealth.MAX_HEALTH:
		_fails.append("되살아났는데 체력이 %d 다" % motion.health.current)


func _check_respawn_looks_like_spawn() -> void:
	var ratio := _similarity("spawn", "respawned")
	if ratio < SAME_RATIO:
		_fails.append("되살아난 화면이 스폰 화면과 다르다(일치율 %.3f)" % ratio)


# =============================================================================
# 도우미
# =============================================================================

func _enter_world() -> void:
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("불사조", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)


func _settle() -> void:
	_wait_time = SETTLE_SECONDS


## **빈손으로 시작한다.** 죽으면 인벤토리가 「데스드롭 상자」로 통째로 옮겨가므로
## (INBOX #37) 하단 핫바 그림이 죽기 전과 뒤가 달라진다 — 그러면 아래 10번의
## "되살아난 화면이 스폰 화면과 같은가"가 **체력·리스폰과 무관한 이유로** 실패한다.
## 이 파일이 보는 것은 체력과 리스폰이다(상자 자체는 `qa_death_box.gd` 가 본다).
func _empty_inventory() -> void:
	var inventory: RefCounted = current_scene.get("inventory")
	if inventory == null:
		_fails.append("월드에 인벤토리가 없다")
		return
	for area: String in [Inventory.AREA_GENERAL, Inventory.AREA_EQUIPMENT]:
		for index in inventory.slot_count(area):
			inventory.take_out(area, index)


## 마우스를 한 자리에 고정한다 — 조준 각도가 캡처마다 달라지면 조준선과 캐릭터
## 방향이 바뀌어서 "같은 화면인가"를 물을 수 없다 (docs/GOTCHAS.md).
func _aim_right() -> void:
	var size := root.get_visible_rect().size
	Input.warp_mouse(Vector2(size.x * 0.75, size.y * 0.5))


## 캡처 하나를 격자로 훑어 표본 색을 남긴다. 화면 전체를 통째로 비교하지 않는 이유는
## 두 캡처의 크기가 기계마다 다를 수 있어서다 (docs/GOTCHAS.md) — 비율로 짚는다.
func _remember_samples(key: String) -> void:
	var image := _capture()
	if image == null:
		return
	var colors: Array[Color] = []
	for gy in SAMPLE_GRID:
		for gx in SAMPLE_GRID:
			var x := int((float(gx) + 0.5) / float(SAMPLE_GRID) * float(image.get_width()))
			var y := int((float(gy) + 0.5) / float(SAMPLE_GRID) * float(image.get_height()))
			colors.append(image.get_pixel(x, y))
	_samples[key] = colors


## 두 캡처의 표본이 얼마나 같은가(0~1).
func _similarity(a: String, b: String) -> float:
	var left: Array = _samples.get(a, [])
	var right: Array = _samples.get(b, [])
	if left.size() != right.size() or left.is_empty():
		_fails.append("캡처 %s / %s 의 표본을 못 읽었다" % [a, b])
		return 0.0
	var same := 0
	for i in left.size():
		if _same(left[i], right[i]):
			same += 1
	return float(same) / float(left.size())


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= DIFF_EPSILON and absf(a.g - b.g) <= DIFF_EPSILON \
			and absf(a.b - b.b) <= DIFF_EPSILON


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


func _world() -> RefCounted:
	return current_scene.get("world")


func _player() -> Node2D:
	return current_scene.get_node("%Player") as Node2D
