extends RefCounted

## 캐릭터 슬롯 3개의 저장/불러오기 (docs/DESIGN.md "클라이언트 화면 흐름").
##
## Godot 노드를 상속하지 않는 순수 클래스다 — 화면 없이 단독으로 돌아가야 한다
## (DESIGN.md "시뮬레이션 구조"). 오토로드로 만들지 않는 이유는 오토로드가
## `--script` 모드 자체 QA에서 컴파일 에러를 내기 때문이다 (docs/GOTCHAS.md).

const SAVE_PATH := "user://characters.json"
const SLOT_COUNT := 3
const FORMAT_VERSION := 1

## 슬롯 안에서 탐험 기록이 앉는 자리 (docs/DESIGN.md 「맵 (M)」).
const EXPLORED_KEY := "explored"

## 슬롯 안에서 인벤토리가 앉는 자리 (docs/DESIGN.md 「인벤토리 / 장비」).
## **캐릭터마다 따로다** — 탐험 기록과 같은 이유로 월드가 아니라 캐릭터에 붙는다.
const INVENTORY_KEY := "inventory"

## 슬롯 안에서 **바닥에 놓인 아이템**이 앉는 자리 (docs/DESIGN.md 「아이템 획득 방식 —
## 바닥 드롭」의 "바닥 아이템은 저장된다").
## **월드에 속한 것이지 캐릭터에 속한 것이 아니지만**, 지금은 월드가 슬롯 하나에
## 한 개(그 슬롯의 `world_seed`)라 여기 같이 둔다 — 한 월드에 여러 캐릭터가 들어오는
## 날이 오면 이 키가 월드 쪽 저장으로 옮겨간다.
const GROUND_KEY := "ground"

## 슬롯 화면에서 고른 슬롯 번호를 다음 화면(커스터마이징 / 월드)으로 넘기는 자리.
## 씬이 바뀌어도 스크립트 자체는 살아 있으므로 static 하나면 충분하다.
static var selected_slot := -1


## 전부 빈 슬롯. 빈 슬롯은 빈 Dictionary 로 표현한다.
static func empty_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for i in SLOT_COUNT:
		slots.append({})
	return slots


static func is_empty(slot: Dictionary) -> bool:
	return slot.is_empty()


## 월드 시드 하나. 0 은 "아직 안 정해짐"을 뜻하므로 쓰지 않는다.
static func new_world_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 0x7FFFFFFF)


## 새 캐릭터 한 명.
## `appearance` 는 커스터마이징 화면이 고른 값이다(scripts/character_appearance.gd 의
## id 들 — 색이 아니라 id 를 저장한다).
## **월드 시드는 캐릭터를 만드는 이 시점에 정해서 슬롯에 박아둔다** — 첫 입장 때 정하면
## 그 전까지 슬롯이 "월드 없는 캐릭터" 상태로 남고, 같은 슬롯으로 다시 들어왔을 때 같은
## 월드가 나온다는 보장을 코드 여러 군데에서 따로 지켜야 한다.
static func make_character(character_name: String, appearance: Dictionary = {}, world_seed: int = 0) -> Dictionary:
	return {
		"name": character_name,
		"created_unix": int(Time.get_unix_time_from_system()),
		"appearance": appearance.duplicate(true),
		"world_seed": world_seed if world_seed != 0 else new_world_seed(),
	}


## 슬롯 하나의 탐험 기록(`explored_map.gd` 이 만든 base64 한 줄)을 저장한다.
## **캐릭터마다 따로다** — 같은 월드라도 다른 캐릭터는 자기가 가본 곳만 안다
## (docs/DESIGN.md 「맵 (M)」). 지형은 여기 넣지 않는다(시드로 다시 계산한다).
static func save_explored(index: int, encoded: String) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	var slots := load_slots()
	var slot: Dictionary = slots[index]
	if slot.is_empty():
		return false  # 빈 슬롯에는 탐험 기록이 붙을 자리가 없다.
	slot[EXPLORED_KEY] = encoded
	slots[index] = slot
	return save_slots(slots)


static func explored_of(slot: Dictionary) -> String:
	return String(slot.get(EXPLORED_KEY, ""))


## 슬롯 하나의 인벤토리(`inventory.gd` 의 `to_data()`)를 저장한다.
## 탐험 기록과 같은 규칙이다 — 빈 슬롯에는 붙을 자리가 없다.
static func save_inventory(index: int, data: Dictionary) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	var slots := load_slots()
	var slot: Dictionary = slots[index]
	if slot.is_empty():
		return false
	slot[INVENTORY_KEY] = data
	slots[index] = slot
	return save_slots(slots)


## 저장된 인벤토리. **키 자체가 없으면 null** 이다 — "아직 한 번도 저장한 적 없는
## 캐릭터"(= 처음 들어오는 캐릭터)와 "다 버려서 비어 있는 인벤토리"를 구별해야
## 하기 때문이다(전자에만 기본 도구를 지급한다).
static func inventory_of(slot: Dictionary) -> Variant:
	var data: Variant = slot.get(INVENTORY_KEY, null)
	return data if typeof(data) == TYPE_DICTIONARY else null


## 슬롯 하나의 바닥 아이템(`ground_items.gd` 의 `to_data()`)을 저장한다.
## 탐험 기록·인벤토리와 같은 규칙이다 — 빈 슬롯에는 붙을 자리가 없다.
static func save_ground(index: int, data: Array) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	var slots := load_slots()
	var slot: Dictionary = slots[index]
	if slot.is_empty():
		return false
	slot[GROUND_KEY] = data
	slots[index] = slot
	return save_slots(slots)


## 저장된 바닥 아이템. 없으면 **빈 배열**이다 — 인벤토리와 달리 "한 번도 저장한 적
## 없음"과 "다 주워서 비어 있음"을 구별할 이유가 없다(처음 지급하는 것이 없다).
static func ground_of(slot: Dictionary) -> Array:
	var data: Variant = slot.get(GROUND_KEY, [])
	return data if typeof(data) == TYPE_ARRAY else []


static func load_slots() -> Array[Dictionary]:
	var slots := empty_slots()
	if not FileAccess.file_exists(SAVE_PATH):
		return slots
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("캐릭터 슬롯을 못 읽었다: %s" % error_string(FileAccess.get_open_error()))
		return slots
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("캐릭터 슬롯 파일이 깨졌다 — 빈 슬롯으로 시작한다.")
		return slots
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != FORMAT_VERSION:
		push_warning("모르는 저장 형식(version=%s) — 빈 슬롯으로 시작한다." % data.get("version", 0))
		return slots
	var saved: Array = data.get("slots", [])
	for i in mini(saved.size(), SLOT_COUNT):
		if typeof(saved[i]) == TYPE_DICTIONARY and not (saved[i] as Dictionary).is_empty():
			slots[i] = saved[i]
	return slots


static func save_slots(slots: Array[Dictionary]) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("캐릭터 슬롯을 못 썼다: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "slots": slots}, "\t"))
	file.close()
	return true
