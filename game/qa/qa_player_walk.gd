extends SceneTree

## INBOX #15 자체 QA — **월드의 플레이어가 실제로 걷는가.**
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_player_walk.gd
##
## 그림 자체(프레임 사이가 매끄러운가, 자세가 idle 과 이어지는가)는 파이썬 쪽
## `qa_sprite_check.py` 의 「이어짐」이 본다. 여기는 **엔진에 제대로 실렸는가**만 본다:
##   1) `<모션>_<방향>` 애니메이션이 **모든 모션 × 네 방향** 다 있고, 프레임 수가
##      시트의 열 수와 같고, 도는(loop) 애니메이션이다. **도구를 든 모션도 여기
##      포함이다**(2026-09-07, INBOX #24 — `docs/DESIGN.md` 「새 도구를 추가하는
##      절차」 4: 안 넓히면 새 모션은 아무도 검사하지 않는다). 동작(좌클릭으로
##      패기)은 `qa_hotbar.gd` 가 보고, 여기는 **시트가 실렸는가**까지다.
##      **사용 모션만 돌지 않는다**(INBOX #25 — 한 번 내려치고 끝난다).
##   2) **모든 모션 시트가 외형대로 칠해진다** — idle 만 칠하고 나머지를 빠뜨리면
##      그 모션으로 바뀌는 순간 캐릭터가 기준색으로 되돌아간다. 모션 × 네 방향 ×
##      모든 프레임을 픽셀로 견준다.
##   3) 이동 키를 누르면 애니메이션이 `walk_<방향>` 으로 바뀌고 **프레임이 실제로
##      넘어간다**(멈춰 있는 애니메이션은 걷는 것으로 안 보인다), 떼면 idle 로 돌아온다.
##   4) 네 방향 모두 그 방향의 걷기로 바뀐다 — 방향과 행이 어긋나면 옆으로 걸으면서
##      앞모습이 나온다.
##   5) **행을 정하는 것은 이동 키가 아니라 마우스다**(INBOX #16) — 왼쪽으로 걸으면서
##      오른쪽을 조준하면 `walk_right` 가 돌아야 한다(게걸음).
##
## 눈으로 볼 몫은 `user://qa_shots/` 에 남긴다 — 걷는 중의 월드 화면과, 걷기
## 프레임을 한 줄로 이어붙여 확대한 것(넘겨보지 않고도 한눈에 견줄 수 있다).

const SettingsStore := preload("res://scripts/settings_store.gd")
const _Inventory := preload("res://scripts/inventory.gd")

const SlotStore := preload("res://scripts/slot_store.gd")
const CharacterSprite := preload("res://scripts/character_sprite.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260906

## 기준색과 먼 조합 — 걷기 시트를 칠하는 걸 빠뜨리면 그 순간 눈에 띄게 색이 튄다.
const LOOK := {
	"skin": "deep", "hair_color": "blond", "clothes_color": "ember", "hairstyle": "long",
}

## 방향 → 누를 키. `player_motion.gd` 의 방향 순서와 이름이 같아야 한다.
const KEYS := {
	"down": "move_down", "left": "move_left", "right": "move_right", "up": "move_up",
}

## 방향 이름 → 조준 각도(라디안). 화면 가운데(=플레이어)에서 마우스를 이쪽으로 민다.
const AIM := {"right": 0.0, "down": PI * 0.5, "left": PI, "up": -PI * 0.5}

## 마우스를 화면 가운데에서 얼마나 밀어놓는가(창 짧은 변에 대한 비율).
const AIM_REACH := 0.3

## 애니메이션이 실제로 넘어가는지 보려면 한 프레임(1/`WALK_FPS` 초)보다 확실히
## 오래 눌러야 한다. 0.5초 = 걷기 5프레임.
##
## **프레임 수가 아니라 시간으로 센다**(2026-09-07, INBOX #20). `--script` 로 띄운
## 창은 수직동기화가 없어 수백~수천 fps 로 돌아서(docs/GOTCHAS.md), "25프레임
## 기다리기"가 실제로는 몇 ms 라 10fps 애니메이션이 한 칸도 안 넘어간다 — 빠른
## 기계에서 이 검사가 통째로 거짓 실패했다.
const HOLD_SECONDS := 0.5

## 상태를 바꾼 뒤 다음 단계까지 두는 여유(초). 캡처가 한 프레임 전을 찍지 않게,
## 그리고 고정 틱(1/60초) 위에서 도는 로직이 실제로 몇 번 돌게 하려면 필요하다.
const SETTLE_SECONDS := 0.15

## 걷기 프레임 미리보기 배율. 17px 칸이라 그냥 저장하면 눈으로 판정할 수 없다.
const STRIP_ZOOM := 8

var _fails: Array[String] = []
var _steps: Array[Callable] = []
var _step := 0
var _wait_time := 0.0
var _seen_frames := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# **일부러 수직동기화를 끈다** (2026-09-07, INBOX #21) — `qa_player_world.gd` 와 같은
	# 이유다. 켜져 있으면 한 프레임이 16ms 라 프레임 수로 기다리는 코드가 우연히
	# 통과하고, 사람의 빠른 기계(120Hz 이상)에서만 거짓 실패한다.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# 이전 실행의 슬롯이 남아 거짓 결과를 내지 않게 지우고 시작한다 (docs/GOTCHAS.md).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("걷는이", LOOK, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	# 첫 씬은 여기서 올린다 (docs/GOTCHAS.md — _steps 에 넣으면 영영 실행되지 않는다).
	change_scene_to_file(WORLD_SCENE)

	_steps = [
		_free_hand,
		_check_animations,
		_check_recolored,
		func(): _shoot("80_walk_idle"),
	]
	# 네 방향을 차례로 걸어본다. 방향마다 (누른다 → 확인 → 뗀다 → idle 확인).
	# 이동 키와 조준을 같은 쪽으로 두는 짝이라 네 방향 시트를 다 지나간다.
	for dir: String in PlayerFrames.DIR_NAMES:
		_steps.append(func(): _press(dir, dir))
		_steps.append(func(): _check_walking(dir))
		_steps.append(func(): _release(dir))
		_steps.append(func(): _check_idle(dir))
	# **어긋난 짝**(INBOX #16): 왼쪽으로 걸으면서 오른쪽을 조준하면 walk_right 다.
	_steps.append(func(): _press("left", "right"))
	_steps.append(func(): _check_walking("right"))
	_steps.append(func(): _shoot("83_walk_left_aim_right"))
	_steps.append(func(): _release("left"))
	_steps.append(func(): _check_idle("right"))
	_steps.append(func(): _press("right", "right"))
	_steps.append(func(): _shoot("81_walk_moving"))
	_steps.append(func(): _release("right"))
	_steps.append(_save_strip)
	_steps.append(_save_tool_strips)



## **맨손으로 만든다** — 이 검사가 보는 것은 맨손 idle/걷기 시트인데, 처음 들어온
## 캐릭터는 **든 칸(1번)에 도구가 들어 있다**(`world.gd` 의 `STARTER_ITEMS`).
## 그 도구에 그림이 생기는 순간 `hold_<도구>` 가 나오므로, 도구 이름에 기대지 않게
## 그 칸을 비운다. (2026-09-07, INBOX #28 — 총에 그림이 생기면서 걸렸다.)
func _free_hand() -> void:
	if current_scene == null:
		return
	var inv: RefCounted = current_scene.get("inventory")
	if inv == null:
		return
	inv.take_out(_Inventory.AREA_GENERAL, 0)

func _process(delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
	if _resize_window_if_needed():
		return false
	if _wait_time > 0.0:
		_wait_time -= delta
		return false
	if _step >= _steps.size():
		return _report()
	var step: Callable = _steps[_step]
	_step += 1
	_wait_time = SETTLE_SECONDS
	step.call()
	return false


# --- 검사 ---------------------------------------------------------------------

func _player() -> Node2D:
	return current_scene.get_node_or_null("%Player") as Node2D


func _sprite() -> AnimatedSprite2D:
	var player := _player()
	return null if player == null else player.get_node_or_null("Sprite") as AnimatedSprite2D


## **모든 모션**이 네 방향 다 있고, 시트의 열 수만큼 프레임이 있고, 도는가.
##
## 여러 프레임짜리 모션(걷기 · 도구 사용)은 `DESIGN.md` 「캐릭터 애니메이션」의
## 4~6프레임도 함께 본다. 서 있는 모션(idle · 도구를 들고 있기)은 한 장이므로 뺀다.
func _check_animations() -> void:
	var sprite := _sprite()
	if sprite == null or sprite.sprite_frames == null:
		_fails.append("플레이어에 SpriteFrames 가 없다")
		return
	var style := String(LOOK["hairstyle"])
	var counted := 0
	for motion: String in PlayerFrames.motions():
		var sheet: Texture2D = load(PlayerFrames.sheet_path(motion, style))
		if sheet == null:
			_fails.append("%s 시트를 못 읽었다 — `--import` 를 안 돌렸을 수 있다" % motion)
			continue
		# **칸 크기는 그 시트에서 읽는다**(2026-09-08, INBOX #47). `CELL` 하나로
		# 나누면 32px idle 옆의 17px 걷기 시트가 6열이 아니라 3열로 읽혀서
		# 멀쩡한 시트가 「4~6프레임이 아니다」로 걸린다 — 엔진(`add_motion()`)이
		# 이미 시트마다 자기 칸으로 자르는 것과 같은 규칙이다(INBOX #46).
		var columns := sheet.get_width() / PlayerFrames.cell_of(sheet)
		if columns > 1 and (columns < 4 or columns > 6):
			_fails.append("%s 가 %d프레임이다 — DESIGN.md 「캐릭터 애니메이션」은 4~6프레임이다"
					% [motion, columns])
		for dir: String in PlayerFrames.DIR_NAMES:
			var anim := "%s_%s" % [motion, dir]
			if not sprite.sprite_frames.has_animation(anim):
				_fails.append("%s 애니메이션이 없다 — %s 시트가 안 실렸다" % [anim, motion])
				continue
			var count := sprite.sprite_frames.get_frame_count(anim)
			if count != columns:
				_fails.append("%s 가 %d프레임이다 — 시트는 %d열이다" % [anim, count, columns])
			# **사용 모션만 돌지 않는다** — 좌클릭 한 번에 한 번 내려치고 끝나야
			# 하기 때문이다(2026-09-07, INBOX #25). 나머지는 전부 돌아야 한다.
			var loops: bool = sprite.sprite_frames.get_animation_loop(anim)
			if loops and PlayerFrames.plays_once(motion):
				_fails.append("%s 가 도는 애니메이션이다 — 사용 모션은 한 번만 재생돼야 한다" % anim)
			elif not loops and not PlayerFrames.plays_once(motion):
				_fails.append("%s 가 도는 애니메이션이 아니다 — 한 바퀴 돌고 멈춘다" % anim)
			counted += 1
	if _fails.is_empty():
		print("[qa] 모션 %d종 × 4방향 = %d개 애니메이션 (사용 모션만 한 번 재생) (%s)"
				% [PlayerFrames.motions().size(), counted,
					", ".join(PlayerFrames.motions().keys())])


## **모든 모션 시트가 고른 외형으로 칠해졌는가.** idle 만 칠하면 다른 모션으로
## 바뀌는 순간 기준색으로 튄다 — 모션 × 네 방향 × 모든 프레임을 픽셀로 견준다.
##
## **도구 재질(자루·날)은 칠해지면 안 된다** — 팔레트 교체는 기준색 램프에 있는
## 색만 갈아끼우고 도구 램프는 커스터마이징과 무관한 고정색이라(`gen_character.py`
## 의 `HELVE`/`BLADE`), 여기서 픽셀이 그대로 같다는 것이 곧 그 확인이다.
func _check_recolored() -> void:
	for motion: String in PlayerFrames.motions():
		if not _check_recolored_motion(motion):
			return
	print("[qa] 모션 %d종 × 4방향 × 모든 프레임이 고른 외형(%s)으로 칠해져 있다"
			% [PlayerFrames.motions().size(), LOOK["hairstyle"]])


func _check_recolored_motion(motion: String) -> bool:
	var want := CharacterSprite.motion_texture(LOOK, motion)
	if want == null:
		_fails.append("칠한 %s 텍스처를 못 만들었다" % motion)
		return false
	var image := want.get_image()
	var sprite := _sprite()
	if sprite == null or sprite.sprite_frames == null:
		return false
	# 칸 크기는 **그 모션의 시트**에서 읽는다 — 32px idle 옆의 17px 걷기 시트를
	# `CELL`(32)로 자르면 엉뚱한 자리를 견주게 된다(2026-09-08, INBOX #47).
	var cell := PlayerFrames.cell_of(want)
	for row in PlayerFrames.DIR_NAMES.size():
		var anim := "%s_%s" % [motion, PlayerFrames.DIR_NAMES[row]]
		if not sprite.sprite_frames.has_animation(anim):
			return false
		for f in sprite.sprite_frames.get_frame_count(anim):
			var texture := sprite.sprite_frames.get_frame_texture(anim, f)
			if texture == null:
				_fails.append("%s #%d 프레임이 비었다" % [anim, f])
				return false
			var got := texture.get_image()
			var wrong := 0
			for y in cell:
				for x in cell:
					if not got.get_pixel(x, y).is_equal_approx(
							image.get_pixel(f * cell + x, row * cell + y)):
						wrong += 1
			if wrong > 0:
				_fails.append("%s #%d 가 칠한 시트와 %d픽셀 다르다 — %s 가 안 칠해졌다"
						% [anim, f, wrong, motion])
				return false
	return true


## 걷는 동안 **조준한 방향**의 걷기가 돌고, **프레임이 실제로 넘어가는가.**
## `dir` 은 누른 키가 아니라 조준 방향이다 (INBOX #16).
func _check_walking(dir: String) -> void:
	var sprite := _sprite()
	if sprite == null:
		return
	var want := "walk_%s" % dir
	if sprite.animation != want:
		_fails.append("%s 를 조준한 채 걷고 있는데 애니메이션이 %s 다" % [dir, sprite.animation])
		return
	if _seen_frames.get(dir, 1) < 2:
		_fails.append("%s 로 걷는 동안 프레임이 %d 종류만 나왔다 — 그림이 멈춰 있다"
				% [dir, _seen_frames.get(dir, 0)])
		return
	print("[qa] %s: %s 재생, %d프레임이 실제로 넘어갔다" % [dir, want, _seen_frames[dir]])


func _check_idle(dir: String) -> void:
	var sprite := _sprite()
	if sprite == null:
		return
	if sprite.animation != "idle_%s" % dir:
		_fails.append("이동 키를 뗐는데 애니메이션이 %s 다 — idle_%s 로 안 돌아온다"
				% [sprite.animation, dir])


# --- 조작 ---------------------------------------------------------------------

## 조준 기준점에서 그 방향으로 실제 마우스를 옮긴다 — 노드의 "마우스 → 각도"
## 변환을 그대로 지나가야 실제 조작과 같은 경로가 된다. 화면 한가운데는 발밑이라
## 몸 절반만큼 위를 기준점으로 잡는다(`player.gd` 의 `aim_origin()`).
func _aim(dir: String) -> void:
	# **논리 좌표**로 잡는다 — 아래에서 `_to_window()` 로 한 번만 창 픽셀로 옮긴다.
	# 창 크기로 잡으면 이미 창 픽셀인 값을 한 번 더 변환해서 조준 각도가 어긋난다
	# (2026-09-08, INBOX #48 — 그 전에는 논리 해상도와 창 크기가 같아서 안 드러났다).
	var size := root.get_visible_rect().size
	var origin := size * 0.5 - Vector2(0.0, PlayerFrames.CELL * PlayerFrames.SCALE * 0.5)
	Input.warp_mouse(_to_window(origin + Vector2.from_angle(AIM[dir]) * minf(size.x, size.y) * AIM_REACH))


## `Input.action_press()` + `Input.warp_mouse()` 로 실제 입력처럼 넣어준다 —
## `player.gd` 는 키와 마우스만 읽으므로 (docs/DESIGN.md 「서버 권위」) 여기를
## 통과시키면 실제 조작과 같은 경로가 돈다. `move_dir` 과 `aim_dir` 은 달라도 된다.
func _press(move_dir: String, aim_dir: String) -> void:
	_aim(aim_dir)
	Input.action_press(KEYS[move_dir])
	_seen_frames[aim_dir] = 0
	_wait_time = HOLD_SECONDS + SETTLE_SECONDS
	# 누르고 있는 **실제 시간** 동안 몇 종류의 프레임이 나왔는지 센다 — 프레임 수로
	# 세면 창이 빠를수록 짧게 눌러서, 걷기가 멀쩡해도 한 칸도 안 넘어간다.
	var seen := {}
	var sprite := _sprite()
	var until := Time.get_ticks_msec() + int(HOLD_SECONDS * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
		if sprite != null:
			seen[sprite.frame] = true
	_seen_frames[aim_dir] = seen.size()


func _release(dir: String) -> void:
	Input.action_release(KEYS[dir])


# --- 캡처 ---------------------------------------------------------------------

## 걷기 프레임을 한 줄로 이어붙여 확대 저장한다 — **앞에 idle 을 한 장 붙인다.**
## idle 에서 걷기로 넘어갈 때 자세가 뚝 끊기는지는 나란히 놓아야 보인다
## (docs/DESIGN.md 「캐릭터 애니메이션」).
func _save_strip() -> void:
	var sprite := _sprite()
	if sprite == null or sprite.sprite_frames == null:
		return
	var cell := PlayerFrames.CELL
	var dirs: Array = PlayerFrames.DIR_NAMES
	var columns := sprite.sprite_frames.get_frame_count("walk_%s" % dirs[0]) + 1
	var strip := Image.create_empty(columns * cell, dirs.size() * cell, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.12, 0.11, 0.13))
	for row in dirs.size():
		_blit(strip, sprite, "idle_%s" % dirs[row], 0, 0, row)
		for f in columns - 1:
			_blit(strip, sprite, "walk_%s" % dirs[row], f, f + 1, row)
	strip.resize(strip.get_width() * STRIP_ZOOM, strip.get_height() * STRIP_ZOOM,
			Image.INTERPOLATE_NEAREST)
	var path := "%s/82_walk_frames.png" % SHOTS
	strip.save_png(path)
	print("[qa] shot %s (왼쪽 첫 칸이 idle, 나머지가 걷기 한 바퀴)" % path)


## 도구를 든 모션도 같은 방식으로 한 장에 이어붙인다 — **맨 왼쪽 두 칸이 맨손
## idle 과 그 도구를 들고 서 있기**다. 「도구를 들었더니 다른 캐릭터가 됐는가」와
## 「사용 모션이 들고 있기에서 자연스럽게 이어지는가」는 나란히 놓아야 보인다
## (docs/DESIGN.md 「캐릭터 애니메이션」).
func _save_tool_strips() -> void:
	var sprite := _sprite()
	if sprite == null or sprite.sprite_frames == null:
		return
	var cell := PlayerFrames.CELL
	var dirs: Array = PlayerFrames.DIR_NAMES
	var shot := 84
	for tool: String in PlayerFrames.TOOLS:
		for motion in ["use_%s" % tool, "walk_%s" % tool]:
			if not sprite.sprite_frames.has_animation("%s_%s" % [motion, dirs[0]]):
				continue
			var frames := sprite.sprite_frames.get_frame_count("%s_%s" % [motion, dirs[0]])
			var columns := frames + 2
			var strip := Image.create_empty(columns * cell, dirs.size() * cell, false,
					Image.FORMAT_RGBA8)
			strip.fill(Color(0.12, 0.11, 0.13))
			for row in dirs.size():
				_blit(strip, sprite, "idle_%s" % dirs[row], 0, 0, row)
				_blit(strip, sprite, "hold_%s_%s" % [tool, dirs[row]], 0, 1, row)
				for f in frames:
					_blit(strip, sprite, "%s_%s" % [motion, dirs[row]], f, f + 2, row)
			strip.resize(strip.get_width() * STRIP_ZOOM, strip.get_height() * STRIP_ZOOM,
					Image.INTERPOLATE_NEAREST)
			var path := "%s/%d_%s_frames.png" % [SHOTS, shot, motion]
			strip.save_png(path)
			print("[qa] shot %s (왼쪽 두 칸이 맨손 idle · 도구를 들고 서 있기)" % path)
			shot += 1


func _blit(strip: Image, sprite: AnimatedSprite2D, anim: String, frame: int,
		column: int, row: int) -> void:
	if not sprite.sprite_frames.has_animation(anim):
		return
	var texture := sprite.sprite_frames.get_frame_texture(anim, frame)
	if texture == null:
		return
	var cell := PlayerFrames.CELL
	strip.blend_rect(texture.get_image(), Rect2i(0, 0, cell, cell),
			Vector2i(column * cell, row * cell))


func _shoot(shot_name: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		print("[qa] 캡처 건너뜀 — --headless 로 돌렸다(뷰포트 텍스처 없음)")
		return
	var path := "%s/%s.png" % [SHOTS, shot_name]
	texture.get_image().save_png(path)
	print("[qa] shot %s" % path)


func _report() -> bool:
	if _fails.is_empty():
		print("[qa] PASS — 네 방향 걷기가 실려 있고, 외형대로 칠해지고, 마우스 조준 방향에 맞춰 돈다")
		return true
	for f in _fails:
		printerr("[qa] FAIL — %s" % f)
	quit(1)
	return true

## 논리 좌표 → 창 픽셀. `Input.warp_mouse` 와 `parse_input_event` 는 OS 가 주는 것과 같은
## **창 픽셀**을 받는데, 우리가 재는 자리(Control 의 global_rect, 카메라 변환 결과)는 전부
## **논리 좌표**다. 논리 해상도(1440x810)와 창 크기가 갈린 2026-09-08 부터 둘이 다르다 —
## 그 전에는 값이 같아서 이 변환 없이도 통했다. `get_screen_transform()` 이 stretch 배율과
## (비율이 안 맞는 창의) 검은 여백 오프셋까지 함께 처리한다.
func _to_window(point: Vector2) -> Vector2:
	return root.get_screen_transform() * point


## 창을 논리 해상도와 같게 **유지**한다. 화면 픽셀을 짚어보고 마우스를 논리 좌표로 미는
## 검사라, 배율이 1 이 아니면 얇은 테두리가 downscale 에 뭉개지고 좌표가 어긋난다
## (2026-09-08, INBOX #48 — 논리 해상도 1440x810 과 기본 창 크기 1280x720 이 갈렸다).
##
## **되돌린 프레임에는 단계를 돌리지 않고 쉰다**(true 를 돌려준다). 창은 늘 기본 크기로
## 열리므로 이 대기는 **매 실행의 첫 프레임에 반드시 한 번 일어난다** — 없으면 크기 변경이
## 화면에 반영되기 전에 첫 단계가 마우스를 밀어 가끔 거짓 실패한다.
## 대기는 프레임 수가 아니라 **초**로 센다 (docs/GOTCHAS.md).
func _resize_window_if_needed() -> bool:
	if DisplayServer.window_get_size() == SettingsStore.BASE_SIZE:
		return false
	DisplayServer.window_set_size(SettingsStore.BASE_SIZE)
	_wait_time = SETTLE_SECONDS
	return true
