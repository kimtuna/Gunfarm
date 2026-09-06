extends SceneTree

## 플레이어 idle 스프라이트 시트 자체 QA (INBOX #8, 머리모양 4종으로 확장 #11).
##
## 실행 (캡처까지 하려면 `--headless` 를 빼야 한다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_player_sprite.gd
##
## 확인하는 것:
##   1) 시트 규격 — `PlayerFrames.CELL` 칸 × (행 = 방향 4개). 아트 × 씬 3배가 화면 크기
##      (docs/STYLE_GUIDE.md 1번: 배율이 정수여야 도트가 안 뭉개진다).
##   2) **방향 4개의 캐릭터 크기가 어긋나지 않는다** — 높이/폭/발밑 y 가 서로
##      가까워야 한다 (docs/DESIGN.md 「캐릭터 애니메이션」의 크기 규칙).
##   3) 칸 안에서 잘리지 않았다 — 사방에 여백이 남아 있어야 외곽선이 살아 있다.
##   4) 도트가 뭉개질 여지가 없다 — 반투명 픽셀이 없고(알파는 0 아니면 255),
##      색 수가 제한 팔레트 범위 안이며, 순검정을 쓰지 않는다(STYLE_GUIDE 2번).
##   5) 프로젝트 텍스처 필터가 nearest 다 — 풀리면 도트가 흐려진다.
##
## 그림이 "보기 좋은가"는 코드가 판정할 수 없다. 이 스크립트는 **기계로 판정할 수
## 있는 것만** 보고, 눈으로 볼 몫은 `user://qa_shots/` 에 캡처를 남긴다.

const PlayerFrames := preload("res://scripts/player_frames.gd")

## 머리모양마다 시트가 따로다 — **네 장 전부 같은 규격이어야** 커스터마이징에서
## 골라도 캐릭터 크기가 안 바뀐다.
const STYLES := ["short", "bob", "long", "ponytail"]
const SHOTS := "user://qa_shots"
## 규격은 **엔진이 쓰는 값 하나에서 가져온다** — 여기 숫자를 따로 적어두면
## 캔버스 크기를 바꾼 바퀴가 한쪽만 고치고 지나간다(INBOX #19 가 그럴 뻔했다).
const CELL := PlayerFrames.CELL
const SCALE := PlayerFrames.SCALE
const DIRS := ["down", "left", "right", "up"]

## 재질 5종 × 램프 4단계 + 잉크 + 눈 하이라이트 + 투명 = 23. 여유를 조금만 둔다.
const MAX_COLORS := 26
const INK := Color8(38, 28, 44)
## 배경은 실제 지형의 풀색 — 실제로 그 위에 서 있을 색이다. 색을 손으로 적지 않고
## 생성기가 내려보낸 램프에서 꺼낸다(`terrain_palettes.gd`).
const TerrainPalettes := preload("res://scripts/terrain_palettes.gd")

var _fails: Array[String] = []
var _image: Image = null
var _style := ""
var _frames := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	for style in STYLES:
		_style = style
		var path := PlayerFrames.sheet_path("idle", style)
		var texture: Texture2D = load(path)
		if texture == null:
			_fail("시트를 못 읽었다: %s — `--import` 를 안 돌렸을 수 있다" % path)
			continue
		_image = texture.get_image()
		_check_sheet_size()
		_check_frames()
		_check_pixels()
	_check_filter()
	_build_board()
	# 캡처는 `_process` 에서 몇 프레임 지난 뒤에 한다 — `_initialize()` 안에서
	# await 하면 그 코루틴이 끝나기 전에 `quit()` 이 먼저 돌아 캡처가 통째로 빠진다.


## 실패 메시지에 어느 머리모양인지 붙인다 — 안 붙이면 네 장 중 어느 것인지 모른다.
func _fail(message: String) -> void:
	_fails.append("[%s] %s" % [_style, message])


func _check_sheet_size() -> void:
	var want := Vector2i(CELL, CELL * DIRS.size())
	if _image.get_size() != want:
		_fail("시트 크기가 %s 인데 %s 여야 한다" % [_image.get_size(), want])


## 칸 안에서 실제로 칠해진 부분의 사각형.
func _bounds(row: int) -> Rect2i:
	var min_x := CELL
	var min_y := CELL
	var max_x := -1
	var max_y := -1
	for y in CELL:
		for x in CELL:
			if _image.get_pixel(x, row * CELL + y).a <= 0.0:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _check_frames() -> void:
	if _image.get_height() < CELL * DIRS.size():
		return
	var boxes: Array[Rect2i] = []
	for row in DIRS.size():
		var box := _bounds(row)
		boxes.append(box)
		if box.size == Vector2i.ZERO:
			_fail("%s: 빈 칸이다" % DIRS[row])
			continue
		# **칸 가장자리에 닿는 것 자체는 잘린 게 아니다.** 17px 칸에 외곽선까지
		# 16줄이 들어가므로(2026-09-07, INBOX #19) 위아래 중 한쪽은 반드시 닿는다.
		# 정말 막아야 하는 것은 **외곽선이 아닌 픽셀이 가장자리에 나오는 것**이다 —
		# 그건 실루엣의 한 줄이 칸 밖으로 잘려나갔다는 뜻이다.
		var bare := _bare_edge(row)
		if bare != "":
			_fail("%s: 칸 %s 가장자리에 외곽선이 아닌 픽셀이 있다 — 실루엣이 잘렸다"
					% [DIRS[row], bare])
		if box.size.y < CELL * 0.7:
			_fail("%s: 캐릭터가 칸에 비해 너무 작다 (높이 %d)" % [DIRS[row], box.size.y])
		print("[qa] %-8s %-5s bbox=%s" % [_style, DIRS[row], box])

	# 방향마다 다른 호출로 그려지므로, 세트 안에서 크기가 어긋나지 않았는지 직접 잰다.
	var heights: Array[int] = []
	var widths: Array[int] = []
	var feet: Array[int] = []
	for box in boxes:
		if box.size == Vector2i.ZERO:
			return
		heights.append(box.size.y)
		widths.append(box.size.x)
		feet.append(box.end.y)
	_spread("높이", heights, 1)
	_spread("발밑 y", feet, 1)
	# 옆모습은 어깨가 좁아지는 게 정상이라 폭은 더 넉넉하게 본다.
	_spread("폭", widths, 4)


## 칸의 네 가장자리 중 **외곽선(잉크)이 아닌 몸 픽셀이 놓인** 변의 이름.
## 없으면 빈 문자열 — 그래야 그림이 칸을 꽉 채워도 "잘리지 않았다"가 성립한다.
func _bare_edge(row: int) -> String:
	var top := row * CELL
	for x in CELL:
		if _solid_not_ink(x, top) or _solid_not_ink(x, top + CELL - 1):
			return "위/아래"
	for y in CELL:
		if _solid_not_ink(0, top + y) or _solid_not_ink(CELL - 1, top + y):
			return "좌/우"
	return ""


func _solid_not_ink(x: int, y: int) -> bool:
	var c := _image.get_pixel(x, y)
	return c.a > 0.0 and not c.is_equal_approx(INK)


func _spread(what: String, values: Array[int], allowed: int) -> void:
	var lo := values[0]
	var hi := values[0]
	for v in values:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	if hi - lo > allowed:
		_fail("방향마다 %s가 %d~%d 로 어긋난다 (허용 %d) — 같은 캐릭터로 안 보인다"
				% [what, lo, hi, allowed])
	else:
		print("[qa] %-8s %s %d~%d (허용 폭 %d)" % [_style, what, lo, hi, allowed])


func _check_pixels() -> void:
	var colors := {}
	var semi := 0
	var black := 0
	for y in _image.get_height():
		for x in _image.get_width():
			var c := _image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if c.a < 1.0:
				semi += 1
			colors[c.to_html(false)] = true
			if c.r8 == 0 and c.g8 == 0 and c.b8 == 0:
				black += 1
	if semi > 0:
		_fail("반투명 픽셀 %d개 — 도트는 알파가 0 아니면 255 여야 한다" % semi)
	if black > 0:
		_fail("순검정 픽셀 %d개 — 외곽선은 잉크색(%s)을 쓴다" % [black, INK.to_html(false)])
	if colors.size() > MAX_COLORS:
		_fail("색이 %d종 — 제한 팔레트(%d종 이하)를 벗어났다" % [colors.size(), MAX_COLORS])
	else:
		print("[qa] %-8s 색 %d종 (상한 %d)" % [_style, colors.size(), MAX_COLORS])
	if not colors.has(INK.to_html(false)):
		_fail("잉크색(%s)이 한 픽셀도 없다 — 외곽선이 빠졌다" % INK.to_html(false))


func _check_filter() -> void:
	var filter: int = ProjectSettings.get_setting(
			"rendering/textures/canvas_textures/default_texture_filter", -1)
	if filter != 0:
		_fail("텍스처 필터가 %d — nearest(0) 가 아니면 도트가 흐려진다" % filter)


func _process(_delta: float) -> bool:
	_frames += 1
	# 상태를 만든 직후 바로 찍으면 한 프레임 전이 찍힌다 (docs/GOTCHAS.md).
	if _frames < 3:
		return false
	_shoot()
	_report()
	return true


## 눈으로 볼 몫. 실제 게임 배율(3배)로, 지형 색 위에 **머리모양 4종 × 방향 4개**를
## 격자로 그려 캡처한다 — 나란히 놓지 않으면 서로 어울리는지 판단할 수 없다.
func _build_board() -> void:
	var step := CELL * SCALE + 24
	var board := ColorRect.new()
	board.color = TerrainPalettes.color_of("grass", 1)
	board.size = Vector2(step * DIRS.size() + 40, step * STYLES.size() + 40)
	root.add_child(board)
	for s in STYLES.size():
		var texture: Texture2D = load(PlayerFrames.sheet_path("idle", STYLES[s]))
		if texture == null:
			continue
		for row in DIRS.size():
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(0, row * CELL, CELL, CELL)
			var view := TextureRect.new()
			view.texture = atlas
			view.position = Vector2(20 + row * step, 20 + s * step)
			view.size = Vector2(CELL, CELL) * SCALE
			view.stretch_mode = TextureRect.STRETCH_SCALE
			board.add_child(view)


func _shoot() -> void:
	var vp := root.get_texture()
	if vp == null:
		print("[qa] 캡처 건너뜀 — --headless 로 돌렸다(뷰포트 텍스처 없음)")
		return
	var shot := vp.get_image()
	var path := "%s/80_player_idle_hairstyles.png" % SHOTS
	shot.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, shot.get_width(), shot.get_height()])


func _report() -> void:
	if _fails.is_empty():
		print("[qa] PASS — 시트 규격 / 방향 간 크기 / 팔레트 / 텍스처 필터 정상")
		quit()
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)
