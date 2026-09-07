extends RefCounted

## 월드 설정 (docs/DESIGN.md 「월드 설정」).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) — 나중에
## 서버가 화면 없이 같은 값을 읽고 판정에 쓴다(「월드 설정」의 "월드 설정은 그 월드를
## 여는 호스트의 것이고 … 서버가 들고 판정에 쓴다").
##
## **그래픽 설정(`settings_store.gd`)과 자리가 다르다.** 그쪽은 `user://settings.json`
## 에 **기계 단위**로 저장되고(해상도는 이 모니터의 사정이다), 월드 설정은 **그
## 슬롯에 저장된다** — 같은 사람이 월드를 여러 개 만들면 서로 다를 수 있다.
## 저장/불러오기는 `slot_store.gd` 의 `world_settings_of()` / `save_world_settings()` 다.

## 데스드롭 상자 타이머가 저장 파일에서 앉는 자리.
const DEATH_BOX_KEY := "death_box_minutes"

## 기본 30분 (docs/DESIGN.md 「데스드롭 상자」).
const DEFAULT_DEATH_BOX_MINUTES := 30

## 고를 수 있는 값(분). **0 은 "사라지지 않음"이다.**
##
## 0 을 넣어둔 이유는 「데스드롭 상자」가 이 설정을 둔 근거 그대로다 — *"죽으면 짐을
## 잃는 방식 자체를 불쾌해하는 사람이 많다 … 그 강도를 사람마다 정할 수 있어야 한다."*
## 강도의 한쪽 끝(아예 안 잃는다)이 없으면 그 문장이 반만 지켜진다. 반대쪽 끝(5분)도
## 같은 이유로 둔다.
const DEATH_BOX_CHOICES: Array[int] = [5, 10, 30, 60, 180, 0]

## 「사라지지 않음」을 초 단위로 나타내는 값. 음수는 "만료가 없다"는 뜻이다
## (`death_boxes.gd` 가 이 약속을 그대로 쓴다).
const FOREVER := -1.0

## 데스드롭 상자가 사라지기까지의 시간(분). 0 이면 사라지지 않는다.
var death_box_minutes := DEFAULT_DEATH_BOX_MINUTES


## 상자 하나에 넣어줄 시간(초). 사라지지 않는 설정이면 `FOREVER` 다.
func death_box_seconds() -> float:
	return FOREVER if death_box_minutes <= 0 else float(death_box_minutes) * 60.0


## 화면에 보여줄 글자. 설정 화면과 상자 창이 **같은 함수**를 쓴다 — 두 곳이 다른
## 말로 같은 값을 부르면 안 된다.
static func minutes_label(minutes: int) -> String:
	if minutes <= 0:
		return "사라지지 않음"
	if minutes < 60:
		return "%d분" % minutes
	if minutes % 60 == 0:
		return "%d시간" % (minutes / 60)
	@warning_ignore("integer_division")
	return "%d시간 %d분" % [minutes / 60, minutes % 60]


## 고른 값이 목록의 몇 번째인가(모르는 값이면 기본값 자리).
func choice_index() -> int:
	var found := DEATH_BOX_CHOICES.find(death_box_minutes)
	return found if found >= 0 else DEATH_BOX_CHOICES.find(DEFAULT_DEATH_BOX_MINUTES)


## 목록에서 한 칸 옮긴다(양끝에서 되감긴다 — 설정 화면의 좌/우 버튼과 같은 규칙).
func step_death_box(delta: int) -> void:
	death_box_minutes = DEATH_BOX_CHOICES[wrapi(choice_index() + delta, 0, DEATH_BOX_CHOICES.size())]


func to_data() -> Dictionary:
	return {DEATH_BOX_KEY: death_box_minutes}


## 저장된 값을 얹는다. **모르는 값은 기본값으로 떨어진다** — 세이브 한 줄이 깨졌다고
## 월드를 못 들어가게 만들지 않는다(`inventory.gd` 의 `from_data` 와 같은 규칙).
func from_data(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = data
	var minutes := int(dict.get(DEATH_BOX_KEY, DEFAULT_DEATH_BOX_MINUTES))
	death_box_minutes = minutes if DEATH_BOX_CHOICES.has(minutes) else DEFAULT_DEATH_BOX_MINUTES
	return true
