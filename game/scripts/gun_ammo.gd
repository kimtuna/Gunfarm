extends RefCounted

## 총의 탄창 — 탄종별 잔여 발수와 재장전 (docs/DESIGN.md 「총기 스탯」의 탄창 항목).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) — 나중에
## 서버가 화면 없이 같은 코드로 "이 발사가 유효한가"를 판정한다. **남은 발수와 든
## 탄종은 화면 상태가 아니라 플레이어 상태다**(「서버 권위」) — 그래서 이 클래스는
## `player_motion.gd`(플레이어 코어)가 들고 있고, HUD 는 그것을 읽어 그리기만 한다.
##
## **탄종마다 탄창이 따로다.** 우클릭으로 탄종을 바꾸는 것은 "다른 탄창으로 갈아
## 끼우는 것"이라, 기본탄을 다 쓰고 마취탄으로 바꿔도 마취탄 탄창은 가득이어야 한다
## (「총기 스탯」 — 하나의 탄약 수를 공유하면 안 된다).
##
## **예비 탄약은 없다.** R 을 누르면 언제나 가득 찬다 — 탄약을 아이템으로 소비하는
## 것은 「새 테크 라인」이 범위 밖이라고 못 박아뒀다(화약 → 탄약 아이템은 이미
## `item_types.gd` 에 있지만 총과 연동하지 않는다).
##
## **저장하지 않는다.** 나갔다 들어오면 탄창이 가득인 채로 시작한다 — 예비 탄약이
## 없어 R 한 번이면 되돌아가는 값이라, 저장 포맷을 늘려서 지킬 이유가 없다
## (날아가는 총알을 저장하지 않는 것과 같은 판단이다, 「전투」).

## 탄종. **`item_types.gd` 의 아이템 id 와 같은 문자열이다** — 이름과 색을 그 표에서
## 그대로 읽어 쓰고(HUD), 나중에 탄약 아이템을 실제로 소비하게 될 때 이어붙일 자리가
## 이미 맞아 있다.
const BASIC := "ammo_basic"
const TRANQ := "ammo_tranq"

## 우클릭이 도는 순서 (docs/DESIGN.md 「조작」의 "장전된 탄종 전환 (기본탄 ↔ 마취탄)").
const KINDS: Array[String] = [BASIC, TRANQ]

## 탄창 한 개 = 8발 (docs/DESIGN.md 「총기 스탯」).
const MAG_SIZE := 8

## 재장전에 걸리는 틱 수. 60틱 = 1초이므로 **90틱 = 1.5초**다.
##
## 「총기 스탯」이 "약간의 시간 소요"라고만 정해둔 값이라 여기서 골랐다: 연사 간격
## (0.5초, `player_motion.gd` 의 `USE_TICKS`)의 세 배다. 그보다 짧으면 탄창이 있으나
## 마나가 되고(쏘는 리듬이 안 끊긴다), 훨씬 길면 8발을 4초에 비우고 재장전을 더 오래
## 기다리게 되어 사냥이 기다림이 된다.
const RELOAD_TICKS := 90

## 지금 장전된 탄종.
var kind := BASIC

## 탄종 → 그 탄창에 남은 발수. **탄종마다 따로다**(위 참고).
var rounds := {}

## 재장전이 끝나기까지 남은 틱. 0 이면 재장전 중이 아니다.
var reload_ticks_left := 0


func _init() -> void:
	refill_all()


## 모든 탄창을 가득 채우고 재장전을 멈춘다 — 처음 만들 때와 새 월드에 들어올 때다.
func refill_all() -> void:
	rounds = {}
	for k: String in KINDS:
		rounds[k] = MAG_SIZE
	reload_ticks_left = 0


## 고정 틱 하나. **프레임 시간을 받지 않는다** — 호출 횟수가 곧 시뮬레이션 시간이다
## (`player_motion.gd` 의 `tick()` 과 같은 규칙이고, 실제로 거기서 불린다).
func tick() -> void:
	if reload_ticks_left > 0:
		reload_ticks_left -= 1
		if reload_ticks_left == 0:
			rounds[kind] = MAG_SIZE


func loaded() -> int:
	return int(rounds.get(kind, 0))


func loaded_of(ammo_kind: String) -> int:
	return int(rounds.get(ammo_kind, 0))


func is_reloading() -> bool:
	return reload_ticks_left > 0


## 재장전이 얼마나 진행됐는가(0~1). 재장전 중이 아니면 0 이다 — HUD 가 탄창이 한 발씩
## 차오르는 것을 그리는 데 쓴다.
func reload_progress() -> float:
	if reload_ticks_left <= 0:
		return 0.0
	return 1.0 - float(reload_ticks_left) / float(RELOAD_TICKS)


## 지금 한 발 나갈 수 있는가. **재장전 중에는 못 쏜다.**
func can_fire() -> bool:
	return reload_ticks_left == 0 and loaded() > 0


## 한 발 쏜다 — 실제로 나갔으면 true, 탄창이 비었거나 재장전 중이면 false 다.
##
## **부르는 쪽은 이 반환값을 보고 총알을 만든다**: "다 쏘면 좌클릭해도 안 나간다"
## (docs/DESIGN.md 「총기 스탯」)가 이 한 줄에서 나온다.
func fire() -> bool:
	if not can_fire():
		return false
	rounds[kind] = loaded() - 1
	return true


## R 로 재장전을 시작한다 — 시작했으면 true.
##
## 이미 가득이거나 이미 재장전 중이면 아무 일도 하지 않는다(연타로 타이머가 되감기지
## 않는다). **예비 탄약이 없으므로 끝나면 언제나 가득이다.**
func start_reload() -> bool:
	if reload_ticks_left > 0 or loaded() >= MAG_SIZE:
		return false
	reload_ticks_left = RELOAD_TICKS
	return true


## 우클릭 — 다음 탄종으로 갈아 끼운다. 바뀐 탄종을 돌려준다.
##
## **진행 중이던 재장전은 취소된다.** 탄종 전환이 곧 "다른 탄창으로 갈아 끼우는 것"
## 이라(「총기 스탯」), 손에서 내려놓은 탄창이 저 혼자 채워지고 있으면 안 된다 —
## 새 탄종은 자기 탄창에 남아 있던 발수 그대로다.
func switch_kind() -> String:
	var next := (KINDS.find(kind) + 1) % KINDS.size()
	kind = KINDS[next]
	reload_ticks_left = 0
	return kind
