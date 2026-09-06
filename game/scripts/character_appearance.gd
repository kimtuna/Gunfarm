extends RefCounted

## 캐릭터 외형 선택지(고정 팔레트)와 그 저장 형식 (docs/DESIGN.md "캐릭터 커스터마이징 항목").
##
## Godot 노드를 상속하지 않는 순수 클래스다 — 화면 없이 단독으로 돌아가야 한다
## (DESIGN.md "시뮬레이션 구조"). 오토로드로 만들지 않는 이유는 오토로드가
## `--script` 모드 자체 QA에서 컴파일 에러를 내기 때문이다 (docs/GOTCHAS.md).
##
## **저장에는 색이 아니라 id 문자열을 넣는다.** 나중에 스프라이트를 팔레트 교체로
## 만들 때 그 id 가 그대로 팔레트 키가 되고, 팔레트 색을 손봐도 기존 세이브가
## 안 깨진다.

## 색은 Color 가 아니라 16진 문자열로 둔다 — GDScript 의 const 는 Color(...) 같은
## 생성자 호출을 못 담는다. 실제 Color 는 `color_of()` 가 만들어 준다.
const SKIN := [
	{"id": "light", "label": "밝은", "color": "f0c8a0"},
	{"id": "warm", "label": "중간", "color": "d9a066"},
	{"id": "tan", "label": "구릿빛", "color": "b07a4a"},
	{"id": "brown", "label": "짙은", "color": "7a4a2b"},
	{"id": "deep", "label": "가장 짙은", "color": "4e2e1c"},
]

const HAIR_COLOR := [
	{"id": "black", "label": "검정", "color": "211c1a"},
	{"id": "brown", "label": "갈색", "color": "6b4a2a"},
	{"id": "blond", "label": "금발", "color": "d8b25c"},
	{"id": "auburn", "label": "적갈색", "color": "93402a"},
	{"id": "silver", "label": "은발", "color": "b9bdb6"},
	{"id": "indigo", "label": "쪽빛", "color": "3e5c7a"},
]

const CLOTHES_COLOR := [
	{"id": "grass", "label": "풀색", "color": "4e7a3a"},
	{"id": "sky", "label": "하늘색", "color": "3e6e9e"},
	{"id": "earth", "label": "흙색", "color": "7a5230"},
	{"id": "plum", "label": "자주색", "color": "7a3b5e"},
	{"id": "ash", "label": "잿빛", "color": "5a5f58"},
	{"id": "ember", "label": "주홍색", "color": "b4543a"},
]

const HAIRSTYLE := [
	{"id": "short", "label": "짧은머리"},
	{"id": "bob", "label": "단발머리"},
	{"id": "long", "label": "긴머리"},
	{"id": "ponytail", "label": "묶은머리"},
]

## 화면이 순서대로 훑는 항목들. 값은 위 팔레트 상수 이름과 같은 뜻이다.
const FIELDS := ["skin", "hair_color", "clothes_color", "hairstyle"]

const FIELD_LABELS := {
	"skin": "피부색",
	"hair_color": "머리색",
	"clothes_color": "옷색",
	"hairstyle": "머리모양",
}

const MAX_NAME_LENGTH := 12


static func options(field: String) -> Array:
	match field:
		"skin":
			return SKIN
		"hair_color":
			return HAIR_COLOR
		"clothes_color":
			return CLOTHES_COLOR
		"hairstyle":
			return HAIRSTYLE
	push_error("모르는 외형 항목: %s" % field)
	return []


## 각 항목의 첫 번째 선택지가 기본값이다.
static func default_appearance() -> Dictionary:
	var appearance := {}
	for field in FIELDS:
		appearance[field] = String(options(field)[0]["id"])
	return appearance


static func index_of(field: String, id: String) -> int:
	var list := options(field)
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return -1


static func id_at(field: String, index: int) -> String:
	var list := options(field)
	if list.is_empty():
		return ""
	return String(list[wrapi(index, 0, list.size())]["id"])


static func label_of(field: String, id: String) -> String:
	var index := index_of(field, id)
	if index < 0:
		return ""
	return String(options(field)[index]["label"])


## 색이 있는 항목(피부/머리/옷)만 의미가 있다. 머리모양에는 색이 없다.
static func color_of(field: String, id: String) -> Color:
	var index := index_of(field, id)
	if index < 0 or not options(field)[index].has("color"):
		return Color.MAGENTA  # 눈에 띄게 — 팔레트에 없는 값이 새어들어온 것이다.
	return Color(String(options(field)[index]["color"]))


## 저장 파일에서 읽은 값을 화면이 믿고 쓸 수 있게 다듬는다 — 빠졌거나 팔레트에
## 없는 id 는 그 항목의 기본값으로 되돌린다(옛 세이브/깨진 파일 대비).
static func normalize(appearance: Dictionary) -> Dictionary:
	var result := default_appearance()
	for field in FIELDS:
		var id := String(appearance.get(field, ""))
		if index_of(field, id) >= 0:
			result[field] = id
	return result


## 앞뒤 공백을 버리고 길이를 자른다. 빈 이름은 확정 버튼 쪽에서 막는다.
static func sanitize_name(raw: String) -> String:
	var trimmed := raw.strip_edges()
	if trimmed.length() > MAX_NAME_LENGTH:
		trimmed = trimmed.substr(0, MAX_NAME_LENGTH)
	return trimmed


static func is_valid_name(raw: String) -> bool:
	return not sanitize_name(raw).is_empty()
