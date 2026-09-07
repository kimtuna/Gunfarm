extends SceneTree

## INBOX #25 자체 QA — **하단 핫바 + 든 도구가 캐릭터에 보이고 좌클릭하면 쓴다.**
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_hotbar.gd
##
## 칸 그림 자체(배치/드래그/저장)는 `qa_inventory.gd`, 시트가 실렸는가는
## `qa_player_walk.gd` 가 본다. **여기는 그 둘을 잇는 부분만** 본다:
##   1) 화면 아래에 핫바가 **항상 보인다** — 9칸이 겹치지 않고 화면 안에 있고,
##      **인벤토리 창과 같은 코어를 비춘다**(별도 보관함이 아니다).
##   2) 1번 칸에 도끼를 두고 1번 키를 누르면 캐릭터가 `hold_axe` 로 선다.
##   3) 그 상태로 걸으면 `walk_axe`, 멈추면 다시 `hold_axe`.
##   4) 좌클릭하면 `use_axe` 가 **한 번** 돌고, 끝나면 `hold_axe` 로 돌아온다.
##      **대상이 없어도(허공에 대고) 나가고**, 재생 중에 또 눌러도 처음부터 다시
##      시작하지 않는다 (docs/DESIGN.md 「생활 스킬 — 채집 계열」/「캐릭터 애니메이션」).
##   5) **빈 칸을 고르면 빈손**(`idle`)이고, **시트가 없는 도구**(그때 남아 있는 것
##      하나를 데이터에서 고른다)를 골라도 빈손으로 조용히 넘어간다 — 에러로 죽지 않는다.
##   6) **E 창에서 칸을 옮기면 하단 핫바가 따라온다** — 화면 픽셀로 본다.
##   7) **창이 열려 있는 동안 좌클릭이 안 먹는다** (인벤토리 드래그와 부딪히므로).
##   8) 사용 모션의 **길이**(`player_motion.gd` 의 `USE_TICKS`)와 그림의 길이
##      (프레임 수 ÷ `USE_FPS`)가 같은가 — 어긋나면 모션이 끊기거나 늘어진다.
##   9) **그림이 있는 도구 전부**가 2)~4) 를 지나는지 훑는다 (2026-09-07, INBOX #27).
##      도구는 바퀴마다 하나씩 늘어나므로, 도끼 하나만 보면 새 도구의 배선이
##      검사되지 않은 채 지나간다.

const SlotStore := preload("res://scripts/slot_store.gd")
const WorldGen := preload("res://scripts/world_gen.gd")
const Inventory := preload("res://scripts/inventory.gd")
const InventoryPanel := preload("res://scripts/inventory_panel.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")
const PlayerMotion := preload("res://scripts/player_motion.gd")
const ItemTypes := preload("res://scripts/item_types.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260907

## 프레임 수가 아니라 **시간**으로 기다린다 (docs/GOTCHAS.md) — 수직동기화를 꺼두므로
## 몇 프레임은 몇 ms 밖에 안 되고, 그러면 고정 틱(1/60초)이 한 번도 안 돈다.
const SETTLE_SECONDS := 0.2

## 마우스를 한 자리에 머물게 하는 시간. 매 프레임 다른 자리로 `warp_mouse()` 하면
## OS 가 커서 이동을 합쳐버린다 (docs/GOTCHAS.md).
const MOUSE_SETTLE_SECONDS := 0.12

## 이동 키를 누르고 있는 시간.
const HOLD_SECONDS := 0.3

## 사용 모션 길이(초). 여기보다 넉넉히 기다려야 "끝나면 돌아온다"를 볼 수 있다.
const USE_SECONDS := 0.5

const COLOR_EPSILON := 0.03

## 도끼를 둘 칸(사람 피드백: "1번칸에 도끼가 있고 1번 키를 누르면") 과, 그 뒤 E 창에서
## 끌어다 옮겨볼 칸.
const AXE_SLOT := 0
const MOVED_SLOT := 4
## 시트가 아직 없는 도구를 두는 칸과, 비워둘 칸. **어느 도구를 쓸지는 박아두지
## 않는다** — 도구는 바퀴마다 하나씩 그림이 생기므로(DESIGN.md 「새 도구를 추가하는
## 절차」), 이름을 적어두면 그 도구를 그리는 바퀴가 여기서 거짓 실패한다.
## `_no_sheet_tool()` 이 그때그때 남아 있는 것 하나를 고른다.
const NO_SHEET_SLOT := 2
const EMPTY_SLOT := 8

## 좌클릭을 흘려보낼 자리(논리 좌표). 화면 왼쪽 위의 정보판(마우스를 먹는다)과
## 겹치지 않는 빈 자리다.
const CLICK_POINT := Vector2(640.0, 300.0)

var _steps: Array[Callable] = []
var _step := 0
var _wait := 0
var _wait_time := 0.0
var _fails: Array[String] = []

var _slot_pixels := {}
## 좌클릭 뒤 **한 프레임이라도** 도구를 쓰는 중이었는가. 단계 사이에만 보면 0.5초짜리
## 모션을 통째로 놓칠 수 있어서 매 프레임 지켜본다.
var _using_seen := false
## 두 번째 좌클릭 직전에 남아 있던 사용 틱 — 겹쳐 재생됐는지 견주는 기준이다.
var _use_left_before := -1


func _initialize() -> void:
	# 일부러 최악(빠른) 조건을 만든다 — 프레임 수로 기다리는 실수가 우연히 통과하지
	# 못하게 한다 (docs/GOTCHAS.md).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(SHOTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))

	_check_use_length()

	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("나무꾼", {}, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	# 첫 씬은 여기서 올린다 (docs/GOTCHAS.md — _steps 에 넣으면 영영 실행되지 않는다).
	change_scene_to_file(WORLD_SCENE)

	_steps = [
		_settle,
		_arrange_inventory,
		_stand_on_open_land,
		_settle,
		# 1) 핫바가 처음부터 보인다
		_check_hotbar_visible,
		_check_hotbar_mirrors_core,
		func(): _shoot("70_hotbar"),
		# 2) 1번 키 → 도끼를 든다
		func(): _send_action("hotbar_%d" % (AXE_SLOT + 1)),
		_settle,
		func(): _check_animation("hold_axe", "1번 칸의 도끼를 들었는데"),
		_check_hotbar_selection_drawn,
		func(): _shoot("71_hold_axe"),
		# 3) 든 채로 걷는다
		func(): _walk("down"),
		func(): _check_animation("walk_axe", "도끼를 들고 걷는데"),
		func(): _shoot("72_walk_axe"),
		_stop_walking,
		_settle,
		func(): _check_animation("hold_axe", "걸음을 멈췄는데"),
		# 4) 좌클릭 → 사용 모션 (대상이 없어도 나온다)
		func(): _warp(CLICK_POINT),
		_mouse_settle,
		_click,
		func(): _check_animation("use_axe", "허공에 대고 좌클릭했는데"),
		func(): _shoot("73_use_axe"),
		# 재생 중에 또 눌러도 처음부터 다시 시작하지 않는다
		_remember_use_left,
		_click,
		_check_use_not_restarted,
		_wait_out_use,
		func(): _check_animation("hold_axe", "사용 모션이 끝났는데"),
		# 7) 창이 열려 있는 동안 좌클릭이 안 먹는다 — 지도부터
		func(): _send_action("toggle_map"),
		_settle,
		_click,
		_click_action,
		func(): _check_use_blocked("지도"),
		func(): _send_action("ui_cancel"),
		_settle,
		# 5) 시트가 없는 도구 → 빈손
		func(): _send_action("hotbar_%d" % (NO_SHEET_SLOT + 1)),
		_settle,
		func(): _check_no_sheet_tool(),
		# 빈 칸 → 빈손
		func(): _send_action("hotbar_%d" % (EMPTY_SLOT + 1)),
		_settle,
		func(): _check_animation("idle", "빈 칸을 골랐는데"),
		func(): _shoot("74_empty_hand"),
		# 다시 도끼로 돌려놓고, 6) E 창에서 칸을 옮기면 핫바가 따라오는지 본다
		func(): _send_action("hotbar_%d" % (AXE_SLOT + 1)),
		_settle,
		_remember_hotbar_pixels,
		func(): _send_action("toggle_inventory"),
		_settle,
		_check_hotbar_hidden_while_open,
		# 인벤토리 창이 열린 동안의 좌클릭도 안 먹는다 — 칸이 없는 자리를 눌러본다.
		func(): _warp(Vector2(640.0, 545.0)),
		_mouse_settle,
		_click,
		_click_action,
		func(): _check_use_blocked("인벤토리 창"),
	]
	# 창 안에서 도끼를 AXE_SLOT → MOVED_SLOT 으로 끌어다 놓는다.
	_steps.append_array(_drag_steps(AXE_SLOT, MOVED_SLOT))
	_steps.append_array([
		func(): _send_action("toggle_inventory"),
		_settle,
		_check_hotbar_followed_move,
		func(): _shoot("75_hotbar_after_move"),
		# 옮긴 칸의 번호를 누르면 다시 도끼를 든다 — 핫바 번호와 자리가 안 어긋났다.
		func(): _send_action("hotbar_%d" % (MOVED_SLOT + 1)),
		_settle,
		func(): _check_animation("hold_axe", "도끼를 옮긴 칸의 번호를 눌렀는데"),
	])
	# 9) **그림이 있는 도구는 전부** 골라서 좌클릭하면 그 도구의 모션이 나온다.
	# 도끼는 위에서 자세히 봤으므로(걷기·겹쳐 재생·창에 막히기까지) 나머지는 훑기만
	# 한다 — 도구가 늘 때마다(`docs/DESIGN.md` 「새 도구를 추가하는 절차」 1단계 8번)
	# **이름을 적지 않아도 여기서 저절로 검사된다.** 도끼가 MOVED_SLOT 으로 옮겨가서
	# AXE_SLOT 이 비어 있으므로 그 칸을 돌려쓴다.
	for tool: String in PlayerFrames.TOOLS:
		if tool == "axe":
			continue
		_steps.append_array([
			func(): _move_to(_inventory(), tool, AXE_SLOT),
			func(): _send_action("hotbar_%d" % (AXE_SLOT + 1)),
			_settle,
			func(): _check_animation("hold_%s" % tool, "%s 를 든 칸의 번호를 눌렀는데" % tool),
			func(): _warp(CLICK_POINT),
			_mouse_settle,
			_click,
		])
		# **사용 모션이 없는 도구는 좌클릭해도 들고 있는 자세 그대로여야 한다**
		# (낚싯대 — INBOX #31). 빈손 idle 로 물러나면 0.5초 동안 손에 든 것이
		# 사라지는데, 그건 「캐릭터 애니메이션」의 "도구를 옆에 아이콘으로 띄우지
		# 않는다"(= 든 것이 늘 보여야 한다)와 정면으로 어긋난다.
		if not PlayerFrames.has_use(tool):
			_steps.append_array([
				func(): _check_animation("hold_%s" % tool,
						"사용 모션이 없는 %s 로 좌클릭했는데" % tool),
				func(): _shoot("76_use_%s" % tool),
				_wait_out_use,
				func(): _check_animation("hold_%s" % tool,
						"사용 모션이 없는 %s 로 좌클릭하고 기다렸는데" % tool),
			])
			continue
		_steps.append_array([
			func(): _check_animation("use_%s" % tool, "%s 로 허공에 대고 좌클릭했는데" % tool),
			func(): _shoot("76_use_%s" % tool),
			_wait_out_use,
			func(): _check_animation("hold_%s" % tool, "%s 의 사용 모션이 끝났는데" % tool),
		])


func _process(delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
	_watch_use()
	if _wait_time > 0.0:
		_wait_time -= delta
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size():
		return _report()
	var step: Callable = _steps[_step]
	_step += 1
	_wait = 4  # 상태를 바꾼 프레임에 바로 찍으면 한 프레임 전 화면이 찍힌다 (docs/GOTCHAS.md).
	step.call()
	return false


func _report() -> bool:
	if _fails.is_empty():
		print("[qa] PASS — 하단 핫바 / 든 도구 / 좌클릭 사용 모션 정상")
		return true
	for f in _fails:
		printerr("[qa] FAIL — %s" % f)
	quit(1)
	return true


# =============================================================================
# 8) 그림 길이와 코어 길이가 맞는가 (화면 없이 본다)
# =============================================================================

## `USE_TICKS`(코어가 도구를 쓰는 시간)와 `use_<도구>` 그림의 길이가 어긋나면,
## 짧은 쪽이 끝난 뒤 남은 시간 동안 도끼가 멈춘 그림으로 얼어 있거나 모션이 잘린다.
func _check_use_length() -> void:
	var style := PlayerFrames.DEFAULT_HAIRSTYLE
	for tool: String in PlayerFrames.TOOLS:
		if not PlayerFrames.has_use(tool):
			continue  # 사용 모션이 없는 도구는 견줄 그림이 없다 (낚싯대 — INBOX #31).
		var motion := "use_%s" % tool
		var sheet: Texture2D = load(PlayerFrames.sheet_path(motion, style))
		if sheet == null:
			_fails.append("%s 시트를 못 읽었다 — `--import` 를 안 돌렸을 수 있다" % motion)
			continue
		var columns := sheet.get_width() / PlayerFrames.CELL
		var art_seconds := float(columns) / PlayerFrames.USE_FPS
		var core_seconds := float(PlayerMotion.USE_TICKS) / float(PlayerMotion.TICK_RATE)
		if not is_equal_approx(art_seconds, core_seconds):
			_fails.append("%s 그림은 %.3f초(%d프레임 ÷ %.0ffps)인데 코어는 %.3f초(%d틱)다"
					% [motion, art_seconds, columns, PlayerFrames.USE_FPS,
						core_seconds, PlayerMotion.USE_TICKS])


# =============================================================================
# 1) 하단 핫바
# =============================================================================

func _check_hotbar_visible() -> void:
	var panel := _hotbar_panel()
	if panel == null:
		_fails.append("화면 아래에 핫바가 없다 (%s)" % _HOTBAR_PANEL_PATH)
		return
	if not panel.is_visible_in_tree():
		_fails.append("핫바가 화면에 안 보인다 — 상시로 떠 있어야 한다")
		return
	if not panel.hotbar_only:
		_fails.append("하단에 뜬 것이 인벤토리 창 전체다 — 맨 위 9칸만 그려야 한다")
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var rects: Array[Rect2] = []
	for index in Inventory.HOTBAR_SLOTS:
		var rect: Rect2 = panel.global_slot_rect(Inventory.AREA_GENERAL, index)
		if not screen.encloses(rect):
			_fails.append("핫바 %d번 칸이 화면 밖으로 나갔다 (%s)" % [index + 1, rect])
		for other in rects:
			if other.intersects(rect):
				_fails.append("핫바 칸이 서로 겹친다: %s / %s" % [other, rect])
		rects.append(rect)
	# 한 줄이어야 한다 — 빈 칸도 자리를 지키므로 번호와 자리가 어긋나지 않는다.
	if rects.size() == Inventory.HOTBAR_SLOTS:
		if not is_equal_approx(rects[0].position.y, rects[Inventory.HOTBAR_SLOTS - 1].position.y):
			_fails.append("핫바 9칸이 한 줄이 아니다")
		if rects[0].get_center().y < screen.size.y * 0.5:
			_fails.append("핫바가 화면 아래쪽에 있지 않다 (y=%.0f)" % rects[0].get_center().y)


## **별도 보관함이 아니라 같은 인벤토리를 비추는가.** 다른 객체를 보고 있으면 E 창에서
## 칸을 옮겨도 하단 핫바가 안 따라온다 — 그 순간부터 두 벌이 어긋난다.
func _check_hotbar_mirrors_core() -> void:
	var panel := _hotbar_panel()
	if panel == null:
		return
	if panel.inventory != _inventory():
		_fails.append("핫바가 월드의 인벤토리가 아닌 다른 것을 비추고 있다")


## 고른 칸이 하단 핫바에서도 눈에 띄게 표시되는가 — 화면 픽셀로 본다.
func _check_hotbar_selection_drawn() -> void:
	var image := _capture()
	var panel := _hotbar_panel()
	if image == null or panel == null:
		return
	var selected: int = _inventory().selected_hotbar
	if not _has_selected_border(image, selected):
		_fails.append("핫바 %d번 칸이 화면에서 '고른 칸'으로 안 보인다" % (selected + 1))
	for other in Inventory.HOTBAR_SLOTS:
		if other != selected and _has_selected_border(image, other):
			_fails.append("%d번을 골랐는데 핫바 %d번도 골라진 것처럼 보인다"
					% [selected + 1, other + 1])
			break


func _has_selected_border(image: Image, index: int) -> bool:
	var rect: Rect2 = _hotbar_panel().global_slot_rect(Inventory.AREA_GENERAL, index)
	var at := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
	for offset in range(-3, 4):
		if _is_color(_pixel(image, at + Vector2(0.0, offset)), InventoryPanel.SELECTED_BORDER):
			return true
	return false


func _check_hotbar_hidden_while_open() -> void:
	var hotbar := _hotbar()
	if hotbar != null and hotbar.is_visible_in_tree():
		_fails.append("인벤토리 창을 열었는데 하단 핫바가 그대로 떠 있다 — 창과 겹친다")


# =============================================================================
# 6) E 창에서 칸을 옮기면 핫바가 따라온다 (화면 픽셀로)
# =============================================================================

func _remember_hotbar_pixels() -> void:
	var image := _capture()
	if image == null:
		return
	for index: int in [AXE_SLOT, MOVED_SLOT]:
		_slot_pixels[index] = _slot_fingerprint(image, index)


func _check_hotbar_followed_move() -> void:
	var inv := _inventory()
	var moved: RefCounted = inv.at(Inventory.AREA_GENERAL, MOVED_SLOT)
	if moved == null or moved.id != "axe":
		_fails.append("창에서 도끼를 %d번 칸으로 못 옮겼다 (%s)"
				% [MOVED_SLOT + 1, "빈 칸" if moved == null else moved.id])
		return
	var image := _capture()
	if image == null or _slot_pixels.is_empty():
		return
	for index: int in [AXE_SLOT, MOVED_SLOT]:
		if _slot_fingerprint(image, index) == _slot_pixels[index]:
			_fails.append("창에서 칸을 옮겼는데 하단 핫바 %d번 칸 그림이 그대로다 — 안 따라온다"
					% (index + 1))


## 핫바 칸 하나의 안쪽을 성기게 훑어 지문 문자열로 만든다. 테두리는 고른 칸 표시가
## 섞이므로 뺀다 — 여기서 보려는 것은 **칸 안의 아이템 그림이 바뀌었는가**다.
func _slot_fingerprint(image: Image, index: int) -> String:
	var rect: Rect2 = _hotbar_panel().global_slot_rect(Inventory.AREA_GENERAL, index).grow(-10.0)
	var out := ""
	for row in 6:
		for column in 6:
			var at := rect.position + rect.size * Vector2(column / 5.0, row / 5.0)
			out += _pixel(image, at).to_html(false)
	return out


# =============================================================================
# 2~5, 7) 든 도구 / 사용 모션
# =============================================================================

## 지금 돌고 있는 애니메이션이 그 모션인가. `motion` 은 `hold_axe` 처럼 방향을 뺀
## 이름이고, 방향은 지금 보고 있는 쪽으로 맞춰 본다.
func _check_animation(motion: String, because: String) -> void:
	var sprite := _sprite()
	if sprite == null:
		_fails.append("플레이어 스프라이트를 못 찾았다")
		return
	var dir: String = PlayerFrames.DIR_NAMES[_player().motion.facing]
	var want := "%s_%s" % [motion, dir]
	if sprite.animation != want:
		_fails.append("%s 애니메이션이 %s 다 — %s 여야 한다" % [because, sprite.animation, want])


## 두 번째 좌클릭 직전에 남아 있던 사용 틱을 적어둔다.
func _remember_use_left() -> void:
	_use_left_before = int(_player().motion.use_ticks_left)
	if _use_left_before <= 8:
		_fails.append("두 번째 좌클릭을 하기도 전에 사용 모션이 거의 끝났다 (%d틱 남음)"
				% _use_left_before)


## 재생 중에 또 눌러도 **처음부터 다시 시작하지 않는다** — 겹쳐 재생됐다면 남은 틱이
## 다시 최대치로 되돌아가서, 그 사이에 흐른 시간만큼 줄어들지 않는다.
func _check_use_not_restarted() -> void:
	var left := int(_player().motion.use_ticks_left)
	if left > _use_left_before - 4:
		_fails.append("사용 모션 중에 또 좌클릭했더니 처음부터 다시 시작했다 (%d틱 → %d틱)"
				% [_use_left_before, left])


## 창이 열려 있는 동안 좌클릭이 **아예 안 먹는가** — 인벤토리에서 아이템을 끄는
## 좌클릭과 부딪히므로(docs/DESIGN.md 「인벤토리 / 장비」의 키 규칙).
func _check_use_blocked(where: String) -> void:
	if _using_seen:
		_fails.append("창(%s)이 열려 있는데 좌클릭이 도구 사용까지 흘러갔다" % where)


## 사용 모션이 끝날 때까지 기다린다.
func _wait_out_use() -> void:
	_wait_time = USE_SECONDS + SETTLE_SECONDS


## 매 프레임 "쓰는 중이었는가"를 지켜본다 — 좌클릭 뒤 한 번이라도 켜졌는지를
## 놓치지 않으려면 단계 사이가 아니라 프레임마다 봐야 한다.
func _watch_use() -> void:
	var player := _player()
	if player == null or player.motion == null:
		return
	if player.motion.is_using():
		_using_seen = true


func _click() -> void:
	_using_seen = false
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = root.get_mouse_position()
	Input.parse_input_event(event)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = event.position
	Input.parse_input_event(release)
	_wait_time = SETTLE_SECONDS


## 좌클릭을 **액션 이벤트로** 흘려보낸다. 겹쳐 뜬 창(지도/인벤토리)은 마우스 버튼을
## 자기 `_input`/GUI 에서 먼저 먹어버려서, 마우스만으로는 `world.gd` 의 "창이 열려
## 있으면 안 먹는다" 판단이 **한 번도 불려보지 않은 채** 통과한다. 액션 이벤트는
## Control 이 안 먹으므로 `_unhandled_input` 까지 그대로 도달한다 (docs/GOTCHAS.md).
func _click_action() -> void:
	_send_action("use_tool")
	_wait_time = SETTLE_SECONDS


func _walk(dir: String) -> void:
	Input.action_press("move_%s" % dir)
	_wait_time = HOLD_SECONDS


func _stop_walking() -> void:
	for dir: String in ["up", "down", "left", "right"]:
		Input.action_release("move_%s" % dir)


# =============================================================================
# 도구
# =============================================================================

const _HOTBAR_PANEL_PATH := "HUD/Layout/Hotbar/HotbarPanel"


## 검사할 상황을 만든다 — 1번 칸에 도끼, 3번 칸에 시트가 없는 도구(곡괭이),
## 9번 칸은 비운다. **코어를 직접 만진다**(끌어다 놓기 자체는 `qa_inventory.gd` 가
## 이미 보고 있고, 여기서 보려는 것은 그 뒤의 캐릭터/핫바다).
func _arrange_inventory() -> void:
	var inv := _inventory()
	if inv == null:
		_fails.append("월드에 인벤토리가 없다")
		return
	_move_to(inv, "axe", AXE_SLOT)
	var bare := _no_sheet_tool()
	if bare != "":
		_move_to(inv, bare, NO_SHEET_SLOT)
	_empty_slot(inv, EMPTY_SLOT)
	_empty_slot(inv, MOVED_SLOT)


## 그 칸을 비운다 — **도구는 버리지 않는다.** 인벤토리 18칸이 처음부터 꽉 차 있어서
## (`world.gd` 의 `STARTER_ITEMS`) 그냥 버리면 그 자리에 밀려 온 것이 사라지는데,
## 도구가 밀려 오면 아래 「도구 훑기」가 그 도구를 못 찾는다. 도구가 걸리면
## **도구가 아닌 칸과 자리를 바꿔서** 버릴 것을 도구가 아닌 것으로 만든다.
## (2026-09-07, INBOX #28 — 총에 그림이 생기면서 `_no_sheet_tool()` 이 고르는 도구가
## 바뀌자 곡괭이가 이 자리에서 조용히 사라졌다.)
func _empty_slot(inv: RefCounted, slot: int) -> void:
	var stack: RefCounted = inv.at(Inventory.AREA_GENERAL, slot)
	if stack == null:
		return
	if ItemTypes.max_stack(stack.id) == ItemTypes.MAX_STACK_UNIQUE:
		for index in inv.slot_count(Inventory.AREA_GENERAL):
			var other: RefCounted = inv.at(Inventory.AREA_GENERAL, index)
			if index == slot or other == null \
					or ItemTypes.max_stack(other.id) == ItemTypes.MAX_STACK_UNIQUE:
				continue
			inv.move(Inventory.AREA_GENERAL, slot, Inventory.AREA_GENERAL, index)
			break
	inv.take_out(Inventory.AREA_GENERAL, slot)


## 아직 그림이 없는 도구 하나(없으면 빈 문자열). **도구**는 한 칸에 하나만 들어가고
## (`MAX_STACK_UNIQUE`) 장비 칸에 안 들어가는 아이템이다 — 그 정의로 고르면
## DESIGN.md 「채집 계열」의 도구 7종이 그대로 나오고, 목록을 여기 또 적지 않아도 된다.
func _no_sheet_tool() -> String:
	for id: String in ItemTypes.ITEMS:
		if ItemTypes.max_stack(id) == ItemTypes.MAX_STACK_UNIQUE \
				and ItemTypes.equip_kind(id) == ItemTypes.EQUIP_NONE \
				and not PlayerFrames.TOOLS.has(id):
			return id
	return ""


## 5) 시트가 없는 도구를 들어도 **빈손으로 조용히 넘어간다**. 도구 7종이 전부 그려지면
## 시험할 것이 없어지므로 그때는 건너뛴다 — 거짓 실패를 만들지 않는다.
func _check_no_sheet_tool() -> void:
	var bare := _no_sheet_tool()
	if bare == "":
		print("[qa] 건너뜀 — 시트 없는 도구가 이제 없다 (도구 7종 전부 그려졌다)")
		return
	_check_animation("idle", "시트가 없는 도구(%s)를 들었는데" % bare)


func _move_to(inv: RefCounted, id: String, slot: int) -> void:
	for index in inv.slot_count(Inventory.AREA_GENERAL):
		var stack: RefCounted = inv.at(Inventory.AREA_GENERAL, index)
		if stack == null or stack.id != id:
			continue
		if index != slot:
			inv.move(Inventory.AREA_GENERAL, index, Inventory.AREA_GENERAL, slot)
		return
	_fails.append("처음 들어온 캐릭터에게 %s 가 없다" % id)


## 인벤토리 창 안에서 한 칸을 다른 칸으로 실제 마우스로 끌어다 놓는 단계들
## (`qa_inventory.gd` 와 같은 방식 — 화면 좌표 → 칸 변환까지 그대로 지나간다).
func _drag_steps(from_slot: int, to_slot: int) -> Array[Callable]:
	return [
		func(): _warp(_window_slot_center(from_slot)),
		_mouse_settle,
		func(): _mouse_button(true),
		_mouse_settle,
		func(): _warp(_window_slot_center(to_slot)),
		_mouse_settle,
		func(): _mouse_button(false),
		_settle,
	]


func _window_slot_center(slot: int) -> Vector2:
	var panel := _window_panel()
	if panel == null:
		_fails.append("인벤토리 창의 칸 그림을 못 찾았다")
		return Vector2.ZERO
	return panel.global_slot_rect(Inventory.AREA_GENERAL, slot).get_center()


func _mouse_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_mouse_position()
	Input.parse_input_event(event)


func _warp(point: Vector2) -> void:
	Input.warp_mouse(point)


func _mouse_settle() -> void:
	_wait_time = MOUSE_SETTLE_SECONDS


func _settle() -> void:
	_wait_time = SETTLE_SECONDS


func _send_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


## 사방이 육지인 자리로 옮겨 선다 — 걷는 검사가 바다에 막혀 거짓 실패하지 않게.
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


func _sprite() -> AnimatedSprite2D:
	var player := _player()
	return null if player == null else player.get_node_or_null("Sprite") as AnimatedSprite2D


func _hotbar() -> Control:
	return current_scene.get_node_or_null("HUD/Layout/Hotbar") as Control


func _hotbar_panel() -> Control:
	return current_scene.get_node_or_null(_HOTBAR_PANEL_PATH) as Control


func _window_panel() -> Control:
	var screen := current_scene.get_node_or_null("HUD/InventoryScreen") as Control
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
