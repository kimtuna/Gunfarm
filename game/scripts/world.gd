extends Node2D

## 월드 입장 — 시드 기반 절차적 지형과 스폰 지점 (docs/DESIGN.md "월드 생성").
##
## 슬롯에 저장된 `world_seed` 로 월드를 만든다. **같은 시드는 항상 같은 월드**여야 하므로
## 생성 자체는 scripts/world_gen.gd(노드를 상속하지 않는 순수 클래스)가 맡고, 여기서는
## 그 결과를 화면에 올리고 플레이어를 스폰 지점에 세우기만 한다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const ExploredMap := preload("res://scripts/explored_map.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_SCENE := preload("res://scenes/settings.tscn")
const MAP_SCENE := preload("res://scenes/map_screen.tscn")

## 걸어다니면서 "가봤음"으로 적히는 반경(타일). 화면 세로 절반이 7.5칸이라 그보다 살짝
## 작게 잡았다 — 실제로 화면에서 본 만큼만 남는다 (docs/DESIGN.md 「맵 (M)」).
const EXPLORE_RADIUS_TILES := 6

## 탐험 기록을 슬롯에 적는 간격(초). 매번 적으면 한 칸 걸을 때마다 파일을 쓴다.
const EXPLORED_SAVE_SECONDS := 3.0

var world: RefCounted = null

## 이 캐릭터가 가본 곳(`explored_map.gd`). 슬롯에서 읽어 오고, 걸어다니면 여기 쌓인다.
var explored: RefCounted = null

## 일시정지 메뉴에서 띄운 설정 화면. 씬을 바꾸지 않고 **월드 위에 겹쳐서** 띄운다 —
## 씬을 바꾸면 월드가 통째로 내려가므로 "월드는 멈추지 않는다"가 성립하지 않는다.
var _settings_overlay: Control = null

## M 으로 연 전체 맵. 설정과 같은 자리(HUD)에 겹쳐 붙는다.
var _map_overlay: Control = null

var _slot_index := -1
var _explored_dirty := false
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

	(%TerrainView as Node2D).set_world(world)
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


# --- 탐험 기록 (docs/DESIGN.md 「맵 (M)」) -------------------------------------
#
# 플레이어가 선 칸이 바뀔 때마다 그 주변 **반경**을 "가봤음"으로 적는다. 시야 콘이
# 아니라 반경인 이유는 DESIGN.md 에 있다 — 콘이면 제자리에서 마우스를 돌리는 것만으로
# 지도가 채워진다.

func _process(delta: float) -> void:
	var tile: Vector2i = (%Player as Node2D).tile()
	if tile != _marked_tile:
		_marked_tile = tile
		if explored.mark_around(tile, EXPLORE_RADIUS_TILES) > 0:
			_explored_dirty = true
	_explored_save_left -= delta
	if _explored_save_left <= 0.0:
		_explored_save_left = EXPLORED_SAVE_SECONDS
		_save_explored()


## 씬이 내려갈 때(메인 메뉴로 나가기, 종료) 마지막으로 한 번 더 적는다 —
## 위 주기 저장만 있으면 마지막 몇 초가 날아간다.
func _exit_tree() -> void:
	_save_explored()


func _save_explored() -> void:
	if not _explored_dirty or _slot_index < 0 or explored == null:
		return
	if SlotStore.save_explored(_slot_index, explored.to_base64()):
		_explored_dirty = false


# --- 일시정지 메뉴 (docs/DESIGN.md 「조작」의 Esc 항목) -------------------------
#
# **월드 시뮬레이션을 멈추지 않는다** — `get_tree().paused` 를 쓰지 않는다. 멀티플레이에서
# 한 사람이 Esc 를 눌렀다고 세계가 멈출 수는 없기 때문이다. 대신 메뉴가 열려 있는 동안
# 플레이어의 **입력만 끊는다**(`player.gd` 의 `input_enabled`) — 시간을 멈추는 게 아니라
# 조작을 안 받는 것이다. 조준 각도는 0 으로 만들지 않고 보던 각도를 유지한다(0 으로 넣으면
# 메뉴를 열 때마다 캐릭터가 오른쪽으로 홱 돈다).

func _menu_open() -> bool:
	return _settings_overlay != null or _map_overlay != null or (%PauseMenu as Control).visible


## 월드 안의 Esc 는 나가는 키가 아니라 일시정지 메뉴다.
## **가장 안쪽 창부터 닫는다** — 설정이 열려 있으면 설정만 닫히고 일시정지 메뉴가 남는다.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		get_viewport().set_input_as_handled()
		_toggle_map()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _settings_overlay != null:
		_close_settings()
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
func _sync_player_input() -> void:
	(%Player as Node2D).input_enabled = not _menu_open()


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
	if _settings_overlay != null or (%PauseMenu as Control).visible:
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
