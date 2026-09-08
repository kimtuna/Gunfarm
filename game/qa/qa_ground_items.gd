extends SceneTree

## INBOX #33 자체 QA — 바닥에 놓인 아이템 (보이기 / 줍기 / 저장).
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_ground_items.gd
##
## 확인하는 것:
##   A. 코어(`ground_items.gd` — 화면 없이 도는 순수 클래스)
##      1) 버리면 그 자리에 놓이고 **잠긴 채로** 시작한다.
##      2) 버린 자리에 서 있는 동안은 안 주워진다. 벗어나면 잠금이 풀리고, 돌아오면 주워진다.
##      3) 줍히는 거리 경계 — 반경 밖에서는 안 주워지고 안에서는 주워진다.
##      4) **꽉 찬 인벤토리에서 넘치는 몫이 바닥에 남는다** (「인벤토리 안전」).
##      5) 수명이 다한 것은 사라진다(실제 시간 기준).
##      6) 저장·불러오기 왕복 — 자리·수량·놓인 시각이 그대로고, 불러온 것은 잠겨 있다.
##      7) **도트 크기가 월드와 같다** (INBOX #38) — 배율이 캐릭터·타일과 같은 3배이고,
##         구워진 바닥 그림의 칸이 그 배율이 전제하는 크기다.
##      8) **버린 것은 바라보는 방향 앞 한 칸에 놓이고, 물 위에는 안 놓인다** (INBOX #42).
##      9) **잠금이 풀리는 기준은 놓인 자리가 아니라 버린 사람이 서 있던 자리다** (INBOX #42).
##   B. 화면(실제 월드 씬에서)
##     10) 버리면 **그 자리에 실제로 그려진다** — 버리기 전 캡처에는 없던 아이템 색이 생긴다.
##         **아무 데도 안 옮기고 본다** — 버린 것이 캐릭터 앞에 놓이므로 그대로 보인다.
##     11) **앞뒤(Y) 정렬이 플레이어와 맞는다** — 플레이어보다 위에 놓이면 뒤에, 아래면 앞에
##         그려진다. 겹치는 픽셀만 골라 네 장(빈 화면/아이템만/플레이어만/둘 다)을 견준다.
##     12) 버린 자리에 서 있으면 안 주워지고, **걸어 나갔다 돌아오면** 주워진다.
##     13) 꽉 찬 인벤토리로 밟으면 들어갈 만큼만 들어가고 나머지는 바닥에 그대로 보인다.
##     14) 메인 메뉴로 나갔다 같은 슬롯으로 다시 들어와도 그 자리에 그대로 있고 보인다.

const SettingsStore := preload("res://scripts/settings_store.gd")
const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const Inventory := preload("res://scripts/inventory.gd")
const ItemStack := preload("res://scripts/item_stack.gd")
const ItemTypes := preload("res://scripts/item_types.gd")
const GroundItems := preload("res://scripts/ground_items.gd")
const GroundItemNode := preload("res://scripts/ground_item_node.gd")
const PlayerMotion := preload("res://scripts/player_motion.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")
const TerrainTiles := preload("res://scripts/terrain_tiles.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260907

## 프레임 수가 아니라 **시간**으로 기다린다 (docs/GOTCHAS.md).
const SETTLE_SECONDS := 0.2

## 키를 몇 초 누르고 있는가 — 240단위/초라 0.25초면 60px, 줍히는 거리(36)를 넘는다.
const HOLD_SECONDS := 0.25

const COLOR_EPSILON := 0.03

const PAUSE_BOX := "HUD/PauseMenu/Box/BoxLayout"

## 처음 지급되는 인벤토리에서 목재가 앉는 칸(`world.gd` 의 `STARTER_ITEMS` 순서).
const WOOD_SLOT := 7
const WOOD_COUNT := 64

## Y정렬 검사에서 아이템을 플레이어 위/아래로 얼마나 옮기는가. 그림이 겹칠 만큼
## 가깝고, 줍히는 거리(36) 안이라 **잠긴 채로 남는다**.
## **2026-09-07(INBOX #38)에 14 → 10 으로 줄였다** — 바닥 아이템 그림이 34px 짜리
## 정사각형에서 자루(30 × 27px)로 바뀌면서 캐릭터와 겹치는 픽셀이 아래 하한 근처로
## 내려왔다. 검사가 헛돌지 않게 더 가까이 놓는다(하한을 낮추는 쪽이 아니다).
const SORT_OFFSET := 10.0

## Y정렬 검사가 "겹쳤다"고 인정하는 최소 픽셀 수 — 이보다 적으면 검사가 헛돈 것이다.
const SORT_MIN_PIXELS := 100

## 조준을 밀어놓을 때 커서를 기준점에서 화면 짧은 변의 몇 배만큼 떼어놓는가
## (`qa_player_world.gd` 와 같은 값·같은 방식).
const AIM_REACH := 0.3

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

## 검사 사이에 들고 다니는 값들.
var _drop_position := Vector2.ZERO
var _shots := {}
var _hold_from := Vector2.ZERO
var _axe_position := Vector2.ZERO
var _shown_position := Vector2.ZERO


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(SHOTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))

	_check_core()

	_enter_world()
	_steps = [
		_settle,
		_stand_on_open_land,
		_settle,
		# 커서를 **일부러 반대쪽(위)** 에 먼저 둔다 — 바로 아래에서 아래를 겨눌 때,
		# 방향이 정말 이 warp 에서 오는 것이지 이 기계의 커서가 우연히 아래에 있어서가
		# 아님이 확인된다.
		func(): _aim_at(-PI / 2.0),
		_settle,
		func(): _aim_at(PI / 2.0),
		_settle,
		# 10) 버리면 그려진다 — **옮기지 않고** 놓인 그 자리에서 본다
		func(): _remember_shot("empty"),
		_drop_wood,
		_read_drop_spot,
		_settle,
		func(): _shoot("70_ground_dropped"),
		_check_drawn_after_drop,
	]
	# 11) 앞뒤(Y) 정렬 — 위에 놓으면 플레이어 뒤, 아래에 놓으면 플레이어 앞
	_steps.append_array(_sort_steps(-SORT_OFFSET, false, "71_ground_behind"))
	_steps.append_array(_sort_steps(SORT_OFFSET, true, "72_ground_front"))
	_steps.append_array([
		# 12) 버린 자리에 서 있는 동안은 안 주워진다
		_move_item_onto_player,
		_settle,
		_check_not_taken_while_standing,
		# 걸어 나갔다 돌아오면 주워진다
		func(): _hold_move("move_up"),
		_check_walked_away,
		_check_unlocked_but_still_there,
		func(): _hold_move("move_down"),
		_settle,
		_check_picked_up,
		func(): _shoot("73_ground_picked_up"),
		# 13) 꽉 찬 인벤토리 — 들어갈 만큼만 들어가고 나머지는 바닥에 남는다
		_fill_inventory_and_drop_stone,
		_settle,
		_step_onto_stone,
		_settle,
		_check_overflow_left_on_ground,
		# 밟고 선 채로는 캐릭터가 가려서 안 보인다 — 비켜선 뒤에 그림을 본다.
		_step_away_from_stone,
		_settle,
		func(): _shoot("74_ground_overflow"),
		_check_leftover_drawn,
		# 14) 나갔다 들어와도 그 자리에 그대로
		func(): _press(PAUSE_BOX + "/ExitButton"),
		_settle,
		func(): change_scene_to_file(WORLD_SCENE),
		_settle,
		_check_survives_save_load,
		_stand_near_stone,
		_settle,
		func(): _shoot("75_ground_reloaded"),
		_check_drawn_after_reload,
		# 아이콘이 있는 아이템(도구)도 바닥에서 어떻게 보이는지 남긴다 — 자리표시
		# 사각형과 달리 이쪽이 실제 그림이다.
		func(): _remember_shot("before_tool"),
		_drop_axe,
		_read_axe_spot,
		_settle,
		func(): _shoot("76_ground_tool"),
		_check_tool_drawn,
	])


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
			print("[qa] PASS — 바닥 아이템 (보이기 / 줍기 / 저장)")
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
	_check_drop_starts_locked()
	_check_lock_needs_leaving()
	_check_lock_follows_dropper()
	_check_drop_spot()
	_check_pickup_radius()
	_check_full_inventory_keeps_leftover()
	_check_lifetime()
	_check_save_round_trip()
	_check_dot_scale()


## 1) 버리면 그 자리에 놓이고 잠긴 채로 시작한다.
func _check_drop_starts_locked() -> void:
	var ground := GroundItems.new()
	var at := Vector2(100.0, 200.0)
	if ground.drop(ItemStack.new("wood", 5), at, 1000.0) == null:
		_fails.append("코어: 버렸는데 바닥에 안 놓였다")
		return
	if ground.size() != 1:
		_fails.append("코어: 바닥에 %d개가 놓였다 — 1개여야 한다" % ground.size())
		return
	var entry: Dictionary = ground.items[0]
	if entry[GroundItems.KEY_POSITION] != at:
		_fails.append("코어: 버린 자리가 아니라 %s 에 놓였다" % entry[GroundItems.KEY_POSITION])
	if not bool(entry[GroundItems.KEY_LOCKED]):
		_fails.append("코어: 버리자마자 잠기지 않았다 — 도로 주워진다")
	if float(entry[GroundItems.KEY_DROPPED]) != 1000.0:
		_fails.append("코어: 놓인 시각이 안 적혔다")
	# 빈 뭉치는 아무것도 안 놓는다.
	if ground.drop(ItemStack.new("wood", 0), at, 1000.0) != null or ground.size() != 1:
		_fails.append("코어: 빈 뭉치가 바닥에 놓였다")


## 7) **도트 크기가 월드와 같다** (2026-09-07, INBOX #38 — 전에는 바닥 아이템만 2배라
## 아트 픽셀 하나가 화면에서 2px 이었고, 캐릭터·지형과 결이 달랐다).
##
## 화면 없이 잴 수 있는 검사라 코어 쪽에 둔다. 보는 것 셋:
##   - 바닥 아이템의 배율이 **캐릭터와 같은가.**
##   - 그 배율이 **타일과도 같은가** — 타일은 아트 `TILE_ART` 가 화면 `TILE_SIZE` 다.
##   - 구워진 그림의 칸이 **`ART` 와 같은가.** 생성기(`gen_character.py` 의 `GROUND_N`)만
##     고치고 게임 쪽 상수를 안 고치면 여기서 걸린다.
##
## **캐릭터 쪽 배율은 상수(`PlayerFrames.SCALE`)가 아니라 실제 시트에서 읽는다**
## (2026-09-08, INBOX #67). 그 상수는 32px 칸 시절 값이라 지금 실려 있는 96px 시트의
## 배율(1)과 다르다 — 상수를 믿으면 **그림은 맞는데 검사만 안 따라오는** 자리가 된다
## (`qa_sprite_check.py` 가 지형 칸 크기를 생성기에서 읽게 된 것과 같은 이유다).
func _check_dot_scale() -> void:
	var character_zoom := _character_zoom()
	if character_zoom <= 0:
		_fails.append("코어: 캐릭터 시트를 못 읽어 도트 배율을 못 쟀다")
	elif GroundItemNode.ZOOM != character_zoom:
		_fails.append("코어: 바닥 아이템 배율 %d 가 캐릭터 %d 와 다르다 — 도트 결이 갈린다"
				% [GroundItemNode.ZOOM, character_zoom])
	var tile_zoom := WorldGen.TILE_SIZE / TerrainTiles.TILE_ART
	if GroundItemNode.ZOOM != tile_zoom:
		_fails.append("코어: 바닥 아이템 배율 %d 가 타일 %d 와 다르다"
				% [GroundItemNode.ZOOM, tile_zoom])
	for id in ["axe", "gun", "fishing_rod"]:
		var art := ItemTypes.ground_of(id)
		if art == null:
			_fails.append("코어: %s 의 바닥 그림이 없다" % id)
			continue
		if art.get_size() != Vector2(GroundItemNode.ART, GroundItemNode.ART):
			_fails.append("코어: %s 의 바닥 그림이 %s — %dpx 한 칸이어야 한다"
					% [id, art.get_size(), GroundItemNode.ART])
	# 자리표시(그림이 없는 아이템)도 제 격자 위에 있어야 한다. **`ZOOM` 이 아니라
	# `PLACEHOLDER_DOT` 으로 나눈다** — 자리표시만 코드에 박힌 무늬라 결이 다르다
	# (그 이유는 `ground_item_node.gd` 의 같은 상수 옆에 있다).
	if GroundItemNode.PLACEHOLDER % GroundItemNode.PLACEHOLDER_DOT != 0:
		_fails.append("코어: 자리표시 %dpx 가 한 칸 %d 로 안 나눠떨어진다"
				% [GroundItemNode.PLACEHOLDER, GroundItemNode.PLACEHOLDER_DOT])


## 지금 실려 있는 캐릭터 시트의 씬 배율. 시트에서 칸 크기를 읽어 `scale_of()` 에
## 물어본다 — 읽을 수 없으면 0 이다.
func _character_zoom() -> int:
	var texture: Texture2D = load(PlayerFrames.sheet_path("idle", PlayerFrames.DEFAULT_HAIRSTYLE))
	if texture == null:
		return 0
	return PlayerFrames.scale_of(PlayerFrames.cell_of(texture))


## 2) 버린 자리를 벗어나야 잠금이 풀린다.
func _check_lock_needs_leaving() -> void:
	var ground := GroundItems.new()
	var inv := Inventory.new()
	var at := Vector2.ZERO
	ground.drop(ItemStack.new("wood", 5), at, 1000.0)
	# 그 자리에 계속 서 있으면 몇 번을 훑어도 안 주워진다.
	for i in 10:
		ground.update(at, inv, 1000.0)
	if ground.size() != 1 or inv.count_of("wood") != 0:
		_fails.append("코어: 버린 자리에 서 있는데 도로 주워졌다")
		return
	# 벗어나면 잠금이 풀리지만 아이템은 그대로 있다.
	ground.update(at + Vector2(200.0, 0.0), inv, 1000.0)
	if ground.size() != 1:
		_fails.append("코어: 멀어졌더니 바닥 아이템이 사라졌다")
		return
	if bool((ground.items[0] as Dictionary)[GroundItems.KEY_LOCKED]):
		_fails.append("코어: 멀어졌는데 잠금이 안 풀렸다")
	# 돌아오면 주워진다.
	ground.update(at, inv, 1000.0)
	if ground.size() != 0 or inv.count_of("wood") != 5:
		_fails.append("코어: 돌아왔는데 안 주워졌다 (바닥 %d개, 인벤 %d개)"
				% [ground.size(), inv.count_of("wood")])


## 9) **잠금이 풀리는 기준은 놓인 자리가 아니라 버린 사람이 서 있던 자리다**
## (2026-09-07, INBOX #42 — 버린 것이 앞 한 칸에 놓이면서 둘이 갈렸다).
func _check_lock_follows_dropper() -> void:
	var ground := GroundItems.new()
	var inv := Inventory.new()
	var stood := Vector2.ZERO
	var at := stood + Vector2(0.0, PlayerMotion.DROP_DISTANCE)  # 바라보는 쪽 한 칸 앞
	ground.drop(ItemStack.new("wood", 5), at, 1000.0, stood)
	# 버린 자리에 서 있는 동안은 — 놓인 것이 줍히는 거리 밖이어도 — 잠긴 채다.
	for i in 10:
		ground.update(stood, inv, 1000.0)
	if not bool((ground.items[0] as Dictionary)[GroundItems.KEY_LOCKED]):
		_fails.append("코어: 버린 자리에 서 있는데 잠금이 풀렸다")
	# 놓인 것 쪽으로 한 발짝 — 줍히는 거리 안이지만 아직 버린 자리를 안 벗어났다.
	ground.update(stood + Vector2(0.0, GroundItems.PICKUP_RADIUS - 1.0), inv, 1000.0)
	if ground.size() != 1 or inv.count_of("wood") != 0:
		_fails.append("코어: 버린 자리를 안 벗어났는데 도로 주워졌다")
	# 버린 자리를 벗어나면 풀리고, 그 뒤에 놓인 자리로 가면 주워진다.
	ground.update(stood + Vector2(0.0, -200.0), inv, 1000.0)
	if bool((ground.items[0] as Dictionary)[GroundItems.KEY_LOCKED]):
		_fails.append("코어: 버린 자리를 벗어났는데 잠금이 안 풀렸다")
	ground.update(at, inv, 1000.0)
	if ground.size() != 0 or inv.count_of("wood") != 5:
		_fails.append("코어: 잠금이 풀린 뒤인데 놓인 자리에서 안 주워졌다")


## 8) **버린 것은 바라보는 방향 앞 한 칸에 놓이고, 물 위에는 안 놓인다**
## (2026-09-07, INBOX #42 — docs/DESIGN.md 「바닥 드롭」).
##
## 자리를 고르는 것은 코어(`player_motion.gd` 의 `drop_position()`)라 화면 없이 잰다.
func _check_drop_spot() -> void:
	var world := WorldGen.new()
	world.build(SEED)
	var motion := PlayerMotion.new(world)

	# (1) 사방이 육지인 칸 — 네 방향 모두 정확히 한 칸 앞이다.
	var open := _find_open_tile(world)
	if open == Vector2i(-1, -1):
		_fails.append("코어: 사방이 육지인 칸을 못 찾았다")
		return
	motion.place_at_tile(open)
	for d in PlayerMotion.DIR_ANGLE.size():
		# `facing` 은 `tick()` 이 조준 각도에서 정하는 값이다 — 여기서는 그 결과만 흉내낸다.
		motion.facing = d
		var spot := motion.drop_position()
		var want := motion.position + motion.facing_direction() * PlayerMotion.DROP_DISTANCE
		if spot.distance_to(want) > 0.5:
			_fails.append("코어: %d번 방향으로 버린 것이 앞 한 칸(%s)이 아니라 %s 에 놓였다"
					% [d, want, spot])
		if spot.distance_to(motion.position) <= GroundItems.PICKUP_RADIUS:
			_fails.append("코어: 버린 자리가 줍히는 거리(%.0f) 안이다 — 발밑과 안 갈린다"
					% GroundItems.PICKUP_RADIUS)

	# (2) 물가에서 물을 보고 버려도 바다 칸에는 안 놓인다 — 놓이면 영영 못 줍는다.
	var shore := _find_shore(world)
	if shore.is_empty():
		_fails.append("코어: 물가 칸을 못 찾았다")
		return
	motion.place_at_tile(shore[0])
	motion.facing = shore[1]
	var at := motion.drop_position()
	var tile := WorldGen.world_to_tile(at)
	if not world.is_land(tile.x, tile.y):
		_fails.append("코어: 물을 보고 버렸더니 바다 칸 %s 에 놓였다 — 영영 못 줍는다" % tile)
	if at.distance_to(motion.position) > PlayerMotion.DROP_DISTANCE + 0.5:
		_fails.append("코어: 버린 자리가 한 칸(%.0f)보다 멀다" % PlayerMotion.DROP_DISTANCE)


## 스폰 근처에서 사방 2칸이 전부 육지인 칸.
func _find_open_tile(world: RefCounted) -> Vector2i:
	var spawn: Vector2i = world.spawn_tile
	for radius in range(0, 40):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := spawn + Vector2i(dx, dy)
				if _land_around(world, tile, 2):
					return tile
	return Vector2i(-1, -1)


## 스폰 근처에서 **한 방향 앞이 바다인** 육지 칸과 그 방향. `[타일, 방향]` 을 돌려준다.
func _find_shore(world: RefCounted) -> Array:
	var spawn: Vector2i = world.spawn_tile
	for radius in range(1, 120):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := spawn + Vector2i(dx, dy)
				if not world.is_land(tile.x, tile.y):
					continue
				for d in PlayerMotion.DIR_ANGLE.size():
					var ahead := Vector2i(Vector2.from_angle(PlayerMotion.DIR_ANGLE[d]).round())
					if not world.is_land(tile.x + ahead.x, tile.y + ahead.y):
						return [tile, d]
	return []


## 3) 줍히는 거리 경계.
func _check_pickup_radius() -> void:
	var ground := GroundItems.new()
	var inv := Inventory.new()
	var at := Vector2.ZERO
	ground.drop(ItemStack.new("stone", 3), at, 1000.0)
	ground.update(at + Vector2(500.0, 0.0), inv, 1000.0)  # 잠금 풀기
	ground.update(at + Vector2(GroundItems.PICKUP_RADIUS + 1.0, 0.0), inv, 1000.0)
	if ground.size() != 1:
		_fails.append("코어: 줍히는 거리 밖에서 주워졌다")
		return
	ground.update(at + Vector2(GroundItems.PICKUP_RADIUS - 1.0, 0.0), inv, 1000.0)
	if ground.size() != 0 or inv.count_of("stone") != 3:
		_fails.append("코어: 줍히는 거리 안인데 안 주워졌다")


## 4) 꽉 찬 인벤토리 — 들어갈 만큼만 들어가고 나머지는 바닥에 남는다 (「인벤토리 안전」).
func _check_full_inventory_keeps_leftover() -> void:
	var ground := GroundItems.new()
	var inv := Inventory.new()
	var full := ItemTypes.MAX_STACK
	for index in Inventory.GENERAL_SLOTS:
		inv.general[index] = ItemStack.new("wood", full)
	inv.general[0] = ItemStack.new("stone", full - 10)  # 돌 10개 자리만 남긴다
	var at := Vector2.ZERO
	ground.drop(ItemStack.new("stone", 60), at, 1000.0)
	ground.update(at + Vector2(500.0, 0.0), inv, 1000.0)  # 잠금 풀기
	ground.update(at, inv, 1000.0)
	if ground.size() != 1:
		_fails.append("코어: 넘치는 몫이 바닥에서 사라졌다 — 「인벤토리 안전」 위반")
		return
	var stack: RefCounted = (ground.items[0] as Dictionary)[GroundItems.KEY_STACK]
	if stack.count != 50:
		_fails.append("코어: 바닥에 %d개가 남았다 — 50개여야 한다" % stack.count)
	if inv.count_of("stone") != full:
		_fails.append("코어: 인벤토리에 돌이 %d개다 — %d개여야 한다"
				% [inv.count_of("stone"), full])


## 5) 수명이 다한 것은 사라진다.
func _check_lifetime() -> void:
	var ground := GroundItems.new()
	var inv := Inventory.new()
	var at := Vector2.ZERO
	var dropped := 1000.0
	ground.drop(ItemStack.new("wood", 5), at, dropped)
	# 아직 하루가 안 지났다 — 멀리 있어도 그대로다.
	ground.update(at + Vector2(500.0, 0.0), inv, dropped + GroundItems.LIFETIME_SECONDS - 1.0)
	if ground.size() != 1:
		_fails.append("코어: 수명이 남았는데 바닥 아이템이 사라졌다")
		return
	ground.update(at + Vector2(500.0, 0.0), inv, dropped + GroundItems.LIFETIME_SECONDS)
	if ground.size() != 0:
		_fails.append("코어: 수명이 다했는데 안 사라졌다")
	if inv.count_of("wood") != 0:
		_fails.append("코어: 사라질 것이 인벤토리로 들어갔다")


## 6) 저장·불러오기 왕복.
func _check_save_round_trip() -> void:
	var ground := GroundItems.new()
	ground.drop(ItemStack.new("wood", 5), Vector2(120.5, -30.25), 1000.0)
	ground.drop(ItemStack.new("axe", 1), Vector2(9.0, 9.0), 2000.0)
	var data := ground.to_data()
	# JSON 한 바퀴를 실제로 돌린다 — 슬롯 파일이 지나가는 길 그대로다.
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var loaded := GroundItems.new()
	if loaded.from_data(parsed) != 2:
		_fails.append("코어: 저장했다 불러오니 개수가 달라졌다")
		return
	for index in 2:
		var before: Dictionary = ground.items[index]
		var after: Dictionary = loaded.items[index]
		var a: RefCounted = before[GroundItems.KEY_STACK]
		var b: RefCounted = after[GroundItems.KEY_STACK]
		if a.id != b.id or a.count != b.count or a.ownership != b.ownership:
			_fails.append("코어: 왕복 후 뭉치가 달라졌다 (%s %d ↔ %s %d)"
					% [a.id, a.count, b.id, b.count])
		if before[GroundItems.KEY_POSITION] != after[GroundItems.KEY_POSITION]:
			_fails.append("코어: 왕복 후 자리가 달라졌다")
		if float(before[GroundItems.KEY_DROPPED]) != float(after[GroundItems.KEY_DROPPED]):
			_fails.append("코어: 왕복 후 놓인 시각이 달라졌다")
		if not bool(after[GroundItems.KEY_LOCKED]):
			_fails.append("코어: 불러온 것이 안 잠겨 있다 — 들어오자마자 도로 주워진다")
	# 깨진 줄은 조용히 건너뛴다.
	var broken := GroundItems.new()
	broken.from_data([{"s": {"id": "없는아이템", "n": 3}, "x": 0.0, "y": 0.0, "t": 0.0}, "쓰레기"])
	if broken.size() != 0:
		_fails.append("코어: 깨진 저장 줄이 살아 들어왔다")


# =============================================================================
# B. 화면 — 실제 월드 씬에서
# =============================================================================

## 8) 버리기 전에는 없던 아이템 색이 버린 뒤에 그 자리에 생긴다.
func _check_drawn_after_drop() -> void:
	var ground := _ground()
	if ground == null or ground.size() != 1:
		_fails.append("버렸는데 바닥 데이터가 안 생겼다")
		return
	if _view().get_child_count() != 1:
		_fails.append("바닥 아이템 노드가 %d개다 — 1개여야 한다" % _view().get_child_count())
		return
	var before := _count_item(_shots["empty"], _shown_position, "wood")
	var after := _count_item(_capture(), _shown_position, "wood")
	if before >= SORT_MIN_PIXELS:
		_fails.append("버리기 전인데 그 자리에 이미 목재 색이 %d px 있다" % before)
	if after < SORT_MIN_PIXELS:
		_fails.append("버린 자리에 목재가 안 보인다 (%d px)" % after)


## 9) 앞뒤(Y) 정렬 — 아이템을 플레이어 위/아래로 옮겨 놓고, **겹친 픽셀만** 골라
## "둘 다 그린 화면"이 이긴 쪽과 같은지 본다. 네 장을 견주므로 그림 모양을 몰라도 된다.
func _sort_steps(offset_y: float, item_in_front: bool, shot_name: String) -> Array[Callable]:
	var steps: Array[Callable] = []
	steps.append(func(): _place_item(_drop_position + Vector2(0.0, offset_y)))
	steps.append(func(): _show_layers(false, false))
	steps.append(func(): _remember_shot("empty_layer"))
	steps.append(func(): _show_layers(true, false))
	steps.append(func(): _remember_shot("item_layer"))
	steps.append(func(): _show_layers(false, true))
	steps.append(func(): _remember_shot("player_layer"))
	steps.append(func(): _show_layers(true, true))
	steps.append(func(): _remember_shot("both_layer"))
	steps.append(func(): _shoot(shot_name))
	steps.append(func(): _check_sort_order(item_in_front, offset_y))
	return steps


func _show_layers(item: bool, player: bool) -> void:
	_view().visible = item
	# **플레이어 노드가 아니라 그 그림만 감춘다** — 카메라가 플레이어의 자식이라
	# 노드째 감추면 화면이 어디를 비추는지가 흔들린다.
	var sprite := _player().get_node_or_null("Sprite") as CanvasItem
	if sprite == null:
		_fails.append("플레이어 그림 노드를 못 찾았다")
		return
	sprite.visible = player


func _check_sort_order(item_in_front: bool, offset_y: float) -> void:
	var empty: Image = _shots.get("empty_layer")
	var only_item: Image = _shots.get("item_layer")
	var only_player: Image = _shots.get("player_layer")
	var both: Image = _shots.get("both_layer")
	if empty == null or only_item == null or only_player == null or both == null:
		_fails.append("Y정렬 검사용 캡처가 모자라다")
		return
	var contested := 0
	var wrong := 0
	var rect := _image_rect(only_item, _drop_position + Vector2(0.0, offset_y))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var at := Vector2i(x, y)
			var background := empty.get_pixelv(at)
			var item_pixel := only_item.get_pixelv(at)
			var player_pixel := only_player.get_pixelv(at)
			# 둘 다 이 픽셀을 칠했을 때만 순서를 따질 수 있다.
			if _same(item_pixel, background) or _same(player_pixel, background):
				continue
			contested += 1
			var winner := item_pixel if item_in_front else player_pixel
			if not _same(both.get_pixelv(at), winner):
				wrong += 1
	if contested < SORT_MIN_PIXELS:
		_fails.append("Y정렬 검사가 헛돌았다 — 겹친 픽셀이 %d px 뿐이다" % contested)
		return
	if wrong > 0:
		_fails.append("Y정렬이 어긋났다 — 겹친 %d px 중 %d px 에서 %s 가 안 이겼다"
				% [contested, wrong, "아이템" if item_in_front else "플레이어"])


func _move_item_onto_player() -> void:
	_place_item(_drop_position)


## 9-1) 버린 자리에 서 있는 동안은 안 주워진다.
func _check_not_taken_while_standing() -> void:
	var ground := _ground()
	if ground == null or ground.size() != 1:
		_fails.append("버린 자리에 서 있는데 도로 주워졌다")
		return
	if _inventory().count_of("wood") != 0:
		_fails.append("버린 자리에 서 있는데 목재가 인벤토리로 돌아왔다")


func _check_walked_away() -> void:
	var moved := _player().global_position.distance_to(_hold_from)
	if moved <= GroundItems.PICKUP_RADIUS:
		_fails.append("걸어서 줍히는 거리 밖으로 못 나갔다 (%.1f px)" % moved)


func _check_unlocked_but_still_there() -> void:
	var ground := _ground()
	if ground == null or ground.size() != 1:
		_fails.append("멀어졌더니 바닥 아이템이 사라졌다")
		return
	if bool((ground.items[0] as Dictionary)[GroundItems.KEY_LOCKED]):
		_fails.append("멀어졌는데 잠금이 안 풀렸다 — 돌아와도 못 줍는다")


## 9-2) 돌아오면 주워진다.
func _check_picked_up() -> void:
	var ground := _ground()
	if ground == null or ground.size() != 0:
		_fails.append("돌아왔는데 바닥에 %d개가 남아 있다" % (0 if ground == null else ground.size()))
	if _inventory().count_of("wood") != WOOD_COUNT:
		_fails.append("주웠는데 목재가 %d개다 — %d개여야 한다"
				% [_inventory().count_of("wood"), WOOD_COUNT])
	if _view().get_child_count() != 0:
		_fails.append("주웠는데 바닥 그림이 %d개 남아 있다" % _view().get_child_count())


## 11) 꽉 찬 인벤토리로 밟으면 들어갈 만큼만 들어간다.
func _fill_inventory_and_drop_stone() -> void:
	var inv := _inventory()
	var full := ItemTypes.MAX_STACK
	for index in Inventory.GENERAL_SLOTS:
		inv.general[index] = ItemStack.new("wood", full)
	inv.general[0] = ItemStack.new("stone", full - 10)
	inv.version += 1
	_drop_position = _player().global_position + Vector2(0.0, -120.0)
	_ground().drop(ItemStack.new("stone", 60), _drop_position)


func _step_onto_stone() -> void:
	_player().place_at(_drop_position)


func _step_away_from_stone() -> void:
	_player().place_at(_drop_position + Vector2(0.0, 120.0))


func _check_overflow_left_on_ground() -> void:
	var ground := _ground()
	if ground == null or ground.size() != 1:
		_fails.append("넘치는 몫이 바닥에서 사라졌다 — 「인벤토리 안전」 위반")
		return
	var stack: RefCounted = (ground.items[0] as Dictionary)[GroundItems.KEY_STACK]
	if stack.count != 50:
		_fails.append("바닥에 돌이 %d개 남았다 — 50개여야 한다" % stack.count)
	if _inventory().count_of("stone") != ItemTypes.MAX_STACK:
		_fails.append("들어갈 만큼 안 들어갔다 (돌 %d개)" % _inventory().count_of("stone"))
	if _view().get_child_count() != 1:
		_fails.append("바닥에 남았는데 그림이 %d개다" % _view().get_child_count())


## 넘쳐서 바닥에 남은 몫이 **화면에도** 남아 있는가.
func _check_leftover_drawn() -> void:
	if _count_item(_capture(), _drop_position, "stone") < SORT_MIN_PIXELS:
		_fails.append("바닥에 남은 돌이 화면에 안 보인다")


## 12) 나갔다 들어와도 그 자리에 그대로.
func _check_survives_save_load() -> void:
	var ground := _ground()
	if ground == null or ground.size() != 1:
		_fails.append("다시 들어오니 바닥 아이템이 사라졌다")
		return
	var entry: Dictionary = ground.items[0]
	var stack: RefCounted = entry[GroundItems.KEY_STACK]
	if stack.id != "stone" or stack.count != 50:
		_fails.append("다시 들어오니 바닥에 %s %d개다 — stone 50개여야 한다"
				% [stack.id, stack.count])
	var at: Vector2 = entry[GroundItems.KEY_POSITION]
	if at.distance_to(_drop_position) > 0.5:
		_fails.append("다시 들어오니 자리가 %.1f px 옮겨졌다" % at.distance_to(_drop_position))
	# 여기서 잠금은 이미 풀려 있는 게 맞다 — 다시 들어오면 스폰 지점에 서므로 그 자리를
	# 벗어난 상태다. "불러온 것이 잠긴 채로 시작한다"는 코어 왕복 검사가 본다.


## 아이콘이 있는 아이템 하나를 바닥에 놓는다(눈으로 볼 캡처용). 앞 단계에서 인벤토리를
## 목재로 가득 채웠으므로 한 칸을 도끼로 바꿔놓고 그 칸을 버린다.
func _drop_axe() -> void:
	var inv := _inventory()
	inv.general[Inventory.HOTBAR_SLOTS - 1] = ItemStack.new("axe", 1)
	inv.version += 1
	current_scene.call("_on_drop_outside", Inventory.AREA_GENERAL, Inventory.HOTBAR_SLOTS - 1)


## 버린 도끼가 놓인 자리를 받아 적는다 — **옮기지 않는다**(INBOX #42 뒤로는 버린 것이
## 캐릭터 앞 한 칸에 놓여서 그대로 보인다). 줍히는 거리 밖이라 그대로 남는다.
func _read_axe_spot() -> void:
	var ground := _ground()
	if ground == null or ground.size() < 2:
		_fails.append("버린 도끼가 바닥에 없다")
		return
	_axe_position = (ground.items[ground.size() - 1] as Dictionary)[GroundItems.KEY_POSITION]


## 도구는 자리표시가 아니라 **구워진 그림**이라 아이템 색으로 셀 수가 없다 —
## 버리기 전 캡처와 견줘서 그 자리의 픽셀이 실제로 바뀌었는지 본다.
func _check_tool_drawn() -> void:
	if _view().get_child_count() != 2:
		_fails.append("도구를 버렸는데 바닥 그림이 %d개다 — 2개여야 한다"
				% _view().get_child_count())
		return
	var changed := _count_changed(_shots["before_tool"], _capture(), _axe_position)
	if changed < SORT_MIN_PIXELS:
		_fails.append("버린 도끼가 화면에 안 보인다 (바뀐 픽셀 %d)" % changed)


## 다시 들어온 뒤 그림을 확인할 자리로 간다 — **줍히는 거리 밖**이라 안 주워진다.
func _stand_near_stone() -> void:
	_player().place_at(_drop_position + Vector2(0.0, 120.0))


func _check_drawn_after_reload() -> void:
	if _view().get_child_count() != 1:
		_fails.append("다시 들어오니 바닥 그림이 %d개다" % _view().get_child_count())
		return
	if _count_item(_capture(), _drop_position, "stone") < SORT_MIN_PIXELS:
		_fails.append("다시 들어오니 바닥 아이템이 화면에 안 보인다")


# =============================================================================
# 도우미
# =============================================================================

func _enter_world() -> void:
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("바닥이", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)


func _settle() -> void:
	_wait_time = SETTLE_SECONDS


## 사방이 육지인 자리에 세운다 — 걸어 나갔다 돌아오는 검사가 바다에 막히면 안 된다.
func _stand_on_open_land() -> void:
	var world := _world()
	var spawn: Vector2i = world.spawn_tile
	for radius in range(0, 40):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := spawn + Vector2i(dx, dy)
				if _land_around(world, tile, 3):
					_player().place_at(WorldGen.tile_center(tile))
					return
	_fails.append("사방이 육지인 자리를 못 찾았다")


## 실제 마우스를 조준 기준점에서 `angle` 쪽으로 밀어놓는다.
##
## **바라보는 방향은 마우스가 정한다**(`player.gd` 의 `aim_angle_for`) — 그래서
## 커서를 안 옮기면 「버린 것이 앞 한 칸에 놓이는가」가 **그 기계의 커서가 어디
## 있었는지**에 따라 통과하거나 실패한다. 각도를 코어에 직접 넣지 않고
## `Input.warp_mouse()` 로 미는 이유는 노드의 "마우스 → 각도" 변환까지 함께
## 지나가야 하기 때문이다 (docs/GOTCHAS.md).
##
## 카메라가 플레이어의 자식이라 **발밑이 화면 한가운데**고, 조준 기준점은 거기서
## 몸 절반만큼 위다(`player.gd` 의 `aim_origin()`).
func _aim_at(angle: float) -> void:
	# **논리 좌표**로 잡는다 — 아래에서 `_to_window()` 로 한 번만 창 픽셀로 옮긴다.
	# 창 크기로 잡으면 이미 창 픽셀인 값을 한 번 더 변환해서 조준 각도가 어긋난다
	# (2026-09-08, INBOX #48 — 그 전에는 논리 해상도와 창 크기가 같아서 안 드러났다).
	var size := root.get_visible_rect().size
	var origin := size * 0.5 - Vector2(0.0, PlayerFrames.CELL * PlayerFrames.SCALE * 0.5)
	Input.warp_mouse(_to_window(origin + Vector2.from_angle(angle) * minf(size.x, size.y) * AIM_REACH))


func _land_around(world: RefCounted, tile: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if not world.is_land(tile.x + dx, tile.y + dy):
				return false
	return true


## 버린 것이 **실제로 놓인 자리**를 받아 적는다.
##
## 예전에는 여기서 아이템을 옆으로 옮겼다 — 발밑에 놓여서 캐릭터에 통째로 가렸기
## 때문이다(2026-09-07, INBOX #42 가 그걸 고쳤다). 지금은 **한 픽셀도 안 옮기고**,
## 코어가 고른 자리가 정말 사람 앞 한 칸인지까지 여기서 함께 본다.
func _read_drop_spot() -> void:
	var ground := _ground()
	if ground == null or ground.size() == 0:
		_fails.append("버렸는데 바닥에 아무것도 없다")
		return
	_shown_position = (ground.items[0] as Dictionary)[GroundItems.KEY_POSITION]
	# 노드가 코어에 물어본 자리 그대로여야 한다(`world.gd` 가 다른 값을 넣지 않았는지).
	var want: Vector2 = _player().call("drop_position")
	if _shown_position.distance_to(want) > 0.5:
		_fails.append("버린 것이 코어가 고른 자리(%s)가 아니라 %s 에 놓였다"
				% [want, _shown_position])
	var gap := _shown_position.distance_to(_drop_position)
	if gap <= GroundItems.PICKUP_RADIUS:
		_fails.append("버린 것이 발밑에서 %.1f px 밖에 안 떨어졌다 — 캐릭터에 가린다" % gap)
	# 바로 앞 단계에서 마우스로 **아래**를 겨눠뒀다(`_aim_at`) — 그래서 앞은 아래쪽이다.
	if _shown_position.y <= _drop_position.y:
		_fails.append("아래를 보고 버렸는데 아이템이 캐릭터 앞으로 안 갔다")


func _drop_wood() -> void:
	_drop_position = _player().global_position
	current_scene.call("_on_drop_outside", Inventory.AREA_GENERAL, WOOD_SLOT)


## 바닥 아이템 하나를 그 자리로 옮긴다(검사용). 그리는 쪽이 알아채게 버전을 올린다.
func _place_item(at: Vector2) -> void:
	var ground := _ground()
	if ground == null or ground.size() == 0:
		_fails.append("옮길 바닥 아이템이 없다")
		return
	(ground.items[0] as Dictionary)[GroundItems.KEY_POSITION] = at
	ground.version += 1


func _hold_move(action: String) -> void:
	_hold_from = _player().global_position
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_press(action)
	_wait_time = HOLD_SECONDS
	# 다음 단계가 시작될 때 키를 뗀다 — 누른 채로 두면 계속 걷는다.
	_steps.insert(_step, func(): Input.action_release(action))


func _press(path: String) -> void:
	var button := current_scene.get_node_or_null(path) as Button
	if button == null:
		_fails.append("버튼을 못 찾았다: %s" % path)
		return
	button.emit_signal("pressed")


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


## 바닥 아이템 하나가 차지하는 캡처 안의 사각형(이미지 밖으로 안 나가게 자른다).
func _image_rect(image: Image, world_point: Vector2) -> Rect2i:
	var zoom := float(image.get_width()) / root.get_visible_rect().size.x
	var center := _image_point(image, world_point)
	var side := int(ceil(GroundItemNode.BOX * zoom))
	var sink := int(ceil(GroundItemNode.SINK * zoom))
	var margin := 2
	var at := Vector2i(center.x - side / 2 - margin, center.y + sink - side - margin)
	var rect := Rect2i(at, Vector2i(side + margin * 2, side + margin * 2))
	return rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))


## 두 캡처에서 그 자리의 픽셀이 몇 개나 달라졌는가.
func _count_changed(before: Image, after: Image, world_point: Vector2) -> int:
	if before == null or after == null:
		return 0
	var rect := _image_rect(after, world_point)
	var found := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not _same(before.get_pixel(x, y), after.get_pixel(x, y)):
				found += 1
	return found


## 그 자리 주변에서 **그 아이템의 자리표시 색**으로 칠해진 픽셀 수.
## 자리표시는 아이템 색 하나에서 만든 램프 4단계로 그려지므로(`ground_item_node.gd`),
## 기본색 한 가지만 세면 그림의 일부만 세는 셈이 된다.
func _count_item(image: Image, world_point: Vector2, id: String) -> int:
	var base := ItemTypes.color_of(id)
	var found := 0
	for color in [base.lightened(GroundItemNode.LIGHTEN), base,
			base.darkened(GroundItemNode.DARKEN), base.darkened(GroundItemNode.DARKEST)]:
		found += _count_color(image, world_point, color)
	return found


## 그 자리 주변에서 그 색으로 칠해진 픽셀 수.
func _count_color(image: Image, world_point: Vector2, color: Color) -> int:
	if image == null:
		return 0
	var rect := _image_rect(image, world_point)
	var found := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if _same(image.get_pixel(x, y), color):
				found += 1
	return found


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= COLOR_EPSILON and absf(a.g - b.g) <= COLOR_EPSILON \
			and absf(a.b - b.b) <= COLOR_EPSILON


func _world() -> RefCounted:
	return current_scene.get("world")


func _inventory() -> RefCounted:
	return current_scene.get("inventory")


func _ground() -> RefCounted:
	return current_scene.get("ground_items")


func _player() -> Node2D:
	return current_scene.get_node_or_null("%Player") as Node2D


func _view() -> Node2D:
	return current_scene.get_node_or_null("%GroundItemsView") as Node2D

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
