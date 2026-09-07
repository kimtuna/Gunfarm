extends Node2D

## 바닥에 놓인 아이템들을 그린다 (docs/DESIGN.md 「아이템 획득 방식 — 바닥 드롭」).
##
## **이 노드는 `ground_items.gd`(순수 클래스)가 들고 있는 목록을 비추기만 한다** —
## 무엇이 어디에 놓였는지, 언제 주워지는지는 전부 그쪽이 정한다(DESIGN.md
## 「시뮬레이션 구조」/「서버 권위」). 여기서 목록을 고치면 안 된다.
##
## **Y정렬**: 이 노드도, 이 노드를 담은 `Entities` 도 `y_sort_enabled` 라 아이템
## 노드들과 플레이어가 **한 묶음으로** 앞뒤가 갈린다. 그래서 아이템 노드마다 노드가
## 하나씩 있다(`ground_item_node.gd`). 이 묶음 안에서는 `z_index` 가 안 먹으니
## (docs/GOTCHAS.md) 쓰지 않는다.

const GroundItemNode := preload("res://scripts/ground_item_node.gd")
const GroundItems := preload("res://scripts/ground_items.gd")

var ground: RefCounted = null

## 마지막으로 그린 목록 버전. 바뀌었을 때만 노드를 다시 맞춘다.
var _version := -1


func setup(new_ground: RefCounted) -> void:
	ground = new_ground
	_version = -1
	_sync()


func _process(_delta: float) -> void:
	if ground != null and ground.version != _version:
		_sync()


## 아이템 노드 개수를 목록에 맞추고 각 노드에 무엇을 어디에 그릴지 알려준다.
## **노드를 매번 지웠다 다시 만들지 않는다** — 하나 주웠다고 나머지가 전부 깜빡이면 안 된다.
func _sync() -> void:
	if ground == null:
		return
	_version = ground.version
	var need: int = ground.items.size()
	while get_child_count() < need:
		add_child(GroundItemNode.new() as Node)
	while get_child_count() > need:
		var extra := get_child(get_child_count() - 1)
		remove_child(extra)
		extra.queue_free()
	for index in need:
		var entry: Dictionary = ground.items[index]
		# 정적 타입이 붙은 변수로 받으면 "그 타입에 show_stack 이 없다"고 파싱에서 막힌다 —
		# 스크립트만 있고 `class_name` 이 없는 노드라 여기는 동적 호출이어야 한다.
		var node: Variant = get_child(index)
		node.show_stack(entry[GroundItems.KEY_STACK], entry[GroundItems.KEY_POSITION])
