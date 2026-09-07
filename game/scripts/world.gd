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
const Bullets := preload("res://scripts/bullets.gd")
const DeathBoxes := preload("res://scripts/death_boxes.gd")
const WorldSettings := preload("res://scripts/world_settings.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_SCENE := preload("res://scenes/settings.tscn")
const MAP_SCENE := preload("res://scenes/map_screen.tscn")
const INVENTORY_SCENE := preload("res://scenes/inventory_screen.tscn")
const DEATH_BOX_SCENE := preload("res://scenes/death_box_screen.tscn")
const WORLD_SETTINGS_SCENE := preload("res://scenes/world_settings.tscn")

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

## 총을 든 상태에서만 조준선이 뜨고 좌클릭이 총알을 쏜다 — 그 판정에 쓰는 아이템 id
## (`item_types.gd` 의 열쇠이자 `player_frames.gd` 의 시트 이름과 같은 문자열이다).
const GUN_ITEM := "gun"

## 한 프레임에 몰아서 돌릴 수 있는 최대 총알 틱 수 — `player.gd` 의
## `MAX_TICKS_PER_FRAME` 과 같은 이유·같은 값이다(밀린 시간을 한꺼번에 시뮬레이션하면
## 총알이 순간이동한다).
const MAX_BULLET_TICKS_PER_FRAME := 5

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

## 날아가는 중인 총알(`bullets.gd` — 순수 클래스). **저장하지 않는다** — 0.9초면
## 사라지는 것이라 나갔다 들어왔을 때 되살릴 값이 아니다 (docs/DESIGN.md 「전투」).
var bullets: RefCounted = null

## 월드에 놓인 데스드롭 상자(`death_boxes.gd` — 순수 클래스). 죽으면 여기에 하나
## 생기고 인벤토리가 통째로 들어간다 (docs/DESIGN.md 「데스드롭 상자」).
## 그리는 것은 `%DeathBoxesView` 가 한다.
var death_boxes: RefCounted = null

## 이 월드(슬롯)의 설정(`world_settings.gd` — 순수 클래스). 지금 있는 항목은
## 데스드롭 상자 타이머 하나다 (docs/DESIGN.md 「월드 설정」).
var world_settings: RefCounted = null

## 일시정지 메뉴에서 띄운 설정 화면. 씬을 바꾸지 않고 **월드 위에 겹쳐서** 띄운다 —
## 씬을 바꾸면 월드가 통째로 내려가므로 "월드는 멈추지 않는다"가 성립하지 않는다.
var _settings_overlay: Control = null

## M 으로 연 전체 맵. 설정과 같은 자리(HUD)에 겹쳐 붙는다.
var _map_overlay: Control = null

## E 로 연 인벤토리 창. 지도와 같은 자리, 같은 규칙이다.
var _inventory_overlay: Control = null

## 좌클릭으로 연 데스드롭 상자 창. 같은 자리, 같은 규칙이다.
var _death_box_overlay: Control = null

## 지금 열어둔 상자의 번호(-1 이면 없음). **항목 자체가 아니라 번호로 들고 있는다** —
## 상자는 다 꺼내거나 시간이 다 되면 목록에서 빠지므로, 아직 살아 있는지를 매 프레임
## 물어야 한다.
var _open_box_id := -1

## 일시정지 메뉴에서 띄운 월드 설정 화면.
var _world_settings_overlay: Control = null

var _slot_index := -1
var _explored_dirty := false
var _inventory_dirty := false
var _ground_dirty := false
var _death_boxes_dirty := false
## 총알을 고정 틱으로 돌리는 누적기. 플레이어의 것(`player.gd`)과 따로인 이유는
## 총알이 플레이어의 소유물이 아니라 **월드의 개체**이기 때문이다 — 쏘고 나면 서로
## 무관하게 날아가므로 두 누적기가 한 틱 어긋나도 결과가 달라지지 않는다.
var _bullet_accumulated := 0.0
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
	# 데스드롭 상자와 월드 설정도 이 슬롯의 것이다 (docs/DESIGN.md 「월드 설정」의
	# "월드 설정은 그 월드(슬롯)에 저장된다").
	death_boxes = DeathBoxes.new()
	world_settings = WorldSettings.new()
	var stored_inventory: Variant = null
	if index >= 0:
		var slot := SlotStore.load_slots()[index]
		stored_inventory = SlotStore.inventory_of(slot)
		# 바닥에 놓인 것도 슬롯에서 되살린다 — 나갔다 들어와도 버린 자리에 그대로
		# 있어야 한다 (docs/DESIGN.md 「바닥 드롭」의 "바닥 아이템은 저장된다").
		ground_items.from_data(SlotStore.ground_of(slot))
		world_settings.from_data(SlotStore.world_settings_of(slot))
		# **나가 있는 동안 흐른 시간은 불러오면서 한 번에 깎인다** — 빨리 감는 코드가
		# 따로 없다 (docs/DESIGN.md 「시뮬레이션 구조」).
		death_boxes.from_data(SlotStore.death_boxes_of(slot))
	if stored_inventory == null:
		_give_starter_items()
	else:
		inventory.from_data(stored_inventory)

	(%TerrainView as Node2D).set_world(world)
	(%GroundItemsView as Node2D).setup(ground_items)
	(%DeathBoxesView as Node2D).setup(death_boxes)
	# 총알은 월드가 있어야 지형에 막힐 수 있다 — 여기서 만든다.
	bullets = Bullets.new(world)
	(%BulletsView as Node2D).setup(bullets)
	(%AimLine as Node2D).setup(%Player as Node2D)
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
	# 좌클릭이 총알이 되는 자리 — **무엇을 들었는지 아는 쪽이 여기다**(인벤토리를
	# 가진 쪽이 판정한다, docs/DESIGN.md 「서버 권위」).
	(%Player as Node2D).use_started.connect(_on_player_use_started)
	# R(재장전) / 우클릭(탄종 전환)도 같은 자리에서 받는다 — 셋 다 "총을 들었는가"를
	# 먼저 물어야 하는 입력이라, 그 판정이 한 함수(`_held_item_id`)에 모여 있다.
	(%Player as Node2D).reload_requested.connect(_on_player_reload_requested)
	(%Player as Node2D).ammo_switch_requested.connect(_on_player_ammo_switch_requested)
	# 죽으면 그 자리에 데스드롭 상자가 생긴다 — **상자를 채우는 것은 인벤토리를 아는
	# 이쪽이다**(코어는 인벤토리를 모른다, docs/DESIGN.md 「데스드롭 상자」).
	(%Player as Node2D).died.connect(_on_player_died)
	# 총 UI 는 탄창을 들고 있는 플레이어 코어를 그대로 읽는다 (docs/DESIGN.md 「서버 권위」).
	(%GunHudPanel as Control).setup((%Player as Node2D).motion)

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
	_update_death_boxes()
	_tick_bullets(delta)
	# 조준선과 총 UI 는 **총을 들고 있을 때만** 뜬다 (docs/DESIGN.md 「전투」와
	# 「총기 스탯」의 "탄창에 남은 발수는 총을 들고 있을 때만 화면에 표시한다") —
	# 다른 도구를 들거나 빈손이면 사라지고, 창이 열려 조작이 끊긴 동안에도 감춘다
	# (핫바와 같은 규칙). **판정이 한 줄인 이유**: 둘이 따로 갈리면 총을 내렸을 때
	# 한쪽만 남는다.
	var armed := not _menu_open() and _held_item_id() == GUN_ITEM
	(%AimLine as Node2D).armed = armed
	(%GunHud as Control).visible = armed
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
		_save_death_boxes()


## 바닥에 놓인 것 훑기 — 줍기 / 잠금 풀기 / 수명 다한 것 치우기.
## **프레임 시간을 안 넘긴다** — 코어가 위치와 벽시계만 보므로 프레임 레이트와 무관하게
## 결과가 같다 (`ground_items.gd` 의 `update` 주석).
func _update_ground_items() -> void:
	if ground_items == null:
		return
	if ground_items.update((%Player as Node2D).global_position, inventory) > 0:
		_inventory_dirty = true
		_ground_dirty = true


# --- 데스드롭 상자 (docs/DESIGN.md 「데스드롭 상자」) ---------------------------

## 상자 훑기 — 타이머 흘리기 / 멀어진 상자 닫기 / 다 된 상자 치우기.
## **프레임 시간을 안 넘긴다** — 코어가 벽시계만 보므로 프레임 레이트와 무관하다
## (`ground_items.gd` 와 같은 방식).
##
## 훑고 나서 **열어둔 상자가 아직 살아 있는지** 확인한다: 다 꺼냈거나(빈 상자는
## 사라진다) 멀어져서 닫힌 것으로 넘어갔으면 창도 같이 닫는다.
func _update_death_boxes() -> void:
	if death_boxes == null:
		return
	if death_boxes.update((%Player as Node2D).global_position) > 0:
		_death_boxes_dirty = true
	if _death_box_overlay == null:
		return
	var entry: Variant = death_boxes.by_id(_open_box_id)
	if entry == null or not death_boxes.is_open(entry):
		_close_death_box()


## 죽었다 — **죽은 자리에 상자가 생기고 인벤토리 내용물이 전부 그 안으로 들어간다**
## (docs/DESIGN.md 「체력 / 죽음 / 리스폰」과 「데스드롭 상자」).
##
## **꺼내는 경로는 `inventory.take_out()` 하나뿐이고 그 뭉치가 그대로 상자로 간다** —
## 중간에 아무 데도 안 들르므로 「인벤토리 안전」대로 사라질 틈이 없다(버리기와 같은 모양).
## 장비 칸도 같이 간다: 「인벤토리 / 장비」에서 장비 9칸은 인벤토리의 일부다.
##
## **빈손으로 죽으면 상자를 만들지 않는다**(`death_boxes.gd` 의 `spawn` 이 null 을
## 돌려준다) — 찾아올 것이 없는 상자를 월드에 남기지 않는다.
func _on_player_died(at: Vector2) -> void:
	if death_boxes == null or inventory == null:
		return
	var taken: Array = []
	for area: String in [Inventory.AREA_GENERAL, Inventory.AREA_EQUIPMENT]:
		for index in inventory.slot_count(area):
			var stack: RefCounted = inventory.take_out(area, index)
			if stack != null:
				taken.append(stack)
	# **타이머 길이는 「월드 설정」이 정한다** — 상자가 만들어지는 이 시점의 값을
	# 새겨두므로, 나중에 설정을 바꿔도 이미 놓인 상자는 안 흔들린다.
	if death_boxes.spawn(at, taken, world_settings.death_box_seconds()) != null:
		_death_boxes_dirty = true
	_inventory_dirty = true


## 좌클릭이 상자를 열었는가. **커서가 상자 위에 있고 가까이 서 있어야** 한다
## (`death_boxes.gd` 의 `at_point`). 열었으면 그 좌클릭은 도구로 가지 않는다 —
## 상자 위를 겨눈 좌클릭이 도끼질이 되면 상자를 영영 못 연다.
func _try_open_death_box() -> bool:
	if death_boxes == null:
		return false
	var player := %Player as Node2D
	var entry: Variant = death_boxes.at_point(player.get_global_mouse_position(),
			player.global_position)
	if entry == null:
		return false
	_open_death_box(entry)
	return true


## 상자 창을 연다 — **여는 순간 타이머가 멈춘다**(docs/DESIGN.md 「데스드롭 상자」의
## *"정해진 시간은 「찾아올 시간」이지 「꺼낼 시간」이 아니다"*). 창은 지도/인벤토리와
## 같은 자리(HUD)에 같은 규칙으로 겹쳐 붙는다.
func _open_death_box(entry: Dictionary) -> void:
	if _death_box_overlay != null:
		return
	death_boxes.open(entry)
	_open_box_id = int(entry[DeathBoxes.KEY_ID])
	var overlay := DEATH_BOX_SCENE.instantiate() as Control
	_death_box_overlay = overlay
	($HUD as CanvasLayer).add_child(overlay)
	overlay.setup(death_boxes, entry, inventory)
	_sync_player_input()


## 창을 닫으면 **타이머가 다시 흐른다.**
func _close_death_box() -> void:
	if _death_box_overlay == null:
		return
	var entry: Variant = death_boxes.by_id(_open_box_id)
	if entry != null:
		death_boxes.close(entry)
	_open_box_id = -1
	_death_box_overlay.queue_free()
	_death_box_overlay = null
	_death_boxes_dirty = true
	_inventory_dirty = true
	_sync_player_input()


# --- 총알 (docs/DESIGN.md 「전투」) --------------------------------------------
#
# **총알은 투사체다** — 쏜 순간 판정하고 끝내는 게 아니라 살아 있는 내내 매 틱 날아간다.
# 계산은 전부 `bullets.gd`(순수 클래스)가 하고, 여기서는 고정 틱으로 돌려주기만 한다
# (`player.gd` 가 이동 코어를 돌리는 것과 같은 모양이다).

func _tick_bullets(delta: float) -> void:
	if bullets == null:
		return
	_bullet_accumulated += delta
	var ticks := 0
	while _bullet_accumulated >= Bullets.TICK_DELTA and ticks < MAX_BULLET_TICKS_PER_FRAME:
		_bullet_accumulated -= Bullets.TICK_DELTA
		bullets.tick()
		ticks += 1
	if _bullet_accumulated >= Bullets.TICK_DELTA:
		_bullet_accumulated = 0.0


## 지금 손에 든 칸에 있는 아이템 id. **든 칸은 코어(플레이어 상태)가 들고 있고,
## 그 칸에 무엇이 있는지는 인벤토리가 답한다** — 클라이언트가 "나는 총을 들었다"고
## 주장할 자리가 없다 (docs/DESIGN.md 「서버 권위」).
func _held_item_id() -> String:
	var player := %Player as Node2D
	if inventory == null or player.motion == null:
		return ""
	var stack: RefCounted = inventory.at(Inventory.AREA_GENERAL, player.motion.held_slot)
	return "" if stack == null else stack.id


## 좌클릭으로 도구 쓰기가 시작됐다 — 그게 총이고 **탄창에 남은 게 있으면** 한 발이 나간다.
##
## 연사 간격은 도구 쓰기 자체가 갖고 있는 0.5초(`player_motion.gd` 의 `USE_TICKS`)가
## 그대로 「총기 스탯」의 초당 2발이 된다 — 여기서 따로 세지 않는다.
##
## **탄창이 비었거나 재장전 중이면 총알만 안 나가고 사용 모션은 그대로 나온다.** 모션은
## 손에 든 것이 무엇인지 모르는 코어가 틀고(「생활 스킬 — 채집 계열」의 "대상이 없어도
## 사용 모션은 나온다"), 총알을 만드는 것은 인벤토리를 아는 이쪽이다 — 못 쐈다는 것은
## 총 UI 의 빈 탄창이 말한다.
func _on_player_use_started() -> void:
	if _held_item_id() != GUN_ITEM:
		return
	var player := %Player as Node2D
	# **한 발을 실제로 덜어낸 경우에만** 총알이 나간다 (docs/DESIGN.md 「총기 스탯」의
	# "다 쏘면 좌클릭해도 발사되지 않고").
	if not player.motion.gun.fire():
		return
	# **탄퍼짐은 지금 조준선의 선명도 그대로다** — 쏜 뒤에 반동으로 깎이므로 순서가
	# 중요하다(먼저 쏘고 그 다음에 흐트러진다).
	bullets.fire(player.muzzle_position(), player.motion.aim_angle,
			player.motion.spread_angle())
	player.motion.apply_recoil()


## R — 재장전 (docs/DESIGN.md 「총기 스탯」). **예비 탄약이 없어서 끝나면 언제나 가득**
## 이고, 이미 가득이거나 이미 재장전 중이면 아무 일도 하지 않는다(`gun_ammo.gd`).
func _on_player_reload_requested() -> void:
	if _held_item_id() != GUN_ITEM:
		return
	(%Player as Node2D).motion.gun.start_reload()


## 우클릭 — 장전된 탄종 전환 (기본탄 ↔ 마취탄, docs/DESIGN.md 「조작」).
## **탄종마다 탄창이 따로라** 바꿔도 그쪽에 남아 있던 발수 그대로다.
func _on_player_ammo_switch_requested() -> void:
	if _held_item_id() != GUN_ITEM:
		return
	(%Player as Node2D).motion.gun.switch_kind()


## 씬이 내려갈 때(메인 메뉴로 나가기, 종료) 마지막으로 한 번 더 적는다 —
## 위 주기 저장만 있으면 마지막 몇 초가 날아간다.
func _exit_tree() -> void:
	# 나가는 순간 열어둔 상자는 닫힌 것으로 친다 — 열린 채로 저장하면 다음에
	# 들어왔을 때 타이머가 멈춘 상자가 된다(불러오기가 한 번 더 막지만, 나가는
	# 쪽에서도 맞춰둔다).
	_close_death_box()
	_save_explored()
	_save_inventory()
	_save_ground()
	_save_death_boxes()


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


## 데스드롭 상자도 같은 규칙으로 슬롯에 적는다.
func _save_death_boxes() -> void:
	if _slot_index < 0 or death_boxes == null or not _death_boxes_dirty:
		return
	if SlotStore.save_death_boxes(_slot_index, death_boxes.to_data()):
		_death_boxes_dirty = false


## 월드 설정도 슬롯에 적는다 — **그래픽 설정과 다른 자리다**(docs/DESIGN.md 「월드 설정」).
func _save_world_settings() -> void:
	if _slot_index < 0 or world_settings == null:
		return
	SlotStore.save_world_settings(_slot_index, world_settings.to_data())


# --- 일시정지 메뉴 (docs/DESIGN.md 「조작」의 Esc 항목) -------------------------
#
# **월드 시뮬레이션을 멈추지 않는다** — `get_tree().paused` 를 쓰지 않는다. 멀티플레이에서
# 한 사람이 Esc 를 눌렀다고 세계가 멈출 수는 없기 때문이다. 대신 메뉴가 열려 있는 동안
# 플레이어의 **입력만 끊는다**(`player.gd` 의 `input_enabled`) — 시간을 멈추는 게 아니라
# 조작을 안 받는 것이다. 조준 각도는 0 으로 만들지 않고 보던 각도를 유지한다(0 으로 넣으면
# 메뉴를 열 때마다 캐릭터가 오른쪽으로 홱 돈다).

func _menu_open() -> bool:
	return _settings_overlay != null or _map_overlay != null or _inventory_overlay != null \
			or _death_box_overlay != null or _world_settings_overlay != null \
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
	if _settings_overlay == null and _world_settings_overlay == null \
			and not (%PauseMenu as Control).visible:
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
	# **좌클릭은 상자를 먼저 본다** — 「조작」이 별도의 상호작용 키를 두지 않기로
	# 했으므로(좌클릭 하나가 그 자리도 겸한다), 커서가 상자 위에 있고 가까이 서 있으면
	# 그 클릭은 상자를 여는 클릭이지 도구를 쓰는 클릭이 아니다.
	if event.is_action_pressed("use_tool"):
		if not _menu_open():
			get_viewport().set_input_as_handled()
			if not _try_open_death_box():
				(%Player as Node2D).request_use()
		return
	# R = 재장전, 우클릭 = 탄종 전환 (docs/DESIGN.md 「조작」/「총기 스탯」).
	# **좌클릭과 같은 규칙**이다: 창이 하나라도 열려 있으면 안 먹고, 총을 들었는지는
	# 여기서 보지 않는다(입력으로 코어까지 갔다가 인벤토리를 아는 자리에서 갈린다).
	if event.is_action_pressed("reload"):
		if not _menu_open():
			get_viewport().set_input_as_handled()
			(%Player as Node2D).request_reload()
		return
	if event.is_action_pressed("switch_ammo"):
		if not _menu_open():
			get_viewport().set_input_as_handled()
			(%Player as Node2D).request_ammo_switch()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _settings_overlay != null:
		_close_settings()
	elif _world_settings_overlay != null:
		_close_world_settings()
	elif _death_box_overlay != null:
		_close_death_box()
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
	if _menu_open():
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
	if _menu_open():
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


## 일시정지 메뉴 → 월드 설정 (docs/DESIGN.md 「월드 설정」). 설정과 같은 자리에
## 같은 방식으로 겹쳐 띄운다 — 씬을 바꾸면 월드가 내려간다.
func _on_pause_world_settings_pressed() -> void:
	if _world_settings_overlay != null:
		return
	var overlay := WORLD_SETTINGS_SCENE.instantiate() as Control
	_world_settings_overlay = overlay
	($HUD as CanvasLayer).add_child(overlay)
	overlay.setup(world_settings)
	# 바꾼 값은 **그 자리에서 슬롯에 적는다** — 월드 설정은 그 월드에 붙는 값이다.
	overlay.changed.connect(_save_world_settings)
	_sync_player_input()


func _close_world_settings() -> void:
	if _world_settings_overlay == null:
		return
	_world_settings_overlay.queue_free()
	_world_settings_overlay = null
	_save_world_settings()
	_sync_player_input()
	(%ResumeButton as Button).grab_focus()


func _close_settings() -> void:
	if _settings_overlay == null:
		return
	_settings_overlay.queue_free()
	_settings_overlay = null
	_sync_player_input()
	(%ResumeButton as Button).grab_focus()


func _on_exit_to_main_menu_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
