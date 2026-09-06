extends SceneTree

## INBOX #15 자체 QA — **월드의 플레이어가 실제로 걷는가.**
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_player_walk.gd
##
## 그림 자체(프레임 사이가 매끄러운가, 자세가 idle 과 이어지는가)는 파이썬 쪽
## `qa_sprite_check.py` 의 「이어짐」이 본다. 여기는 **엔진에 제대로 실렸는가**만 본다:
##   1) `walk_<방향>` 애니메이션이 네 방향 다 있고, 프레임 수가 시트의 열 수와
##      같고, 도는(loop) 애니메이션이다.
##   2) **걷기 시트도 외형대로 칠해진다** — idle 만 칠하고 걷기를 빠뜨리면 움직이는
##      순간 캐릭터가 기준색으로 되돌아간다. 네 방향 × 모든 프레임을 픽셀로 견준다.
##   3) 이동 키를 누르면 애니메이션이 `walk_<방향>` 으로 바뀌고 **프레임이 실제로
##      넘어간다**(멈춰 있는 애니메이션은 걷는 것으로 안 보인다), 떼면 idle 로 돌아온다.
##   4) 네 방향 모두 그 방향의 걷기로 바뀐다 — 방향과 행이 어긋나면 옆으로 걸으면서
##      앞모습이 나온다.
##   5) **행을 정하는 것은 이동 키가 아니라 마우스다**(INBOX #16) — 왼쪽으로 걸으면서
##      오른쪽을 조준하면 `walk_right` 가 돌아야 한다(게걸음).
##
## 눈으로 볼 몫은 `user://qa_shots/` 에 남긴다 — 걷는 중의 월드 화면과, 걷기
## 프레임을 한 줄로 이어붙여 확대한 것(넘겨보지 않고도 한눈에 견줄 수 있다).

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
	# 이전 실행의 슬롯이 남아 거짓 결과를 내지 않게 지우고 시작한다 (docs/GOTCHAS.md).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("걷는이", LOOK, SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	# 첫 씬은 여기서 올린다 (docs/GOTCHAS.md — _steps 에 넣으면 영영 실행되지 않는다).
	change_scene_to_file(WORLD_SCENE)

	_steps = [
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


func _process(delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
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


## 걷기 애니메이션이 네 방향 다 있고, 시트의 열 수만큼 프레임이 있고, 도는가.
func _check_animations() -> void:
	var sprite := _sprite()
	if sprite == null or sprite.sprite_frames == null:
		_fails.append("플레이어에 SpriteFrames 가 없다")
		return
	var sheet: Texture2D = load(PlayerFrames.sheet_path("walk", String(LOOK["hairstyle"])))
	if sheet == null:
		_fails.append("걷기 시트를 못 읽었다 — `--import` 를 안 돌렸을 수 있다")
		return
	var columns := sheet.get_width() / PlayerFrames.CELL
	if columns < 4 or columns > 6:
		_fails.append("걷기가 %d프레임이다 — DESIGN.md 「캐릭터 애니메이션」은 4~6프레임이다"
				% columns)
	for dir: String in PlayerFrames.DIR_NAMES:
		var anim := "walk_%s" % dir
		if not sprite.sprite_frames.has_animation(anim):
			_fails.append("%s 애니메이션이 없다 — 걷기 시트가 안 실렸다" % anim)
			continue
		var count := sprite.sprite_frames.get_frame_count(anim)
		if count != columns:
			_fails.append("%s 가 %d프레임이다 — 시트는 %d열이다" % [anim, count, columns])
		if not sprite.sprite_frames.get_animation_loop(anim):
			_fails.append("%s 가 도는 애니메이션이 아니다 — 한 바퀴 돌고 멈춘다" % anim)
	if _fails.is_empty():
		print("[qa] walk_<방향> 4개 × %d프레임, 전부 loop" % columns)


## **걷기 시트도 고른 외형으로 칠해졌는가.** idle 만 칠하면 움직이는 순간 기준색으로
## 튄다 — 네 방향 × 모든 프레임을 시트와 픽셀 단위로 견준다.
func _check_recolored() -> void:
	var want := CharacterSprite.motion_texture(LOOK, "walk")
	if want == null:
		_fails.append("칠한 걷기 텍스처를 못 만들었다")
		return
	var image := want.get_image()
	var sprite := _sprite()
	if sprite == null or sprite.sprite_frames == null:
		return
	var cell := PlayerFrames.CELL
	for row in PlayerFrames.DIR_NAMES.size():
		var anim := "walk_%s" % PlayerFrames.DIR_NAMES[row]
		if not sprite.sprite_frames.has_animation(anim):
			return
		for f in sprite.sprite_frames.get_frame_count(anim):
			var texture := sprite.sprite_frames.get_frame_texture(anim, f)
			if texture == null:
				_fails.append("%s #%d 프레임이 비었다" % [anim, f])
				return
			var got := texture.get_image()
			var wrong := 0
			for y in cell:
				for x in cell:
					if not got.get_pixel(x, y).is_equal_approx(
							image.get_pixel(f * cell + x, row * cell + y)):
						wrong += 1
			if wrong > 0:
				_fails.append("%s #%d 가 칠한 시트와 %d픽셀 다르다 — 걷기가 안 칠해졌다"
						% [anim, f, wrong])
				return
	print("[qa] 걷기 4방향 × 모든 프레임이 고른 외형(%s)으로 칠해져 있다" % LOOK["hairstyle"])


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
	var size := Vector2(DisplayServer.window_get_size())
	var origin := size * 0.5 - Vector2(0.0, PlayerFrames.CELL * PlayerFrames.SCALE * 0.5)
	Input.warp_mouse(origin + Vector2.from_angle(AIM[dir]) * minf(size.x, size.y) * AIM_REACH)


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
