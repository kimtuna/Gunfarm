extends RefCounted

## 바닥에 놓인 아이템 (docs/DESIGN.md 「아이템 획득 방식 — 바닥 드롭」).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) — 나중에
## 서버가 "무엇이 어디에 떨어져 있는가"를 화면 없이 들고 있어야 하기 때문이다.
## 그리는 일은 `ground_items_view.gd` 가 이 목록을 보고 한다.
##
## 여기 있는 규칙 세 가지 (전부 DESIGN.md 「바닥 드롭」에 근거가 적혀 있다):
##
## 1. **줍기는 접촉이다** — 습득 버튼이 없다(좌클릭은 도구 동작이다). 플레이어가
##    `PICKUP_RADIUS` 안에 들어오면 자동으로 인벤토리로 간다.
## 2. **버린 자리를 벗어나기 전까지는 안 주워진다**(`KEY_LOCKED`). 시간 유예가 아니라
##    **거리**로 잠근 이유는, 시간으로 하면 버려놓고 그 자리에 서 있을 때 몇 초 뒤에
##    도로 주워져서 "버릴 수가 없는" 상태가 되기 때문이다. 거리로 하면 그런 경우가
##    아예 생기지 않는다 — 한 번 걸어 나가면 그때부터 다시 주울 수 있다.
## 3. **인벤토리에 다 못 들어가면 남은 몫은 바닥에 그대로 남는다** — 넣기는 언제나
##    `inventory.take_in(뭉치)` 를 지나가고, 그 함수가 못 넣은 몫을 뭉치에 남긴다
##    (DESIGN.md 「인벤토리 안전」). 여기서 뭉치를 지우는 것은 **빈 뭉치가 됐을 때뿐**이다.

const ItemStack := preload("res://scripts/item_stack.gd")

## 줍히는 거리(월드 단위). 타일 한 칸이 48이므로 0.75칸이다 — 아이템 위를 지나가면
## 주워지되, 옆 칸을 스쳐 지나갈 때 딸려오지는 않는 정도다.
const PICKUP_RADIUS := 36.0

## 바닥에 놓인 것이 사라지기까지의 **실제 시간**(초). 2026-09-07 에 정했고 근거는
## DESIGN.md 「아이템 획득 방식 — 바닥 드롭」에 적었다 — 요약하면 "한 세션보다 훨씬
## 길고 하루를 넘기지 않는다".
const LIFETIME_SECONDS := 24.0 * 60.0 * 60.0

## 항목 하나의 키. `stack` 은 `item_stack.gd`, `position` 은 월드 좌표,
## `dropped` 는 놓인 시각(유닉스 초), `locked` 는 위 2번의 잠금이다.
const KEY_STACK := "stack"
const KEY_POSITION := "position"
const KEY_DROPPED := "dropped"
const KEY_LOCKED := "locked"

## 저장 파일에 들어가는 키(슬롯 JSON 이 길어지지 않게 짧게 쓴다 — `item_stack.gd` 와 같다).
const SAVE_STACK := "s"
const SAVE_X := "x"
const SAVE_Y := "y"
const SAVE_DROPPED := "t"

## 바닥에 놓인 것들.
var items: Array[Dictionary] = []

## 내용이 바뀔 때마다 오른다 — 그리는 쪽이 "다시 그려야 하는가"를 이걸로 판단한다
## (`inventory.gd` / `explored_map.gd` 와 같은 방식).
var version := 0


## 한 뭉치를 그 자리에 놓는다. 놓인 항목을 돌려준다(빈 뭉치면 null — 아무것도 안 놓는다).
## **놓자마자는 잠겨 있다** — 버린 사람이 그 자리를 벗어나야 다시 주울 수 있다.
func drop(stack: RefCounted, world_position: Vector2, now_unix: float = -1.0) -> Variant:
	if stack == null or stack.is_empty():
		return null
	var entry := {
		KEY_STACK: stack,
		KEY_POSITION: world_position,
		KEY_DROPPED: _now(now_unix),
		KEY_LOCKED: true,
	}
	items.append(entry)
	version += 1
	return entry


func size() -> int:
	return items.size()


## 그 자리 근처에 놓인 것들.
func near(world_position: Vector2, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in items:
		if (entry[KEY_POSITION] as Vector2).distance_to(world_position) <= radius:
			out.append(entry)
	return out


## 한 번 훑는다 — **줍기 + 잠금 풀기 + 수명 다한 것 치우기**. 바뀐 항목 수를 돌려준다.
##
## **프레임 시간을 받지 않는다.** 결과가 오직 "지금 플레이어가 어디 있는가"와 "지금이
## 몇 시인가"로만 정해지므로, 몇 번을 부르든 프레임 레이트가 얼마든 같은 상태가 된다
## (docs/DESIGN.md 「시뮬레이션 구조」의 "프레임 레이트가 달라도 결과가 같아야 한다").
## 그래서 고정 틱 누적기가 필요 없다.
##
## 수명은 **오프라인 시간을 포함한 실제 시간**이라 벽시계로 잰다 — 「시뮬레이션 구조」의
## "서버를 다시 켰을 때 `지금 시각 - 마지막 저장 시각`만큼 큐를 앞으로 감으면 끝난다"와
## 같은 방식이고, 그래서 불러올 때 따로 빨리 감는 코드가 없어도 저절로 맞는다.
##
## 훑는 비용은 바닥에 놓인 개수에 비례한다. 이 개수는 "사람이 버린 것"이라 작게 유지되고,
## 커지는 쪽(자원 드롭이 쏟아지는 경우)이 오면 여기에 공간 색인이 들어간다.
func update(player_position: Vector2, inventory: RefCounted, now_unix: float = -1.0) -> int:
	var t := _now(now_unix)
	var changed := 0
	var index := 0
	while index < items.size():
		var entry: Dictionary = items[index]
		if t - float(entry[KEY_DROPPED]) >= LIFETIME_SECONDS:
			items.remove_at(index)
			changed += 1
			continue
		var distance := (entry[KEY_POSITION] as Vector2).distance_to(player_position)
		if bool(entry[KEY_LOCKED]):
			# 버린 자리를 벗어났다 — 이제부터 다시 주울 수 있다(화면은 안 바뀐다).
			if distance > PICKUP_RADIUS:
				entry[KEY_LOCKED] = false
			index += 1
			continue
		if inventory == null or distance > PICKUP_RADIUS:
			index += 1
			continue
		var stack: RefCounted = entry[KEY_STACK]
		if inventory.take_in(stack) > 0:
			changed += 1
		# **못 들어간 몫은 여기 그대로 남는다** (DESIGN.md 「인벤토리 안전」).
		if stack.is_empty():
			items.remove_at(index)
			continue
		index += 1
	if changed > 0:
		version += 1
	return changed


# --- 저장 / 불러오기 (슬롯에 캐릭터마다 따로 들어간다) ---------------------------

func to_data() -> Array:
	var out: Array = []
	for entry in items:
		var position: Vector2 = entry[KEY_POSITION]
		out.append({
			SAVE_STACK: (entry[KEY_STACK] as RefCounted).to_data(),
			SAVE_X: position.x,
			SAVE_Y: position.y,
			SAVE_DROPPED: entry[KEY_DROPPED],
		})
	return out


## 저장된 값을 그대로 얹는다. **깨진 항목은 조용히 건너뛴다** — 세이브 한 줄이 깨졌다고
## 월드를 못 들어가게 만들지 않는다(`inventory.gd` 의 `from_data` 와 같은 규칙).
##
## **불러온 것은 전부 잠긴 채로 시작한다.** 나갈 때 아이템 위에 서 있었으면 다시
## 들어오는 순간 도로 주워질 텐데, 그건 "버렸다"는 행동을 되돌리는 것이다 — 한 번
## 걸어 나가면 바로 풀린다.
func from_data(data: Variant, now_unix: float = -1.0) -> int:
	items.clear()
	version += 1
	if typeof(data) != TYPE_ARRAY:
		return 0
	var t := _now(now_unix)
	for raw in (data as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var stack := ItemStack.from_data(row.get(SAVE_STACK, null))
		if stack == null:
			continue
		items.append({
			KEY_STACK: stack,
			KEY_POSITION: Vector2(float(row.get(SAVE_X, 0.0)), float(row.get(SAVE_Y, 0.0))),
			KEY_DROPPED: float(row.get(SAVE_DROPPED, t)),
			KEY_LOCKED: true,
		})
	return items.size()


func _now(now_unix: float) -> float:
	return now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
