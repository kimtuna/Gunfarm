extends Node2D

## 월드에 놓인 데스드롭 상자들을 그린다 (docs/DESIGN.md 「데스드롭 상자」).
##
## **이 노드는 `death_boxes.gd`(순수 클래스)가 들고 있는 목록을 비추기만 한다** —
## 어디에 무엇이 얼마나 남았는지는 전부 그쪽이 정한다(「시뮬레이션 구조」/「서버 권위」).
##
## **Y정렬**: `ground_items_view.gd` 와 같은 자리(`Entities`)에 같은 이유로 들어간다 —
## 상자마다 노드가 하나씩 있어야 플레이어와 한 묶음으로 앞뒤가 갈린다. 이 묶음 안에서
## `z_index` 는 안 먹으니 쓰지 않는다 (docs/GOTCHAS.md).

const DeathBoxNode := preload("res://scripts/death_box_node.gd")
const DeathBoxes := preload("res://scripts/death_boxes.gd")

var boxes: RefCounted = null

var _version := -1


func setup(new_boxes: RefCounted) -> void:
	boxes = new_boxes
	_version = -1
	_sync()


## **남은 시간 막대는 매 프레임 흐르므로** 목록 버전만 보고 있으면 안 된다 — 노드마다
## 지금 값을 넘겨주고, 실제로 다시 그릴지는 그 노드가 정한다(막대 길이가 눈에 띄게
## 달라졌을 때만 다시 그린다).
func _process(_delta: float) -> void:
	if boxes == null:
		return
	if boxes.version != _version:
		_sync()
		return
	for index in get_child_count():
		var node: Variant = get_child(index)
		node.show_box(boxes.items[index])


## 상자 노드 개수를 목록에 맞춘다. **매번 지웠다 다시 만들지 않는다** — 하나가
## 사라졌다고 나머지가 전부 깜빡이면 안 된다 (`ground_items_view.gd` 와 같은 규칙).
func _sync() -> void:
	if boxes == null:
		return
	_version = boxes.version
	var need: int = boxes.items.size()
	while get_child_count() < need:
		add_child(DeathBoxNode.new() as Node)
	while get_child_count() > need:
		var extra := get_child(get_child_count() - 1)
		remove_child(extra)
		extra.queue_free()
	for index in need:
		# 스크립트만 있고 `class_name` 이 없는 노드라 동적 호출이어야 한다
		# (`ground_items_view.gd` 의 같은 자리 주석 참고).
		var node: Variant = get_child(index)
		node.show_box(boxes.items[index])
