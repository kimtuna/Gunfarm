extends SceneTree

## INBOX #37 자체 QA — 데스드롭 상자 + 월드 설정.
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_death_box.gd
##
## **아직 게임 안에서 죽을 방법이 없다** — 동물이 없고 이 서버는 PvE 다
## (docs/DESIGN.md 「전투」). 그래서 `qa_health.gd` 와 같이 **코드로 데미지를 준다.**
##
## 확인하는 것:
##   A. 코어(`death_boxes.gd` / `world_settings.gd` — 화면 없이 도는 순수 클래스)
##      1) 타이머 기본 30분이고, 「사라지지 않음」은 만료가 없는 값이다.
##      2) 시간이 다 되면 **상자와 내용물이 함께** 사라진다(그 전에는 안 사라진다).
##      3) **열면 타이머가 멈추고** 닫으면 다시 흐른다.
##      4) **열어둔 채 멀리 떠나면 닫힌 것으로 친다** — 안 그러면 영영 안 사라진다.
##      5) 꺼내기가 「인벤토리 안전」을 지킨다 — 못 들어간 몫이 상자에 그대로 남고,
##         다 꺼낸 상자는 사라진다.
##      6) 「사라지지 않음」은 아무리 시간이 흘러도 안 사라진다.
##      7) 저장 왕복 + **오프라인에 흐른 시간**이 불러오면서 한 번에 깎인다.
##      8) 월드 설정도 저장 왕복이 되고, 모르는 값은 기본값으로 떨어진다.
##      9) **보이는 자리와 클릭이 먹는 자리가 같다**(`box_rect` / `at_point`) —
##         멀리서 클릭하거나 상자 밖을 겨누면 안 열린다.
##   B. 화면(실제 월드 씬에서)
##     10) **죽으면 죽은 자리에 상자가 생기고 인벤토리가 통째로 들어간다**(플레이어는
##         리스폰 지점으로 돌아간다).
##     11) 상자가 실제로 화면에 보인다(캡처의 픽셀로 본다).
##     12) **좌클릭으로 열린다** — 창이 뜨고 그 좌클릭은 도구로 가지 않는다.
##     13) 창이 열려 있는 동안 남은 시간이 **실제로 멈춘다**.
##     14) 「모두 가져가기」로 되돌아오고, 빈 상자는 사라지고 창도 닫힌다.
##     15) 일시정지 메뉴에서 **월드 설정**이 열리고, 바꾼 값이 슬롯에 저장된다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const PlayerHealth := preload("res://scripts/player_health.gd")
const DeathBoxes := preload("res://scripts/death_boxes.gd")
const WorldSettings := preload("res://scripts/world_settings.gd")
const Inventory := preload("res://scripts/inventory.gd")
const ItemStack := preload("res://scripts/item_stack.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260907

## 프레임 수가 아니라 **시간**으로 기다린다 (docs/GOTCHAS.md).
const SETTLE_SECONDS := 0.35

## 스폰에서 이만큼 떨어진 땅에서 죽는다 — 상자가 리스폰 지점과 겹치면 "죽은 자리에
## 생겼는가"를 화면에서 구별할 수 없다.
const FAR_TILES := 20

## 상자를 열려고 설 자리(상자 밑동에서 아래로). `OPEN_RADIUS`(72) 안이어야 한다.
const STAND_OFFSET := Vector2(56.0, 20.0)

## "창이 열려 있는 동안 시간이 멈추는가"를 재는 시간.
const HOLD_SECONDS := 0.6

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

var _far_position := Vector2.ZERO
var _before_death: Dictionary = {}
var _box_position := Vector2.ZERO
var _held_remaining := -1.0


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(SHOTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))

	_check_core()

	_enter_world()
	_steps = [
		_settle,
		_aim_right,
		# 10) 멀리 가서 죽는다 — 상자는 죽은 자리에, 플레이어는 리스폰 지점에.
		_go_far,
		_settle,
		_remember_inventory,
		_kill,
		_settle,
		_check_box_spawned_where_i_died,
		# 11) 상자가 화면에 보인다
		_stand_by_box,
		_settle,
		func(): _shoot("95_death_box_world"),
		_check_box_is_on_screen,
		# 12) 좌클릭으로 열린다
		_point_at_box,
		_click,
		_settle,
		_check_box_opened,
		func(): _shoot("96_death_box_open"),
		# 13) 열려 있는 동안 시간이 멈춘다
		_remember_remaining,
		func(): _wait_time = HOLD_SECONDS,
		_check_timer_is_stopped,
		# 14) 모두 가져가기
		_take_all,
		_settle,
		_check_taken_back,
		func(): _shoot("97_death_box_taken"),
		# 15) 일시정지 메뉴 → 월드 설정
		_open_pause,
		_settle,
		_open_world_settings,
		_settle,
		_check_world_settings_open,
		func(): _shoot("98_world_settings"),
		_change_world_setting,
		_settle,
		_check_world_setting_saved,
		_escape,
		_settle,
		_check_world_settings_closed,
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
			print("[qa] PASS — 데스드롭 상자 + 월드 설정")
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
	_check_default_timer()
	_check_expires_with_contents()
	_check_open_stops_timer()
	_check_far_counts_as_closed()
	_check_inventory_safety()
	_check_forever()
	_check_save_and_offline()
	_check_world_settings_roundtrip()
	_check_hit_test()


## 1) 타이머 기본 30분 (docs/DESIGN.md 「데스드롭 상자」).
func _check_default_timer() -> void:
	var settings := WorldSettings.new()
	if settings.death_box_minutes != 30:
		_fails.append("코어: 기본 타이머가 %d분이다 — 「데스드롭 상자」는 30분이다"
				% settings.death_box_minutes)
	if not is_equal_approx(settings.death_box_seconds(), 1800.0):
		_fails.append("코어: 30분이 %f초로 나왔다" % settings.death_box_seconds())
	if not WorldSettings.DEATH_BOX_CHOICES.has(0):
		_fails.append("코어: 「사라지지 않음」을 고를 수 없다 — 「데스드롭 상자」가 이 설정을 둔 근거의 절반이 빠진다")
	settings.death_box_minutes = 0
	if settings.death_box_seconds() >= 0.0:
		_fails.append("코어: 「사라지지 않음」이 만료가 있는 값으로 나왔다")


## 2) 시간이 다 되면 **상자와 내용물이 함께** 사라진다.
func _check_expires_with_contents() -> void:
	var boxes := DeathBoxes.new()
	var t := 1000.0
	var entry: Variant = boxes.spawn(Vector2.ZERO, [ItemStack.new("wood", 5)], 60.0)
	if entry == null:
		_fails.append("코어: 상자를 못 만들었다")
		return
	boxes.update(Vector2.ZERO, t)
	boxes.update(Vector2.ZERO, t + 59.0)
	if boxes.size() != 1:
		_fails.append("코어: 60초짜리 상자가 59초에 사라졌다")
		return
	boxes.update(Vector2.ZERO, t + 61.0)
	if boxes.size() != 0:
		_fails.append("코어: 60초가 지났는데 상자가 남아 있다")
	# 빈손으로 죽으면 빈 상자를 만들지 않는다.
	if boxes.spawn(Vector2.ZERO, [], 60.0) != null:
		_fails.append("코어: 빈손으로 죽었는데 빈 상자가 생겼다")


## 3) **열면 타이머가 멈춘다** — *"정해진 시간은 「찾아올 시간」이지 「꺼낼 시간」이 아니다."*
func _check_open_stops_timer() -> void:
	var boxes := DeathBoxes.new()
	var t := 1000.0
	var entry: Dictionary = boxes.spawn(Vector2.ZERO, [ItemStack.new("wood", 5)], 60.0)
	boxes.update(Vector2.ZERO, t)
	boxes.open(entry)
	boxes.update(Vector2.ZERO, t + 30.0)
	var remaining: float = entry[DeathBoxes.KEY_REMAINING]
	if not is_equal_approx(remaining, 60.0):
		_fails.append("코어: 열어둔 30초 동안 타이머가 %.1f 초로 흘렀다 — 멈춰 있어야 한다" % remaining)
	boxes.close(entry)
	boxes.update(Vector2.ZERO, t + 40.0)
	remaining = entry[DeathBoxes.KEY_REMAINING]
	if not is_equal_approx(remaining, 50.0):
		_fails.append("코어: 닫고 10초 뒤 남은 시간이 %.1f 다 — 50 이어야 한다(다시 흘러야 한다)" % remaining)


## 4) **열어둔 채 멀리 떠나면 닫힌 것으로 친다** (docs/DESIGN.md 「데스드롭 상자」).
func _check_far_counts_as_closed() -> void:
	var boxes := DeathBoxes.new()
	var t := 1000.0
	var near := Vector2.ZERO
	var far := Vector2(DeathBoxes.CLOSE_DISTANCE + 10.0, 0.0)
	var entry: Dictionary = boxes.spawn(Vector2.ZERO, [ItemStack.new("wood", 5)], 60.0)
	boxes.update(near, t)
	boxes.open(entry)
	boxes.update(near, t + 5.0)
	if not boxes.is_open(entry):
		_fails.append("코어: 옆에 서 있는데 상자가 저 혼자 닫혔다")
	boxes.update(far, t + 5.0)
	if boxes.is_open(entry):
		_fails.append("코어: 열어둔 채 %d 만큼 떠났는데 계속 열려 있다 — 영영 안 사라진다"
				% int(DeathBoxes.CLOSE_DISTANCE))
	boxes.update(far, t + 15.0)
	var remaining: float = entry[DeathBoxes.KEY_REMAINING]
	if not is_equal_approx(remaining, 50.0):
		_fails.append("코어: 멀어져 닫힌 뒤에도 타이머가 안 흐른다(남은 시간 %.1f)" % remaining)


## 5) 꺼내기가 「인벤토리 안전」을 지킨다 — **못 들어간 몫은 상자에 그대로 남는다.**
func _check_inventory_safety() -> void:
	var boxes := DeathBoxes.new()
	var inventory := Inventory.new()
	# 일반 18칸 중 17칸을 꽉 채우고, 한 칸에는 목재를 89개만 둔다(10칸 남음).
	for index in Inventory.GENERAL_SLOTS - 1:
		inventory.general[index] = ItemStack.new("stone", 99)
	inventory.general[Inventory.GENERAL_SLOTS - 1] = ItemStack.new("wood", 89)
	var entry: Dictionary = boxes.spawn(Vector2.ZERO, [ItemStack.new("wood", 99)], 60.0)
	var moved := boxes.take(entry, 0, inventory)
	if moved != 10:
		_fails.append("코어: 자리가 10개뿐인데 %d개가 들어갔다" % moved)
	var left: RefCounted = (entry[DeathBoxes.KEY_STACKS] as Array)[0]
	if left == null or left.count != 89:
		_fails.append("코어: 못 들어간 몫이 상자에 안 남았다 — 「인벤토리 안전」이 깨진다")
	if boxes.size() != 1:
		_fails.append("코어: 아직 내용물이 있는데 상자가 사라졌다")
	# 자리를 비워주면 나머지가 들어가고, **빈 상자는 사라진다.**
	inventory.general[0] = null
	boxes.take_all(entry, inventory)
	if not DeathBoxes.is_empty_box(entry):
		_fails.append("코어: 자리를 비웠는데 상자에 남아 있다")
	if boxes.size() != 0:
		_fails.append("코어: 다 꺼낸 상자가 월드에 남아 있다")


## 6) 「사라지지 않음」은 시간이 아무리 흘러도 안 사라진다.
func _check_forever() -> void:
	var boxes := DeathBoxes.new()
	var entry: Dictionary = boxes.spawn(Vector2.ZERO, [ItemStack.new("wood", 5)],
			WorldSettings.FOREVER)
	boxes.update(Vector2.ZERO, 1000.0)
	boxes.update(Vector2.ZERO, 1000.0 + 365.0 * 24.0 * 3600.0)
	if boxes.size() != 1:
		_fails.append("코어: 「사라지지 않음」 상자가 사라졌다")
	if DeathBoxes.remaining_ratio(entry) >= 0.0:
		_fails.append("코어: 「사라지지 않음」인데 남은 시간 막대가 그려진다 — 줄지 않는 막대는 거짓말이다")


## 7) 저장 왕복 + **오프라인에 흐른 시간**.
func _check_save_and_offline() -> void:
	var boxes := DeathBoxes.new()
	boxes.spawn(Vector2(300.0, 400.0), [ItemStack.new("wood", 7), ItemStack.new("axe", 1)], 600.0)
	var now := Time.get_unix_time_from_system()
	var data := boxes.to_data()

	var back := DeathBoxes.new()
	if back.from_data(data, now + 300.0) != 1:
		_fails.append("코어: 저장한 상자를 못 불러왔다")
		return
	var entry: Dictionary = back.items[0]
	if (entry[DeathBoxes.KEY_POSITION] as Vector2) != Vector2(300.0, 400.0):
		_fails.append("코어: 불러온 상자의 자리가 %s 다" % entry[DeathBoxes.KEY_POSITION])
	var remaining: float = entry[DeathBoxes.KEY_REMAINING]
	if absf(remaining - 300.0) > 2.0:
		_fails.append("코어: 300초 나가 있었는데 남은 시간이 %.1f 다 — 290~310 이어야 한다" % remaining)
	if bool(entry[DeathBoxes.KEY_OPENED]):
		_fails.append("코어: 불러온 상자가 열린 채로 시작했다 — 그러면 타이머가 멈춰 있다")
	var stacks: Array = entry[DeathBoxes.KEY_STACKS]
	var first: RefCounted = stacks[0]
	var second: RefCounted = stacks[1]
	if first == null or first.id != "wood" or first.count != 7 or second == null or second.id != "axe":
		_fails.append("코어: 불러온 상자의 내용물이 어긋났다")

	var gone := DeathBoxes.new()
	if gone.from_data(data, now + 700.0) != 0:
		_fails.append("코어: 나가 있는 동안 시간이 다 됐는데 상자가 되살아났다")


## 8) 월드 설정 저장 왕복.
func _check_world_settings_roundtrip() -> void:
	var settings := WorldSettings.new()
	settings.death_box_minutes = 60
	var back := WorldSettings.new()
	back.from_data(settings.to_data())
	if back.death_box_minutes != 60:
		_fails.append("코어: 월드 설정이 저장 왕복에서 %d 로 바뀌었다" % back.death_box_minutes)
	back.from_data({WorldSettings.DEATH_BOX_KEY: 4242})
	if back.death_box_minutes != WorldSettings.DEFAULT_DEATH_BOX_MINUTES:
		_fails.append("코어: 모르는 값이 기본값으로 안 떨어졌다(%d)" % back.death_box_minutes)


## 9) **보이는 자리와 클릭이 먹는 자리가 같다** — 멀리서 클릭하거나 상자 밖을 겨누면
## 안 열린다.
func _check_hit_test() -> void:
	var boxes := DeathBoxes.new()
	var at := Vector2(1000.0, 1000.0)
	boxes.spawn(at, [ItemStack.new("wood", 5)], 60.0)
	var rect := DeathBoxes.box_rect(at)
	if not is_equal_approx(rect.end.y, at.y) or not is_equal_approx(rect.get_center().x, at.x):
		_fails.append("코어: 상자 사각형의 밑동이 놓인 자리와 안 맞는다(%s)" % rect)
	var center := rect.get_center()
	var stand := at + Vector2(0.0, 40.0)
	if boxes.at_point(center, stand) == null:
		_fails.append("코어: 상자 옆에 서서 상자 한가운데를 겨눴는데 안 잡힌다")
	if boxes.at_point(center + Vector2(200.0, 0.0), stand) != null:
		_fails.append("코어: 상자 밖을 겨눴는데 상자가 잡힌다")
	if boxes.at_point(center, at + Vector2(0.0, DeathBoxes.OPEN_RADIUS + 50.0)) != null:
		_fails.append("코어: 손이 안 닿는 거리에서 클릭했는데 상자가 열린다")


# =============================================================================
# B. 화면 — 실제 월드 씬에서
# =============================================================================

## 스폰에서 멀리 떨어진 땅으로 옮긴다 — 거기서 죽어야 "죽은 자리에 생겼는가"를
## 리스폰 지점과 구별할 수 있다.
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


func _remember_inventory() -> void:
	_before_death = _inventory_counts()
	if _before_death.is_empty():
		_fails.append("죽기 전에 인벤토리가 이미 비어 있다 — 상자 검사가 무의미해진다")


func _kill() -> void:
	_player().motion.take_damage(PlayerHealth.MAX_HEALTH)


## 10) 죽으면 **죽은 자리에** 상자가 생기고 인벤토리가 통째로 들어간다.
func _check_box_spawned_where_i_died() -> void:
	var boxes: RefCounted = _boxes()
	if boxes.size() != 1:
		_fails.append("죽었는데 상자가 %d개다 — 하나여야 한다" % boxes.size())
		return
	var entry: Dictionary = boxes.items[0]
	_box_position = entry[DeathBoxes.KEY_POSITION]
	if _box_position.distance_to(_far_position) > 1.0:
		_fails.append("상자가 %s 에 생겼다 — 죽은 자리 %s 여야 한다" % [_box_position, _far_position])
	var spawn: Vector2 = WorldGen.tile_center(_world().spawn_tile)
	if _player().motion.position != spawn:
		_fails.append("죽었는데 플레이어가 리스폰 지점으로 안 돌아갔다(%s)" % _player().motion.position)
	if not _inventory().is_empty():
		_fails.append("죽었는데 인벤토리에 아직 물건이 남아 있다")
	var inside := _box_counts(entry)
	if not _same_counts(inside, _before_death):
		_fails.append("상자 안(%s)이 죽기 전 인벤토리(%s)와 다르다" % [inside, _before_death])
	# 「월드 설정」의 기본값 30분이 그대로 새겨져야 한다.
	var total: float = entry[DeathBoxes.KEY_TOTAL]
	if not is_equal_approx(total, 1800.0):
		_fails.append("상자 타이머가 %.0f초로 생겼다 — 기본 30분(1800)이어야 한다" % total)


## 상자를 열 수 있는 거리에 선다. **옆으로 비켜 선다** — 상자 앞에 서면 플레이어가
## 상자를 가려서(Y정렬상 앞) "상자가 보이는가"를 픽셀로 물을 수 없다.
func _stand_by_box() -> void:
	_player().place_at(_box_position + STAND_OFFSET)


## 11) 상자가 실제로 화면에 보인다 — 상자 한가운데의 픽셀이 지형색이 아니어야 한다.
func _check_box_is_on_screen() -> void:
	var image := _capture()
	if image == null:
		return
	var rect := DeathBoxes.box_rect(_box_position)
	# 자물쇠(금색)와 쇠 띠(회색)를 피해 몸통 왼쪽을 짚는다 — 나무색이 나와야 한다.
	var probe := _to_pixels(rect.position + rect.size * Vector2(0.12, 0.75), image)
	var color := image.get_pixelv(probe)
	# 궤짝은 나무색(붉은 기가 도는 갈색)이라 풀밭(초록)과 R/G 관계가 뒤집힌다.
	if color.r <= color.g:
		_fails.append("상자 자리의 픽셀이 %s 다 — 나무색(R>G)이 아니다. 상자가 안 그려졌다" % color)


## 상자 한가운데로 마우스를 옮긴다. **각도로 밀어넣지 않고 실제 커서를 옮긴다** —
## 여는 판정이 커서 자리를 보기 때문이다 (docs/GOTCHAS.md).
func _point_at_box() -> void:
	var center := DeathBoxes.box_rect(_box_position).get_center()
	Input.warp_mouse(root.get_canvas_transform() * center)


func _click() -> void:
	var event := InputEventAction.new()
	event.action = "use_tool"
	event.pressed = true
	Input.parse_input_event(event)


## 12) 좌클릭으로 창이 열리고, **그 좌클릭은 도구로 가지 않는다**.
func _check_box_opened() -> void:
	if _overlay("_death_box_overlay") == null:
		_fails.append("상자를 겨누고 좌클릭했는데 창이 안 열렸다")
		return
	if not _boxes().is_open(_boxes().items[0]):
		_fails.append("창은 떴는데 코어의 상자가 열린 상태가 아니다 — 타이머가 계속 흐른다")
	if _player().motion.is_using():
		_fails.append("상자를 여는 좌클릭이 도구 동작으로도 갔다")


func _remember_remaining() -> void:
	_held_remaining = _boxes().items[0][DeathBoxes.KEY_REMAINING]


## 13) 창이 열려 있는 동안 남은 시간이 **실제로 멈춘다**(화면 쪽에서도).
func _check_timer_is_stopped() -> void:
	var now: float = _boxes().items[0][DeathBoxes.KEY_REMAINING]
	if not is_equal_approx(now, _held_remaining):
		_fails.append("창을 열어둔 %.1f초 동안 남은 시간이 %.3f → %.3f 로 흘렀다"
				% [HOLD_SECONDS, _held_remaining, now])


func _take_all() -> void:
	var overlay := _overlay("_death_box_overlay")
	if overlay == null:
		return
	(overlay.get_node("%TakeAllButton") as Button).pressed.emit()


## 14) 되돌아오고, 빈 상자는 사라지고, 창도 같이 닫힌다.
func _check_taken_back() -> void:
	var after := _inventory_counts()
	if not _same_counts(after, _before_death):
		_fails.append("모두 가져갔는데 인벤토리(%s)가 죽기 전(%s)과 다르다" % [after, _before_death])
	if _boxes().size() != 0:
		_fails.append("다 꺼낸 상자가 월드에 남아 있다")
	if _overlay("_death_box_overlay") != null:
		_fails.append("상자가 사라졌는데 창이 그대로 떠 있다")


func _open_pause() -> void:
	_escape()


func _open_world_settings() -> void:
	current_scene.call("_on_pause_world_settings_pressed")


## 15) 일시정지 메뉴에서 월드 설정이 열린다 (docs/DESIGN.md 「월드 설정」).
func _check_world_settings_open() -> void:
	if _overlay("_world_settings_overlay") == null:
		_fails.append("일시정지 메뉴에서 월드 설정이 안 열렸다")


func _change_world_setting() -> void:
	var overlay := _overlay("_world_settings_overlay")
	if overlay == null:
		return
	(overlay.get_node("%NextButton") as Button).pressed.emit()


## 바꾼 값은 **그 슬롯에** 저장된다 — 그래픽 설정(`user://settings.json`)과 다른 자리다.
func _check_world_setting_saved() -> void:
	var settings: RefCounted = current_scene.get("world_settings")
	var minutes: int = settings.death_box_minutes
	if minutes == WorldSettings.DEFAULT_DEATH_BOX_MINUTES:
		_fails.append("월드 설정의 값이 안 바뀌었다")
	var slot := SlotStore.load_slots()[0]
	var saved := SlotStore.world_settings_of(slot)
	if int(saved.get(WorldSettings.DEATH_BOX_KEY, -1)) != minutes:
		_fails.append("바꾼 월드 설정(%d분)이 슬롯에 %s 로 저장됐다" % [minutes, saved])


func _check_world_settings_closed() -> void:
	if _overlay("_world_settings_overlay") != null:
		_fails.append("Esc 를 눌렀는데 월드 설정이 안 닫혔다")
	# **가장 안쪽 창부터 닫힌다** — 월드 설정만 닫히고 일시정지 메뉴는 남아야 한다
	# (docs/DESIGN.md 「조작」의 Esc 규칙).
	if not (current_scene.get_node("%PauseMenu") as Control).visible:
		_fails.append("Esc 한 번에 월드 설정과 일시정지 메뉴가 같이 닫혔다")


# =============================================================================
# 도우미
# =============================================================================

func _enter_world() -> void:
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("유품", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)


func _settle() -> void:
	_wait_time = SETTLE_SECONDS


## 마우스를 한 자리에 고정한다 — 조준 각도가 캡처마다 달라지면 안 된다 (docs/GOTCHAS.md).
func _aim_right() -> void:
	var size := root.get_visible_rect().size
	Input.warp_mouse(Vector2(size.x * 0.75, size.y * 0.5))


func _escape() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


func _inventory() -> RefCounted:
	return current_scene.get("inventory")


func _boxes() -> RefCounted:
	return current_scene.get("death_boxes")


func _overlay(field: String) -> Control:
	var node: Variant = current_scene.get(field)
	return node as Control


## 인벤토리에 무엇이 몇 개 있는가(id → 개수).
func _inventory_counts() -> Dictionary:
	var out := {}
	var inventory := _inventory()
	for area: String in [Inventory.AREA_GENERAL, Inventory.AREA_EQUIPMENT]:
		for index in inventory.slot_count(area):
			var stack: RefCounted = inventory.at(area, index)
			if stack != null:
				out[stack.id] = int(out.get(stack.id, 0)) + stack.count
	return out


## 두 목록이 같은가. **Dictionary 를 `==` 로 견주지 않는다** — 비교 방식이 엔진
## 판에 따라 달라질 수 있어서, 키와 값을 직접 훑는다.
func _same_counts(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: String in a:
		if int(b.get(key, -1)) != int(a[key]):
			return false
	return true


func _box_counts(entry: Dictionary) -> Dictionary:
	var out := {}
	for stack: RefCounted in (entry[DeathBoxes.KEY_STACKS] as Array):
		if stack != null:
			out[stack.id] = int(out.get(stack.id, 0)) + stack.count
	return out


## 월드 좌표 → 캡처 이미지의 픽셀. **논리 좌표와 캡처 크기가 다를 수 있으므로**
## 캡처의 크기로 환산한다 (docs/GOTCHAS.md).
func _to_pixels(world_point: Vector2, image: Image) -> Vector2i:
	var view := root.get_canvas_transform() * world_point
	var size := root.get_visible_rect().size
	return Vector2i(
		clampi(int(view.x / size.x * float(image.get_width())), 0, image.get_width() - 1),
		clampi(int(view.y / size.y * float(image.get_height())), 0, image.get_height() - 1),
	)


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
