extends Node2D

## 월드 안의 플레이어.
##
## **이 노드가 하는 일은 입력을 모으는 것과 그리는 것뿐이다.** 실제 이동 계산은
## `scripts/player_motion.gd`(노드를 상속하지 않는 순수 클래스)가 한다 —
## docs/DESIGN.md 「서버 권위 / 클라이언트 신뢰」대로, 나중에 서버가 붙으면 서버가
## 같은 코드로 위치를 계산하고 이 노드는 그 결과를 그리기만 하게 된다. 그래서
## 여기서 `position` 을 직접 계산하는 코드를 넣으면 안 된다.

const PlayerMotion := preload("res://scripts/player_motion.gd")
const PlayerInput := preload("res://scripts/player_input.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")
const CharacterSprite := preload("res://scripts/character_sprite.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const Appearance := preload("res://scripts/character_appearance.gd")
const Inventory := preload("res://scripts/inventory.gd")

## 이 틱에 **도구 쓰기가 시작됐다**. 총이면 여기서 한 발이 나간다 — 다만 무엇을 들었는지
## 아는 것은 인벤토리를 가진 쪽(`world.gd`)이라, 이 노드는 "시작했다"만 알린다
## (docs/DESIGN.md 「서버 권위」의 "서버는 그 칸에 무엇이 있는지 자기 인벤토리에서
## 직접 본다"). **틱 안에서 쏘는 것**이라 위치는 `muzzle_position()` 으로 봐야 한다.
signal use_started

## 이 틱에 **재장전(R)을 눌렀다**. 총을 들었을 때만 실제로 재장전이 시작되는데, 무엇을
## 들었는지 아는 것은 인벤토리를 가진 쪽(`world.gd`)이라 여기서는 "눌렸다"만 알린다
## (`use_started` 와 같은 자리다).
signal reload_requested

## 이 틱에 **우클릭(탄종 전환)을 눌렀다.** 위와 같은 규칙이다.
signal ammo_switch_requested

## 이 틱에 **죽어서 리스폰했다** — 인자는 **죽은 자리**(데스드롭 상자가 생길 곳)다.
## `use_started` 와 같은 자리·같은 이유로 노드는 "죽었다"만 알린다: 상자에 무엇을
## 넣을지는 인벤토리를 아는 쪽(`world.gd`)이 정한다 (docs/DESIGN.md 「서버 권위」).
signal died(at: Vector2)

## 한 프레임에 몰아서 돌릴 수 있는 최대 틱 수. 창을 끌거나 잠깐 멈췄다 돌아왔을 때
## 밀린 시간을 한꺼번에 시뮬레이션하면 순간이동처럼 보인다 — 그냥 버린다.
const MAX_TICKS_PER_FRAME := 5

## 이동 계산 코어. 밖에서 위치를 볼 일이 있으면 이걸 통해서 본다.
var motion: RefCounted = null

## 이 노드가 로컬 플레이어의 입력을 받는가. 나중에 다른 플레이어를 그릴 때는 꺼진다
## (그때 조준 각도는 마우스가 아니라 서버가 보낸 값으로 들어온다).
var input_enabled := true

## 이 캐릭터의 인벤토리(`inventory.gd` — 순수 클래스). **손에 든 칸이 무엇인지**
## 알아야 도구를 든 모션을 고를 수 있어서 들고 있는다 (docs/DESIGN.md 「캐릭터
## 애니메이션」의 "손에 든 도구가 캐릭터에 그대로 보인다").
## **null 이어도 된다** — 슬롯을 안 거치고 씬을 직접 띄우면(자체 QA) 빈손이다.
var inventory: RefCounted = null

## 이 캐릭터의 외형(`character_appearance.gd` 의 id 들 — 슬롯에 저장된 그대로).
## **빈 Dictionary 면 기본 외형**이다 — 슬롯을 안 거치고 월드 씬을 직접 띄워도
## (자체 QA 가 그렇게 한다) 캐릭터가 멀쩡히 떠야 하기 때문이다.
## 값을 넣으면 그 자리에서 시트를 다시 칠한다.
var appearance: Dictionary = {}:
	set(value):
		var next := Appearance.normalize(value)
		if next == appearance:
			return
		appearance = next
		_apply_appearance()

var _accumulated := 0.0

## 아직 틱에 넘기지 않은 좌클릭. 키를 받는 곳(`world.gd` 의 `_unhandled_input`)과
## 고정 틱을 도는 곳이 달라서, 한 번 받아 두었다가 **틱이 실제로 돈 뒤에** 지운다 —
## 프레임이 빨라 이번 프레임에 틱이 하나도 안 돌면 클릭이 그냥 사라진다.
var _use_pressed := false

## 아직 틱에 넘기지 않은 재장전(R) / 탄종 전환(우클릭). 좌클릭과 같은 이유로 받아
## 두었다가 틱이 실제로 돈 뒤에 지운다.
var _reload_pressed := false
var _switch_pressed := false

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	# 이름값 칸의 보정으로 시작한다 — 실제 값은 애니메이션이 정해지는 대로
	# `_update_animation()` 이 그 시트의 칸으로 다시 넣는다.
	_sprite.offset = PlayerFrames.feet_offset()
	_sprite.scale = Vector2.ONE * PlayerFrames.scale_of(PlayerFrames.CELL)
	if _sprite.sprite_frames == null:
		_apply_appearance()  # appearance 를 안 넣었으면 기본 외형으로 뜬다.
	set_process(false)  # setup() 전에는 월드가 없어서 이동 계산을 할 수 없다.


## 지금 외형으로 시트를 다시 칠해 갈아끼운다. 색은 팔레트 교체, 머리모양은 시트가
## 따로다 (`character_sprite.gd`). 노드가 아직 준비되기 전에 외형을 넣었으면
## `_ready()` 가 대신 부른다.
func _apply_appearance() -> void:
	if _sprite == null:
		return
	var frames := CharacterSprite.sprite_frames(appearance)
	if frames == null:
		frames = PlayerFrames.build()  # 칠하기에 실패해도 기준색으로는 서 있게 한다.
	_sprite.sprite_frames = frames
	_update_animation()


## 월드에 들어올 때 한 번 부른다.
func setup(world: RefCounted, spawn_tile: Vector2i) -> void:
	motion = PlayerMotion.new(world)
	motion.place_at_tile(spawn_tile)
	# **리스폰 지점은 월드를 처음 만들 때의 스폰 좌표다** (docs/DESIGN.md 「체력 /
	# 죽음 / 리스폰」). 값 하나라, 나중에 침대를 설치하면 그쪽이 이 한 줄과 같은
	# 함수를 그 침대 자리로 부르면 된다. **`place_at()`(텔레포트)로는 안 바뀐다** —
	# 옮겨졌다고 리스폰 지점까지 따라가면 침대의 의미가 없어진다.
	motion.set_respawn(motion.position)
	position = motion.position
	_update_animation()
	set_process(true)


## 위치를 강제로 옮긴다(스폰/텔레포트, 자체 QA). 플레이어 입력으로는 여기 못 들어온다.
func place_at(world_position: Vector2) -> void:
	if motion == null:
		return
	motion.place_at(world_position)
	position = motion.position


func tile() -> Vector2i:
	return WorldGen.world_to_tile(position)


## 총알이 나가는 자리(전역, **지면 평면**). 총알의 좌표계는 플레이어 노드와 같아서
## 원점이 발밑이다 — 그래야 "지금 어느 타일 위인가"가 바로 나온다. 그림에서 총구
## 높이로 올리는 것은 그리는 쪽(`bullets_view.gd`)이 한다.
##
## **노드의 `position` 이 아니라 코어의 것을 쓴다** — 노드는 틱 루프가 다 끝난 뒤에야
## 따라오므로, 틱 도중에 나가는 총알이 한 틱 뒤처진 자리에서 출발하게 된다.
func muzzle_position() -> Vector2:
	if motion == null:
		return global_position
	return motion.position + (global_position - position)


## 인벤토리 창 밖으로 버린 것이 놓일 자리(전역, 지면 평면). **발밑이 아니라 바라보는
## 방향 앞 한 칸**이고, 물 위는 피한다 — 계산은 전부 코어의 `drop_position()` 이 하고
## 여기서는 좌표계만 옮긴다(`muzzle_position()` 과 같은 모양이다).
func drop_position() -> Vector2:
	if motion == null:
		return global_position
	return motion.drop_position() + (global_position - position)


## 조준 각도를 재는 기준점(전역 좌표). **노드 원점은 발밑이라 발에서 재면 안 된다** —
## 마우스를 캐릭터 가슴 높이에 두는 것만으로 "위쪽 조준"으로 읽혀서 방향이 뒤집힌다.
## **몸 한가운데**에서 잰다 (`PlayerFrames.BODY_CENTER`).
##
## **2026-09-10 (INBOX #76): 여기 96.0 * 0.5 가 박혀 있었다.** 「캐릭터는 늘 화면
## 96px 이다」가 맞았던 것은 인물이 칸을 꽉 채우던 동안뿐이라, 인물이 72px 로
## 내려간 뒤에는 기준점이 몸 한가운데(36)가 아니라 목 언저리(48)였다.
func aim_origin() -> Vector2:
	return global_position - Vector2(0.0, PlayerFrames.BODY_CENTER)


## 마우스 좌표(전역) → 조준 각도. **노드가 하는 일은 여기까지다** —
## 이 각도로 무엇을 할지(어느 4방향 시트를 그릴지 등)는 코어가 정한다
## (docs/DESIGN.md 「조작」: 화면 좌표는 클라이언트마다 다르지만 각도는 같다).
func aim_angle_for(mouse_global: Vector2) -> float:
	var offset := mouse_global - aim_origin()
	if offset.is_zero_approx():
		return _aim_angle()  # 정확히 겹치면 각도가 없다 — 보던 쪽을 그대로 둔다.
	return offset.angle()


## 좌클릭을 받아 둔다 — 키를 정하는 곳은 `world.gd` 의 `_unhandled_input` 한 곳이고
## (docs/DESIGN.md 「인벤토리 / 장비」의 키 규칙), 여기는 그것을 **입력 한 벌에 실어
## 코어로 넘기는** 일만 한다. 창이 열려 있으면 그쪽이 애초에 부르지 않는다.
func request_use() -> void:
	if input_enabled:
		_use_pressed = true


## R(재장전) / 우클릭(탄종 전환)도 같은 길로 코어에 넘어간다 — 키를 정하는 곳은
## `world.gd` 한 곳이고, 여기는 입력 한 벌에 실어주는 일만 한다.
## **실제로 재장전/전환이 일어나는지는 총을 들었는지 아는 쪽이 정한다**(「서버 권위」).
func request_reload() -> void:
	if input_enabled:
		_reload_pressed = true


func request_ammo_switch() -> void:
	if input_enabled:
		_switch_pressed = true


## 지금 눌려 있는 이동 키와 마우스 조준, **든 칸과 좌클릭**을 한 벌로 모은다.
## **이게 서버로 보낼 입력이다** (docs/DESIGN.md 「서버 권위 / 클라이언트 신뢰」).
##
## **든 칸은 입력이 끊겨도 그대로 넘긴다** — 숫자키는 인벤토리 창이 열려 있어도 먹으므로
## (핫바는 그 창의 일부다), 창 안에서 칸을 바꾸면 뒤의 캐릭터도 같이 바뀌어야 한다.
func read_input() -> RefCounted:
	var slot: int = 0 if inventory == null else inventory.selected_hotbar
	if not input_enabled:
		_use_pressed = false
		_reload_pressed = false
		_switch_pressed = false
		return PlayerInput.new(Vector2i.ZERO, _aim_angle(), slot, false)
	return PlayerInput.new(
		Vector2i(
			int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left")),
			int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up")),
		),
		aim_angle_for(get_global_mouse_position()),
		slot,
		_use_pressed,
		_reload_pressed,
		_switch_pressed,
	)


## 지금 손에 든 것의 **시트 이름**. 빈손이거나, 아직 그 도구의 시트가 없으면 빈
## 문자열이다 — 그때는 예전대로 `idle`/`walk` 로 돈다(도구 7종 중 그림이 있는 것은
## `player_frames.gd` 의 `TOOLS` 뿐이고, 없는 것을 들어도 에러로 죽지 않는다).
## 아이템 id 와 시트 이름은 같은 문자열이다(`axe` — `gen_character.py` 의 `TOOLS`).
func held_tool() -> String:
	if inventory == null or motion == null:
		return ""
	var stack: RefCounted = inventory.at(Inventory.AREA_GENERAL, motion.held_slot)
	if stack == null:
		return ""
	return stack.id if PlayerFrames.TOOLS.has(stack.id) else ""


func _aim_angle() -> float:
	return PlayerInput.AIM_DOWN if motion == null else motion.aim_angle


## 프레임 시간을 고정 틱으로 쪼개서 코어를 돌린다 — 프레임 레이트가 달라도 같은
## 시간에 같은 거리를 간다 (docs/DESIGN.md 「시뮬레이션 구조」).
func _process(delta: float) -> void:
	var input := read_input()
	_accumulated += delta
	var ticks := 0
	while _accumulated >= PlayerMotion.TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
		_accumulated -= PlayerMotion.TICK_DELTA
		motion.tick(input)
		# **틱 안에서 알린다** — 한 프레임에 여러 틱이 돌면 그중 어느 틱에 쏘았는지가
		# 총알의 출발 자리를 정한다(코어의 위치는 틱마다 다르다).
		if motion.use_started:
			use_started.emit()
		if motion.reload_started:
			reload_requested.emit()
		if motion.switch_started:
			ammo_switch_requested.emit()
		# **틱 안에서 알린다** — `respawned` 는 그 틱 하나에만 참이라, 프레임이
		# 끝난 뒤에 보면 여러 틱이 돈 프레임에서 죽음을 통째로 놓친다.
		if motion.respawned:
			died.emit(motion.death_position)
		ticks += 1
	if ticks > 0:
		# 틱이 실제로 돈 뒤에야 지운다 — 프레임이 빠를 때 클릭이 틱을 못 만나고
		# 사라지는 것을 막는다. 여러 틱이 한꺼번에 돌아도 코어가 겹쳐 재생을 막는다.
		_use_pressed = false
		_reload_pressed = false
		_switch_pressed = false
	if _accumulated >= PlayerMotion.TICK_DELTA:
		_accumulated = 0.0
	position = motion.position
	_update_animation()


## 지금 상태에 맞는 애니메이션을 튼다.
##
## 우선순위는 **쓰는 중 → 걷는 중 → 서 있기**다(docs/DESIGN.md 「캐릭터 애니메이션」의
## "도끼를 고르면 hold_axe, 걸으면 walk_axe, 좌클릭하면 use_axe 가 한 번 재생된 뒤
## 다시 hold_axe"). 든 도구가 없으면 이름에 접미사가 안 붙어 예전 `idle`/`walk` 그대로다.
##
## **없는 애니메이션은 빈손 → 서 있기 순으로 물러난다** — 시트가 한 장 빠져도 캐릭터가
## 통째로 사라지지 않는다.
func _update_animation() -> void:
	if motion == null:
		return
	var dir: String = PlayerFrames.DIR_NAMES[motion.facing]
	var tool := held_tool()
	var suffix := "" if tool.is_empty() else "_%s" % tool
	var wanted := ""
	# **사용 모션이 없는 도구는 좌클릭해도 자세가 안 바뀐다**(낚싯대 — INBOX #31).
	# `PlayerFrames.has_use()` 를 안 보면 없는 `use_` 를 원하게 되고, 아래 물러나기가
	# **빈손 idle** 까지 내려가서 0.5초 동안 손에 든 낚싯대가 사라진다.
	if not tool.is_empty() and motion.is_using() and PlayerFrames.has_use(tool):
		wanted = "use%s_%s" % [suffix, dir]
	elif motion.is_moving:
		wanted = "walk%s_%s" % [suffix, dir]
	else:
		wanted = ("hold%s_%s" % [suffix, dir]) if not tool.is_empty() else "idle_%s" % dir
	# 물러나는 순서에 **`hold_<도구>`** 가 먼저 온다 — 시트가 한 장 빠졌을 때 손에
	# 든 것까지 같이 사라지는 것보다 자세만 굳는 쪽이 덜 어긋난다.
	for fallback: String in [wanted,
			("hold%s_%s" % [suffix, dir]) if not tool.is_empty() else "idle_%s" % dir,
			"walk_%s" % dir if motion.is_moving else "idle_%s" % dir, "idle_%s" % dir]:
		if _sprite.sprite_frames.has_animation(fallback):
			wanted = fallback
			break
	if _sprite.animation != wanted:
		_sprite.play(wanted)
	# **발밑 보정은 애니메이션마다 다시 넣는다** — 시트마다 칸 크기가 다를 수 있어서다
	# (2026-09-07, INBOX #46: idle 만 32px 이고 걷기·도구는 17px 이다). 한 번만 넣어
	# 두면 칸이 다른 모션으로 넘어가는 순간 캐릭터가 땅에 묻히거나 공중에 뜬다.
	# **배율도 애니메이션마다 다시 넣는다** (2026-09-08). 칸 크기가 48 이냐 96 이냐에
	# 따라 씬 배율이 2배/1배로 달라야 화면에서 늘 96px(= 타일 두 칸)이 된다.
	var cell := PlayerFrames.anim_cell(_sprite.sprite_frames, wanted)
	_sprite.offset = PlayerFrames.feet_offset(cell)
	_sprite.scale = Vector2.ONE * PlayerFrames.scale_of(cell)
