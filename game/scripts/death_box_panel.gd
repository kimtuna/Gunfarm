extends Control

## 데스드롭 상자 창의 칸 그림 (docs/DESIGN.md 「데스드롭 상자」).
##
## **여기는 그리기와 자리 계산만 한다** — 무엇이 어디로 가는지는 전부
## `death_boxes.gd`(순수 클래스)의 `take()` 가 정한다. 띄우기/마우스는
## `death_box_screen.gd` 다. (`inventory_panel.gd` ↔ `inventory_screen.gd` 와 같은 나눔.)
##
## **칸 그림과 아이템 그림은 인벤토리 창의 것을 그대로 쓴다**
## (`inventory_panel.gd` 의 색 상수와 `draw_item()`) — 같은 아이템이 상자 안과
## 인벤토리 안에서 다르게 보이면 안 된다.

const InventoryPanel := preload("res://scripts/inventory_panel.gd")
const DeathBoxes := preload("res://scripts/death_boxes.gd")

const COLS := 9

## 이 창이 비추는 상자 항목(`death_boxes.gd` 의 items 한 줄). 빈 Dictionary 면 안 그린다.
var box: Dictionary = {}

## 마우스가 올라간 칸(-1 이면 없음). 창 아래 설명 줄이 이걸 읽는다.
var hovered := -1


func panel_size() -> Vector2:
	var rows := ceili(float(DeathBoxes.SLOT_COUNT) / COLS)
	return Vector2(
		COLS * InventoryPanel.SLOT + (COLS - 1) * InventoryPanel.GAP,
		rows * InventoryPanel.SLOT + (rows - 1) * InventoryPanel.GAP,
	)


## 칸 하나가 이 Control 안에서 차지하는 사각형. **짚는 쪽도 자체 QA 도 여기만 쓴다.**
func slot_rect(index: int) -> Rect2:
	var column := index % COLS
	@warning_ignore("integer_division")
	var row := index / COLS
	return Rect2(
		Vector2(column * (InventoryPanel.SLOT + InventoryPanel.GAP),
				row * (InventoryPanel.SLOT + InventoryPanel.GAP)),
		Vector2(InventoryPanel.SLOT, InventoryPanel.SLOT),
	)


func global_slot_rect(index: int) -> Rect2:
	var rect := slot_rect(index)
	rect.position += global_position
	return rect


## 그 화면 좌표에 있는 칸 번호(-1 이면 없음).
func slot_at(global_point: Vector2) -> int:
	for index in DeathBoxes.SLOT_COUNT:
		if global_slot_rect(index).has_point(global_point):
			return index
	return -1


func stack_at(index: int) -> RefCounted:
	if box.is_empty() or index < 0 or index >= DeathBoxes.SLOT_COUNT:
		return null
	return (box[DeathBoxes.KEY_STACKS] as Array)[index]


func _draw() -> void:
	if box.is_empty():
		return
	var font := get_theme_default_font()
	for index in DeathBoxes.SLOT_COUNT:
		var rect := slot_rect(index)
		draw_rect(rect, InventoryPanel.HOVER_BG if index == hovered else InventoryPanel.SLOT_BG)
		draw_rect(rect, InventoryPanel.SLOT_BORDER, false, 2.0)
		var stack := stack_at(index)
		if stack != null:
			InventoryPanel.draw_item(self, font, rect, stack)
