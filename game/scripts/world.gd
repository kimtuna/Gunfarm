extends Node2D

## 월드 입장 — 시드 기반 절차적 지형과 스폰 지점 (docs/DESIGN.md "월드 생성").
##
## 슬롯에 저장된 `world_seed` 로 월드를 만든다. **같은 시드는 항상 같은 월드**여야 하므로
## 생성 자체는 scripts/world_gen.gd(노드를 상속하지 않는 순수 클래스)가 맡고, 여기서는
## 그 결과를 화면에 올리고 플레이어를 스폰 지점에 세우기만 한다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")

const SLOTS_SCENE := "res://scenes/character_slots.tscn"

var world: RefCounted = null


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
	(%BackButton as Button).grab_focus()


func _on_back_pressed() -> void:
	_back_to_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back_to_slots()


func _back_to_slots() -> void:
	get_tree().change_scene_to_file(SLOTS_SCENE)
