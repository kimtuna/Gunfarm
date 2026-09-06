extends SceneTree

## INBOX #23 자체 QA — 인벤토리 + 핫바 (데이터 구조와 UI).
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_inventory.gd
##
## 확인하는 것:
##   A. 코어(`inventory.gd` — 화면 없이 도는 순수 클래스)
##      1) 칸 구성이 DESIGN.md 그대로다 — 일반 18(맨 위 9칸이 핫바), 장비 9(모자1/상의1/
##         하의1/신발1/목걸이2/반지2/가방1).
##      2) 겹치기 쌓임 — 한 칸 한도를 넘으면 다음 칸으로 넘어간다.
##      3) **꽉 찬 인벤토리에 넣으면 넘치는 몫이 안 사라진다** (「인벤토리 안전」) —
##         넣은 만큼만 뭉치에서 덜리고 나머지는 그 뭉치에 그대로 남는다.
##      4) 장비 칸은 종류가 맞는 것만 받는다.
##      5) 옮기기 — 자리 바꾸기 / 같은 아이템 합치기(넘치면 원래 칸에 남는다).
##      6) **저장·불러오기 왕복** — JSON 한 바퀴 돌아도 배치·수량·소유 상태가 그대로다.
##         모르는 아이템은 빈 칸이 되고, 장비 칸에 안 맞는 것이 저장돼 있으면 버리지 않고
##         일반 칸으로 간다.
##   B. 화면(실제 월드 씬에서)
##      7) E 로 열리고 다시 E 로 닫힌다. **Esc 는 인벤토리만 닫는다**(일시정지 메뉴가
##         같이 열리지 않는다 — 「가장 안쪽 창부터」). 인벤토리가 열려 있을 때 M 은
##         아무 일도 하지 않는다.
##      8) 창이 없을 때는 상시 요약 HUD 도 없다 (docs/DESIGN.md 명시).
##      9) 숫자키 1~9 로 손에 든 칸이 바뀐다 — 코어 값과 **화면 픽셀**(고른 칸 테두리)
##         둘 다로 본다.
##     10) **드래그로 옮겨진다** — 실제 마우스(`Input.warp_mouse` + 버튼 이벤트)로
##         일반↔일반(자리 바꾸기), 일반→장비(가방), 종류가 안 맞는 장비 칸(거부).
##     11) **창 밖에 놓으면 버려진다** — 인벤토리에서 사라지고 바닥 드롭 데이터가 생긴다.
##     12) 창이 열린 동안 플레이어가 안 움직이고, 닫으면 다시 움직인다.
##     13) **저장했다 불러와도 배치가 그대로다** — 메인 메뉴로 나갔다 같은 슬롯으로
##         다시 들어와서 확인한다(슬롯 파일을 거치는 진짜 경로다).

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const Inventory := preload("res://scripts/inventory.gd")
const ItemStack := preload("res://scripts/item_stack.gd")
const ItemTypes := preload("res://scripts/item_types.gd")
const InventoryPanel := preload("res://scripts/inventory_panel.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SEED := 20260907

## 프레임 수가 아니라 **시간**으로 기다린다 (docs/GOTCHAS.md) — 수직동기화를 꺼두므로
## 몇 프레임은 몇 ms 밖에 안 되고, 그러면 고정 틱(1/60초)이 한 번도 안 돈다.
const SETTLE_SECONDS := 0.2

## 마우스를 한 자리에 머물게 하는 시간. 매 프레임 다른 자리로 `warp_mouse()` 하면
## OS 가 커서 이동을 합쳐버린다 (docs/GOTCHAS.md).
const MOUSE_SETTLE_SECONDS := 0.12

## 키를 몇 초 누르고 있는가 — 240단위/초라 0.25초면 타일 한 칸이 넘는다.
const HOLD_SECONDS := 0.25

const COLOR_EPSILON := 0.03

const PAUSE := "HUD/PauseMenu"
const PAUSE_BOX := "HUD/PauseMenu/Box/BoxLayout"
const INVENTORY_NODE := "HUD/InventoryScreen"

## 도구 7종 (docs/DESIGN.md 「생활 스킬 — 채집 계열」의 도구 표) — 처음 들어온 캐릭터가
## 전부 갖고 있어야 한다(「도구 등급」의 무료 지급).
const TOOL_IDS := ["gun", "axe", "pickaxe", "sickle", "hoe", "watering_can", "fishing_rod"]

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

## 검사 사이에 들고 다니는 값들.
var _before := {}
var _hold_from := Vector2.ZERO


func _initialize() -> void:
	# 일부러 최악(빠른) 조건을 만든다 — 프레임 수로 기다리는 실수가 우연히 통과하지
	# 못하게 한다 (docs/GOTCHAS.md).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(SHOTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))

	_check_core()

	_enter_world()
	_steps = [
		_settle,
		_check_closed_at_start,
		_check_starter_items,
		_stand_on_open_land,
		_settle,
		_press_inventory_key,
		_settle,
		_check_opens,
		func(): _shoot("60_inventory_open"),
		_check_slot_layout_on_screen,
		# 9) 숫자키
		func(): _send_action("hotbar_3"),
		_settle,
		func(): _check_hotbar_selected(2),
		func(): _send_action("hotbar_9"),
		_settle,
		func(): _check_hotbar_selected(8),
		func(): _shoot("61_hotbar_9"),
	]
	# 10) 드래그 — 일반 0 ↔ 일반 12 (자리 바꾸기)
	_steps.append(func(): _remember_slots([_g(0), _g(12)]))
	_steps.append_array(_drag_steps(_g(0), func() -> Vector2: return _slot_center(_g(12))))
	_steps.append(_check_swapped_general)
	# 가방(일반 17) → 장비 가방 칸(8)
	_steps.append(func(): _remember_slots([_g(17), _e(8)]))
	_steps.append_array(_drag_steps(_g(17), func() -> Vector2: return _slot_center(_e(8)),
			"62_inventory_drag"))
	_steps.append(_check_bag_equipped)
	# 종류가 안 맞는 장비 칸(모자)에는 안 들어간다
	_steps.append(func(): _remember_slots([_g(7), _e(0)]))
	_steps.append_array(_drag_steps(_g(7), func() -> Vector2: return _slot_center(_e(0))))
	_steps.append(_check_wrong_equip_refused)
	# 11) 창 밖에 놓기 = 버리기
	_steps.append(func(): _remember_slots([_g(8)]))
	_steps.append_array(_drag_steps(_g(8), func() -> Vector2: return Vector2(70.0, 620.0)))
	_steps.append(_check_dropped_outside)
	_steps.append(func(): _shoot("63_after_drop"))
	# 12) 창이 열린 동안엔 안 움직인다
	_steps.append_array([
		_hold_move, _check_did_not_move,
		# 7) M 은 인벤토리가 열려 있는 동안 아무 일도 안 한다
		func(): _send_action("toggle_map"),
		_settle,
		_check_map_did_not_open,
		# Esc 로 닫으면 인벤토리만 닫힌다
		func(): _send_action("ui_cancel"),
		_settle,
		_check_escape_closed_only_inventory,
		_hold_move, _check_moved_again,
		# E 로 열고 다시 E 로 닫기
		_press_inventory_key, _settle, _check_opens_again,
		_press_inventory_key, _settle, _check_closed_by_e,
		# 13) 저장 → 메인 메뉴 → 다시 입장
		func(): _press(PAUSE_BOX + "/ExitButton"),
		_settle,
		func(): change_scene_to_file(WORLD_SCENE),
		_settle,
		_check_survives_save_load,
		_press_inventory_key,
		_settle,
		func(): _shoot("64_reloaded"),
	])


func _process(delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
	if _wait_time > 0.0:
		_wait_time -= delta
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size():
		if _fails.is_empty():
			print("[qa] PASS — 인벤토리 / 핫바 정상")
			return true
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)
		return true
	var step: Callable = _steps[_step]
	_step += 1
	_wait = 4  # 상태를 바꾼 프레임에 바로 찍으면 한 프레임 전 화면이 찍힌다 (docs/GOTCHAS.md).
	step.call()
	return false


# =============================================================================
# A. 코어 — 화면 없이 도는 부분
# =============================================================================

func _check_core() -> void:
	_check_slot_shape()
	_check_stacking()
	_check_full_inventory_keeps_leftover()
	_check_equipment_kinds()
	_check_moving()
	_check_save_round_trip()


## 1) 칸 구성이 DESIGN.md 「인벤토리 / 장비」 그대로인가.
func _check_slot_shape() -> void:
	var inv := Inventory.new()
	if inv.slot_count(Inventory.AREA_GENERAL) != 18:
		_fails.append("일반 칸이 %d개다 — 18칸이어야 한다" % inv.slot_count(Inventory.AREA_GENERAL))
	if Inventory.HOTBAR_SLOTS != 9:
		_fails.append("핫바가 %d칸이다 — 맨 위 9칸이어야 한다" % Inventory.HOTBAR_SLOTS)
	if inv.slot_count(Inventory.AREA_EQUIPMENT) != 9:
		_fails.append("장비 칸이 %d개다 — 9칸이어야 한다" % inv.slot_count(Inventory.AREA_EQUIPMENT))
	var want := {ItemTypes.EQUIP_HAT: 1, ItemTypes.EQUIP_SHIRT: 1, ItemTypes.EQUIP_PANTS: 1,
			ItemTypes.EQUIP_SHOES: 1, ItemTypes.EQUIP_NECKLACE: 2, ItemTypes.EQUIP_RING: 2,
			ItemTypes.EQUIP_BAG: 1}
	var got := {}
	for kind: String in Inventory.EQUIPMENT_KINDS:
		got[kind] = int(got.get(kind, 0)) + 1
	for kind: String in want:
		if int(got.get(kind, 0)) != int(want[kind]):
			_fails.append("장비 칸에 %s 가 %d개다 — %d개여야 한다"
					% [kind, int(got.get(kind, 0)), int(want[kind])])
	if got.size() != want.size():
		_fails.append("장비 칸 구성이 %s 다 — 모자1/상의1/하의1/신발1/목걸이2/반지2/가방1 이어야 한다" % got)
	if not inv.is_empty():
		_fails.append("새 인벤토리가 비어 있지 않다")


## 2) 겹치기 쌓임 — 한 칸 한도(99)를 넘으면 다음 칸으로 간다.
func _check_stacking() -> void:
	var inv := Inventory.new()
	var left := inv.add("wood", 150)
	if left != 0:
		_fails.append("빈 인벤토리에 목재 150개를 넣었더니 %d개가 남았다" % left)
	if inv.count_of("wood") != 150:
		_fails.append("목재 150개를 넣었는데 %d개다" % inv.count_of("wood"))
	var first: RefCounted = inv.at(Inventory.AREA_GENERAL, 0)
	var second: RefCounted = inv.at(Inventory.AREA_GENERAL, 1)
	if first == null or first.count != ItemTypes.MAX_STACK:
		_fails.append("첫 칸이 한도(%d)까지 안 찼다" % ItemTypes.MAX_STACK)
	if second == null or second.count != 150 - ItemTypes.MAX_STACK:
		_fails.append("넘친 몫이 두 번째 칸에 안 갔다")
	# 도구는 한 칸에 하나씩이다.
	var tools := Inventory.new()
	tools.add("axe", 3)
	if tools.at(Inventory.AREA_GENERAL, 0).count != 1 or tools.count_of("axe") != 3:
		_fails.append("도끼 3개가 한 칸에 뭉쳤다 — 도구는 칸당 하나여야 한다")


## 3) **꽉 찬 인벤토리** (docs/DESIGN.md 「인벤토리 안전」).
func _check_full_inventory_keeps_leftover() -> void:
	var inv := Inventory.new()
	# 17칸 가득 + 마지막 칸 90개 = 18칸 전부 사용, 마지막 칸에만 9칸의 여유.
	var total := ItemTypes.MAX_STACK * 17 + 90
	inv.add("stone", total)
	var spill := ItemStack.new("stone", 20)
	var added := inv.take_in(spill)
	if added != 9 or spill.count != 11:
		_fails.append("여유가 9개뿐인데 20개를 넣었더니 %d개 들어가고 %d개 남았다 (9/11 이어야 한다)"
				% [added, spill.count])
	if inv.count_of("stone") != total + 9:
		_fails.append("넣은 개수와 늘어난 개수가 다르다 — 아이템이 새고 있다")
	# 이제 정말 꽉 찼다. 다른 아이템은 한 개도 안 들어가고, **한 개도 사라지지 않는다**.
	var blocked := ItemStack.new("wood", 5)
	if inv.take_in(blocked) != 0 or blocked.count != 5:
		_fails.append("꽉 찬 인벤토리에 목재를 넣었더니 %d개가 사라졌다" % (5 - blocked.count))
	if inv.add("wood", 5) != 5:
		_fails.append("꽉 찬 인벤토리에 add() 했더니 남은 수량을 5로 안 돌려줬다")
	# 모르는 아이템도 조용히 사라지지 않는다(들어가지 않을 뿐이다).
	var unknown := ItemStack.new("이런아이템없다", 3)
	if Inventory.new().take_in(unknown) != 0 or unknown.count != 3:
		_fails.append("모르는 아이템을 넣었더니 개수가 줄었다")


## 4) 장비 칸은 종류가 맞는 것만 받는다.
func _check_equipment_kinds() -> void:
	var inv := Inventory.new()
	inv.add("bag", 1)
	inv.add("wood", 10)
	if inv.accepts(Inventory.AREA_EQUIPMENT, 0, "bag"):
		_fails.append("가방이 모자 칸에 들어간다고 한다")
	if not inv.accepts(Inventory.AREA_EQUIPMENT, 8, "bag"):
		_fails.append("가방이 가방 칸에 안 들어간다고 한다")
	if inv.accepts(Inventory.AREA_EQUIPMENT, 8, "wood"):
		_fails.append("장비가 아닌 목재가 장비 칸에 들어간다고 한다")
	if inv.move(Inventory.AREA_GENERAL, 0, Inventory.AREA_EQUIPMENT, 0):
		_fails.append("가방을 모자 칸으로 옮기는 데 성공해버렸다")
	if not inv.move(Inventory.AREA_GENERAL, 0, Inventory.AREA_EQUIPMENT, 8):
		_fails.append("가방을 가방 칸으로 못 옮겼다")
	if inv.at(Inventory.AREA_GENERAL, 0) != null:
		_fails.append("장비 칸으로 옮겼는데 원래 칸에 아이템이 남아 있다")


## 5) 옮기기 — 자리 바꾸기와 합치기.
func _check_moving() -> void:
	var inv := Inventory.new()
	inv.add("wood", 60)
	inv.add("stone", 5)
	inv.move(Inventory.AREA_GENERAL, 0, Inventory.AREA_GENERAL, 5)
	inv.move(Inventory.AREA_GENERAL, 1, Inventory.AREA_GENERAL, 0)
	if inv.at(Inventory.AREA_GENERAL, 5).id != "wood" or inv.at(Inventory.AREA_GENERAL, 0).id != "stone":
		_fails.append("빈 칸으로 옮기기가 안 된다")
	inv.move(Inventory.AREA_GENERAL, 0, Inventory.AREA_GENERAL, 5)
	if inv.at(Inventory.AREA_GENERAL, 0).id != "wood" or inv.at(Inventory.AREA_GENERAL, 5).id != "stone":
		_fails.append("다른 아이템끼리 자리 바꾸기가 안 된다")
	# 합치기 — 넘치는 몫은 원래 칸에 남는다.
	var merge := Inventory.new()
	merge.add("wood", 150)  # 0번 99개, 1번 51개
	merge.move(Inventory.AREA_GENERAL, 1, Inventory.AREA_GENERAL, 0)
	if merge.count_of("wood") != 150:
		_fails.append("합치는 사이에 목재가 사라졌다 (%d개)" % merge.count_of("wood"))
	if merge.at(Inventory.AREA_GENERAL, 1) == null or merge.at(Inventory.AREA_GENERAL, 1).count != 51:
		_fails.append("이미 가득 찬 칸에 합쳤는데 넘친 몫이 원래 칸에 안 남았다")
	merge.at(Inventory.AREA_GENERAL, 0).count = 90
	merge.move(Inventory.AREA_GENERAL, 1, Inventory.AREA_GENERAL, 0)
	if merge.at(Inventory.AREA_GENERAL, 0).count != 99 \
			or merge.at(Inventory.AREA_GENERAL, 1).count != 42:
		_fails.append("합칠 때 한도(99)까지만 채우고 나머지를 남기지 않았다")


## 6) 저장 → JSON → 불러오기 왕복 (docs/DESIGN.md 「아이템 소유권 상태」 포함).
func _check_save_round_trip() -> void:
	var inv := Inventory.new()
	inv.add("wood", 150)
	inv.add("axe", 1)
	inv.add("bag", 1)
	inv.move(Inventory.AREA_GENERAL, 3, Inventory.AREA_EQUIPMENT, 8)
	inv.select_hotbar(4)
	var data := inv.to_data()
	var slot_data: Dictionary = data[Inventory.KEY_GENERAL][0]
	if String(slot_data.get(ItemStack.KEY_OWNERSHIP, "")) != ItemStack.OWNERSHIP_LOCAL:
		_fails.append("저장한 칸에 소유 상태(`%s`)가 없다 — 나중에 넣으면 세이브가 깨진다"
				% ItemStack.OWNERSHIP_LOCAL)
	# 실제로 슬롯 파일에 들어가는 그대로 — JSON 문자열 한 바퀴를 돌린다.
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var loaded := Inventory.new()
	if not loaded.from_data(parsed):
		_fails.append("저장한 인벤토리를 다시 못 읽었다")
	if JSON.stringify(loaded.to_data()) != JSON.stringify(data):
		_fails.append("저장했다 불러왔더니 내용이 달라졌다")
	if loaded.selected_hotbar != 4:
		_fails.append("손에 든 칸이 저장/복원되지 않는다")
	# 깨진 저장: 모르는 아이템은 빈 칸이 되고, 장비 칸에 안 맞는 것은 일반 칸으로 간다.
	var broken := Inventory.new()
	broken.from_data({
		Inventory.KEY_GENERAL: [{"id": "없는아이템", "n": 5}, {"id": "wood", "n": 7}],
		Inventory.KEY_EQUIPMENT: [{"id": "wood", "n": 3}],
		Inventory.KEY_HOTBAR: 99,
	})
	if broken.at(Inventory.AREA_GENERAL, 0) != null:
		_fails.append("모르는 아이템이 그대로 살아났다 — 빈 칸이어야 한다")
	if broken.count_of("wood") != 10:
		_fails.append("장비 칸에 잘못 저장돼 있던 목재가 사라졌다 (%d개)" % broken.count_of("wood"))
	if broken.at(Inventory.AREA_EQUIPMENT, 0) != null:
		_fails.append("장비 칸에 종류가 안 맞는 것이 그대로 들어갔다")
	if broken.selected_hotbar < 0 or broken.selected_hotbar >= Inventory.HOTBAR_SLOTS:
		_fails.append("저장 파일의 이상한 핫바 번호(99)가 그대로 들어왔다")
	print("[qa] 코어 검사 끝 — 슬롯에 들어갈 JSON %d자" % JSON.stringify(data).length())


# =============================================================================
# B. 화면
# =============================================================================

func _enter_world() -> void:
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("보따리", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	change_scene_to_file(WORLD_SCENE)


func _check_closed_at_start() -> void:
	if _screen() != null:
		_fails.append("월드에 들어오자마자 인벤토리가 열려 있다")
	# 상시 요약 HUD 를 만들지 않는다 (docs/DESIGN.md 「인벤토리 / 장비」).
	for node in current_scene.find_children("*", "Control", true, false):
		if node.get_script() == InventoryPanel:
			_fails.append("창을 안 열었는데 인벤토리 칸이 화면에 떠 있다 (%s)" % node.name)


func _check_starter_items() -> void:
	var inv := _inventory()
	if inv == null:
		_fails.append("월드에 인벤토리가 없다")
		return
	for id: String in TOOL_IDS:
		if inv.count_of(id) < 1:
			_fails.append("처음 들어온 캐릭터에게 %s 가 없다" % ItemTypes.name_of(id))
	if inv.count_of("wood") < 1 or inv.count_of("bag") < 1:
		_fails.append("테스트용 아이템이 안 들어왔다")


func _check_opens() -> void:
	var screen := _screen()
	if screen == null:
		_fails.append("E 를 눌렀는데 인벤토리가 안 열렸다")
		return
	if _world() == null:
		_fails.append("인벤토리를 열었더니 월드 씬이 통째로 바뀌었다 — 겹쳐서 띄워야 한다")
	if paused:
		_fails.append("인벤토리를 열면서 get_tree().paused 로 세계를 세웠다")
	var player := _player()
	if player != null and player.input_enabled:
		_fails.append("인벤토리가 열려 있는데 플레이어 입력이 살아 있다")


## 칸 27개가 창 안에 제대로 자리잡았는가 — 겹치지 않고, 핫바 9칸이 일반 칸 맨 윗줄이다.
func _check_slot_layout_on_screen() -> void:
	var panel := _panel()
	if panel == null:
		_fails.append("인벤토리 칸 그림(Panel)을 못 찾았다")
		return
	var box := _screen().get_node("%Box") as Control
	var window := Rect2(box.global_position, box.size)
	var rects: Array[Rect2] = []
	for area: String in [Inventory.AREA_GENERAL, Inventory.AREA_EQUIPMENT]:
		for index in _inventory().slot_count(area):
			var rect: Rect2 = panel.global_slot_rect(area, index)
			if not window.encloses(rect):
				_fails.append("%s %d번 칸이 창 밖으로 나갔다 (%s)" % [area, index, rect])
			for other in rects:
				if other.intersects(rect):
					_fails.append("칸이 서로 겹친다: %s / %s" % [other, rect])
			rects.append(rect)
	# 핫바 9칸은 일반 칸의 **맨 윗줄**이어야 한다(별도 UI 가 아니다).
	var first_row_y: float = panel.global_slot_rect(Inventory.AREA_GENERAL, 0).position.y
	for index in Inventory.HOTBAR_SLOTS:
		if not is_equal_approx(panel.global_slot_rect(Inventory.AREA_GENERAL, index).position.y, first_row_y):
			_fails.append("핫바 %d번 칸이 맨 윗줄에 없다" % (index + 1))
	if is_equal_approx(panel.global_slot_rect(Inventory.AREA_GENERAL, 9).position.y, first_row_y):
		_fails.append("10번째 일반 칸이 핫바와 같은 줄에 있다 — 핫바는 9칸이다")


## 9) 숫자키. 코어 값과 **화면에 그려진 테두리** 둘 다로 본다.
func _check_hotbar_selected(index: int) -> void:
	var inv := _inventory()
	if inv.selected_hotbar != index:
		_fails.append("숫자키 %d 를 눌렀는데 손에 든 칸이 %d번이다" % [index + 1, inv.selected_hotbar + 1])
		return
	var image := _capture()
	if image == null:
		return
	if not _has_selected_border(image, index):
		_fails.append("%d번 칸이 화면에서 '고른 칸'으로 안 보인다" % (index + 1))
	for other in Inventory.HOTBAR_SLOTS:
		if other != index and _has_selected_border(image, other):
			_fails.append("%d번 칸을 골랐는데 %d번 칸도 골라진 것처럼 보인다" % [index + 1, other + 1])
			break
	var held: RefCounted = inv.held()
	if held != null and not _find_text(ItemTypes.name_of(held.id)):
		_fails.append("손에 든 것(%s)이 창에 안 적혀 있다" % ItemTypes.name_of(held.id))


## 그 칸의 위쪽 테두리에 "고른 칸" 색이 있는가. 선 두께가 안팎 어느 쪽으로 그려지든
## 잡히도록 테두리를 가로지르는 짧은 세로 구간을 훑는다.
func _has_selected_border(image: Image, index: int) -> bool:
	var rect: Rect2 = _panel().global_slot_rect(Inventory.AREA_GENERAL, index)
	var at := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
	for offset in range(-3, 4):
		if _is_color(_pixel(image, at + Vector2(0.0, offset)), InventoryPanel.SELECTED_BORDER):
			return true
	return false


# --- 10~11) 드래그 -------------------------------------------------------------

## 실제 마우스로 한 번 끌어다 놓는 단계들. `Input.warp_mouse` 로 커서를 옮기고 버튼
## 이벤트를 흘려보내므로 **화면 좌표 → 칸** 변환까지 그대로 지나간다.
func _drag_steps(from: Dictionary, to_point: Callable, shot_name: String = "") -> Array[Callable]:
	var steps: Array[Callable] = [
		func(): _warp(_slot_center(from)),
		_mouse_settle,
		func(): _check_cursor_reached(_slot_center(from)),
		func(): _mouse_button(true),
		_mouse_settle,
	]
	if shot_name != "":
		# 칸이 하나도 없는 자리에서 찍는다 — 끌고 있는 그림이 어느 칸 위에 겹치면
		# "정말 마우스를 따라오는가"를 눈으로 가릴 수 없다.
		steps.append(func(): _warp(Vector2(640.0, 470.0)))
		steps.append(_mouse_settle)
		steps.append(func(): _shoot(shot_name))
	steps.append_array([
		func(): _warp(to_point.call()),
		_mouse_settle,
		func(): _mouse_button(false),
		_settle,
	])
	return steps


## 커서가 실제로 그 자리에 갔는가. 이게 어긋나면(창 크기/배율 문제) 뒤의 드래그 검사가
## 전부 엉뚱한 칸을 짚으면서 조용히 통과할 수 있다 — 그러기 전에 여기서 잡는다.
func _check_cursor_reached(point: Vector2) -> void:
	var at := root.get_mouse_position()
	if at.distance_to(point) > 4.0:
		_fails.append("마우스를 %s 로 옮겼는데 %s 에 있다 — 창 크기/배율을 확인할 것" % [point, at])


func _check_swapped_general() -> void:
	var inv := _inventory()
	var moved: RefCounted = inv.at(Inventory.AREA_GENERAL, 12)
	var swapped: RefCounted = inv.at(Inventory.AREA_GENERAL, 0)
	if moved == null or moved.id != String(_before["general_0"]):
		_fails.append("일반 0번을 12번으로 끌었는데 12번이 %s 다" % _slot_text(moved))
	if swapped == null or swapped.id != String(_before["general_12"]):
		_fails.append("자리 바꾸기가 안 됐다 — 0번이 %s 다" % _slot_text(swapped))


func _check_bag_equipped() -> void:
	var inv := _inventory()
	var equipped: RefCounted = inv.at(Inventory.AREA_EQUIPMENT, 8)
	if equipped == null or equipped.id != "bag":
		_fails.append("가방을 장비 칸으로 끌었는데 %s 다" % _slot_text(equipped))
	if inv.at(Inventory.AREA_GENERAL, 17) != null:
		_fails.append("장비 칸으로 옮겼는데 원래 칸에 아직 남아 있다")


func _check_wrong_equip_refused() -> void:
	var inv := _inventory()
	if inv.at(Inventory.AREA_EQUIPMENT, 0) != null:
		_fails.append("목재가 모자 칸에 들어갔다")
	var stayed: RefCounted = inv.at(Inventory.AREA_GENERAL, 7)
	if stayed == null or stayed.id != String(_before["general_7"]):
		_fails.append("종류가 안 맞아 거부됐는데 원래 칸에서도 사라졌다 — 아이템이 증발한다")


func _check_dropped_outside() -> void:
	var inv := _inventory()
	if inv.at(Inventory.AREA_GENERAL, 8) != null:
		_fails.append("창 밖에 놓았는데 인벤토리에 그대로 있다")
	var ground: RefCounted = current_scene.get("ground_items")
	if ground == null or ground.size() != 1:
		_fails.append("바닥에 놓였다는 데이터가 안 생겼다")
		return
	var entry: Dictionary = ground.items[0]
	var stack: RefCounted = entry["stack"]
	if stack.id != String(_before["general_8"]) or stack.count != int(_before["general_8_count"]):
		_fails.append("버린 것과 바닥에 놓인 것이 다르다 (%s %d개)" % [stack.id, stack.count])
	var player := _player()
	if player != null and (entry["position"] as Vector2).distance_to(player.global_position) > 1.0:
		_fails.append("버린 아이템이 플레이어 근처에 안 놓였다")
	if inv.count_of(stack.id) != 0:
		_fails.append("버렸는데 인벤토리에 %s 가 남아 있다" % stack.id)


# --- 12) 창이 열린 동안 안 움직인다 --------------------------------------------

func _hold_move() -> void:
	_hold_from = _player().global_position
	Input.action_press("move_up")
	_wait_time = HOLD_SECONDS


func _check_did_not_move() -> void:
	Input.action_release("move_up")
	var moved := _player().global_position.distance_to(_hold_from)
	if moved > 1.0:
		_fails.append("인벤토리가 열려 있는데 W 로 %.0f 만큼 움직였다" % moved)


func _check_moved_again() -> void:
	Input.action_release("move_up")
	var moved := _player().global_position.distance_to(_hold_from)
	if moved < 20.0:
		_fails.append("인벤토리를 닫았는데 W 를 눌러도 %.0f 밖에 안 움직였다" % moved)


# --- 7) 열기/닫기 규칙 ----------------------------------------------------------

func _check_map_did_not_open() -> void:
	if current_scene.get_node_or_null("HUD/MapScreen") != null:
		_fails.append("인벤토리가 열려 있는데 M 이 지도까지 열었다 — 창을 겹겹이 쌓지 않는다")
	if _screen() == null:
		_fails.append("M 을 눌렀더니 인벤토리가 닫혔다")


func _check_escape_closed_only_inventory() -> void:
	if _screen() != null:
		_fails.append("인벤토리가 열린 채로 Esc 를 눌렀는데 안 닫혔다")
	var menu := current_scene.get_node_or_null(PAUSE) as Control
	if menu != null and menu.visible:
		_fails.append("Esc 로 인벤토리를 닫았는데 일시정지 메뉴까지 열렸다 — 가장 안쪽 창 하나만 닫아야 한다")
	var player := _player()
	if player != null and not player.input_enabled:
		_fails.append("인벤토리를 닫았는데 플레이어 입력이 안 돌아왔다")


func _check_opens_again() -> void:
	if _screen() == null:
		_fails.append("닫은 뒤 E 를 다시 눌렀는데 안 열렸다")


func _check_closed_by_e() -> void:
	if _screen() != null:
		_fails.append("E 를 한 번 더 눌렀는데 인벤토리가 안 닫혔다")


# --- 13) 저장 → 불러오기 --------------------------------------------------------

func _check_survives_save_load() -> void:
	var inv := _inventory()
	if inv == null:
		_fails.append("다시 들어온 월드에 인벤토리가 없다")
		return
	var equipped: RefCounted = inv.at(Inventory.AREA_EQUIPMENT, 8)
	if equipped == null or equipped.id != "bag":
		_fails.append("나갔다 다시 들어왔더니 장비 칸의 가방이 사라졌다")
	var moved: RefCounted = inv.at(Inventory.AREA_GENERAL, 12)
	if moved == null or moved.id != String(_before["general_0"]):
		_fails.append("나갔다 다시 들어왔더니 옮겨둔 칸 배치가 사라졌다")
	if inv.at(Inventory.AREA_GENERAL, 8) != null:
		_fails.append("버린 아이템이 다시 들어왔다")
	if inv.selected_hotbar != 8:
		_fails.append("나갔다 다시 들어왔더니 손에 든 칸이 %d번이다 — 9번이어야 한다"
				% (inv.selected_hotbar + 1))
	var total := 0
	for area: String in [Inventory.AREA_GENERAL, Inventory.AREA_EQUIPMENT]:
		for index in inv.slot_count(area):
			if inv.at(area, index) != null:
				total += 1
	print("[qa] 다시 들어온 인벤토리에 찬 칸 %d개" % total)


# =============================================================================
# 도구
# =============================================================================

func _g(index: int) -> Dictionary:
	return {"area": Inventory.AREA_GENERAL, "index": index}


func _e(index: int) -> Dictionary:
	return {"area": Inventory.AREA_EQUIPMENT, "index": index}


## 지금 그 칸에 무엇이 들어 있는지 기억해둔다 — 끌어다 놓은 뒤에 견주려고.
func _remember_slots(slots: Array) -> void:
	for slot: Dictionary in slots:
		var stack: RefCounted = _inventory().at(slot["area"], slot["index"])
		var key := "%s_%d" % [slot["area"], slot["index"]]
		_before[key] = "" if stack == null else stack.id
		_before[key + "_count"] = 0 if stack == null else stack.count


func _slot_text(stack: RefCounted) -> String:
	return "빈 칸" if stack == null else "%s %d개" % [stack.id, stack.count]


func _slot_center(slot: Dictionary) -> Vector2:
	return _panel().global_slot_rect(slot["area"], slot["index"]).get_center()


func _warp(point: Vector2) -> void:
	Input.warp_mouse(point)


func _mouse_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_mouse_position()
	Input.parse_input_event(event)


func _mouse_settle() -> void:
	_wait_time = MOUSE_SETTLE_SECONDS


func _settle() -> void:
	_wait_time = SETTLE_SECONDS


func _press_inventory_key() -> void:
	_send_action("toggle_inventory")


func _send_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _press(node_path: String) -> void:
	var button := current_scene.get_node_or_null(node_path) as Button
	if button == null:
		_fails.append("버튼을 못 찾음: %s (현재 씬 %s)" % [node_path, current_scene.name])
		return
	button.emit_signal("pressed")


## 사방이 육지인 자리로 옮겨 선다 — W 를 눌러 움직이는 검사가 바다에 막혀서
## 거짓 실패하지 않게.
func _stand_on_open_land() -> void:
	var world := _world()
	var spawn: Vector2i = world.spawn_tile
	for radius in range(0, 40):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := spawn + Vector2i(dx, dy)
				if _land_around(world, tile, 3):
					_player().place_at(WorldGen.tile_center(tile))
					return
	_fails.append("사방이 육지인 자리를 못 찾았다")


func _land_around(world: RefCounted, tile: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if not world.is_land(tile.x + dx, tile.y + dy):
				return false
	return true


func _world() -> RefCounted:
	return current_scene.get("world")


func _inventory() -> RefCounted:
	return current_scene.get("inventory")


func _player() -> Node2D:
	return current_scene.get_node_or_null("%Player") as Node2D


func _screen() -> Control:
	return current_scene.get_node_or_null(INVENTORY_NODE) as Control


func _panel() -> Control:
	var screen := _screen()
	return null if screen == null else screen.get_node_or_null("Box/BoxLayout/Panel") as Control


func _capture() -> Image:
	var texture := root.get_texture()
	if texture == null:
		_fails.append("캡처 실패: 뷰포트 텍스처 없음 — --headless 로 돌린 건 아닌지 확인")
		return null
	return texture.get_image()


func _shoot(shot_name: String) -> void:
	var image := _capture()
	if image == null:
		return
	var path := "%s/%s.png" % [SHOTS, shot_name]
	image.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, image.get_width(), image.get_height()])


## 논리 좌표(1280×720) → 캡처 이미지의 픽셀. 창 크기가 달라도 맞게 옮긴다.
func _to_pixels(point: Vector2) -> Vector2:
	var logical := root.get_visible_rect().size
	var pixels := Vector2(root.get_texture().get_size())
	return point * (pixels / logical)


func _pixel(image: Image, point: Vector2) -> Color:
	var at := Vector2i(_to_pixels(point))
	return image.get_pixelv(at.clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE))


func _is_color(color: Color, want: Color) -> bool:
	return Vector3(color.r - want.r, color.g - want.g, color.b - want.b).length() <= COLOR_EPSILON


func _find_text(expect_text: String) -> bool:
	for label in current_scene.find_children("*", "Label", true, false):
		if (label as Label).text.findn(expect_text) != -1:
			return true
	return false
