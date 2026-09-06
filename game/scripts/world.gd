extends Node2D

## 월드 입장 — 시드 기반 절차적 지형과 스폰 지점 (docs/DESIGN.md "월드 생성").
##
## 슬롯에 저장된 `world_seed` 로 월드를 만든다. **같은 시드는 항상 같은 월드**여야 하므로
## 생성 자체는 scripts/world_gen.gd(노드를 상속하지 않는 순수 클래스)가 맡고, 여기서는
## 그 결과를 화면에 올리고 플레이어를 스폰 지점에 세우기만 한다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_SCENE := preload("res://scenes/settings.tscn")

var world: RefCounted = null

## 일시정지 메뉴에서 띄운 설정 화면. 씬을 바꾸지 않고 **월드 위에 겹쳐서** 띄운다 —
## 씬을 바꾸면 월드가 통째로 내려가므로 "월드는 멈추지 않는다"가 성립하지 않는다.
var _settings_overlay: Control = null


func _ready() -> void:
	var index := SlotStore.selected_slot
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


# --- 일시정지 메뉴 (docs/DESIGN.md 「조작」의 Esc 항목) -------------------------
#
# **월드 시뮬레이션을 멈추지 않는다** — `get_tree().paused` 를 쓰지 않는다. 멀티플레이에서
# 한 사람이 Esc 를 눌렀다고 세계가 멈출 수는 없기 때문이다. 대신 메뉴가 열려 있는 동안
# 플레이어의 **입력만 끊는다**(`player.gd` 의 `input_enabled`) — 시간을 멈추는 게 아니라
# 조작을 안 받는 것이다. 조준 각도는 0 으로 만들지 않고 보던 각도를 유지한다(0 으로 넣으면
# 메뉴를 열 때마다 캐릭터가 오른쪽으로 홱 돈다).

func _menu_open() -> bool:
	return _settings_overlay != null or (%PauseMenu as Control).visible


## 월드 안의 Esc 는 나가는 키가 아니라 일시정지 메뉴다.
## **가장 안쪽 창부터 닫는다** — 설정이 열려 있으면 설정만 닫히고 일시정지 메뉴가 남는다.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _settings_overlay != null:
		_close_settings()
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
