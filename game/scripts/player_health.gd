extends RefCounted

## 플레이어의 체력 (docs/DESIGN.md 「체력 / 죽음 / 리스폰」).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) — 나중에
## 서버가 화면 없이 같은 코드로 "이 총알이 얼마를 깎았는가 / 이 플레이어가 죽었는가"를
## 판정한다(「서버 권위」의 "명중 판정은 전부 서버가 계산한다"). **체력은 화면 상태가
## 아니라 플레이어 상태다** — 그래서 `player_motion.gd`(플레이어 코어)가 탄창(`gun`)
## 옆에 들고 있다.
##
## **이 클래스는 죽음을 처리하지 않는다** — 0 이 됐다는 사실까지만 안다. 되살리는
## 것(리스폰 지점으로 옮기기)은 위치를 아는 `player_motion.gd` 의 틱이 한다.
##
## **저장하지 않는다.** 월드에 들어오면 언제나 가득이다 — 근거는 DESIGN.md 의
## 같은 절에 적어뒀다(회복 수단이 아직 하나도 없어서, 저장하면 다친 채로 영영
## 돌아오지 못한다).

## 최대 체력. **사슴과 같은 값이다** — 밸런스는 나중에 조정하는 임시값이라고
## DESIGN.md 가 못 박아뒀다 (「체력 / 죽음 / 리스폰」, 「총기 스탯」).
const MAX_HEALTH := 100

## 지금 체력(0 ~ `MAX_HEALTH`).
var current := MAX_HEALTH


## 데미지를 받는다 — **실제로 깎인 양**을 돌려준다(남은 체력보다 큰 데미지를 받으면
## 남은 만큼만이다). 음수/0 은 아무 일도 하지 않는다.
##
## **여기서 죽지 않는다.** 체력이 0 이 됐다는 것만 남고, 되살리는 것은 코어의 틱이다
## (`player_motion.gd`) — 데미지를 주는 쪽이 위치까지 옮기면 그 틱의 이동 계산과
## 순서가 어긋난다.
func take_damage(amount: int) -> int:
	if amount <= 0:
		return 0
	var dealt := mini(amount, current)
	current -= dealt
	return dealt


func is_dead() -> bool:
	return current <= 0


## 가득 채운다 — 리스폰할 때다.
func refill() -> void:
	current = MAX_HEALTH
