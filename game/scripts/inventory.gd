extends RefCounted

## 인벤토리 + 핫바 + 장비 (docs/DESIGN.md 「인벤토리 / 장비」, 「인벤토리 안전」).
##
## **Godot 노드를 상속하지 않는 순수 클래스다** (DESIGN.md 「시뮬레이션 구조」) —
## 화면 없이 단독으로 돌아야 한다. 나중에 서버가 「서버 권위」의 "재료 소모 / 제작
## 완료는 전부 서버가 계산한다"를 할 때 **이 클래스를 그대로 부른다.** 그래서 여기에
## 그리기/입력 코드를 넣으면 안 된다 — 화면 쪽은 `inventory_panel.gd` 가 한다.
##
## 칸 구성 (DESIGN.md):
##   * 일반 18칸 — **맨 위 9칸이 곧 핫바다.** 핫바는 별도 UI 가 아니라 인벤토리의
##     일부고, 숫자키 1~9 가 그 칸을 손에 든다.
##   * 장비 9칸 — 모자1 / 상의1 / 하의1 / 신발1 / 목걸이2 / 반지2 / 가방1.
##     효과는 범위 밖이고, 지금은 종류가 맞는 아이템만 들어가면 된다.
##
## **「인벤토리 안전」은 반환값의 모양으로 지킨다.** 넣는 경로는 `take_in(뭉치)` 하나이고,
## 그 함수는 **넣은 만큼 인자로 받은 뭉치에서 덜어낸다** — 다 못 넣으면 못 넣은 몫이
## 호출한 쪽의 뭉치에 그대로 남는다. 호출한 쪽이 남은 것을 무시해도 아이템이 조용히
## 사라지지 않는다(그 뭉치가 바닥/출력 버퍼/상자에 여전히 있는 그 물건이다).

const ItemTypes := preload("res://scripts/item_types.gd")
const ItemStack := preload("res://scripts/item_stack.gd")

## 칸 무리 이름. 드래그가 "어디에서 어디로"를 이 두 값으로 말한다.
const AREA_GENERAL := "general"
const AREA_EQUIPMENT := "equipment"

const GENERAL_SLOTS := 18
## 일반 칸 중 맨 위 몇 칸이 핫바인가. 숫자키 1~9 와 같은 수여야 한다.
const HOTBAR_SLOTS := 9

## 장비 9칸이 각각 받는 종류 (docs/DESIGN.md 「인벤토리 / 장비」의 순서 그대로).
const EQUIPMENT_KINDS: Array[String] = [
	ItemTypes.EQUIP_HAT, ItemTypes.EQUIP_SHIRT, ItemTypes.EQUIP_PANTS,
	ItemTypes.EQUIP_SHOES, ItemTypes.EQUIP_NECKLACE, ItemTypes.EQUIP_NECKLACE,
	ItemTypes.EQUIP_RING, ItemTypes.EQUIP_RING, ItemTypes.EQUIP_BAG,
]
const EQUIPMENT_SLOTS := 9

## 저장 파일의 키 이름.
const KEY_GENERAL := "general"
const KEY_EQUIPMENT := "equipment"
const KEY_HOTBAR := "hotbar"

## 칸 하나 = `item_stack.gd` 하나, 빈 칸은 null 이다.
var general: Array = []
var equipment: Array = []

## 지금 손에 든 핫바 칸(0~8). 숫자키 1~9 가 정한다.
var selected_hotbar := 0

## 내용이 바뀔 때마다 오른다 — 화면이 "다시 그려야 하는가"를 이걸로 판단한다
## (`explored_map.gd` 와 같은 방식).
var version := 0


func _init() -> void:
	general.resize(GENERAL_SLOTS)
	equipment.resize(EQUIPMENT_SLOTS)


# --- 칸 읽기 -------------------------------------------------------------------

func slots(area: String) -> Array:
	return equipment if area == AREA_EQUIPMENT else general


func slot_count(area: String) -> int:
	return slots(area).size()


func valid(area: String, index: int) -> bool:
	return index >= 0 and index < slot_count(area)


## 그 칸의 뭉치(없으면 null). **돌려준 것은 원본이다** — 밖에서 고치면 인벤토리가 바뀐다.
func at(area: String, index: int) -> RefCounted:
	if not valid(area, index):
		return null
	return slots(area)[index]


## 지금 손에 든 것 (핫바에서 고른 칸). 빈 칸이면 null.
func held() -> RefCounted:
	return at(AREA_GENERAL, selected_hotbar)


## 숫자키 1~9. 범위 밖이면 아무 일도 안 한다.
func select_hotbar(index: int) -> bool:
	if index < 0 or index >= HOTBAR_SLOTS or index == selected_hotbar:
		return false
	selected_hotbar = index
	version += 1
	return true


func is_empty() -> bool:
	for area in [AREA_GENERAL, AREA_EQUIPMENT]:
		for stack in slots(area):
			if stack != null:
				return false
	return true


## 그 아이템을 몇 개 갖고 있는가(일반 + 장비 전부).
func count_of(id: String) -> int:
	var total := 0
	for area in [AREA_GENERAL, AREA_EQUIPMENT]:
		for stack in slots(area):
			if stack != null and stack.id == id:
				total += stack.count
	return total


## 그 칸이 이 아이템을 받을 수 있는가. 장비 칸은 **종류가 맞아야** 한다.
func accepts(area: String, index: int, id: String) -> bool:
	if not valid(area, index) or not ItemTypes.exists(id):
		return false
	if area != AREA_EQUIPMENT:
		return true
	return ItemTypes.equip_kind(id) == EQUIPMENT_KINDS[index]


# --- 넣기 (docs/DESIGN.md 「인벤토리 안전」) -------------------------------------

## 뭉치를 **넣을 수 있는 만큼만** 넣는다. 넣은 개수를 돌려주고, **못 넣은 몫은 인자로
## 받은 `stack` 에 그대로 남는다** — 바닥 드롭 줍기 / 제작 수령 / 상자 이전이 전부 이
## 함수 하나를 지나가고, 어느 경로도 아이템을 조용히 없앨 수 없다.
##
## 순서: 먼저 **같은 아이템이 이미 있는 칸**에 쌓고(핫바 쪽부터), 그래도 남으면 빈 칸에
## 새 뭉치를 만든다. 장비 칸에는 자동으로 넣지 않는다 — 장비는 사람이 끌어다 놓는다.
func take_in(stack: RefCounted) -> int:
	if stack == null or stack.is_empty() or not ItemTypes.exists(stack.id):
		return 0
	var added := 0
	for index in general.size():
		if stack.count <= 0:
			break
		var slot: RefCounted = general[index]
		if slot == null or not slot.can_merge(stack):
			continue
		var moved := mini(slot.space_left(), stack.count)
		if moved <= 0:
			continue
		slot.count += moved
		stack.count -= moved
		added += moved
	for index in general.size():
		if stack.count <= 0:
			break
		if general[index] != null:
			continue
		var moved := mini(ItemTypes.max_stack(stack.id), stack.count)
		general[index] = stack.split(moved)
		added += moved
	if added > 0:
		version += 1
	return added


## `take_in` 의 편의 판. **돌려주는 것은 못 넣고 남은 수량이다** — 0 이 아니면 호출한
## 쪽이 남은 것을 처리해야 한다(바닥에 떨어뜨리든, 상자에 두든).
func add(id: String, count: int) -> int:
	var stack := ItemStack.new(id, count)
	take_in(stack)
	return stack.count


# --- 꺼내기 / 옮기기 -----------------------------------------------------------

## 그 칸을 통째로 비우고 그 뭉치를 돌려준다(빈 칸이면 null). 버리기/드롭이 쓴다.
func take_out(area: String, index: int) -> RefCounted:
	var stack := at(area, index)
	if stack == null:
		return null
	slots(area)[index] = null
	version += 1
	return stack


## 한 칸에서 다른 칸으로 옮긴다 — 드래그가 부르는 유일한 함수다.
## 같은 아이템이면 **쌓고**(넘치면 넘친 만큼 원래 칸에 남는다), 다르면 **자리를 바꾼다**.
## 장비 칸의 종류가 안 맞으면 아무것도 하지 않고 false 다.
func move(from_area: String, from_index: int, to_area: String, to_index: int) -> bool:
	if from_area == to_area and from_index == to_index:
		return false
	var source := at(from_area, from_index)
	if source == null:
		return false
	if not accepts(to_area, to_index, source.id):
		return false
	var target := at(to_area, to_index)
	if target != null and target.can_merge(source):
		var moved := mini(target.space_left(), source.count)
		if moved <= 0:
			return false
		target.count += moved
		source.count -= moved
		if source.count <= 0:
			slots(from_area)[from_index] = null
		version += 1
		return true
	# 자리 바꾸기 — 되돌아가는 쪽도 그 칸이 받을 수 있어야 한다(장비 칸 종류).
	if target != null and not accepts(from_area, from_index, target.id):
		return false
	slots(to_area)[to_index] = source
	slots(from_area)[from_index] = target
	version += 1
	return true


# --- 저장 / 불러오기 (슬롯에 캐릭터마다 따로 들어간다) ---------------------------

func to_data() -> Dictionary:
	return {
		KEY_GENERAL: _slots_to_data(AREA_GENERAL),
		KEY_EQUIPMENT: _slots_to_data(AREA_EQUIPMENT),
		KEY_HOTBAR: selected_hotbar,
	}


## 저장된 값을 그대로 얹는다. **모르는 아이템/깨진 칸은 빈 칸이 된다** — 세이브 하나가
## 깨졌다고 캐릭터를 통째로 못 쓰게 만들지 않는다. 읽을 게 하나도 없으면 false.
func from_data(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = data
	var ok := _slots_from_data(AREA_GENERAL, dict.get(KEY_GENERAL, []))
	ok = _slots_from_data(AREA_EQUIPMENT, dict.get(KEY_EQUIPMENT, [])) or ok
	selected_hotbar = clampi(int(dict.get(KEY_HOTBAR, 0)), 0, HOTBAR_SLOTS - 1)
	version += 1
	return ok


func _slots_to_data(area: String) -> Array:
	var out: Array = []
	for stack in slots(area):
		out.append(null if stack == null else stack.to_data())
	return out


func _slots_from_data(area: String, data: Variant) -> bool:
	var target := slots(area)
	for index in target.size():
		target[index] = null
	if typeof(data) != TYPE_ARRAY:
		return false
	var array: Array = data
	var loaded := 0
	for index in mini(array.size(), target.size()):
		var stack := ItemStack.from_data(array[index])
		# 장비 칸에 종류가 안 맞는 것이 저장돼 있으면 버리지 않고 일반 칸으로 보낸다.
		if stack == null:
			continue
		if not accepts(area, index, stack.id):
			take_in(stack)
			continue
		target[index] = stack
		loaded += 1
	return loaded > 0
