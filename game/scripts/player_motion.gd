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
const GunAmmo := preload("res://scripts/gun_ammo.gd")
const PlayerHealth := preload("res://scripts/player_health.gd")

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

## 버린 아이템이 놓이는 자리 — **발밑이 아니라 바라보는 방향 앞 타일 한 칸**이다
## (docs/DESIGN.md 「아이템 획득 방식 — 바닥 드롭」, 2026-09-07 INBOX #42).
## 줍히는 거리(`ground_items.gd` 의 36)보다 커서, 서 있는 자리와 놓인 자리가 확실히
## 갈린다.
const DROP_DISTANCE := 48.0

## 그 자리를 찾을 때 앞으로 나아가는 한 걸음. 타일(48)의 1/4 이라 **물 한 칸을 통째로
## 건너뛰지 않는다** — 총알의 한 걸음(`bullets.gd`)과 같은 이유로 속도/거리와 따로 둔다.
const DROP_STEP := 12.0

## 손에 든 도구를 한 번 쓰는 데 걸리는 틱 수. 60틱 = 1초이므로 30틱 = 0.5초다.
## **그림(`player_frames.gd` 의 `use_<도구>` 6프레임 × `USE_FPS` 12)과 같은 길이**여야
## 모션이 끝나는 순간과 다시 쓸 수 있게 되는 순간이 맞는다 — `qa_hotbar.gd` 가 둘이
## 어긋나지 않았는지 직접 견준다. **여기 있는 이유**는 이게 그림 사정이 아니라
## "얼마나 자주 휘두를 수 있는가"라는 게임 값이고, 나중에 서버가 좌클릭의 결과를
## 계산할 때 같은 값을 봐야 하기 때문이다 (docs/DESIGN.md 「서버 권위」).
const USE_TICKS := 30

## 정조준이 완전히 흐트러졌을 때의 탄퍼짐 반각(도). 사거리 절반(400)에서 좌우로
## 56 단위 = 타일 한 칸 남짓 벌어진다 — 멈춰 쏘면 거의 안 빗나가고 뛰면서 쏘면
## 어림잡아야 하는 정도다 (docs/DESIGN.md 「총기 스탯」의 탄퍼짐).
const MAX_SPREAD_DEGREES := 8.0

## 가만히 있을 때 정조준이 모이는 속도(초당). 1.0 이 완전히 모인 상태라 바닥에서
## 1.1초면 다 모인다 — "사격을 멈추면 빠르게 원래대로"(「총기 스탯」의 반동).
const FOCUS_GAIN := 0.9

## 움직일 때 흩어지는 속도(초당). 모이는 것보다 두 배 빠르다 — 뛰기 시작하면 0.55초
## 만에 완전히 풀린다.
const FOCUS_LOSS := 1.8

## 한 발 쏠 때 깎이는 정조준. 연사 간격(0.5초)에 다시 모이는 양(0.45)보다 커서,
## **계속 쏘면 조준이 점점 흐트러지고** 멈추면 곧 돌아온다 (「총기 스탯」의 반동 —
## 탑다운이라 "위로 튀는" 반동이 아니라 이 축에서 다룬다).
const RECOIL_KICK := 0.5

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

## **이 틱에 도구 쓰기가 시작됐는가.** 쓰는 내내 참인 `is_using()` 과 달리 시작한 틱
## 하나에만 참이다 — 총이면 이 틱에 한 발이 나간다. **무엇을 들었는지는 여기서 모른다**
## (칸 번호까지만 안다) — 그 칸에 총이 있는지는 인벤토리를 가진 쪽이 본다
## (docs/DESIGN.md 「서버 권위」).
var use_started := false

## 정조준(0~1). 1 이면 완전히 모인 상태다. **가만히 있으면 모이고 움직이면 흩어지며,
## 쏘면 반동으로 깎인다** (docs/DESIGN.md 「전투」의 조준선).
##
## **이 값 하나가 조준선의 선명도이자 탄퍼짐이다** — 조준선은 정조준의 표시가 아니라
## 정조준 그 자체를 그린 것이라, 퍼짐을 따로 계산하는 자리를 만들지 말 것.
## 화면 상태가 아니라 **플레이어 상태**다: 총알이 어디로 갈지를 정하므로 나중에
## 서버가 알아야 한다 (「서버 권위」).
var aim_focus := 1.0

## 지금 조준하고 있는 각도(라디안) — **스냅되지 않은 원본이다.**
## `facing` 은 4방향 시트를 고르려고 여기서 스냅한 값이고, 총알 방향과 시야 콘은
## 스냅된 `facing` 이 아니라 이 각도를 써야 한다 (docs/DESIGN.md 「조작」).
var aim_angle := PlayerInput.AIM_DOWN

## 총의 탄창(`gun_ammo.gd` — 탄종별 잔여 발수 + 재장전). **화면 상태가 아니라 플레이어
## 상태다** — 서버가 "이 발사가 유효한가"를 판정하려면 알아야 한다 (docs/DESIGN.md
## 「서버 권위」, INBOX #35). **총을 들고 있지 않아도 여기 있다**: 이 코어는 든 칸
## 번호까지만 알고 그 칸에 총이 있는지는 모르므로(아래 `held_slot`), 총을 잠깐
## 내려놨다고 탄창이 없어지면 도로 채워지는 꼴이 된다.
var gun: RefCounted = GunAmmo.new()

## **이 틱에 재장전(R)을 눌렀는가** — 눌린 내내가 아니라 눌린 순간 하나다.
## `use_started` 와 같은 자리이고, 실제로 재장전을 시작할지는 **총을 들었는지 아는
## 쪽**(인벤토리를 가진 `world.gd`)이 정한다 (docs/DESIGN.md 「서버 권위」).
var reload_started := false

## **이 틱에 우클릭(탄종 전환)을 눌렀는가.** 위와 같은 규칙이다.
var switch_started := false

## 체력(`player_health.gd` — 최대 100). 탄창과 같은 자리에 있는 이유도 같다:
## **화면 상태가 아니라 플레이어 상태**라 나중에 서버가 들고 판정한다
## (docs/DESIGN.md 「체력 / 죽음 / 리스폰」, 「서버 권위」).
var health: RefCounted = PlayerHealth.new()

## **리스폰 지점(월드 좌표) — 값 하나다.** 지금은 월드를 처음 만들 때의 스폰 좌표이고
## (`player.gd` 의 `setup()` 이 넣는다), 나중에 침대를 설치하면 **이 값 하나만** 그
## 침대 자리로 덮어쓰면 된다 (docs/DESIGN.md 「체력 / 죽음 / 리스폰」과 「건축 / 방
## 시스템」의 침대 — 침대는 건축과 같이 오므로 지금 범위가 아니다).
##
## 위치와 마찬가지로 **입력으로는 여기 못 들어온다** — 클라이언트가 "내 리스폰 지점은
## 여기다"라고 주장하면 어디로든 순간이동할 수 있다 (「서버 권위」).
var respawn_position := Vector2.ZERO

## **이 틱에 죽어서 리스폰했는가** — `use_started` 와 같은, 그 틱 하나에만 참인 표시다.
## 데스드롭 상자가 여기에 붙는다(`world.gd` — 인벤토리를 아는 쪽이다).
var respawned := false

## **죽은 자리(월드 좌표).** `respawned` 가 참인 틱에만 뜻이 있다 — 데스드롭 상자가
## 생겨야 하는 자리다 (docs/DESIGN.md 「데스드롭 상자」의 "죽으면 그 자리에").
##
## **되살아나기 전에 적어둔다** — `_respawn()` 이 `position` 을 리스폰 지점으로
## 덮어쓰고 나면 죽은 자리를 아무도 모르게 된다. **상자를 만드는 것은 여기가 아니다**:
## 이 코어는 인벤토리를 모르므로(「서버 권위」의 칸 번호까지만 안다), 상자를 채우는
## 것은 인벤토리를 아는 `world.gd` 다.
var death_position := Vector2.ZERO

var _world: RefCounted = null
## 지난 틱에 눌려 있었는가 — 누르고 있는 동안 매 틱 다시 시작되지 않게 하는 것뿐이다.
var _reload_held := false
var _switch_held := false


func _init(world: RefCounted) -> void:
	_world = world


## 고정 틱 하나를 진행한다. `input` 은 `player_input.gd` 한 벌(이동 두 축 + 조준
## 각도) — 이게 곧 네트워크로 오갈 입력이다.
func tick(input: RefCounted) -> void:
	# **죽었으면 이 틱은 되살아나는 틱이다** (docs/DESIGN.md 「체력 / 죽음 / 리스폰」).
	# 데미지를 주는 쪽(`take_damage()`)이 아니라 **틱 안에서** 되살리는 이유: 리스폰은
	# 위치를 옮기는 시뮬레이션 한 단계라 서버가 도는 틱 위에 있어야 한다 — 밖에서
	# 부르는 함수가 위치를 옮기면 그 틱의 이동 계산과 순서가 어긋난다.
	respawned = false
	if health.is_dead():
		# 죽은 자리를 먼저 적어둔다 — `_respawn()` 이 위치를 덮어쓴다.
		death_position = position
		_respawn()
		respawned = true
	# **바라보는 방향은 이동이 아니라 조준이 정한다** (docs/DESIGN.md 「조작」) —
	# 그래서 서 있을 때도 마우스를 돌리면 캐릭터가 같이 돈다.
	aim_angle = input.aim_angle
	facing = _facing_for_aim(aim_angle)
	held_slot = input.hotbar
	# **쓰는 중에 또 눌러도 겹쳐 재생되지 않는다** — 남은 틱이 0 이 되어야 다시 시작한다
	# (docs/DESIGN.md 「캐릭터 애니메이션」의 "한 번 재생된 뒤 다시 hold 로 돌아온다").
	# **대상이 있는지는 보지 않는다** — 허공에 대고도 나가야 나중에 근접무기가 성립한다
	# (docs/DESIGN.md 「생활 스킬 — 채집 계열」).
	use_started = false
	use_ticks_left = maxi(0, use_ticks_left - 1)
	if use_ticks_left == 0 and input.use:
		use_ticks_left = USE_TICKS
		use_started = true
	# **재장전 타이머는 손에 무엇을 들었든 여기서 돈다** — 총을 든 동안만 돌게 하면
	# 재장전 중에 도끼로 바꿨다가 돌아왔을 때 시간이 멈춰 있던 게 된다.
	gun.tick()
	# 눌린 순간 하나만 잡는다. 한 프레임에 여러 틱이 돌아도(`player.gd`) 같은 입력이
	# 여러 번 들어오므로, 이 가장자리 검출이 없으면 R 한 번에 재장전이 계속 되감긴다.
	reload_started = input.reload and not _reload_held
	_reload_held = input.reload
	switch_started = input.switch_ammo and not _switch_held
	_switch_held = input.switch_ammo
	var dir := Vector2(signf(float(input.move.x)), signf(float(input.move.y)))
	is_moving = dir != Vector2.ZERO
	# 정조준은 **서 있는가 움직이는가**로만 정해진다 — 조준선이 스스로 흐려지고
	# 선명해지는 것이 이 두 줄이다 (docs/DESIGN.md 「전투」의 조준선).
	var focus_rate := -FOCUS_LOSS if is_moving else FOCUS_GAIN
	aim_focus = clampf(aim_focus + focus_rate * TICK_DELTA, 0.0, 1.0)
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


## 지금 보고 있는 4방향의 단위 벡터 — **그림이 보는 쪽**이다(`aim_direction()` 과 달리
## 45도 단위로 스냅된 값이라, 화면의 캐릭터가 향한 쪽과 어긋날 수가 없다).
func facing_direction() -> Vector2:
	return Vector2.from_angle(DIR_ANGLE[facing])


## 버린 아이템이 놓일 자리 (docs/DESIGN.md 「아이템 획득 방식 — 바닥 드롭」).
##
## 바라보는 방향으로 한 칸 앞이되, **물 위에는 놓지 않는다** — 걸어 들어갈 수 없는
## 자리에 놓이면 영영 못 줍고, 그건 「인벤토리 안전」의 *"아이템이 조용히 사라지면
## 안 된다"* 와 같은 말이 된다. 앞으로 한 걸음씩 나아가며 **걸어 들어갈 수 있는
## 마지막 자리**를 고르므로, 물가에서 물을 보고 버리면 발밑에 놓인다(그 경우만
## 예전과 같다).
##
## **나무·바위 칸도 물과 같이 피한다** (2026-09-08, INBOX #65 — 그전에는 `is_land()`
## 만 봤다). 나무에 둘러싸인 칸에 떨어지면 다가갈 수가 없어서, 물 위와 **똑같이**
## 영영 못 줍는 아이템이 된다 — 규칙이 늘어난 게 아니라 「걸어 들어갈 수 없는 곳」의
## 목록이 늘어난 것이다.
##
## **걸을 수 있는지는 몸통 상자가 아니라 떨어진 칸으로 판정한다** — 놓이는 것은
## 걸어다니는 몸이 아니라 점 하나다(「낚시」의 *"물 위인가는 찌가 떨어진 칸으로
## 판정한다"* 와 같은 자리다).
##
## **코어에 있는 이유**: 나중에 서버가 "이 버리기가 유효한가"를 판정하려면 같은
## 계산을 화면 없이 해야 한다 (docs/DESIGN.md 「서버 권위」).
func drop_position() -> Vector2:
	var direction := facing_direction()
	var at := position
	var travelled := DROP_STEP
	while travelled <= DROP_DISTANCE + SKIN:
		var next := position + direction * travelled
		var t := WorldGen.world_to_tile(next)
		if not _world.is_walkable(t.x, t.y):
			break
		at = next
		travelled += DROP_STEP
	return at


## 지금 탄퍼짐 반각(라디안) — 쏜 총알이 조준 각도에서 좌우로 벌어질 수 있는 최대치다.
##
## **조준선의 선명도와 같은 값이다**(docs/DESIGN.md 「전투」의 "그 선명도가 곧 정조준이고
## 탄퍼짐과 같은 값이다 — 따로 계산하지 말 것"). 그래서 그리는 쪽(`aim_line.gd`)과
## 쏘는 쪽(`bullets.gd` 의 `fire`)이 **둘 다 이 함수 하나를 부른다** — 화면에 보이는
## 흐릿함과 실제로 빗나가는 정도가 어긋날 자리가 없다.
func spread_angle() -> float:
	return deg_to_rad(MAX_SPREAD_DEGREES) * (1.0 - aim_focus)


## 한 발 쏜 반동으로 정조준이 풀린다.
##
## **틱 안에서 저절로 일어나지 않는다** — 부르는 쪽이 "이번 좌클릭이 실제로 총을 쏜
## 것"임을 확인한 뒤에 부른다. 이 코어는 든 칸 번호까지만 알고 그 칸에 총이 있는지는
## 모르기 때문이다(docs/DESIGN.md 「서버 권위」) — 도끼를 휘두른 것으로 조준이
## 흐트러지면 안 된다.
func apply_recoil() -> void:
	aim_focus = clampf(aim_focus - RECOIL_KICK, 0.0, 1.0)


## 데미지를 받는다 — **실제로 깎인 양**을 돌려준다. 체력이 0 이 되면 **다음 틱에**
## 리스폰 지점에서 되살아난다(위 `tick()`).
##
## **지금 이 함수를 부르는 것은 자체 QA 뿐이다** — 동물이 없고 이 서버는 PvE 라
## 사람도 서로 안 맞는다(docs/DESIGN.md 「전투」). 실제로 죽는 일은 동물이 생긴
## 뒤부터이고, 그때 이 함수를 부르는 것은 **서버**다(「서버 권위」의 "명중 판정 /
## 자원 획득은 전부 서버가 계산한다") — `bullets.gd` 의 `hit_test` 자리가 그 입구다.
func take_damage(amount: int) -> int:
	return health.take_damage(amount)


## 리스폰 지점을 정한다. **부르는 곳은 월드에 들어올 때 한 곳뿐**이고(스폰 좌표),
## 나중에 침대를 설치하면 같은 함수를 그 침대 자리로 부르면 그만이다 — 리스폰 지점을
## 값 하나로 둔 이유가 이것이다 (docs/DESIGN.md 「체력 / 죽음 / 리스폰」).
func set_respawn(world_position: Vector2) -> void:
	respawn_position = world_position


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

## 리스폰 지점에서 되살아난다 — 체력을 가득 채우고 그 자리로 옮긴다.
##
## **인벤토리는 건드리지 않는다** — 죽을 때 아이템이 어떻게 되는지(「데스드롭 상자」)는
## 인벤토리를 아는 쪽(`world.gd`)이 `respawned` 와 `death_position` 을 보고 정한다.
## 애초에 이 코어는 인벤토리를 모른다.
func _respawn() -> void:
	position = respawn_position
	health.refill()
	# 휘두르던 도중에 죽었으면 그 모션은 여기서 끊는다 — 안 그러면 스폰 지점에
	# 나타나자마자 죽기 전의 도끼질을 마저 한다.
	use_ticks_left = 0


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


## 몸통 상자가 **걸을 수 없는 칸**에 걸치는가. 바다(지도 밖도 바다다 — `world_gen.gd`
## 의 `at()`)와, **걷기를 막는 월드 오브젝트가 선 칸**(나무·바위 — `world_objects.gd` 의
## `BLOCKS_WALK`)이 그것이다. 둘을 한 물음으로 묶는 것이 `world_gen.gd` 의
## `is_walkable()` 이다.
##
## **이건 「걸을 수 있는가」만 답하는 자리다** — 총알은 이 판정을 쓰지 않는다(물을
## 통과한다, docs/DESIGN.md 「전투」). 총알을 막는 것은 `bullets.gd` 의 `blocks_bullet`
## 에 따로 꽂힌다.
func blocked_at(p: Vector2) -> bool:
	var box := body_at(p)
	var from := WorldGen.world_to_tile(box.position)
	var to := WorldGen.world_to_tile(box.end - Vector2(SKIN, SKIN))
	for ty in range(from.y, to.y + 1):
		for tx in range(from.x, to.x + 1):
			if not _world.is_walkable(tx, ty):
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
