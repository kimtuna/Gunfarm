extends SceneTree

## INBOX #14 자체 QA — **월드 안의 플레이어가 슬롯에 저장된 외형을 입고 있는가.**
##
## 실행 (--headless 를 붙이면 캡처가 안 된다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_player_appearance.gd
##
## 확인하는 것:
##   1) 슬롯에 저장된 외형으로 들어가면 월드의 스프라이트가 **커스터마이징 화면이
##      보여주던 그림과 픽셀 단위로 같다** (`character_sprite.gd` 가 칠한 것과 동일).
##      네 방향 전부 본다 — 한 행만 칠하고 끝내는 실수를 잡는다.
##   2) 기준색(밝은 피부/검정 머리/풀색 옷)이 한 픽셀도 안 남아 있다 — 남아 있으면
##      그 픽셀은 옷을 갈아입지 않은 것이다.
##   3) **머리모양 시트가 바뀌었다** — 실루엣(알파)이 고른 머리모양 시트와 같고,
##      기본 머리모양 시트와는 다르다. 색만 바꾸고 시트를 안 고르면 여기서 걸린다.
##      **머리모양이 한 벌뿐이면 뒷부분은 물을 수가 없다** — 그때는 「고른 시트와
##      같다」까지만 본다(2026-09-08, INBOX #57).
##   4) **슬롯을 안 거치고 월드 씬을 직접 띄워도**(자체 QA 가 그렇게 한다) 기본
##      외형으로 멀쩡히 뜬다 — 스프라이트가 비거나 에러로 죽지 않는다.
##
## 눈으로 볼 몫은 `user://qa_shots/` 에 남긴다 — 월드 화면 한 장과, 캐릭터만
## 확대해서 자른 한 장(작아서 전체 화면에서는 색이 잘 안 보인다).

const SlotStore := preload("res://scripts/slot_store.gd")
const Appearance := preload("res://scripts/character_appearance.gd")
const CharacterSprite := preload("res://scripts/character_sprite.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")
const Palettes := preload("res://scripts/character_palettes.gd")

const SHOTS := "user://qa_shots"
const WORLD_SCENE := "res://scenes/world.tscn"
const SEED := 20260906

## **기준색과 최대한 먼 조합**을 고른다 — 외형이 안 전달되면 기준색 그대로 뜨는데,
## 비슷한 색을 고르면 그게 눈에도 검사에도 안 잡힌다. **머리모양은 이름을 박지 않고
## 「기본이 아닌 것이 있으면 그것」을 고른다**(2026-09-08, INBOX #57) — 없는 id 를
## 적으면 `normalize()` 가 조용히 기본값으로 되돌려서, 검사가 기본 외형을 「고른
## 외형」이라 믿고 통과해 버린다.
const CHOSEN_COLORS := {"skin": "deep", "hair_color": "silver", "clothes_color": "plum"}

## 캐릭터 주변을 잘라낼 크기(논리 픽셀)와 확대 배율. 화면 한가운데가 곧 플레이어다
## (카메라가 플레이어의 자식이다).
const CROP := 200
const CROP_ZOOM := 3

var _fails: Array[String] = []
var _steps: Array[Callable] = []
var _step := 0
var _wait := 0


## 위 색 + 지금 고를 수 있는 머리모양 하나.
static func chosen() -> Dictionary:
	var look := CHOSEN_COLORS.duplicate()
	look["hairstyle"] = _other_hairstyle()
	return look


## 기본과 다른 머리모양이 있으면 그것, 없으면 기본. 머리모양이 한 벌뿐인 동안은
## 뒤엣것이 나온다 (`docs/CHARACTER.md` 8절).
static func _other_hairstyle() -> String:
	for option in Appearance.options("hairstyle"):
		if String(option["id"]) != PlayerFrames.DEFAULT_HAIRSTYLE:
			return String(option["id"])
	return PlayerFrames.DEFAULT_HAIRSTYLE


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	# 이전 실행의 슬롯이 남아 거짓 결과를 내지 않게 지우고 시작한다 (docs/GOTCHAS.md).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SlotStore.SAVE_PATH))
	var slots := SlotStore.empty_slots()
	slots[0] = SlotStore.make_character("멋쟁이", chosen(), SEED)
	SlotStore.save_slots(slots)
	SlotStore.selected_slot = 0
	# 첫 씬은 여기서 올린다 (docs/GOTCHAS.md — _steps 에 넣으면 영영 실행되지 않는다).
	change_scene_to_file(WORLD_SCENE)

	_steps = [
		_check_frames_sliced,
		func(): _check_matches(chosen(), "슬롯 외형"),
		_check_no_base_colors,
		_check_hairstyle_sheet,
		func(): _shoot("70_world_appearance"),
		func(): _crop_shot("71_world_appearance_zoom"),
		# --- 슬롯을 안 거치고 월드 씬만 직접 띄운 경우 ---
		_enter_without_slot,
		_check_frames_sliced,
		func(): _check_matches(Appearance.default_appearance(), "기본 외형"),
		func(): _shoot("72_world_default"),
		func(): _crop_shot("73_world_default_zoom"),
	]


func _process(delta: float) -> bool:
	if current_scene == null:
		return false  # change_scene_to_file 은 지연 반영된다 (docs/GOTCHAS.md).
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size():
		return _report()
	var step: Callable = _steps[_step]
	_step += 1
	_wait = 3  # 상태를 바꾼 직후 캡처하면 한 프레임 전이 찍힌다 (docs/GOTCHAS.md).
	step.call()
	return false


# --- 검사 ---------------------------------------------------------------------

func _sprite() -> AnimatedSprite2D:
	var player := current_scene.get_node_or_null("%Player") as Node2D
	if player == null:
		return null
	return player.get_node_or_null("Sprite") as AnimatedSprite2D


func _check_frames_sliced() -> void:
	var sprite := _sprite()
	if sprite == null or sprite.sprite_frames == null:
		_fails.append("플레이어에 SpriteFrames 가 없다 — 외형을 입히다 시트를 잃어버렸다")
		return
	for dir: String in PlayerFrames.DIR_NAMES:
		if not sprite.sprite_frames.has_animation("idle_%s" % dir):
			_fails.append("idle_%s 애니메이션이 없다" % dir)


## 월드의 스프라이트 = 커스터마이징 화면이 보여주던 그림. 네 방향 전부 본다.
func _check_matches(appearance: Dictionary, what: String) -> void:
	var want := CharacterSprite.idle_texture(appearance)
	if want == null:
		_fails.append("%s: 기대 텍스처를 못 만들었다 — `--import` 를 안 돌렸을 수 있다" % what)
		return
	var want_image := want.get_image()
	for row in PlayerFrames.DIR_NAMES.size():
		var got := _frame_image(PlayerFrames.DIR_NAMES[row])
		if got == null:
			_fails.append("%s: idle_%s 프레임을 못 읽었다" % [what, PlayerFrames.DIR_NAMES[row]])
			return
		var wrong := _diff_pixels(got, want_image, row)
		if wrong > 0:
			_fails.append("%s: idle_%s 가 고른 외형과 %d 픽셀 다르다 — 월드가 다른 그림을 쓴다"
					% [what, PlayerFrames.DIR_NAMES[row], wrong])
			return
	print("[qa] %s: 네 방향 모두 커스터마이징 화면과 픽셀 단위로 같다" % what)


## 기준색이 남아 있으면 그 픽셀은 색이 안 바뀐 것이다. 고른 외형에서 실제로 값이
## **달라진 램프 색만** 본다(우연히 같은 색이 있으면 남아 있는 게 맞다).
func _check_no_base_colors() -> void:
	var base := CharacterSprite.ramps(Palettes.BASE)
	var want := CharacterSprite.ramps(chosen())
	var forbidden := {}
	for mat: String in CharacterSprite.MATERIALS:
		var from: PackedColorArray = base[mat]
		var to: PackedColorArray = want[mat]
		for i in from.size():
			if not from[i].is_equal_approx(to[i]):
				forbidden[from[i].to_html(false)] = mat
	var left := {}
	for dir: String in PlayerFrames.DIR_NAMES:
		var image := _frame_image(dir)
		if image == null:
			return
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a == 0.0:
					continue
				var key := pixel.to_html(false)
				if forbidden.has(key):
					left[key] = forbidden[key]
	if not left.is_empty():
		_fails.append("월드 캐릭터에 기준색이 남아 있다: %s" % left)
	elif not _sheet_is_recolorable(base):
		# **기준색이 시트에 애초에 없으면 이 통과는 공짜다** — 그렇다고 말해 둔다.
		# 2026-09-08 에 캐릭터가 ComfyUI 그림 + 리그로 바뀌면서 색이 그림에 구워졌다
		# (`docs/CHARACTER.md` 8절 · `docs/LATER.md` #54). 램프가 다시 생기면
		# 이 줄이 사라지고 아래 줄이 나온다 — 검사를 고칠 필요가 없다.
		print("[qa] 기준색 검사는 지금 공짜다 — 시트에 기준색 램프가 한 픽셀도 없다 "
				+ "(팔레트 교체가 아직 성립하지 않는다: LATER.md #54)")
	else:
		print("[qa] 기준색 %d 개가 한 픽셀도 안 남았다 — 전부 고른 색으로 칠해졌다"
				% forbidden.size())


## 기준 시트에 기준색 램프가 실제로 들어 있는가 — 없으면 팔레트 교체 자체가 아직
## 성립하지 않는 시트다(`qa_character_sprite.gd` 가 같은 것을 본다).
func _sheet_is_recolorable(base: Dictionary) -> bool:
	var sheet: Texture2D = load(PlayerFrames.sheet_path("idle", PlayerFrames.DEFAULT_HAIRSTYLE))
	if sheet == null:
		return false
	var colors := {}
	for mat: String in CharacterSprite.MATERIALS:
		for c in base[mat] as PackedColorArray:
			colors[c.to_html(false)] = true
	var image := sheet.get_image()
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and colors.has(pixel.to_html(false)):
				return true
	return false


## 색만 바꾸고 머리모양 시트를 안 고르면, 색은 맞는데 실루엣이 기본 머리모양이다.
## 알파(형태)는 팔레트 교체가 건드리지 않으므로 시트를 직접 견줄 수 있다.
## **방향 하나만 보면 안 된다** — 묶은머리 뒷모습처럼 실루엣은 그대로고 색만 다른
## 방향이 있다. 고른 시트와는 네 방향 모두 같고, 기본 시트와는 적어도 한 방향에서
## 달라야 한다.
func _check_hairstyle_sheet() -> void:
	var style := String(chosen()["hairstyle"])
	var chosen_sheet: Texture2D = load(PlayerFrames.sheet_path("idle", style))
	var default_sheet: Texture2D = load(PlayerFrames.sheet_path("idle", PlayerFrames.DEFAULT_HAIRSTYLE))
	if chosen_sheet == null or default_sheet == null:
		_fails.append("머리모양 시트를 못 읽었다 — `--import` 를 안 돌렸을 수 있다")
		return
	var chosen_image := chosen_sheet.get_image()
	var default_image := default_sheet.get_image()
	var differs_from_default := 0
	for row in PlayerFrames.DIR_NAMES.size():
		var dir: String = PlayerFrames.DIR_NAMES[row]
		var got := _frame_image(dir)
		if got == null:
			_fails.append("idle_%s 프레임을 못 읽었다" % dir)
			return
		if _alpha_diff(got, chosen_image, row) > 0:
			_fails.append("idle_%s 의 실루엣이 고른 머리모양(%s) 시트와 다르다" % [dir, style])
			return
		if _alpha_diff(got, default_image, row) > 0:
			differs_from_default += 1
	if style == PlayerFrames.DEFAULT_HAIRSTYLE:
		# **고를 머리모양이 한 벌뿐이라 「기본과 다른가」를 물을 수가 없다**
		# (2026-09-08, INBOX #57 — `docs/CHARACTER.md` 8절). 머리모양이 늘면 위
		# `_other_hairstyle()` 이 다른 것을 골라 아래 검사가 저절로 살아난다.
		print("[qa] 실루엣이 머리모양(%s) 시트와 네 방향 모두 일치한다 — "
				% style + "머리모양이 한 벌뿐이라 「기본과 다른가」는 아직 못 묻는다")
	elif differs_from_default == 0:
		_fails.append("네 방향 실루엣이 전부 기본 머리모양과 똑같다 — 머리모양이 반영되지 않았다")
	else:
		print("[qa] 실루엣이 고른 머리모양(%s) 시트와 네 방향 모두 일치하고, 기본(%s)과는 %d 방향에서 다르다"
				% [style, PlayerFrames.DEFAULT_HAIRSTYLE, differs_from_default])


## 슬롯을 고르지 않은 채 월드 씬만 띄운다 — 자체 QA 와 개발 중 씬 직접 실행이 이 경로다.
func _enter_without_slot() -> void:
	SlotStore.selected_slot = -1
	change_scene_to_file(WORLD_SCENE)
	_wait = 6


# --- 도구 ---------------------------------------------------------------------

func _frame_image(dir: String) -> Image:
	var sprite := _sprite()
	if sprite == null or sprite.sprite_frames == null:
		return null
	var anim := "idle_%s" % dir
	if not sprite.sprite_frames.has_animation(anim):
		return null
	var texture := sprite.sprite_frames.get_frame_texture(anim, 0)
	return texture.get_image() if texture != null else null


## 시트의 `row` 행과 프레임 한 장을 견준다 — 다른 픽셀 수.
func _diff_pixels(frame: Image, sheet: Image, row: int) -> int:
	return _compare(frame, sheet, row, false)


func _alpha_diff(frame: Image, sheet: Image, row: int) -> int:
	return _compare(frame, sheet, row, true)


func _compare(frame: Image, sheet: Image, row: int, alpha_only: bool) -> int:
	# **칸은 프레임에서 읽는다** (2026-09-08, INBOX #57). `CELL` 상수로 자르면 96px
	# 시트를 32px 로 견주게 되어 멀쩡한 그림이 「109 픽셀 다르다」로 걸린다 —
	# 엔진이 시트마다 제 칸으로 자르는 것(`player_frames.cell_of()`)과 같은 규칙이다.
	var cell := frame.get_height()
	var wrong := 0
	for y in cell:
		for x in cell:
			var a := frame.get_pixel(x, y)
			var b := sheet.get_pixel(x, row * cell + y)
			if alpha_only:
				if (a.a > 0.0) != (b.a > 0.0):
					wrong += 1
			elif not a.is_equal_approx(b):
				wrong += 1
	return wrong


func _shoot(shot_name: String) -> void:
	var image := _screen()
	if image == null:
		return
	var path := "%s/%s.png" % [SHOTS, shot_name]
	image.save_png(path)
	print("[qa] shot %s" % path)


## 화면 한가운데(= 플레이어)만 잘라 확대한다. 캐릭터는 화면에서 96px 이라
## 전체 화면 캡처로는 색·머리모양을 눈으로 판정하기 어렵다.
func _crop_shot(shot_name: String) -> void:
	var image := _screen()
	if image == null:
		return
	# 크롭 좌표는 논리 좌표가 아니라 **캡처한 이미지 크기** 기준이다 (docs/GOTCHAS.md).
	var size := image.get_size()
	# 논리 폭 → 캡처 이미지 폭. 논리 해상도를 손으로 적지 않는다(2026-09-08 에 넓혔다).
	var side := mini(int(CROP * size.x / root.get_visible_rect().size.x), mini(size.x, size.y))
	var region := Rect2i(Vector2i((size.x - side) / 2, (size.y - side) / 2), Vector2i(side, side))
	var crop := image.get_region(region)
	crop.resize(side * CROP_ZOOM, side * CROP_ZOOM, Image.INTERPOLATE_NEAREST)
	var path := "%s/%s.png" % [SHOTS, shot_name]
	crop.save_png(path)
	print("[qa] shot %s (캐릭터 확대)" % path)


func _screen() -> Image:
	var texture := root.get_texture()
	if texture == null:
		print("[qa] 캡처 건너뜀 — --headless 로 돌렸다(뷰포트 텍스처 없음)")
		return null
	return texture.get_image()


func _report() -> bool:
	if _fails.is_empty():
		print("[qa] PASS — 월드의 플레이어가 슬롯 외형(색 + 머리모양)을 입고 있고, 슬롯 없이도 기본 외형으로 뜬다")
		return true
	for f in _fails:
		printerr("[qa] FAIL — %s" % f)
	quit(1)
	return true
