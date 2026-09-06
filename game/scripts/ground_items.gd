extends RefCounted

## 바닥에 놓인 아이템 (docs/DESIGN.md 「아이템 획득 방식 — 바닥 드롭」).
##
## **이번 바퀴(INBOX #23)는 데이터까지만이다** — 인벤토리 창 밖으로 끌어다 버린 아이템이
## "월드의 이 자리에 놓였다"는 사실만 여기 쌓인다. 그림과 줍기는 바닥 드롭을 실제로
## 만드는 다음 바퀴가 이 자리에 붙인다(그래서 클래스를 지금 만들어 자리를 남겨둔다).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) — 나중에
## 서버가 "무엇이 어디에 떨어져 있는가"를 화면 없이 들고 있어야 하기 때문이다.
##
## **줍기를 붙일 때 지킬 것**: 인벤토리에 넣는 것은 `inventory.gd` 의 `take_in(뭉치)` 로
## 하고, **다 못 들어가면 그 뭉치를 여기서 지우지 않는다** — 「인벤토리 안전」 그대로다.

## 바닥에 놓인 것 하나. `stack` 은 `item_stack.gd` 이고 `position` 은 월드 좌표다.
var items: Array[Dictionary] = []


## 한 뭉치를 그 자리에 놓는다. 놓인 항목을 돌려준다(빈 뭉치면 null — 아무것도 안 놓는다).
func drop(stack: RefCounted, world_position: Vector2) -> Variant:
	if stack == null or stack.is_empty():
		return null
	var entry := {"stack": stack, "position": world_position}
	items.append(entry)
	return entry


func size() -> int:
	return items.size()


## 그 자리 근처에 놓인 것들(줍기가 쓸 자리 — 지금은 자체 QA 만 부른다).
func near(world_position: Vector2, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in items:
		if (entry["position"] as Vector2).distance_to(world_position) <= radius:
			out.append(entry)
	return out
