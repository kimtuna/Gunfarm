extends RefCounted

## 한 칸에 들어 있는 아이템 뭉치 하나 (아이템 id + 수량 + 소유 상태).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (docs/DESIGN.md 「시뮬레이션 구조」).
##
## **소유 상태(`ownership`)는 지금 아무 동작도 하지 않는다** — 값은 항상 `로컬` 하나다
## (docs/DESIGN.md 「아이템 소유권 상태」). 그래도 지금 넣어두는 이유는 저장 포맷에
## 자리를 미리 잡아두기 위해서다: 나중에 세션 서버 사이의 이동/거래를 붙이는 시점에
## 이 필드를 추가하면 그때까지의 세이브가 전부 깨진다.
##
## **뭉치는 값이 아니라 객체다.** 인벤토리에 넣을 때 이 객체를 통째로 넘기고
## (`inventory.gd` 의 `take_in`), 다 못 들어가면 **못 들어간 몫이 이 객체에 그대로
## 남는다** — 「인벤토리 안전」의 "나머지는 원래 위치에 그대로 남겨야 한다"가
## 호출한 쪽의 성실함이 아니라 자료구조 자체로 지켜진다.

const ItemTypes := preload("res://scripts/item_types.gd")

## 소유 상태. 나중에 쓸 값은 `반출중`/`정산중` 이고, 지금은 이것 하나뿐이다.
const OWNERSHIP_LOCAL := "local"

## 저장 파일에 들어가는 키 이름. 짧게 쓰는 이유는 슬롯 JSON 한 줄에 27칸이 들어가기 때문이다.
const KEY_ID := "id"
const KEY_COUNT := "n"
const KEY_OWNERSHIP := "own"

var id := ""
var count := 0
var ownership := OWNERSHIP_LOCAL


func _init(item_id: String = "", amount: int = 0, own: String = OWNERSHIP_LOCAL) -> void:
	id = item_id
	count = amount
	ownership = own


func is_empty() -> bool:
	return id == "" or count <= 0


func max_count() -> int:
	return ItemTypes.max_stack(id)


## 이 뭉치에 더 담을 수 있는 개수.
func space_left() -> int:
	return maxi(0, max_count() - count)


## 같은 칸에 합쳐질 수 있는가. **소유 상태가 다르면 안 합친다** — 지금은 값이 하나뿐이라
## 항상 같지만, 나중에 `반출중` 이 생기면 잠긴 물건과 안 잠긴 물건이 한 칸에 섞이면 안 된다.
func can_merge(other: RefCounted) -> bool:
	if other == null or is_empty() or other.is_empty():
		return false
	return id == other.id and ownership == other.ownership


## 이 뭉치에서 `amount` 개를 덜어낸 새 뭉치. 가진 것보다 많이 달라고 하면 있는 만큼만 준다.
func split(amount: int) -> RefCounted:
	var taken := clampi(amount, 0, count)
	count -= taken
	return get_script().new(id, taken, ownership)


func duplicate_stack() -> RefCounted:
	return get_script().new(id, count, ownership)


func to_data() -> Dictionary:
	return {KEY_ID: id, KEY_COUNT: count, KEY_OWNERSHIP: ownership}


## 저장 파일 한 칸 → 뭉치. 모르는 아이템이거나 수량이 이상하면 **빈 칸(null)** 이다 —
## 세이브가 깨졌다고 캐릭터를 못 쓰게 만들지 않는다.
static func from_data(data: Variant) -> RefCounted:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data
	var id_value := String(dict.get(KEY_ID, ""))
	if not ItemTypes.exists(id_value):
		return null
	var amount := clampi(int(dict.get(KEY_COUNT, 0)), 0, ItemTypes.max_stack(id_value))
	if amount <= 0:
		return null
	var own := String(dict.get(KEY_OWNERSHIP, OWNERSHIP_LOCAL))
	if own == "":
		own = OWNERSHIP_LOCAL
	return (load("res://scripts/item_stack.gd") as GDScript).new(id_value, amount, own)
