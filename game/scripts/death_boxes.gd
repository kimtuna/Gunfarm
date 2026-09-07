extends RefCounted

## 데스드롭 상자 (docs/DESIGN.md 「데스드롭 상자」).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) — 서버가
## 화면 없이 "어디에 무엇이 얼마나 남았는가"를 들고 있어야 한다(「서버 권위」).
## 그리는 일은 `death_boxes_view.gd` 가, 창은 `death_box_screen.gd` 가 한다.
##
## **바닥 아이템(`ground_items.gd`)과 다른 오브젝트다** — 그건 낱개로 놓여 다가가면
## 자동으로 주워지고, 이건 **담는 것**이라 열어서 꺼낸다. 건축의 설치형 상자와도
## 다르다(그건 타이머가 없다).
##
## 여기 있는 규칙 (전부 DESIGN.md 「데스드롭 상자」에 근거가 있다):
##
## 1. **타이머가 다 되면 상자와 내용물이 함께 사라진다.** 기본 30분이고 값은
##    「월드 설정」이 정한다(`world_settings.gd`). 「사라지지 않음」은 음수 초다.
## 2. **열면 타이머가 멈춘다** — *"정해진 시간은 「찾아올 시간」이지 「꺼낼 시간」이
##    아니다."* 닫으면 다시 흐른다.
## 3. **열어둔 채 멀리 떠나면 닫힌 것으로 친다**(`CLOSE_DISTANCE`). 안 그러면 열어둔
##    상자가 영영 안 사라진다.
## 4. **꺼내기는 `inventory.take_in(뭉치)` 하나만 지나간다** — 못 들어간 몫은 상자에
##    그대로 남는다 (DESIGN.md 「인벤토리 안전」).
##
## **상자에 "누가 죽었는가"를 적어두지 않는다.** 그게 곧 「데스드롭 상자」의 미정
## 항목("다른 플레이어가 남의 상자를 열 수 있는가")에 대한 답의 구현이다 — 누구나
## 열 수 있다. 근거는 DESIGN.md 의 같은 절에 적어뒀다.

const ItemStack := preload("res://scripts/item_stack.gd")
const WorldSettings := preload("res://scripts/world_settings.gd")

## 상자 한 칸 수. 인벤토리 일반 18칸 + 장비 9칸이 통째로 들어와야 하므로 그 합이다
## (`inventory.gd` 의 `GENERAL_SLOTS` + `EQUIPMENT_SLOTS`).
const SLOT_COUNT := 27

## 상자가 월드에서 차지하는 크기(월드 단위). **씬 스케일 3배의 배수다** — 도트 하나가
## 화면에서 3px 이어야 캐릭터·지형과 같은 단위가 된다 (DESIGN.md 「아이템/오브젝트
## 크기 표준」). 48 × 42 = 아트 16 × 14px 로, 타일 한 칸 폭에 플레이어(51px)의 8할이다.
const BOX_SIZE := Vector2(48.0, 42.0)

## 상자를 열 수 있는 거리(월드 단위, 플레이어 발밑 ↔ 상자 밑동). 타일 1.5칸이다.
## **줍기 거리(36)보다 넉넉해야 한다** — 상자가 48 폭이라 36 안에 들어가려면 상자를
## 밟고 서야 한다.
const OPEN_RADIUS := 72.0

## 열어둔 상자가 "닫힌 것으로" 넘어가는 거리(월드 단위). 타일 10칸 = 480 이다.
## 화면 세로 절반(360)보다 커서 **그 거리면 상자가 화면에 아예 없다** — 「열어둔 채
## 멀리 떠나면 닫힌 것으로 친다」가 눈에 보이는 것과 어긋나지 않는다.
const CLOSE_DISTANCE := 480.0

## 만료가 없다는 뜻의 남은 시간. 「월드 설정」의 「사라지지 않음」이 이 값으로 온다.
const FOREVER := WorldSettings.FOREVER

## 항목 하나의 키.
const KEY_ID := "id"
const KEY_STACKS := "stacks"
const KEY_POSITION := "position"
const KEY_REMAINING := "remaining"
const KEY_TOTAL := "total"
const KEY_OPENED := "opened"

## 저장 파일에 들어가는 키(슬롯 JSON 이 길어지지 않게 짧게 쓴다 — `ground_items.gd` 와 같다).
const SAVE_STACKS := "s"
const SAVE_X := "x"
const SAVE_Y := "y"
const SAVE_REMAINING := "r"
const SAVE_TOTAL := "n"
const SAVE_AT := "t"

## 월드에 놓인 상자들.
var items: Array[Dictionary] = []

## 내용이 바뀔 때마다 오른다 — 그리는 쪽이 "다시 그려야 하는가"를 이걸로 판단한다
## (`ground_items.gd` 와 같은 방식).
var version := 0

var _next_id := 1
## 마지막으로 시계를 본 시각. 첫 `update()` 는 흐른 시간을 0 으로 본다.
var _last_unix := -1.0


## 죽은 자리에 상자 하나를 놓고 뭉치들을 통째로 담는다. 만든 항목을 돌려준다.
## **빈 뭉치 목록이면 아무것도 만들지 않는다**(null) — 빈손으로 죽었는데 빈 상자가
## 남으면 그건 월드에 쓰레기를 하나 놓는 것일 뿐이다(찾아올 것이 없다).
##
## `seconds` 는 「월드 설정」이 정한 값이다(`world_settings.gd` 의 `death_box_seconds()`).
## **상자를 만드는 시점의 값을 새겨둔다** — 이미 놓인 상자의 남은 시간을 설정이
## 나중에 흔들지 않는다(근거는 DESIGN.md 「월드 설정」).
func spawn(world_position: Vector2, stacks: Array, seconds: float) -> Variant:
	var filled: Array = []
	filled.resize(SLOT_COUNT)
	var index := 0
	for stack: RefCounted in stacks:
		if stack == null or stack.is_empty() or index >= SLOT_COUNT:
			continue
		filled[index] = stack
		index += 1
	if index == 0:
		return null
	var entry := {
		KEY_ID: _next_id,
		KEY_STACKS: filled,
		KEY_POSITION: world_position,
		KEY_REMAINING: seconds,
		KEY_TOTAL: seconds,
		KEY_OPENED: false,
	}
	_next_id += 1
	items.append(entry)
	version += 1
	return entry


func size() -> int:
	return items.size()


func by_id(id: int) -> Variant:
	for entry in items:
		if int(entry[KEY_ID]) == id:
			return entry
	return null


## 상자가 월드에서 덮는 사각형. **원점은 밑동(땅에 닿는 점)** 이라 그림이 그 위로
## 올라간다 — `ground_item_node.gd` 와 같은 약속이다.
##
## **그리는 쪽과 짚는 쪽이 이 함수 하나를 같이 쓴다** — 배치를 바꿔도 "보이는 자리"와
## "클릭이 먹는 자리"가 어긋날 데가 없다(`inventory_panel.gd` 의 `slot_rect` 와 같은 방식).
static func box_rect(world_position: Vector2) -> Rect2:
	return Rect2(world_position - Vector2(BOX_SIZE.x * 0.5, BOX_SIZE.y), BOX_SIZE)


## 그 지점을 겨눈 좌클릭이 여는 상자(없으면 null). **커서가 상자 위에 있고 플레이어가
## `OPEN_RADIUS` 안에 있어야** 한다 — 화면 저쪽 끝의 상자를 클릭 한 번으로 열 수는 없다.
func at_point(world_point: Vector2, player_position: Vector2) -> Variant:
	for entry in items:
		var at: Vector2 = entry[KEY_POSITION]
		if at.distance_to(player_position) > OPEN_RADIUS:
			continue
		if box_rect(at).has_point(world_point):
			return entry
	return null


func open(entry: Dictionary) -> void:
	if bool(entry[KEY_OPENED]):
		return
	entry[KEY_OPENED] = true
	version += 1


func close(entry: Dictionary) -> void:
	if not bool(entry[KEY_OPENED]):
		return
	entry[KEY_OPENED] = false
	version += 1


func is_open(entry: Dictionary) -> bool:
	return bool(entry[KEY_OPENED])


## 남은 시간이 다는 비율(0~1). 「사라지지 않음」이면 -1 이다 — 그릴 것이 없다는 뜻이다.
static func remaining_ratio(entry: Dictionary) -> float:
	var total: float = entry[KEY_TOTAL]
	if total < 0.0:
		return -1.0
	return clampf(float(entry[KEY_REMAINING]) / maxf(total, 0.001), 0.0, 1.0)


## 상자 안이 다 비었는가.
static func is_empty_box(entry: Dictionary) -> bool:
	for stack: RefCounted in (entry[KEY_STACKS] as Array):
		if stack != null and not stack.is_empty():
			return false
	return true


## 한 번 훑는다 — **멀어진 상자 닫기 + 타이머 흘리기 + 다 된 상자 치우기.**
## 바뀐 항목 수를 돌려준다.
##
## **프레임 시간을 받지 않는다.** 흐른 시간을 벽시계로 재므로 프레임 레이트와 무관하게
## 결과가 같고(「시뮬레이션 구조」), **오프라인 시간도 같은 식으로 저절로 맞는다**
## (아래 `from_data` — 불러올 때 빨리 감는 코드가 따로 없다).
func update(player_position: Vector2, now_unix: float = -1.0) -> int:
	var t := _now(now_unix)
	var elapsed := 0.0 if _last_unix < 0.0 else maxf(0.0, t - _last_unix)
	_last_unix = t
	var changed := 0
	var index := 0
	while index < items.size():
		var entry: Dictionary = items[index]
		# 3. 열어둔 채 멀리 떠났으면 닫힌 것으로 친다 — 안 그러면 영영 안 사라진다.
		if bool(entry[KEY_OPENED]) \
				and (entry[KEY_POSITION] as Vector2).distance_to(player_position) > CLOSE_DISTANCE:
			entry[KEY_OPENED] = false
			changed += 1
		var remaining: float = entry[KEY_REMAINING]
		# 2. 열려 있는 동안은 시간이 안 흐른다. 「사라지지 않음」(음수)도 그대로 둔다.
		if remaining >= 0.0 and not bool(entry[KEY_OPENED]):
			remaining -= elapsed
			entry[KEY_REMAINING] = remaining
			# 1. 다 되면 **상자와 내용물이 함께** 사라진다.
			if remaining <= 0.0:
				items.remove_at(index)
				changed += 1
				continue
		index += 1
	if changed > 0:
		version += 1
	return changed


# --- 꺼내기 (docs/DESIGN.md 「인벤토리 안전」) -----------------------------------
#
# **넣는 경로는 `inventory.take_in(뭉치)` 하나뿐이고, 못 들어간 몫은 그 뭉치에 그대로
# 남는다** — 여기서 칸을 비우는 것은 **뭉치가 빈 뭉치가 됐을 때뿐**이다.
#
# **상자에 물건을 넣는 길은 두지 않는다.** 이 상자는 30분 뒤 내용물과 함께 사라지는
# 것이라, 넣을 수 있게 만들면 「인벤토리 안전」의 "아이템이 조용히 사라지면 안 된다"와
# 정면으로 부딪힌다. 데스드롭 상자는 **꺼내기만 되는 상자**다(근거는 DESIGN.md).

## 한 칸을 인벤토리로 옮긴다 — 실제로 들어간 개수를 돌려준다.
func take(entry: Dictionary, slot_index: int, inventory: RefCounted) -> int:
	if inventory == null or slot_index < 0 or slot_index >= SLOT_COUNT:
		return 0
	var stacks: Array = entry[KEY_STACKS]
	var stack: RefCounted = stacks[slot_index]
	if stack == null or stack.is_empty():
		return 0
	var moved: int = inventory.take_in(stack)
	if stack.is_empty():
		stacks[slot_index] = null
	if moved > 0:
		_drop_if_empty(entry)
		version += 1
	return moved


## 들어가는 만큼 전부 옮긴다 — 옮긴 총 개수를 돌려준다. 못 들어간 몫은 상자에 남는다.
func take_all(entry: Dictionary, inventory: RefCounted) -> int:
	var moved := 0
	for index in SLOT_COUNT:
		moved += take(entry, index, inventory)
	return moved


## 다 꺼낸 상자는 그 자리에서 없어진다 — 찾아올 것이 없는 상자를 월드에 남기지 않는다
## (같은 이유로 `spawn()` 도 빈 상자를 만들지 않는다).
func _drop_if_empty(entry: Dictionary) -> void:
	if not is_empty_box(entry):
		return
	var index := items.find(entry)
	if index >= 0:
		items.remove_at(index)


# --- 저장 / 불러오기 ------------------------------------------------------------

func to_data() -> Array:
	var now := Time.get_unix_time_from_system()
	var out: Array = []
	for entry in items:
		var stacks: Array = []
		for stack: RefCounted in (entry[KEY_STACKS] as Array):
			stacks.append(null if stack == null else stack.to_data())
		var at: Vector2 = entry[KEY_POSITION]
		out.append({
			SAVE_STACKS: stacks,
			SAVE_X: at.x,
			SAVE_Y: at.y,
			SAVE_REMAINING: entry[KEY_REMAINING],
			SAVE_TOTAL: entry[KEY_TOTAL],
			SAVE_AT: now,
		})
	return out


## 저장된 값을 그대로 얹는다. **깨진 항목은 조용히 건너뛴다** (`ground_items.gd` 와
## 같은 규칙 — 세이브 한 줄이 깨졌다고 월드를 못 들어가게 만들지 않는다).
##
## **오프라인에 흐른 시간은 여기서 한 번에 깎인다** — 적어둔 시각과 지금의 차이만큼
## 남은 시간에서 뺀다. 그게 「시뮬레이션 구조」의 "서버를 다시 켰을 때 `지금 시각 -
## 마지막 저장 시각`만큼 큐를 앞으로 감으면 끝난다"이고, 그래서 **빨리 감는 코드가
## 따로 없다.** 이미 다 된 상자는 아예 안 살아난다.
##
## **불러온 상자는 전부 닫힌 채로 시작한다** — 나갈 때 열어뒀다고 다시 들어오는 순간
## 타이머가 멈춰 있으면 영영 안 사라진다(위 3번과 같은 이유).
func from_data(data: Variant, now_unix: float = -1.0) -> int:
	items.clear()
	version += 1
	_last_unix = -1.0
	if typeof(data) != TYPE_ARRAY:
		return 0
	var t := _now(now_unix)
	for raw in (data as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var stacks: Array = []
		stacks.resize(SLOT_COUNT)
		var saved: Variant = row.get(SAVE_STACKS, [])
		if typeof(saved) == TYPE_ARRAY:
			var array: Array = saved
			for index in mini(array.size(), SLOT_COUNT):
				stacks[index] = ItemStack.from_data(array[index])
		var remaining := float(row.get(SAVE_REMAINING, 0.0))
		if remaining >= 0.0:
			remaining -= maxf(0.0, t - float(row.get(SAVE_AT, t)))
			if remaining <= 0.0:
				continue  # 나가 있는 동안 시간이 다 됐다.
		var entry := {
			KEY_ID: _next_id,
			KEY_STACKS: stacks,
			KEY_POSITION: Vector2(float(row.get(SAVE_X, 0.0)), float(row.get(SAVE_Y, 0.0))),
			KEY_REMAINING: remaining,
			KEY_TOTAL: float(row.get(SAVE_TOTAL, remaining)),
			KEY_OPENED: false,
		}
		_next_id += 1
		if is_empty_box(entry):
			continue
		items.append(entry)
	return items.size()


func _now(now_unix: float) -> float:
	return now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
