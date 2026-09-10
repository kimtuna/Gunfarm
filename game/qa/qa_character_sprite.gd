extends SceneTree

## INBOX #11 자체 QA — 캐릭터 스프라이트의 **팔레트 교체**.
##
## 실행 (캡처까지 하려면 `--headless` 를 빼야 한다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_character_sprite.gd
##
## 확인하는 것:
##   1) **선택지와 램프 표가 서로 맞는가** — `character_appearance.gd` 의 id 마다
##      `character_palettes.gd` 에 램프가 있고, 그 반대도 참인가. 한쪽만 늘리면
##      화면에서는 색이 안 바뀌는데 에러도 안 나서 눈치채기 어렵다.
##   2) **내놓는 머리모양마다** 시트 파일이 실제로 있는가 (몇 종인지는 안 센다).
##   3) **기준색 램프의 색이 서로 겹치지 않는가** — 겹치면 "이 색을 무슨 재질로
##      볼 것인가"가 모호해져서 바꿔치기가 엉뚱한 재질을 칠한다.
##   4) 바꿔치기가 **하나도 빠짐없이** 되는가 — 칠한 뒤에도 기준색이 남아 있으면
##      그 픽셀은 옷을 갈아입지 않은 것이다. 잉크·눈 하이라이트는 예외(고정색).
##   5) 고른 색이 실제로 반영되는가 — 피부/머리/옷을 바꾸면 그 재질 픽셀의 색이
##      바뀌고, 다른 선택지끼리 결과가 서로 다른가.
##   6) 알파(실루엣)는 그대로인가 — 색만 바꿨는데 형태가 달라지면 안 된다.
##
## 눈으로 볼 몫은 `user://qa_shots/` 에 남긴다 — 색 조합을 여러 개 나란히 띄운다.
## **팔레트 교체 코드를 고쳤으면 이 캡처를 반드시 눈으로 볼 것**
## (`docs/STYLE_GUIDE.md` 6번: "한 벌만 보면 멀쩡하다").
##
## **3~6 번은 시트가 팔레트 교체 대상일 때만 돈다** (2026-09-08, INBOX #57).
## 2026-09-08 에 캐릭터가 ComfyUI 그림 + 리그로 바뀌면서 시트에 **기준색 램프가 한
## 픽셀도 안 들어 있게** 됐다 — 색이 그림에 구워져 있어 무엇이 피부고 무엇이 옷인지
## 구분할 근거가 없다(`docs/CHARACTER.md` 8절, `docs/LATER.md` #54).
## 그 상태에서 「선택지끼리 결과가 달라야 한다」를 그대로 재면 **아직 만들지 않은 것**을
## 불합격으로 적게 된다. 그래서 **기준색이 시트에 실제로 있는지를 먼저 보고**, 없으면
## 그 이유를 찍고 건너뛴다 — 램프가 다시 구워지는 순간 이 검사는 저절로 되살아난다.

const Appearance := preload("res://scripts/character_appearance.gd")
const Palettes := preload("res://scripts/character_palettes.gd")
const CharacterSprite := preload("res://scripts/character_sprite.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")

const SHOTS := "user://qa_shots"
## 배경은 실제 지형의 풀색 — 실제로 그 위에 서 있을 색이다. 색을 손으로 적지 않고
## 생성기가 내려보낸 램프에서 꺼낸다(`terrain_palettes.gd`).
const TerrainPalettes := preload("res://scripts/terrain_palettes.gd")

## 눈으로 볼 색 조합. **일부러 극단으로 고른다** — 가장 밝은 조합과 가장 어두운
## 조합에서 무너지면 나머지는 볼 것도 없다. **머리모양은 이름을 박지 않고 지금 있는
## 것을 돌려 쓴다**(2026-09-08, INBOX #57) — 없는 이름을 적으면 `normalize()` 가
## 조용히 기본값으로 되돌려서, 여섯 줄이 다 같은 머리모양인 줄 모르고 지나간다.
const COLOR_COMBOS := [
	{"skin": "light", "hair_color": "black", "clothes_color": "grass"},
	{"skin": "deep", "hair_color": "silver", "clothes_color": "sky"},
	{"skin": "warm", "hair_color": "blond", "clothes_color": "ember"},
	{"skin": "brown", "hair_color": "auburn", "clothes_color": "plum"},
	{"skin": "tan", "hair_color": "indigo", "clothes_color": "ash"},
	{"skin": "light", "hair_color": "brown", "clothes_color": "earth"},
]

var _fails: Array[String] = []
var _frames := 0


## 색 조합 × (있는 머리모양을 돌려가며) — 실제로 만들어 볼 외형들.
func _combos() -> Array:
	var styles := Appearance.options("hairstyle")
	var out := []
	for i in COLOR_COMBOS.size():
		var look: Dictionary = COLOR_COMBOS[i].duplicate()
		look["hairstyle"] = String(styles[i % styles.size()]["id"])
		out.append(look)
	return out


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	_check_tables_match()
	_check_sheets_exist()
	_check_base_ramps_distinct()
	_check_recolor()
	_build_board()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_fails.append(message)


# --- 1) 선택지 ↔ 램프 표 ----------------------------------------------------

func _check_tables_match() -> void:
	_match("skin", Palettes.SKIN)
	_match("hair_color", Palettes.HAIR)
	_match("clothes_color", Palettes.CLOTHES)
	for key in ["skin", "hair_color", "clothes_color"]:
		var base := String(Palettes.BASE.get(key, ""))
		_expect(Appearance.index_of(key, base) >= 0,
			"기준색 %s=%s 가 선택지에 없다" % [key, base])


func _match(field: String, table: Dictionary) -> void:
	var ids := {}
	for option in Appearance.options(field):
		var id := String(option["id"])
		ids[id] = true
		_expect(table.has(id),
			"%s/%s 의 램프가 character_palettes.gd 에 없다 — 생성기를 다시 돌릴 것" % [field, id])
	for id in table:
		_expect(ids.has(id), "character_palettes.gd 의 %s/%s 는 선택지에 없다" % [field, id])


func _check_sheets_exist() -> void:
	for option in Appearance.options("hairstyle"):
		var path := PlayerFrames.sheet_path("idle", String(option["id"]))
		_expect(ResourceLoader.exists(path), "머리모양 시트가 없다: %s" % path)


# --- 2) 기준색 램프이 서로 안 겹치는가 --------------------------------------

func _check_base_ramps_distinct() -> void:
	var seen := {}
	for mat in CharacterSprite.MATERIALS:
		var ramp: PackedColorArray = CharacterSprite.ramps(Palettes.BASE)[mat]
		for c in ramp:
			var key := c.to_html(false)
			_expect(not seen.has(key),
				"기준색 램프에서 %s 와 %s 가 같은 색(#%s)이다 — 바꿔치기가 모호해진다"
					% [mat, seen.get(key, ""), key])
			seen[key] = mat


# --- 3) 실제 바꿔치기 -------------------------------------------------------

func _check_recolor() -> void:
	var style := PlayerFrames.DEFAULT_HAIRSTYLE
	var base_sheet: Texture2D = load(PlayerFrames.sheet_path("idle", style))
	if base_sheet == null:
		_fails.append("기준 시트를 못 읽었다 — `--import` 를 안 돌렸을 수 있다")
		return
	var source := base_sheet.get_image()
	var base_colors := {}
	for mat in CharacterSprite.MATERIALS:
		for c in CharacterSprite.ramps(Palettes.BASE)[mat] as PackedColorArray:
			base_colors[c.to_html(false)] = mat

	# **기준색이 시트에 한 픽셀도 없으면 팔레트 교체 자체가 성립하지 않는다** —
	# 그건 이 검사가 잡을 결함이 아니라 아직 안 만든 것이다(위 머리말).
	if _base_pixels(source, base_colors) == 0:
		print("[qa] 팔레트 교체 검사 건너뜀 — %s 시트에 기준색 램프가 한 픽셀도 없다 "
				% style + "(docs/CHARACTER.md 8절 · LATER.md #54). 램프가 생기면 저절로 되살아난다")
		return

	for field in ["skin", "hair_color", "clothes_color"]:
		# 비교는 **같은 항목 안에서만** 한다 — 항목마다 기준색 선택지 하나는
		# 아무것도 안 바뀌는 게 정상이라, 그것들끼리는 당연히 결과가 같다.
		var previous := {}
		for option in Appearance.options(field):
			var id := String(option["id"])
			var look := Appearance.default_appearance()
			look[field] = id
			var image := CharacterSprite.recolored(source, look)
			_expect(image.get_size() == source.get_size(),
				"%s/%s: 칠하고 나니 크기가 달라졌다" % [field, id])

			# 실루엣(알파)은 그대로여야 한다 — 색만 바꾸는 작업이다.
			var alpha_changed := 0
			var leftovers := {}
			var counts := {}
			for y in image.get_height():
				for x in image.get_width():
					var before := source.get_pixel(x, y)
					var after := image.get_pixel(x, y)
					if before.a != after.a:
						alpha_changed += 1
					if after.a <= 0.0:
						continue
					var html := after.to_html(false)
					counts[html] = int(counts.get(html, 0)) + 1
					# 고른 색과 기준색이 같은 재질이면 그대로인 게 맞다.
					var mat: String = base_colors.get(html, "")
					if mat != "" and not _is_base_choice(field, id):
						if _material_of(field).has(mat):
							leftovers[html] = mat
			_expect(alpha_changed == 0,
				"%s/%s: 알파가 %d px 바뀌었다 — 형태를 건드리면 안 된다" % [field, id, alpha_changed])
			_expect(leftovers.is_empty(),
				"%s/%s: 기준색이 %d 색 그대로 남았다 %s — 바꿔치기에서 빠졌다"
					% [field, id, leftovers.size(), leftovers.keys()])

			# 선택지끼리 결과가 달라야 한다 — 같으면 고른 의미가 없다.
			var fingerprint := _fingerprint(counts)
			for other in previous:
				if previous[other] == fingerprint:
					_fails.append("%s: %s 와 %s 의 결과가 똑같다 — 고른 색이 반영되지 않았다"
						% [field, id, other])
			previous["%s/%s" % [field, id]] = fingerprint


## 이 시트에 기준색 램프 색이 몇 픽셀이나 들어 있는가. 0 이면 팔레트 교체 대상이
## 아닌 시트다 — 색이 그림에 구워져 있어 바꿔칠 자리가 없다.
func _base_pixels(image: Image, base_colors: Dictionary) -> int:
	var found := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and base_colors.has(pixel.to_html(false)):
				found += 1
	return found


## 그 항목이 기준 시트를 구울 때 쓴 색인가 (그 경우 색이 안 바뀌는 게 정상).
func _is_base_choice(field: String, id: String) -> bool:
	return String(Palettes.BASE.get(field, "")) == id


## 그 항목이 정하는 재질들.
func _material_of(field: String) -> Array:
	match field:
		"skin":
			return ["skin", "blush"]
		"hair_color":
			return ["hair"]
		"clothes_color":
			return ["shirt", "pants", "boot"]
	return []


func _fingerprint(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s:%d" % [k, counts[k]])
	return ",".join(parts)


# --- 눈으로 볼 몫 -----------------------------------------------------------

## 색 조합 × 방향 4개를 실제 게임 배율로 지형 색 위에 늘어놓는다.
func _build_board() -> void:
	var combos := _combos()
	var first := CharacterSprite.idle_texture(combos[0])
	if first == null:
		return
	# **칸과 배율은 시트에서 읽는다** (2026-09-08, INBOX #57) — 상수로 적어두면 칸이
	# 바뀐 순간 엉뚱한 자리를 잘라 판이 통째로 조각난다(96px 시트를 32 로 잘랐다).
	var cell := PlayerFrames.cell_of(first)
	var zoom := PlayerFrames.scale_of(cell)
	# 조합 6줄이 캡처 안에 다 들어가야 한다 — 넘치면 잘려서 극단 조합을 넣어둔 의미가
	# 없다. 창 세로에 안 들어가면 배율을 낮춘다(도트가 뭉개지지 않게 정수로만).
	var height := root.get_visible_rect().size.y
	while zoom > 1 and (cell * zoom + 8) * combos.size() + 20 > height:
		zoom -= 1
	var step := cell * zoom + 8
	var board := ColorRect.new()
	board.color = TerrainPalettes.color_of("grass", 1)
	board.size = Vector2(step * 4 + 20, step * combos.size() + 20)
	root.add_child(board)
	for i in combos.size():
		var texture := CharacterSprite.idle_texture(combos[i])
		if texture == null:
			continue
		for row in PlayerFrames.DIR_NAMES.size():
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(0, row * cell, cell, cell)
			var view := TextureRect.new()
			view.texture = atlas
			view.position = Vector2(10 + row * step, 10 + i * step)
			view.size = Vector2(cell, cell) * zoom
			view.stretch_mode = TextureRect.STRETCH_SCALE
			board.add_child(view)


func _process(_delta: float) -> bool:
	_frames += 1
	# 상태를 만든 직후 바로 찍으면 한 프레임 전이 찍힌다 (docs/GOTCHAS.md).
	if _frames < 3:
		return false
	_shoot()
	_report()
	return true


func _shoot() -> void:
	var vp := root.get_texture()
	if vp == null:
		print("[qa] 캡처 건너뜀 — --headless 로 돌렸다(뷰포트 텍스처 없음)")
		return
	var path := "%s/85_palette_swap.png" % SHOTS
	vp.get_image().save_png(path)
	print("[qa] shot %s" % path)


func _report() -> void:
	if _fails.is_empty():
		print("[qa] PASS — 램프 표 동기화 / 머리모양마다 시트 있음 / 색 충돌 없음 / 팔레트 교체")
		quit()
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)
