extends Control

## 인벤토리 창의 칸 그림 (docs/DESIGN.md 「인벤토리 / 장비」).
##
## **여기는 그리기와 자리 계산만 한다** — 무엇이 어디로 옮겨지는지는 전부
## `inventory.gd`(순수 클래스)가 정한다. 띄우기/키/드래그는 `inventory_screen.gd` 다.
##
## 칸의 자리는 **이 파일 한 곳에서만** 나온다(`slot_rect`). 드래그가 "어느 칸에
## 놓았는가"를 물을 때도, 자체 QA 가 "그 칸이 화면 어디인가"를 물을 때도 같은 함수를
## 부르므로 배치를 바꿔도 어긋날 데가 없다 — `map_canvas.gd` 의 `map_rect()` 와 같은 방식.
##
## **화면 아래 핫바도 이 스크립트다**(2026-09-07, INBOX #25) — `hotbar_only` 를 켜면
## 인벤토리 맨 위 9칸만 한 줄로 그린다. **별도 보관함이 아니라 같은 코어를 비추는
## 것이라** 창에서 1번 칸을 바꾸면 하단 핫바도 같이 바뀐다(둘 다 `inventory.version`
## 을 보고 다시 그린다). 칸 그림·아이콘·번호·고른 칸 표시가 **같은 코드**라 두 곳이
## 어긋날 수가 없다.

const ItemTypes := preload("res://scripts/item_types.gd")
const Inventory := preload("res://scripts/inventory.gd")

## 칸 하나의 크기와 사이 간격(화면 px).
const SLOT := 56.0
const GAP := 8.0
## 무리 제목("장비" / "소지품")이 차지하는 높이.
const CAPTION_H := 24.0
## 장비 무리와 일반 무리 사이.
const SECTION_GAP := 40.0

const EQUIP_COLS := 3
const GENERAL_COLS := 9

## 칸 색. 어두운 창 안에서 빈 칸과 찬 칸이 구별돼야 한다.
const SLOT_BG := Color(0.086, 0.098, 0.078)
const SLOT_BORDER := Color(0.278, 0.310, 0.243)
## 핫바(맨 위 9칸)는 테두리가 다르다 — **별도 UI 가 아니라 인벤토리의 일부**라는 것이
## 한눈에 보여야 한다 (docs/DESIGN.md 「인벤토리 / 장비」).
const HOTBAR_BORDER := Color(0.478, 0.427, 0.278)
## 지금 손에 든 칸. 자체 QA 가 이 색으로 "숫자키가 먹었는지"를 화면에서 판정한다.
const SELECTED_BORDER := Color(0.976, 0.882, 0.522)
const HOVER_BG := Color(0.153, 0.180, 0.133)

const CAPTION_COLOR := Color(0.851, 0.761, 0.478)
const EMPTY_KIND_COLOR := Color(0.353, 0.376, 0.325)
const COUNT_COLOR := Color(0.965, 0.949, 0.898)
const COUNT_SHADOW := Color(0.039, 0.045, 0.035)
const INDEX_COLOR := Color(0.604, 0.627, 0.561)

const CAPTION_FONT_SIZE := 18
const NAME_FONT_SIZE := 19
const COUNT_FONT_SIZE := 17
const INDEX_FONT_SIZE := 14

## 아이템 자리표시가 칸 안에서 남기는 여백.
const ITEM_INSET := 8.0

var inventory: RefCounted = null

## 하단 핫바 모드 — 일반 칸 맨 위 9칸만 한 줄로 그린다(장비 칸도 제목도 없다).
var hotbar_only := false

## 지금 끌고 있는 칸({"area","index"}, 없으면 빈 Dictionary). 끌려나간 칸은 흐리게 그린다.
var drag_from: Dictionary = {}

## 마우스가 올라간 칸. 창 아래 설명 줄이 이걸 읽는다.
var hovered: Dictionary = {}

var _drawn_version := -1


func setup(new_inventory: RefCounted, only_hotbar: bool = false) -> void:
	inventory = new_inventory
	hotbar_only = only_hotbar
	custom_minimum_size = panel_size()
	_drawn_version = -1
	queue_redraw()


func panel_size() -> Vector2:
	if hotbar_only:
		return Vector2(Inventory.HOTBAR_SLOTS * SLOT + (Inventory.HOTBAR_SLOTS - 1) * GAP, SLOT)
	var equip_w := EQUIP_COLS * SLOT + (EQUIP_COLS - 1) * GAP
	var general_w := GENERAL_COLS * SLOT + (GENERAL_COLS - 1) * GAP
	var rows := ceili(float(Inventory.EQUIPMENT_SLOTS) / EQUIP_COLS)
	return Vector2(equip_w + SECTION_GAP + general_w, CAPTION_H + rows * SLOT + (rows - 1) * GAP)


func _process(_delta: float) -> void:
	if inventory != null and inventory.version != _drawn_version:
		queue_redraw()


# --- 자리 계산 (드래그도 자체 QA 도 이 두 함수만 쓴다) --------------------------

## 칸 하나가 이 Control 안에서 차지하는 사각형.
func slot_rect(area: String, index: int) -> Rect2:
	if hotbar_only:
		# 핫바는 일반 칸 맨 위 9칸뿐이다 — 나머지는 그리지도, 짚히지도 않는다.
		if area != Inventory.AREA_GENERAL or index >= Inventory.HOTBAR_SLOTS:
			return Rect2()
		return Rect2(Vector2(index * (SLOT + GAP), 0.0), Vector2(SLOT, SLOT))
	var cols := EQUIP_COLS if area == Inventory.AREA_EQUIPMENT else GENERAL_COLS
	var origin := Vector2(0.0, CAPTION_H)
	if area != Inventory.AREA_EQUIPMENT:
		origin.x = EQUIP_COLS * SLOT + (EQUIP_COLS - 1) * GAP + SECTION_GAP
	var column := index % cols
	@warning_ignore("integer_division")
	var row := index / cols
	return Rect2(origin + Vector2(column * (SLOT + GAP), row * (SLOT + GAP)), Vector2(SLOT, SLOT))


## 화면(뷰포트) 좌표로 본 칸. 창을 옮겨도 여기 하나만 보면 된다.
func global_slot_rect(area: String, index: int) -> Rect2:
	var rect := slot_rect(area, index)
	rect.position += global_position
	return rect


## 그 화면 좌표에 있는 칸({"area","index"}). 칸이 없으면 빈 Dictionary.
func slot_at(global_point: Vector2) -> Dictionary:
	if inventory == null:
		return {}
	if hotbar_only:
		for index in Inventory.HOTBAR_SLOTS:
			if global_slot_rect(Inventory.AREA_GENERAL, index).has_point(global_point):
				return {"area": Inventory.AREA_GENERAL, "index": index}
		return {}
	for area in [Inventory.AREA_GENERAL, Inventory.AREA_EQUIPMENT]:
		for index in inventory.slot_count(area):
			if global_slot_rect(area, index).has_point(global_point):
				return {"area": area, "index": index}
	return {}


# --- 그리기 -------------------------------------------------------------------

func _draw() -> void:
	if inventory == null:
		return
	_drawn_version = inventory.version
	var font := get_theme_default_font()
	if hotbar_only:
		for index in Inventory.HOTBAR_SLOTS:
			_draw_slot(font, Inventory.AREA_GENERAL, index)
		return
	_draw_caption(font, Vector2(0.0, 0.0), "장비")
	_draw_caption(font, Vector2(slot_rect(Inventory.AREA_GENERAL, 0).position.x, 0.0), "소지품")
	for index in inventory.slot_count(Inventory.AREA_EQUIPMENT):
		_draw_slot(font, Inventory.AREA_EQUIPMENT, index)
	for index in inventory.slot_count(Inventory.AREA_GENERAL):
		_draw_slot(font, Inventory.AREA_GENERAL, index)


func _draw_caption(font: Font, at: Vector2, text: String) -> void:
	draw_string(font, at + Vector2(2.0, CAPTION_FONT_SIZE), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_FONT_SIZE, CAPTION_COLOR)


func _draw_slot(font: Font, area: String, index: int) -> void:
	var rect := slot_rect(area, index)
	var is_hotbar := area == Inventory.AREA_GENERAL and index < Inventory.HOTBAR_SLOTS
	var selected: bool = is_hotbar and index == inventory.selected_hotbar
	var same: bool = hovered.get("area", "") == area and hovered.get("index", -1) == index
	draw_rect(rect, HOVER_BG if same else SLOT_BG)
	var border := SLOT_BORDER
	var width := 2.0
	if selected:
		border = SELECTED_BORDER
		width = 3.0
	elif is_hotbar:
		border = HOTBAR_BORDER
	draw_rect(rect, border, false, width)

	var stack: RefCounted = inventory.at(area, index)
	if stack != null:
		var dragging: bool = drag_from.get("area", "") == area and drag_from.get("index", -1) == index
		draw_item(self, font, rect, stack, 0.30 if dragging else 1.0)
	elif area == Inventory.AREA_EQUIPMENT:
		# 빈 장비 칸에는 무엇이 들어가는 자리인지 적어둔다(모자/반지 …).
		var kind: String = Inventory.EQUIPMENT_KINDS[index]
		_draw_centered(font, rect, String(ItemTypes.EQUIP_NAMES.get(kind, kind)),
				CAPTION_FONT_SIZE, EMPTY_KIND_COLOR)

	if is_hotbar:
		# 숫자키 1~9 가 이 칸이라는 표시. **아이템 다음에** 그린다 — 칸이 56px 이라
		# 아이템을 피해 놓을 자리가 없어서 위에 겹쳐야 하고, 먼저 그리면 아이템이 덮는다.
		# 어두운 그림자를 깔아 어떤 아이템 색 위에서도 읽히게 한다(수량 숫자와 같은 방식).
		var at := rect.position + Vector2(4.0, INDEX_FONT_SIZE + 1.0)
		draw_string(font, at + Vector2(1.0, 1.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, INDEX_FONT_SIZE, COUNT_SHADOW)
		draw_string(font, at, str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				INDEX_FONT_SIZE, INDEX_COLOR)


## 칸 하나에 아이템 하나. **아이콘 그림이 있으면 그걸 그리고**, 없으면 아이템 색으로
## 칠한 자리표시(밝은 띠 + 그림자 + 어두운 테두리)를 그린다 — 도구가 하나씩 그려지는
## 동안 두 가지가 섞여 있게 된다(`item_types.gd` 의 `icon`).
##
## **그리는 대상(`canvas`)을 인자로 받는 `static` 함수다** — 칸 안에 그릴 때는 이
## Control 이고, 끌고 있는 동안 마우스를 따라다니는 그림은 창 위를 덮는 다른 노드이며,
## **데스드롭 상자 창의 칸**(`death_box_panel.gd`)도 이 함수를 그대로 부른다. 같은
## 아이템이 창 안팎에서 다르게 보일 자리가 없다.
static func draw_item(canvas: CanvasItem, font: Font, slot: Rect2, stack: RefCounted, alpha: float = 1.0) -> void:
	var rect := slot.grow(-ITEM_INSET)
	var icon := ItemTypes.icon_of(stack.id)
	if icon != null:
		_draw_icon(canvas, icon, slot, alpha)
	else:
		_draw_placeholder(canvas, font, rect, stack, alpha)
	if stack.count > 1:
		var text := str(stack.count)
		var at := slot.position + slot.size - Vector2(6.0, 5.0)
		at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, COUNT_FONT_SIZE).x
		canvas.draw_string(font, at + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				COUNT_FONT_SIZE, Color(COUNT_SHADOW, alpha))
		canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				COUNT_FONT_SIZE, Color(COUNT_COLOR, alpha))


## 아이콘 그림 한 장을 칸 가운데에 그린다.
##
## **배율은 정수여야 한다**(`docs/STYLE_GUIDE.md` 1번) — 소수 배율로 늘리면 아트
## 픽셀 하나가 화면에서 2px, 3px 로 들쭉날쭉해져 도트가 뭉개진다. 칸(56px)에
## 들어가는 가장 큰 정수 배율을 쓰고, **자리도 정수로 반올림**한다(반 픽셀에
## 놓으면 같은 일이 벌어진다).
static func _draw_icon(canvas: CanvasItem, icon: Texture2D, slot: Rect2, alpha: float) -> void:
	var art := Vector2(icon.get_size())
	var zoom := maxi(1, int(floor(minf(slot.size.x / art.x, slot.size.y / art.y))))
	var size := art * float(zoom)
	var at := (slot.position + (slot.size - size) * 0.5).round()
	canvas.draw_texture_rect(icon, Rect2(at, size), false, Color(1.0, 1.0, 1.0, alpha))


## 아이콘이 아직 없는 아이템의 자리표시 — 아이템 색으로 칠한 사각형 위에 밝은
## 띠(빛)와 아래 그림자, 어두운 테두리를 넣어 도트 그림들과 같은 결로 보이게 한다.
static func _draw_placeholder(canvas: CanvasItem, font: Font, rect: Rect2, stack: RefCounted,
		alpha: float) -> void:
	var base: Color = ItemTypes.color_of(stack.id)
	canvas.draw_rect(rect, Color(base, alpha))
	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)),
			Color(base.lightened(0.25), alpha))
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - 4.0), Vector2(rect.size.x, 4.0)),
			Color(base.darkened(0.35), alpha))
	canvas.draw_rect(rect, Color(base.darkened(0.6), alpha), false, 2.0)
	# 글자는 바탕 밝기에 따라 검거나 희게 — 어느 아이템 색에서도 읽혀야 한다.
	var ink := Color(0.06, 0.07, 0.05) if base.get_luminance() > 0.42 else Color(0.95, 0.95, 0.92)
	_string_centered(canvas, font, rect, ItemTypes.short_name(stack.id), NAME_FONT_SIZE,
			Color(ink, alpha))


## 끌고 있는 아이템을 마우스 자리에 그린다 — 창 위에 떠 있어야 하므로 이 Control 이
## 아니라 화면 전체를 덮는 노드(`inventory_screen.gd`)가 자기 캔버스를 넘겨 부른다.
func draw_floating(canvas: CanvasItem, stack: RefCounted, at: Vector2) -> void:
	var rect := Rect2(at - Vector2(SLOT, SLOT) * 0.5, Vector2(SLOT, SLOT))
	canvas.draw_rect(rect, Color(SLOT_BG, 0.85))
	canvas.draw_rect(rect, SELECTED_BORDER, false, 2.0)
	draw_item(canvas, get_theme_default_font(), rect, stack)


func _draw_centered(font: Font, rect: Rect2, text: String, font_size: int, color: Color) -> void:
	_string_centered(self, font, rect, text, font_size, color)


static func _string_centered(canvas: CanvasItem, font: Font, rect: Rect2, text: String,
		font_size: int, color: Color) -> void:
	var size_of := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var at := rect.position + (rect.size - Vector2(size_of.x, 0.0)) * 0.5
	at.y = rect.position.y + (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
