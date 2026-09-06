extends Node2D

## 월드 안의 플레이어.
##
## **이 노드가 하는 일은 입력을 모으는 것과 그리는 것뿐이다.** 실제 이동 계산은
## `scripts/player_motion.gd`(노드를 상속하지 않는 순수 클래스)가 한다 —
## docs/DESIGN.md 「서버 권위 / 클라이언트 신뢰」대로, 나중에 서버가 붙으면 서버가
## 같은 코드로 위치를 계산하고 이 노드는 그 결과를 그리기만 하게 된다. 그래서
## 여기서 `position` 을 직접 계산하는 코드를 넣으면 안 된다.

const PlayerMotion := preload("res://scripts/player_motion.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")
const WorldGen := preload("res://scripts/world_gen.gd")

## 한 프레임에 몰아서 돌릴 수 있는 최대 틱 수. 창을 끌거나 잠깐 멈췄다 돌아왔을 때
## 밀린 시간을 한꺼번에 시뮬레이션하면 순간이동처럼 보인다 — 그냥 버린다.
const MAX_TICKS_PER_FRAME := 5

## 이동 계산 코어. 밖에서 위치를 볼 일이 있으면 이걸 통해서 본다.
var motion: RefCounted = null

## 이 노드가 로컬 플레이어의 입력을 받는가. 나중에 다른 플레이어를 그릴 때는 꺼진다.
var input_enabled := true

var _accumulated := 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	_sprite.sprite_frames = PlayerFrames.build()
	_sprite.offset = PlayerFrames.feet_offset()
	_sprite.scale = Vector2.ONE * PlayerFrames.SCALE
	set_process(false)  # setup() 전에는 월드가 없어서 이동 계산을 할 수 없다.


## 월드에 들어올 때 한 번 부른다.
func setup(world: RefCounted, spawn_tile: Vector2i) -> void:
	motion = PlayerMotion.new(world)
	motion.place_at_tile(spawn_tile)
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


## 지금 눌려 있는 이동 키를 -1/0/1 두 축으로 모은다. **이게 서버로 보낼 입력이다.**
func read_input() -> Vector2i:
	if not input_enabled:
		return Vector2i.ZERO
	return Vector2i(
		int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left")),
		int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up")),
	)


## 프레임 시간을 고정 틱으로 쪼개서 코어를 돌린다 — 프레임 레이트가 달라도 같은
## 시간에 같은 거리를 간다 (docs/DESIGN.md 「시뮬레이션 구조」).
func _process(delta: float) -> void:
	var move := read_input()
	_accumulated += delta
	var ticks := 0
	while _accumulated >= PlayerMotion.TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
		_accumulated -= PlayerMotion.TICK_DELTA
		motion.tick(move)
		ticks += 1
	if _accumulated >= PlayerMotion.TICK_DELTA:
		_accumulated = 0.0
	position = motion.position
	_update_animation()


func _update_animation() -> void:
	if motion == null:
		return
	var dir: String = PlayerFrames.DIR_NAMES[motion.facing]
	# 걷기 시트(INBOX #13)가 생기면 자동으로 그쪽을 쓴다. 아직 없으면 idle 로 둔다.
	var wanted := "walk_%s" % dir if motion.is_moving else "idle_%s" % dir
	if not _sprite.sprite_frames.has_animation(wanted):
		wanted = "idle_%s" % dir
	if _sprite.animation != wanted:
		_sprite.play(wanted)
