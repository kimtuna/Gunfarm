extends RefCounted

## 플레이어 이동 코어. **노드를 상속하지 않는 순수 클래스**다
## (docs/DESIGN.md 「시뮬레이션 구조」) — 씬 트리 없이 단독으로 돌아야 서버가 화면
## 없이 같은 계산을 할 수 있다.
##
## **이 클래스는 위치를 받지 않는다. 입력(이동 방향 / 조준 각도)만 받는다**
## (docs/DESIGN.md 「서버 권위 / 클라이언트 신뢰」). 나중에 서버가 붙으면 클라이언트는
## `tick()` 에 넣는 `PlayerInput` 만 보내고, 서버가 같은 코드로 `position` 을 계산한다 —
## "나 여기 있다"를 받는 순간 이동속도 핵을 구조적으로 막을 방법이 없어지기 때문이다.
##
## 한 번의 `tick()` = 고정 틱 하나(`TICK_DELTA` 초)다. 프레임 시간을 인자로 받지
## 않는 것도 같은 이유다 — 호출 횟수가 곧 시뮬레이션 시간이라, 서버는 "실제 경과
## 시간이 허용하는 횟수"만 돌려주면 그게 그대로 속도 상한이 된다.

const WorldGen := preload("res://scripts/world_gen.gd")
const PlayerInput := preload("res://scripts/player_input.gd")

## 스프라이트 시트의 행 순서와 같다 (scripts/player_frames.gd 의 `DIR_NAMES`).
enum { DOWN = 0, LEFT = 1, RIGHT = 2, UP = 3 }

## 초당 틱 수. 프레임 레이트와 무관하게 이 간격으로만 시뮬레이션한다.
const TICK_RATE := 60
const TICK_DELTA := 1.0 / float(TICK_RATE)

## 이동 속도(월드 단위/초). 타일 한 칸이 48이므로 초당 5칸이다.
const SPEED := 240.0

## 충돌에 쓰는 몸통 상자의 반크기. 원점은 **발밑**이라 발 주변의 납작한 상자다
## (그림 전체가 아니라 실제로 땅을 밟는 부분만 막혀야 머리가 물 위로 넘어가는
## 일 없이 해안에 자연스럽게 붙는다). 18×10 으로 타일(48) 안에 넉넉히 들어간다.
## **2026-09-07 (INBOX #19) 에 캐릭터 캔버스가 절반이 되면서 같이 줄었다**(32×18 →
## 18×10). 어깨 폭이 아트 7px × 3배 = 21 이라, 상자는 그보다 조금 좁아야 해안에
## 비스듬히 붙었을 때 어깨가 걸리지 않는다(옛 값도 36 짜리 어깨에 32 였다).
const BODY_HALF := Vector2(9.0, 5.0)

## 물가에 붙일 때 남기는 아주 얇은 틈. 0 이면 상자의 끝이 다음 칸에 걸쳐 있다고
## 판정돼서 그 자리에서 다시 막힌다.
const SKIN := 0.01

## 한 틱에 움직이는 거리. 타일(48)보다 훨씬 작아야 바다 한 칸을 통째로 건너뛰지 않는다.
const MAX_STEP := SPEED * TICK_DELTA

## 방향마다 그 시트가 대표하는 각도(라디안). 배열 순서는 위 enum 과 같다.
const DIR_ANGLE := [PI * 0.5, PI, 0.0, -PI * 0.5]

## 한 방향이 맡는 부채꼴의 반각. 네 방향이라 45도다.
const FACING_HALF_SECTOR := PI * 0.25

## 스냅 경계에서 붙잡고 있는 여유각(10도). 45도 경계에 마우스를 올려두면 손이
## 조금만 떨려도 두 시트가 매 프레임 번갈아 나와 캐릭터가 덜덜 떤다 — 지금 방향은
## 45+10도까지 유지하고, 그걸 넘겨야 다음 방향으로 넘어간다.
const FACING_HYSTERESIS := PI / 18.0

## 손에 든 도구를 한 번 쓰는 데 걸리는 틱 수. 60틱 = 1초이므로 30틱 = 0.5초다.
## **그림(`player_frames.gd` 의 `use_<도구>` 6프레임 × `USE_FPS` 12)과 같은 길이**여야
## 모션이 끝나는 순간과 다시 쓸 수 있게 되는 순간이 맞는다 — `qa_hotbar.gd` 가 둘이
## 어긋나지 않았는지 직접 견준다. **여기 있는 이유**는 이게 그림 사정이 아니라
## "얼마나 자주 휘두를 수 있는가"라는 게임 값이고, 나중에 서버가 좌클릭의 결과를
## 계산할 때 같은 값을 봐야 하기 때문이다 (docs/DESIGN.md 「서버 권위」).
const USE_TICKS := 30

var position := Vector2.ZERO
var facing := DOWN
var is_moving := false

## 지금 손에 든 핫바 칸. **입력이 정한다**(`player_input.gd` 의 `hotbar`) —
## 화면 상태가 아니라 플레이어 상태다 (docs/DESIGN.md 「캐릭터 애니메이션」의
## "무엇을 들고 있는가는 플레이어 상태다"). 그 칸에 무엇이 들어 있는지는
## 인벤토리를 가진 쪽이 본다 — 이 코어는 칸 번호까지만 안다.
var held_slot := 0

## 도구를 쓰는 중이면 남은 틱 수. 0 이면 안 쓰는 중이다.
var use_ticks_left := 0

## 지금 조준하고 있는 각도(라디안) — **스냅되지 않은 원본이다.**
## `facing` 은 4방향 시트를 고르려고 여기서 스냅한 값이고, 총알 방향과 시야 콘은
## 스냅된 `facing` 이 아니라 이 각도를 써야 한다 (docs/DESIGN.md 「조작」).
var aim_angle := PlayerInput.AIM_DOWN

var _world: RefCounted = null


func _init(world: RefCounted) -> void:
	_world = world


## 고정 틱 하나를 진행한다. `input` 은 `player_input.gd` 한 벌(이동 두 축 + 조준
## 각도) — 이게 곧 네트워크로 오갈 입력이다.
func tick(input: RefCounted) -> void:
	# **바라보는 방향은 이동이 아니라 조준이 정한다** (docs/DESIGN.md 「조작」) —
	# 그래서 서 있을 때도 마우스를 돌리면 캐릭터가 같이 돈다.
	aim_angle = input.aim_angle
	facing = _facing_for_aim(aim_angle)
	held_slot = input.hotbar
	# **쓰는 중에 또 눌러도 겹쳐 재생되지 않는다** — 남은 틱이 0 이 되어야 다시 시작한다
	# (docs/DESIGN.md 「캐릭터 애니메이션」의 "한 번 재생된 뒤 다시 hold 로 돌아온다").
	# **대상이 있는지는 보지 않는다** — 허공에 대고도 나가야 나중에 근접무기가 성립한다
	# (docs/DESIGN.md 「생활 스킬 — 채집 계열」).
	use_ticks_left = maxi(0, use_ticks_left - 1)
	if use_ticks_left == 0 and input.use:
		use_ticks_left = USE_TICKS
	var dir := Vector2(signf(float(input.move.x)), signf(float(input.move.y)))
	is_moving = dir != Vector2.ZERO
	if not is_moving:
		return
	# 대각선도 정규화해서 넘긴다 — 안 하면 대각으로 갈 때만 1.41배 빨라진다.
	var step := dir.normalized() * MAX_STEP
	# 축을 따로 밀어야 벽에 비스듬히 붙었을 때 멈추지 않고 미끄러진다.
	_move_axis(Vector2(step.x, 0.0))
	_move_axis(Vector2(0.0, step.y))


## 지금 손에 든 도구를 쓰는 중인가. 그리는 쪽은 이게 참인 동안 `use_<도구>` 를
## 틀고, 거짓이 되면 `hold_<도구>` 로 돌아온다.
func is_using() -> bool:
	return use_ticks_left > 0


## 조준 방향의 단위 벡터. 총알/시야 콘처럼 **정확한 방향이 필요한 쪽은 여기를**
## 쓴다 (`facing` 은 그림을 고르느라 45도 단위로 뭉갠 값이다).
func aim_direction() -> Vector2:
	return Vector2.from_angle(aim_angle)


## 지금 서 있는 타일.
func tile() -> Vector2i:
	return WorldGen.world_to_tile(position)


## 서버(또는 자체 QA)가 위치를 직접 정하는 유일한 통로 — 스폰/텔레포트용이다.
## 클라이언트 입력으로는 절대 여기로 들어오지 않는다.
func place_at(world_position: Vector2) -> void:
	position = world_position


func place_at_tile(t: Vector2i) -> void:
	position = WorldGen.tile_center(t)


# --- 내부 -------------------------------------------------------------------

## 조준 각도를 4방향 시트 중 하나로 스냅한다. 지금 방향을 계속 쓸 수 있으면
## 그대로 두고(히스테리시스), 여유각까지 넘어갔을 때만 가장 가까운 방향으로 바꾼다.
func _facing_for_aim(angle: float) -> int:
	if absf(angle_difference(DIR_ANGLE[facing], angle)) <= FACING_HALF_SECTOR + FACING_HYSTERESIS:
		return facing
	var best := facing
	var best_gap := INF
	for d in DIR_ANGLE.size():
		var gap := absf(angle_difference(DIR_ANGLE[d], angle))
		if gap < best_gap:
			best_gap = gap
			best = d
	return best


func body_at(p: Vector2) -> Rect2:
	return Rect2(p - BODY_HALF, BODY_HALF * 2.0)


## 몸통 상자가 바다 칸에 걸치는가. 지도 밖도 바다다(`world_gen.gd` 의 `at()`).
func blocked_at(p: Vector2) -> bool:
	var box := body_at(p)
	var from := WorldGen.world_to_tile(box.position)
	var to := WorldGen.world_to_tile(box.end - Vector2(SKIN, SKIN))
	for ty in range(from.y, to.y + 1):
		for tx in range(from.x, to.x + 1):
			if not _world.is_land(tx, ty):
				return true
	return false


func _move_axis(step: Vector2) -> void:
	if step.is_zero_approx():
		return
	var want := position + step
	if not blocked_at(want):
		position = want
		return
	# 바다에 막혔다 — 한 틱 앞에서 그냥 멈추면 해안에 최대 4단위 틈이 남는다.
	# 막은 칸의 경계에 몸통을 딱 붙인다. (축 하나만 움직였으므로 새로 걸친 칸은
	# 진행 방향 맨 앞 줄뿐이고, 그 줄의 경계가 곧 물가다.)
	var size := float(WorldGen.TILE_SIZE)
	if step.x > 0.0:
		position.x = floorf((want.x + BODY_HALF.x) / size) * size - BODY_HALF.x - SKIN
	elif step.x < 0.0:
		position.x = (floorf((want.x - BODY_HALF.x) / size) + 1.0) * size + BODY_HALF.x
	elif step.y > 0.0:
		position.y = floorf((want.y + BODY_HALF.y) / size) * size - BODY_HALF.y - SKIN
	else:
		position.y = (floorf((want.y - BODY_HALF.y) / size) + 1.0) * size + BODY_HALF.y
