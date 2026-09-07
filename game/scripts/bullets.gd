extends RefCounted

## 날아가는 총알 (docs/DESIGN.md 「전투」).
##
## **총알은 투사체다 — 즉시판정(히트스캔)이 아니다.** 쏜 순간 "이 각도의 선분 위에
## 누가 있나"를 한 번 계산하고 끝내지 않고, 총알을 개체로 두고 **살아 있는 내내 매 틱**
## 움직이며 충돌을 본다. 그래서 총알을 **피할 수 있다** — 이 차이가 이 클래스가 있는
## 이유 전부다.
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) — 나중에
## 서버가 화면 없이 같은 코드로 명중을 판정한다 (「서버 권위」의 "명중 판정은 서버가
## 계산한다"가 가리키는 대상이 바로 이쪽이다). 그리는 일은 `bullets_view.gd` 가 한다.
##
## **저장하지 않는다.** 날아가는 중인 총알은 0.9초면 사라지는 것이라, 월드를 나갔다
## 들어왔을 때 되살릴 값이 아니다(바닥 아이템과 다른 점이다).

const WorldGen := preload("res://scripts/world_gen.gd")

## 초당 틱 수. `player_motion.gd` 와 같은 값이어야 한다 — 총알과 사람이 서로 다른
## 시간 위에서 돌면 "피할 수 있다"가 성립하지 않는다.
const TICK_RATE := 60
const TICK_DELTA := 1.0 / float(TICK_RATE)

## 총알 속도(월드 단위/초). 플레이어(240)의 3.75배라 **눈으로 쫓을 수 있고 피할 수도
## 있다** — 사거리 800 을 다 날아가는 데 0.89초가 걸리고, 그동안 사람은 두 타일 넘게
## 움직인다. 더 빠르게 하면 사실상 즉시판정이 되어 위 「전투」의 결정이 무의미해진다.
const SPEED := 900.0

## 사거리(월드 단위) — docs/DESIGN.md 「총기 스탯」. 다 날아가면 사라진다.
const RANGE := 800.0

## 충돌을 보며 나아가는 한 걸음의 상한. **타일(48)보다 훨씬 작아야 한다** — 크면 벽
## 한 칸을 통째로 건너뛴다 (`player_motion.gd` 가 같은 함정을 이미 겪었다,
## docs/GOTCHAS.md). 타일의 1/4 이라 한 틱(15)이 두 걸음으로 쪼개진다. **속도를 올려도
## 이 값이 그대로면 벽을 못 뚫는다** — 그러라고 속도와 따로 둔 값이다.
const MAX_STEP := 12.0

## 항목 하나의 키. `position` 은 **지면 평면의 월드 좌표**(플레이어 노드의 원점이
## 발밑인 것과 같다 — 그래야 어느 타일 위에 있는지가 바로 나온다), `direction` 은
## 단위 벡터, `travelled` 는 지금까지 날아온 거리다.
const KEY_POSITION := "position"
const KEY_DIRECTION := "direction"
const KEY_TRAVELLED := "travelled"

## 날아가는 중인 총알들.
var bullets: Array[Dictionary] = []

## **대상 명중 판정이 들어올 자리다.** 지금은 비어 있다 — 동물이 아직 없고 이 서버는
## PvE 라 사람도 안 맞는다 (docs/DESIGN.md 「전투」의 2026-09-07 결정). 그래서 이번
## 단계의 명중은 **지형에 막히는 것과 사거리 소진**뿐이다.
##
## 동물을 만드는 바퀴가 여기에 `func(from: Vector2, to: Vector2) -> Variant` 를 꽂으면
## 된다 — 그 선분에 맞은 대상을 돌려주는 순간 총알이 사라진다. 데미지(「총기 스탯」의
## 25)는 그 함수를 꽂은 쪽이 매긴다. **한 걸음(`MAX_STEP`)짜리 선분으로 부르는** 이유는
## 위와 같다: 한 틱 이동량을 통째로 넘기면 빠른 총알이 얇은 대상을 지나쳐버린다.
var hit_test := Callable()

var _world: RefCounted = null

## 탄퍼짐을 굴리는 난수. **씨앗을 정할 수 있다** — 자체 QA 가 같은 결과를 재현해야
## 하고, 나중에 서버가 판정할 때도 굴림이 서버 것이어야 하기 때문이다.
var _rng := RandomNumberGenerator.new()


func _init(world: RefCounted) -> void:
	_world = world


## 한 발 쏜다. `origin` 은 지면 평면의 월드 좌표, `angle` 은 **스냅되지 않은 조준
## 각도**(docs/DESIGN.md 「조작」 — 4방향 시트를 고르는 `facing` 이 아니다),
## `spread` 는 탄퍼짐 반각이다(`player_motion.gd` 의 `spread_angle()` — 조준선의
## 선명도와 **같은 값**이라 여기서 따로 계산하지 않는다).
func fire(origin: Vector2, angle: float, spread: float = 0.0) -> Dictionary:
	var aimed := angle
	if spread > 0.0:
		aimed += _rng.randf_range(-spread, spread)
	var entry := {
		KEY_POSITION: origin,
		KEY_DIRECTION: Vector2.from_angle(aimed),
		KEY_TRAVELLED: 0.0,
	}
	bullets.append(entry)
	return entry


func size() -> int:
	return bullets.size()


func set_random_seed(value: int) -> void:
	_rng.seed = value


## 고정 틱 하나를 진행한다 — **프레임 시간을 인자로 받지 않는다.** 호출 횟수가 곧
## 시뮬레이션 시간이라, 서버는 "실제 경과 시간이 허용하는 횟수"만 돌려주면 된다
## (`player_motion.gd` 의 `tick()` 과 같은 규칙이다). 사라진 총알 수를 돌려준다.
func tick() -> int:
	var gone := 0
	var index := 0
	while index < bullets.size():
		if _advance(bullets[index]):
			bullets.remove_at(index)
			gone += 1
			continue
		index += 1
	return gone


## 총알 하나를 한 틱만큼 나아가게 한다. 사라져야 하면 true.
##
## 한 틱 이동량(15)을 `MAX_STEP`(12) 이하의 걸음으로 쪼개서 걷는다 — 한 번에 옮기고
## 도착지만 보면 그 사이의 벽을 통째로 건너뛴다.
func _advance(bullet: Dictionary) -> bool:
	var direction: Vector2 = bullet[KEY_DIRECTION]
	var left := SPEED * TICK_DELTA
	while left > 0.0:
		var travelled: float = bullet[KEY_TRAVELLED]
		var step := minf(left, MAX_STEP)
		# 사거리를 넘겨서까지 날아가지 않는다 — 남은 사거리만큼만 가고 거기서 사라진다.
		if travelled + step >= RANGE:
			bullet[KEY_POSITION] = (bullet[KEY_POSITION] as Vector2) \
					+ direction * (RANGE - travelled)
			bullet[KEY_TRAVELLED] = RANGE
			return true
		var from: Vector2 = bullet[KEY_POSITION]
		var to := from + direction * step
		bullet[KEY_POSITION] = to
		bullet[KEY_TRAVELLED] = travelled + step
		if hit_test.is_valid() and hit_test.call(from, to) != null:
			return true
		if blocked_at(to):
			return true
		left -= step
	return false


## 그 자리가 총알을 막는가. **막힌 지형은 플레이어 이동과 같은 판정을 쓴다** —
## 지금은 바다뿐이고, 나무·벽은 그것들을 만드는 바퀴가 `world_gen` 의 같은 자리에
## 덧붙인다 (docs/DESIGN.md 「플레이어 이동」). 총알은 점이라 몸통 상자가 없다.
func blocked_at(point: Vector2) -> bool:
	if _world == null:
		return false
	var tile := WorldGen.world_to_tile(point)
	return not _world.is_land(tile.x, tile.y)
