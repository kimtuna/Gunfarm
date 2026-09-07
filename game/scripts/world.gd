extends Node2D

## 월드 입장 — 시드 기반 절차적 지형과 스폰 지점 (docs/DESIGN.md "월드 생성").
##
## 슬롯에 저장된 `world_seed` 로 월드를 만든다. **같은 시드는 항상 같은 월드**여야 하므로
## 생성 자체는 scripts/world_gen.gd(노드를 상속하지 않는 순수 클래스)가 맡고, 여기서는
## 그 결과를 화면에 올리고 플레이어를 스폰 지점에 세우기만 한다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const ExploredMap := preload("res://scripts/explored_map.gd")
const Inventory := preload("res://scripts/inventory.gd")
const GroundItems := preload("res://scripts/ground_items.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_SCENE := preload("res://scenes/settings.tscn")
const MAP_SCENE := preload("res://scenes/map_screen.tscn")
const INVENTORY_SCENE := preload("res://scenes/inventory_screen.tscn")

## 처음 들어오는 캐릭터에게 넣어주는 것 (docs/DESIGN.md 「도구 등급」의 "게임 시작 시
## 공짜로 지급하는 기본 도구" + 창을 돌려보기 위한 **테스트용 아이템**).
## **아이템을 실제로 얻는 경로(채집/드롭/제작)는 아직 없다** — 그걸 만드는 바퀴가
## 붙는다(INBOX #23 범위 밖). 그때까지 이 목록이 「테스트용 저장 상자 자동 보급」의
## 자리를 대신한다(상자 자체가 아직 없다).
const STARTER_ITEMS := [
	["gun", 1], ["axe", 1], ["pickaxe", 1], ["sickle", 1], ["hoe", 1],
	["watering_can", 1], ["fishing_rod", 1], ["wood", 64], ["stone", 48],
	["iron_ore", 24], ["sulfur_ore", 12], ["plank", 30], ["iron", 8],
	["charcoal", 16], ["gunpowder", 6], ["rice", 20], ["meat", 9], ["bag", 1],
]

## 걸어다니면서 "가봤음"으로 적히는 반경(타일). 화면 세로 절반이 7.5칸이라 그보다 살짝
## 작게 잡았다 — 실제로 화면에서 본 만큼만 남는다 (docs/DESIGN.md 「맵 (M)」).
const EXPLORE_RADIUS_TILES := 6

## 탐험 기록을 슬롯에 적는 간격(초). 매번 적으면 한 칸 걸을 때마다 파일을 쓴다.
const EXPLORED_SAVE_SECONDS := 3.0

var world: RefCounted = null

## 이 캐릭터가 가본 곳(`explored_map.gd`). 슬롯에서 읽어 오고, 걸어다니면 여기 쌓인다.
var explored: RefCounted = null

## 이 캐릭터의 인벤토리(`inventory.gd` — 순수 클래스). 탐험 기록과 같이 슬롯에 저장된다.
var inventory: RefCounted = null

## 바닥에 놓인 아이템(`ground_items.gd` — 순수 클래스). 버린 것이 여기 쌓이고,
## 다가가면 자동으로 인벤토리로 간다. 그리는 것은 `%GroundItemsView` 가 한다
## (docs/DESIGN.md 「아이템 획득 방식 — 바닥 드롭」).
var ground_items: RefCounted = null

## 일시정지 메뉴에서 띄운 설정 화면. 씬을 바꾸지 않고 **월드 위에 겹쳐서** 띄운다 —
## 씬을 바꾸면 월드가 통째로 내려가므로 "월드는 멈추지 않는다"가 성립하지 않는다.
var _settings_overlay: Control = null

## M 으로 연 전체 맵. 설정과 같은 자리(HUD)에 겹쳐 붙는다.
var _map_overlay: Control = null

## E 로 연 인벤토리 창. 지도와 같은 자리, 같은 규칙이다.
var _inventory_overlay: Control = null

var _slot_index := -1
var _explored_dirty := false
var _inventory_dirty := false
var _ground_dirty := false
## 마지막으로 슬롯에 적은 인벤토리 버전 — 바뀐 게 없으면 파일을 다시 쓰지 않는다.
var _saved_inventory_version := -1
var _explored_save_left := EXPLORED_SAVE_SECONDS
## 마지막으로 주변을 기록한 칸. 같은 칸에 서 있는 동안은 다시 훑지 않는다.
var _marked_tile := Vector2i(-1, -1)


func _ready() -> void:
	var index := SlotStore.selected_slot
	_slot_index = index
	var character_name := "이름 없는 캐릭터"
	var seed_value := 0
	# 슬롯을 안 거치고 이 씬을 직접 띄운 경우(자체 QA)에는 빈 외형 = 기본 외형이다.
	var appearance: Dictionary = {}
	if index >= 0:
		var slots := SlotStore.load_slots()
		var slot := slots[index]
		character_name = String(slot.get("name", character_name))
		seed_value = int(slot.get("world_seed", 0))
		var stored: Variant = slot.get("appearance", {})
		if typeof(stored) == TYPE_DICTIONARY:
			appearance = stored
		# 시드가 아직 없는(옛 형식으로 저장된) 캐릭터는 지금 한 번 정해서 슬롯에 박아둔다 —
		# 다음에 다시 들어와도 같은 월드가 나와야 하기 때문이다.
		if seed_value == 0:
			seed_value = SlotStore.new_world_seed()
			slot["world_seed"] = seed_value
			slots[index] = slot
			SlotStore.save_slots(slots)

	world = WorldGen.new()
	world.build(seed_value)

	# 탐험 기록은 캐릭터에 붙는다 — 슬롯을 안 거치고 들어온 경우(자체 QA)에는 빈 지도로
	# 시작하고 저장하지 않는다. 읽지 못하는 기록이어도 빈 지도로 계속 간다.
	explored = ExploredMap.new()
	if index >= 0:
		explored.load_base64(SlotStore.explored_of(SlotStore.load_slots()[index]))

	# 인벤토리도 캐릭터에 붙는다(슬롯 저장). **저장된 적이 없는 캐릭터에게만** 기본
	# 도구를 지급한다 — "다 버려서 비어 있는 인벤토리"와 구별해야 하기 때문이다.
	inventory = Inventory.new()
	ground_items = GroundItems.new()
	var stored_inventory: Variant = null
	if index >= 0:
		var slot := SlotStore.load_slots()[index]
		stored_inventory = SlotStore.inventory_of(slot)
		# 바닥에 놓인 것도 슬롯에서 되살린다 — 나갔다 들어와도 버린 자리에 그대로
		# 있어야 한다 (docs/DESIGN.md 「바닥 드롭」의 "바닥 아이템은 저장된다").
		ground_items.from_data(SlotStore.ground_of(slot))
	if stored_inventory == null:
		_give_starter_items()
	else:
		inventory.from_data(stored_inventory)

	(%TerrainView as Node2D).set_world(world)
	(%GroundItemsView as Node2D).setup(ground_items)
	# 화면 아래 핫바는 **인벤토리 맨 위 9칸을 그대로 비추는 것**이지 별도 보관함이
	# 아니다 (docs/DESIGN.md 「인벤토리 / 장비」) — 그래서 E 창과 **같은 코어**를 넘긴다.
	# 그리는 코드도 창과 같은 스크립트다(`inventory_panel.gd` 의 `hotbar_only`).
	(%HotbarPanel as Control).setup(inventory, true)
	# 플레이어도 인벤토리를 본다 — **든 칸에 무엇이 있는가**가 어느 모션을 그릴지
	# 정하기 때문이다 (docs/DESIGN.md 「캐릭터 애니메이션」).
	(%Player as Node2D).inventory = inventory
	# 슬롯에 저장된 외형을 그대로 입힌다 — 커스터마이징 화면에서 고른 색·머리모양이
	# 월드에서도 같아야 한다. 칠하는 일은 `character_sprite.gd`(팔레트 교체)가 한다.
	(%Player as Node2D).appearance = appearance
	# 플레이어를 스폰 칸에 세운다. 카메라는 플레이어의 자식이라 따로 따라다니게 만들
	# 코드가 없다 — 확대/축소도 하지 않는다(보이는 월드 범위는 모든 해상도에서 고정,
	# docs/DESIGN.md "카메라 / 해상도" PvP 공정성 규칙).
	(%Player as Node2D).setup(world, world.spawn_tile)

	(%WhoLabel as Label).text = character_name
	(%InfoLabel as Label).text = "시드 %d   ·   스폰 (%d, %d)   ·   지도 %d×%d칸   ·   바다 %d%%" % [
		seed_value, world.spawn_tile.x, world.spawn_tile.y,
		WorldGen.MAP_TILES, WorldGen.MAP_TILES, roundi(world.sea_ratio() * 100.0),
	]


## 처음 들어오는 캐릭터에게 기본 도구 + 테스트용 아이템을 넣는다.
## **넣기는 언제나 `add()` 를 지나간다** — 자리가 모자라면 남는 수량이 돌아오고,
## 그것을 그냥 버리지 않고 경고로 남긴다 (docs/DESIGN.md 「인벤토리 안전」).
func _give_starter_items() -> void:
	for entry: Array in STARTER_ITEMS:
		var left: int = inventory.add(String(entry[0]), int(entry[1]))
		if left > 0:
			push_warning("기본 지급 %s %d개가 인벤토리에 안 들어갔다" % [entry[0], left])
	_inventory_dirty = true


# --- 탐험 기록 (docs/DESIGN.md 「맵 (M)」) -------------------------------------
#
# 플레이어가 선 칸이 바뀔 때마다 그 주변 **반경**을 "가봤음"으로 적는다. 시야 콘이
# 아니라 반경인 이유는 DESIGN.md 에 있다 — 콘이면 제자리에서 마우스를 돌리는 것만으로
# 지도가 채워진다.

func _process(delta: float) -> void:
	_update_ground_items()
	var tile: Vector2i = (%Player as Node2D).tile()
	if tile != _marked_tile:
		_marked_tile = tile
		if explored.mark_around(tile, EXPLORE_RADIUS_TILES) > 0:
			_explored_dirty = true
	_explored_save_left -= delta
	if _explored_save_left <= 0.0:
		_explored_save_left = EXPLORED_SAVE_SECONDS
		_save_explored()
		_save_inventory()
		_save_ground()


## 바닥에 놓인 것 훑기 — 줍기 / 잠금 풀기 / 수명 다한 것 치우기.
## **프레임 시간을 안 넘긴다** — 코어가 위치와 벽시계만 보므로 프레임 레이트와 무관하게
## 결과가 같다 (`ground_items.gd` 의 `update` 주석).
func _update_ground_items() -> void:
	if ground_items == null:
		return
	if ground_items.update((%Player as Node2D).global_position, inventory) > 0:
		_inventory_dirty = true
		_ground_dirty = true


## 씬이 내려갈 때(메인 메뉴로 나가기, 종료) 마지막으로 한 번 더 적는다 —
## 위 주기 저장만 있으면 마지막 몇 초가 날아간다.
func _exit_tree() -> void:
	_save_explored()
	_save_inventory()
	_save_ground()


func _save_explored() -> void:
	if not _explored_dirty or _slot_index < 0 or explored == null:
		return
	if SlotStore.save_explored(_slot_index, explored.to_base64()):
		_explored_dirty = false


## 인벤토리도 같은 규칙으로 슬롯에 적는다(캐릭터마다 따로).
func _save_inventory() -> void:
	if _slot_index < 0 or inventory == null:
		return
	if not _inventory_dirty and inventory.version == _saved_inventory_version:
		return
	if SlotStore.save_inventory(_slot_index, inventory.to_data()):
		_inventory_dirty = false
		_saved_inventory_version = inventory.version


## 바닥에 놓인 것도 같은 규칙으로 슬롯에 적는다.
func _save_ground() -> void:
	if _slot_index < 0 or ground_items == null or not _ground_dirty:
		return
	if SlotStore.save_ground(_slot_index, ground_items.to_data()):
		_ground_dirty = false


# --- 일시정지 메뉴 (docs/DESIGN.md 「조작」의 Esc 항목) -------------------------
#
# **월드 시뮬레이션을 멈추지 않는다** — `get_tree().paused` 를 쓰지 않는다. 멀티플레이에서
# 한 사람이 Esc 를 눌렀다고 세계가 멈출 수는 없기 때문이다. 대신 메뉴가 열려 있는 동안
# 플레이어의 **입력만 끊는다**(`player.gd` 의 `input_enabled`) — 시간을 멈추는 게 아니라
# 조작을 안 받는 것이다. 조준 각도는 0 으로 만들지 않고 보던 각도를 유지한다(0 으로 넣으면
# 메뉴를 열 때마다 캐릭터가 오른쪽으로 홱 돈다).

func _menu_open() -> bool:
	return _settings_overlay != null or _map_overlay != null or _inventory_overlay != null \
			or (%PauseMenu as Control).visible


## 월드 안의 Esc 는 나가는 키가 아니라 일시정지 메뉴다.
## **가장 안쪽 창부터 닫는다** — 설정이 열려 있으면 설정만 닫히고 일시정지 메뉴가 남는다.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		get_viewport().set_input_as_handled()
		_toggle_map()
		return
	if event.is_action_pressed("toggle_inventory"):
		get_viewport().set_input_as_handled()
		_toggle_inventory()
		return
	# 숫자키 1~9 = 핫바에서 손에 들 칸 고르기 (docs/DESIGN.md 「조작」).
	# **인벤토리 창이 열려 있어도 먹는다**(핫바는 그 창의 일부다). 반대로 일시정지/설정이
	# 열려 있으면 안 먹는다 — 그때는 플레이어 조작 자체가 끊긴 상태다.
	if _settings_overlay == null and not (%PauseMenu as Control).visible:
		for index in Inventory.HOTBAR_SLOTS:
			if not event.is_action_pressed("hotbar_%d" % (index + 1)):
				continue
			get_viewport().set_input_as_handled()
			if inventory.select_hotbar(index):
				_inventory_dirty = true
			return
	# 좌클릭 = 지금 손에 든 도구의 동작 (docs/DESIGN.md 「조작」). **창이 하나라도
	# 열려 있으면 안 먹는다** — 인벤토리에서 아이템을 끄는 좌클릭과 부딪힌다(그쪽은
	# 자기 `_input` 에서 먼저 소비하지만, 지도/일시정지/설정은 여기서 막아야 한다).
	# 대상이 없어도(허공에 대고) 모션은 나간다 — 「생활 스킬 — 채집 계열」.
	if event.is_action_pressed("use_tool"):
		if not _menu_open():
			get_viewport().set_input_as_handled()
			(%Player as Node2D).request_use()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _settings_overlay != null:
		_close_settings()
	elif _inventory_overlay != null:
		_close_inventory()
	elif _map_overlay != null:
		_close_map()
	else:
		_set_pause_open(not (%PauseMenu as Control).visible)


func _set_pause_open(open: bool) -> void:
	(%PauseMenu as Control).visible = open
	if open:
		(%ResumeButton as Button).grab_focus()
	_sync_player_input()


## 메뉴가 하나라도 열려 있으면 플레이어는 조작을 받지 않는다.
##
## **하단 핫바도 그때 같이 감춘다**(2026-09-07, INBOX #25 — 고른 쪽을 적어둔다).
## 인벤토리 창은 같은 9칸을 자기 맨 윗줄에 이미 그리고 있어서 두 벌이 겹치고,
## 지도·일시정지는 화면을 어둡게 덮는데 핫바만 그 위에 밝게 남으면 "지금 조작이
## 끊겨 있다"는 신호와 어긋난다.
func _sync_player_input() -> void:
	(%Player as Node2D).input_enabled = not _menu_open()
	(%Hotbar as Control).visible = not _menu_open()


# --- 전체 맵 (docs/DESIGN.md 「맵 (M)」) ---------------------------------------
#
# 설정과 같은 규칙이다: **씬을 바꾸지 않고 HUD 에 겹쳐 붙이고**, 닫는 것은 띄운 이쪽이
# 한다(겹쳐 뜬 화면은 자기 M/Esc 를 처리하지 않는다). 지도가 열려 있는 동안에도 월드는
# 계속 돌고, 끊기는 것은 플레이어 입력뿐이다.

func _toggle_map() -> void:
	if _map_overlay != null:
		_close_map()
		return
	# 더 안쪽 창이 열려 있으면 M 은 아무 일도 하지 않는다 — 창을 겹겹이 쌓지 않는다.
	if _settings_overlay != null or _inventory_overlay != null or (%PauseMenu as Control).visible:
		return
	var overlay := MAP_SCENE.instantiate() as Control
	overlay.setup(world, explored, %Player as Node2D)
	_map_overlay = overlay
	($HUD as CanvasLayer).add_child(overlay)
	_sync_player_input()


func _close_map() -> void:
	if _map_overlay == null:
		return
	_map_overlay.queue_free()
	_map_overlay = null
	_sync_player_input()


# --- 인벤토리 창 (docs/DESIGN.md 「인벤토리 / 장비」) ---------------------------
#
# 지도와 같은 자리(HUD)에 같은 규칙으로 붙는다 — 씬을 바꾸지 않고, 닫는 것은 이쪽이 하고,
# 열려 있는 동안 월드는 계속 돌되 플레이어 입력만 끊긴다.

func _toggle_inventory() -> void:
	if _inventory_overlay != null:
		_close_inventory()
		return
	# 더 안쪽 창이 열려 있으면 E 는 아무 일도 하지 않는다 — 창을 겹겹이 쌓지 않는다.
	if _settings_overlay != null or _map_overlay != null or (%PauseMenu as Control).visible:
		return
	var overlay := INVENTORY_SCENE.instantiate() as Control
	_inventory_overlay = overlay
	($HUD as CanvasLayer).add_child(overlay)
	overlay.setup(inventory)
	overlay.drop_outside.connect(_on_drop_outside)
	_sync_player_input()


func _close_inventory() -> void:
	if _inventory_overlay == null:
		return
	_inventory_overlay.queue_free()
	_inventory_overlay = null
	_sync_player_input()


## 인벤토리 창 **바깥**에 끌어다 놓았다 = 버리기 (docs/DESIGN.md 「인벤토리 / 장비」).
## 인벤토리에서 빠진 뭉치는 **그 자리에서 바닥으로 간다** — 중간에 아무 데도 안 들르므로
## 「인벤토리 안전」대로 사라질 틈이 없다. 놓인 것은 바로 보이고(`%GroundItemsView`),
## **그 자리를 벗어났다 돌아오면** 다시 주워진다(`ground_items.gd` 의 잠금).
func _on_drop_outside(area: String, index: int) -> void:
	var stack: RefCounted = inventory.take_out(area, index)
	if stack == null:
		return
	ground_items.drop(stack, (%Player as Node2D).global_position)
	_inventory_dirty = true
	_ground_dirty = true


func _on_resume_pressed() -> void:
	_set_pause_open(false)


## 메뉴 화면의 설정과 **같은 화면**을 띄운다(docs/DESIGN.md 「조작」). 겹쳐 띄운 것이라
## 그쪽의 Esc 는 메인 메뉴로 가지 않고 자기만 닫는다 — 그 처리는 여기서 한다.
func _on_pause_settings_pressed() -> void:
	if _settings_overlay != null:
		return
	var overlay := SETTINGS_SCENE.instantiate() as Control
	overlay.as_overlay = true
	_settings_overlay = overlay
	# 일시정지 메뉴보다 뒤에 붙으므로 그 위에 그려진다.
	($HUD as CanvasLayer).add_child(overlay)
	_sync_player_input()


func _close_settings() -> void:
	if _settings_overlay == null:
		return
	_settings_overlay.queue_free()
	_settings_overlay = null
	_sync_player_input()
	(%ResumeButton as Button).grab_focus()


func _on_exit_to_main_menu_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
