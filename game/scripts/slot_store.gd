extends RefCounted

## 캐릭터 슬롯 3개의 저장/불러오기 (docs/DESIGN.md "클라이언트 화면 흐름").
##
## Godot 노드를 상속하지 않는 순수 클래스다 — 화면 없이 단독으로 돌아가야 한다
## (DESIGN.md "시뮬레이션 구조"). 오토로드로 만들지 않는 이유는 오토로드가
## `--script` 모드 자체 QA에서 컴파일 에러를 내기 때문이다 (docs/GOTCHAS.md).

const SAVE_PATH := "user://characters.json"
const SLOT_COUNT := 3
const FORMAT_VERSION := 1

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
