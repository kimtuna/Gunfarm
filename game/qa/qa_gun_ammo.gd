extends SceneTree

## INBOX #35 자체 QA — 탄창 8발 / R 재장전 / 우클릭 탄종 전환 / 총 UI.
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_gun_ammo.gd
##
## 확인하는 것:
##   A. 코어(`gun_ammo.gd` / `player_motion.gd` — 화면 없이 도는 순수 클래스)
##      1) 탄창 8발 — 처음엔 가득, 8발 쏘면 비고, **9발째는 안 나간다.**
##      2) 재장전은 **즉시가 아니다** — 걸리는 시간 동안 못 쏘고, 끝나면 가득이다.
##         가득일 때 R 은 아무 일도 하지 않고, 연타해도 타이머가 되감기지 않는다.
##      3) **탄종마다 탄창이 따로다** — 기본탄을 다 쓰고 마취탄으로 바꿔도 마취탄은
##         가득이고, 되돌아오면 기본탄은 여전히 비어 있다.
##      4) 탄종을 바꾸면 진행 중이던 재장전이 취소된다.
##      5) **재장전 타이머는 플레이어 코어의 틱 안에서 돈다** — 그리고 R/우클릭은
##         누르고 있는 내내가 아니라 **눌린 틱 하나**에만 시작된다.
##      6) 연사 간격 0.5초(`USE_TICKS`)가 그대로 「총기 스탯」의 초당 2발이다.
##   B. 화면(실제 월드 씬에서)
##      7) **총을 들었을 때만 총 UI 가 보인다** — 도끼를 들면 사라진다.
##      8) 창(일시정지)이 열리면 사라진다.
##      9) 좌클릭하면 남은 발수가 줄고 **화면 그림도 같이 바뀐다**(탄창 칸을 픽셀로 본다).
##     10) 탄창을 비우면 좌클릭해도 총알이 안 나가고, **R 을 누르면 다시 나간다.**
##     11) 우클릭하면 탄종이 바뀌고 **화면의 탄창 색도 같이 바뀐다.**

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const GunAmmo := preload("res://scripts/gun_ammo.gd")
const GunHud := preload("res://scripts/gun_hud.gd")
const ItemTypes := preload("res://scripts/item_types.gd")
const PlayerMotion := preload("res://scripts/player_motion.gd")
const PlayerInput := preload("res://scripts/player_input.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260907

## 프레임 수가 아니라 **시간**으로 기다린다 (docs/GOTCHAS.md).
const SETTLE_SECONDS := 0.2

## 연사 간격(0.5초)보다 넉넉히 긴 대기 — 좌클릭을 연달아 흘려보낼 때 쓴다.
const SHOT_GAP_SECONDS := 0.6

## 재장전이 끝나기를 기다리는 시간(초). `RELOAD_TICKS` 보다 넉넉해야 한다.
const RELOAD_WAIT_SECONDS := 2.0

## 픽셀이 "달라졌다"고 보는 문턱 (qa_bullets.gd 와 같은 값).
const DIFF_EPSILON := 0.008

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

var _shots := {}
var _pip_colors := {}
var _loaded_before := 0
var _bullets_before := 0


## 총알 검사용 가짜 월드 — `player_motion.gd` 는 `is_land()` 하나만 본다.
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
		_stand_on_open_land,
		_aim_right,
		_settle,
		_settle,
		# 7) 총을 들었을 때만 보인다
		_hold_gun,
		_settle,
		func(): _remember_pip_colors("full"),
		_check_hud_visible,
		func(): _shoot("85_gun_hud_full"),
		_hold_axe,
		_settle,
		_check_hud_hidden_with_axe,
		func(): _shoot("86_gun_hud_axe"),
		_hold_gun,
		_settle,
		# 8) 창이 열리면 사라진다
		func(): _send_action("ui_cancel"),
		_settle,
		_check_hud_hidden_while_paused,
		func(): _send_action("ui_cancel"),
		_settle,
		_check_hud_back_after_close,
		# 9) 한 발 쏘면 발수가 줄고 화면도 바뀐다
		_remember_before_shot,
		_fire_once,
		_settle,
		_check_one_round_spent,
		func(): _remember_pip_colors("after_one"),
		_check_pip_changed_after_shot,
		func(): _shoot("87_gun_hud_after_one"),
		# 10) 다 쏘면 안 나가고, R 로 되살아난다
		_empty_the_magazine,
		_settle,
		_check_magazine_empty,
		func(): _shoot("88_gun_hud_empty"),
		_remember_before_shot,
		_fire_once,
		_settle,
		_check_click_on_empty_does_nothing,
		func(): _send_action("reload"),
		_settle,
		_check_reloading_now,
		func(): _shoot("89_gun_hud_reloading"),
		func(): _wait_time = RELOAD_WAIT_SECONDS,
		_check_reload_finished,
		_remember_before_shot,
		_fire_once,
		_settle,
		_check_fires_again_after_reload,
		# 11) 우클릭으로 탄종이 바뀌고 화면도 바뀐다
		func(): _send_action("switch_ammo"),
		_settle,
		_check_kind_switched,
		func(): _remember_pip_colors("tranq"),
		_check_pip_color_changed,
		func(): _shoot("90_gun_hud_tranq"),
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
			print("[qa] PASS — 탄창 + 재장전 + 탄종 전환 + 총 UI")
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
	_check_magazine_size()
	_check_reload_takes_time()
	_check_kinds_are_separate()
	_check_switch_cancels_reload()
	_check_core_ticks_and_edges()
	_check_fire_rate()


## 1) 탄창 8발 — 처음엔 가득, 8발 쏘면 비고, 9발째는 안 나간다.
func _check_magazine_size() -> void:
	if GunAmmo.MAG_SIZE != 8:
		_fails.append("코어: 탄창이 %d발이다 — 「총기 스탯」은 8발이다" % GunAmmo.MAG_SIZE)
	var gun := GunAmmo.new()
	if gun.loaded() != GunAmmo.MAG_SIZE:
		_fails.append("코어: 처음 탄창이 %d발이다 — 가득이어야 한다" % gun.loaded())
	for i in GunAmmo.MAG_SIZE:
		if not gun.fire():
			_fails.append("코어: %d발째가 안 나갔다" % (i + 1))
			return
	if gun.loaded() != 0:
		_fails.append("코어: 8발 쏘고 %d발 남았다" % gun.loaded())
	if gun.fire():
		_fails.append("코어: 탄창이 비었는데 9발째가 나갔다")
	if gun.can_fire():
		_fails.append("코어: 탄창이 비었는데 쏠 수 있다고 한다")


## 2) 재장전은 즉시가 아니다 — 걸리는 시간 동안 못 쏘고, 끝나면 가득이다.
func _check_reload_takes_time() -> void:
	if GunAmmo.RELOAD_TICKS <= PlayerMotion.USE_TICKS:
		_fails.append("코어: 재장전(%d틱)이 연사 간격(%d틱)보다 짧다 — 탄창이 있으나 마나다"
				% [GunAmmo.RELOAD_TICKS, PlayerMotion.USE_TICKS])
	var gun := GunAmmo.new()
	if gun.start_reload():
		_fails.append("코어: 탄창이 가득인데 재장전이 시작됐다")
	for i in GunAmmo.MAG_SIZE:
		gun.fire()
	if not gun.start_reload():
		_fails.append("코어: 빈 탄창인데 재장전이 시작되지 않았다")
	# 연타해도 되감기지 않는다.
	var left := gun.reload_ticks_left
	gun.tick()
	if gun.start_reload():
		_fails.append("코어: 재장전 중에 R 을 또 눌렀더니 다시 시작됐다")
	if gun.reload_ticks_left >= left:
		_fails.append("코어: 재장전 중에 R 을 눌렀더니 타이머가 되감겼다")
	# 끝나기 전까지는 못 쏘고 탄창도 안 찬다.
	while gun.reload_ticks_left > 1:
		if gun.can_fire():
			_fails.append("코어: 재장전 중인데 쏠 수 있다고 한다")
			break
		if gun.loaded() != 0:
			_fails.append("코어: 재장전이 끝나기 전에 탄창이 찼다 (%d발)" % gun.loaded())
			break
		gun.tick()
	gun.tick()
	if gun.is_reloading():
		_fails.append("코어: %d틱을 다 돌았는데 재장전이 안 끝났다" % GunAmmo.RELOAD_TICKS)
	if gun.loaded() != GunAmmo.MAG_SIZE:
		_fails.append("코어: 재장전이 끝났는데 %d발이다 — 가득이어야 한다" % gun.loaded())


## 3) **탄종마다 탄창이 따로다** — 하나의 수를 공유하면 안 된다 (「총기 스탯」).
func _check_kinds_are_separate() -> void:
	var gun := GunAmmo.new()
	if gun.kind != GunAmmo.BASIC:
		_fails.append("코어: 처음 탄종이 %s 다 — 기본탄이어야 한다" % gun.kind)
	for i in GunAmmo.MAG_SIZE:
		gun.fire()
	var next := gun.switch_kind()
	if next != GunAmmo.TRANQ:
		_fails.append("코어: 우클릭했더니 탄종이 %s 가 됐다 — 마취탄이어야 한다" % next)
	if gun.loaded() != GunAmmo.MAG_SIZE:
		_fails.append("코어: 기본탄을 다 쓰고 마취탄으로 바꿨더니 %d발이다 — 가득이어야 한다"
				% gun.loaded())
	gun.fire()
	gun.fire()
	if gun.switch_kind() != GunAmmo.BASIC:
		_fails.append("코어: 한 번 더 우클릭했는데 기본탄으로 안 돌아왔다")
	if gun.loaded() != 0:
		_fails.append("코어: 비워둔 기본탄으로 돌아왔더니 %d발이다 — 0이어야 한다" % gun.loaded())
	if gun.loaded_of(GunAmmo.TRANQ) != GunAmmo.MAG_SIZE - 2:
		_fails.append("코어: 마취탄이 %d발이다 — 두 발 썼으니 %d발이어야 한다"
				% [gun.loaded_of(GunAmmo.TRANQ), GunAmmo.MAG_SIZE - 2])
	# 검사에 이가 있는지 — 두 탄창이 한 수를 공유하면 위가 전부 무너진다.
	if gun.rounds.size() != GunAmmo.KINDS.size():
		_fails.append("코어: 탄창이 %d개다 — 탄종 수(%d)만큼 있어야 한다"
				% [gun.rounds.size(), GunAmmo.KINDS.size()])


## 4) 탄종을 바꾸면 진행 중이던 재장전은 취소된다("다른 탄창으로 갈아 끼우는 것").
func _check_switch_cancels_reload() -> void:
	var gun := GunAmmo.new()
	for i in GunAmmo.MAG_SIZE:
		gun.fire()
	gun.start_reload()
	gun.switch_kind()
	if gun.is_reloading():
		_fails.append("코어: 탄종을 바꿨는데 재장전이 계속 돌고 있다")
	gun.switch_kind()
	if gun.loaded() != 0:
		_fails.append("코어: 취소된 재장전이 그래도 탄창을 채웠다 (%d발)" % gun.loaded())


## 5) 재장전 타이머는 **플레이어 코어의 틱 안에서** 돌고, R/우클릭은 눌린 틱 하나에만
## 시작된다(누르고 있는 내내가 아니다 — 그러면 R 한 번에 타이머가 계속 되감긴다).
func _check_core_ticks_and_edges() -> void:
	var motion := PlayerMotion.new(OpenWorld.new())
	if motion.gun == null:
		_fails.append("코어: 플레이어 코어가 탄창을 안 들고 있다 — 화면 상태가 되어 버렸다")
		return
	for i in GunAmmo.MAG_SIZE:
		motion.gun.fire()
	motion.gun.start_reload()
	var idle := PlayerInput.new()
	for i in GunAmmo.RELOAD_TICKS:
		motion.tick(idle)
	if motion.gun.is_reloading():
		_fails.append("코어: 플레이어 틱을 %d번 돌렸는데 재장전이 안 끝났다 — 재장전 타이머가 코어의 틱 밖에 있다"
				% GunAmmo.RELOAD_TICKS)
	# 눌린 틱 하나 — 누르고 있는 30틱 동안 한 번만 시작된다.
	var reloading := PlayerInput.new(Vector2i.ZERO, 0.0, 0, false, true, false)
	var reload_starts := 0
	for i in 30:
		motion.tick(reloading)
		if motion.reload_started:
			reload_starts += 1
	if reload_starts != 1:
		_fails.append("코어: R 을 누르고 있는 30틱 동안 재장전이 %d번 시작됐다 — 1번이어야 한다"
				% reload_starts)
	var switching := PlayerInput.new(Vector2i.ZERO, 0.0, 0, false, false, true)
	var switch_starts := 0
	for i in 30:
		motion.tick(switching)
		if motion.switch_started:
			switch_starts += 1
	if switch_starts != 1:
		_fails.append("코어: 우클릭을 누르고 있는 30틱 동안 탄종이 %d번 바뀔 뻔했다 — 1번이어야 한다"
				% switch_starts)
	# 뗐다가 다시 누르면 또 시작된다.
	motion.tick(idle)
	motion.tick(reloading)
	if not motion.reload_started:
		_fails.append("코어: R 을 뗐다 다시 눌렀는데 재장전이 시작되지 않았다")


## 6) 연사 간격 0.5초 — 「총기 스탯」의 초당 2발이 도구 쓰기의 `USE_TICKS` 그대로다.
func _check_fire_rate() -> void:
	var per_second := float(PlayerMotion.TICK_RATE) / float(PlayerMotion.USE_TICKS)
	if absf(per_second - 2.0) > 0.001:
		_fails.append("코어: 연사가 초당 %.2f발이다 — 「총기 스탯」은 2발이다" % per_second)


# =============================================================================
# B. 화면 — 실제 월드 씬에서
# =============================================================================

## 7) 총을 들면 총 UI 가 보인다.
func _check_hud_visible() -> void:
	if not _hud().visible:
		_fails.append("총을 들었는데 총 UI 가 안 보인다")
	if _hud_panel().motion == null:
		_fails.append("총 UI 가 플레이어 코어를 못 받았다 — 아무것도 못 그린다")
	var full: Array = _pip_colors.get("full", [])
	if full.size() != GunAmmo.MAG_SIZE:
		_fails.append("총 UI 의 탄창 칸을 화면에서 못 찾았다 (%d칸)" % full.size())


func _check_hud_hidden_with_axe() -> void:
	if _hud().visible:
		_fails.append("도끼를 들었는데 총 UI 가 남아 있다")


func _check_hud_hidden_while_paused() -> void:
	if _hud().visible:
		_fails.append("일시정지 메뉴가 열렸는데 총 UI 가 남아 있다")


func _check_hud_back_after_close() -> void:
	if not _hud().visible:
		_fails.append("메뉴를 닫았는데 총 UI 가 안 돌아왔다")


## 9) 한 발 쏘면 남은 발수가 하나 줄고, 총알이 실제로 나갔다.
func _check_one_round_spent() -> void:
	var gun := _gun()
	if gun.loaded() != _loaded_before - 1:
		_fails.append("한 발 쐈는데 탄창이 %d → %d 다" % [_loaded_before, gun.loaded()])
	if _bullets_count() <= _bullets_before:
		_fails.append("좌클릭했는데 총알이 안 나갔다")


## 9) 그리고 **화면 그림도 같이 바뀐다** — 마지막 칸이 찬 색에서 빈 색으로 바뀐다.
func _check_pip_changed_after_shot() -> void:
	var full: Array = _pip_colors.get("full", [])
	var after: Array = _pip_colors.get("after_one", [])
	if full.size() != GunAmmo.MAG_SIZE or after.size() != GunAmmo.MAG_SIZE:
		_fails.append("탄창 칸 색을 못 읽었다")
		return
	var last := GunAmmo.MAG_SIZE - 1
	if _same(full[last], after[last]):
		_fails.append("한 발 쐈는데 마지막 탄창 칸이 그대로다 — 화면이 안 따라왔다")
	if not _same(full[0], after[0]):
		_fails.append("한 발 쐈는데 첫 탄창 칸까지 바뀌었다 — 칸이 밀리고 있다")
	if not _close(after[last], GunHud.EMPTY_BG, 0.06):
		_fails.append("쓴 탄창 칸이 빈 칸 색이 아니다 (%s)" % after[last])


## 10) 탄창이 비었다.
func _check_magazine_empty() -> void:
	if _gun().loaded() != 0:
		_fails.append("다 쏘려고 했는데 %d발 남았다" % _gun().loaded())


## 10) 빈 탄창으로 좌클릭 — **총알이 안 나간다.**
func _check_click_on_empty_does_nothing() -> void:
	if _bullets_count() > _bullets_before:
		_fails.append("탄창이 비었는데 좌클릭으로 총알이 나갔다")
	if _gun().loaded() != 0:
		_fails.append("빈 탄창인데 발수가 %d 로 바뀌었다" % _gun().loaded())


func _check_reloading_now() -> void:
	if not _gun().is_reloading():
		_fails.append("R 을 눌렀는데 재장전이 시작되지 않았다")
	if _gun().loaded() != 0:
		_fails.append("재장전을 시작하자마자 탄창이 찼다 — 시간이 안 걸린다")


func _check_reload_finished() -> void:
	if _gun().is_reloading():
		_fails.append("%.1f초를 기다렸는데 재장전이 안 끝났다" % RELOAD_WAIT_SECONDS)
	if _gun().loaded() != GunAmmo.MAG_SIZE:
		_fails.append("재장전이 끝났는데 %d발이다" % _gun().loaded())


func _check_fires_again_after_reload() -> void:
	if _bullets_count() <= _bullets_before:
		_fails.append("재장전했는데 좌클릭으로 총알이 안 나간다")


## 11) 우클릭으로 탄종이 바뀐다.
func _check_kind_switched() -> void:
	if _gun().kind != GunAmmo.TRANQ:
		_fails.append("우클릭했는데 탄종이 %s 다 — 마취탄이어야 한다" % _gun().kind)


## 11) 그리고 화면의 탄창 색도 같이 바뀐다(탄종을 눈으로 알 수 있어야 한다).
func _check_pip_color_changed() -> void:
	var basic: Array = _pip_colors.get("full", [])
	var tranq: Array = _pip_colors.get("tranq", [])
	if basic.size() != GunAmmo.MAG_SIZE or tranq.size() != GunAmmo.MAG_SIZE:
		_fails.append("탄종을 바꾼 뒤 탄창 칸 색을 못 읽었다")
		return
	if _same(basic[0], tranq[0]):
		_fails.append("탄종을 바꿨는데 탄창 색이 그대로다 (%s)" % basic[0])
	if not _close(tranq[0], ItemTypes.color_of(GunAmmo.TRANQ), 0.12):
		_fails.append("마취탄 탄창이 마취탄 색(%s)이 아니라 %s 다"
				% [ItemTypes.color_of(GunAmmo.TRANQ), tranq[0]])


# =============================================================================
# 도우미
# =============================================================================

func _enter_world() -> void:
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("사수", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)


func _settle() -> void:
	_wait_time = SETTLE_SECONDS


## 사방이 육지인 자리에 세운다 — 총알이 물가에서 사라지면 "총알이 나갔는가"를 셀 수
## 없다 (qa_bullets.gd 와 같은 방식이다).
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


func _land_around(world: RefCounted, tile: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if not world.is_land(tile.x + dx, tile.y + dy):
				return false
	return true


func _aim_right() -> void:
	var size := root.get_visible_rect().size
	Input.warp_mouse(Vector2(size.x * 0.75, size.y * 0.5))


func _hold_gun() -> void:
	_send_action("hotbar_1")


func _hold_axe() -> void:
	_send_action("hotbar_2")


func _remember_before_shot() -> void:
	_loaded_before = _gun().loaded()
	_bullets_before = _bullets_count()


func _fire_once() -> void:
	_send_action("use_tool")


## 남은 8발을 전부 쏜다 — **연사 간격(0.5초)을 지켜서** 한 발씩 나가게 한다.
## 그 간격을 안 지키면 코어가 겹쳐 쓰기를 막아 실제로는 몇 발만 나간다.
func _empty_the_magazine() -> void:
	# 이 자리는 `_steps` 한 칸이라, 남은 발수만큼 발사 단계를 그 뒤에 끼워 넣는다.
	# **기다린 다음 쏜다** — 바로 앞의 좌클릭에서 0.5초(`USE_TICKS`)가 아직 안 지났으면
	# 코어가 겹쳐 쓰기를 막아 그 한 발이 통째로 사라진다.
	var inserted: Array[Callable] = []
	for i in _gun().loaded():
		inserted.append(func(): _wait_time = SHOT_GAP_SECONDS)
		inserted.append(_fire_once)
	for i in inserted.size():
		_steps.insert(_step + i, inserted[i])


## 액션을 실제 입력으로 흘려보낸다 — 겹쳐 뜬 Control 이 마우스 버튼을 먼저 먹어도
## `InputEventAction` 은 `_unhandled_input()` 까지 간다 (docs/GOTCHAS.md).
func _send_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


## 탄창 칸 8개의 **화면 픽셀 색**. 자리는 `gun_hud.gd` 의 `pip_rect()` 에게 묻는다 —
## 그림과 검사가 같은 계산을 쓰므로 배치를 바꿔도 어긋날 데가 없다.
func _remember_pip_colors(key: String) -> void:
	var image := _capture()
	if image == null:
		return
	var panel := _hud_panel()
	var colors: Array[Color] = []
	for index in GunAmmo.MAG_SIZE:
		var rect: Rect2 = panel.pip_rect(index)
		# 칸 한가운데를 짚는다 — 테두리와 밝은 띠를 피해야 "찬 칸의 색"이 나온다.
		var at := _image_point(image, panel.global_position + rect.position + rect.size * 0.5)
		if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
			_fails.append("탄창 칸 %d 이 화면 밖이다" % index)
			return
		colors.append(image.get_pixel(at.x, at.y))
	_pip_colors[key] = colors


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


## 화면(HUD) 좌표 → 캡처 이미지의 픽셀 좌표. **논리 해상도와 실제 캡처 크기가 다를 수
## 있으므로** 배율을 캡처에서 구한다 (docs/GOTCHAS.md). HUD 는 CanvasLayer 라 카메라
## 변환을 타지 않는다 — 월드 좌표를 옮길 때와 다른 점이다.
func _image_point(image: Image, screen_point: Vector2) -> Vector2i:
	var zoom := float(image.get_width()) / root.get_visible_rect().size.x
	return Vector2i((screen_point * zoom).round())


func _same(a: Color, b: Color) -> bool:
	return _close(a, b, DIFF_EPSILON)


func _close(a: Color, b: Color, epsilon: float) -> bool:
	return absf(a.r - b.r) <= epsilon and absf(a.g - b.g) <= epsilon \
			and absf(a.b - b.b) <= epsilon


func _world() -> RefCounted:
	return current_scene.get("world")


func _bullets_count() -> int:
	var bullets: RefCounted = current_scene.get("bullets")
	return 0 if bullets == null else bullets.size()


func _player() -> Node2D:
	return current_scene.get_node("%Player") as Node2D


func _gun() -> RefCounted:
	return _player().motion.gun


func _hud() -> Control:
	return current_scene.get_node("%GunHud") as Control


func _hud_panel() -> Control:
	return current_scene.get_node("%GunHudPanel") as Control
