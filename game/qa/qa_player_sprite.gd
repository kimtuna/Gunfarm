extends SceneTree

## INBOX #8 자체 QA — 플레이어 idle 스프라이트 시트.
##
## 실행 (캡처까지 하려면 `--headless` 를 빼야 한다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_player_sprite.gd
##
## 확인하는 것:
##   1) 시트 규격 — 34px 칸 × (행 = 방향 4개). 아트 34px × 씬 3배 = 화면 102px
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

const SHEET_PATH := "res://assets/sprites/player_idle.png"
const SHOTS := "user://qa_shots"
const CELL := 34
const SCALE := 3
const DIRS := ["down", "left", "right", "up"]

## 재질 5종 × 램프 4단계 + 잉크 + 눈 하이라이트 + 투명 = 23. 여유를 조금만 둔다.
const MAX_COLORS := 26
const INK := Color8(38, 28, 44)
## 배경은 지형 색(terrain_view.gd 의 땅)으로 — 실제로 그 위에 서 있을 색이다.
const COLOR_LAND := Color(0.286275, 0.415686, 0.243137)

var _fails: Array[String] = []
var _image: Image = null
var _frames := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var texture: Texture2D = load(SHEET_PATH)
	if texture == null:
		_fails.append("시트를 못 읽었다: %s — `--import` 를 안 돌렸을 수 있다" % SHEET_PATH)
		_report()
		return
	_image = texture.get_image()

	_check_sheet_size()
	_check_frames()
	_check_pixels()
	_check_filter()
	_build_board()
	# 캡처는 `_process` 에서 몇 프레임 지난 뒤에 한다 — `_initialize()` 안에서
	# await 하면 그 코루틴이 끝나기 전에 `quit()` 이 먼저 돌아 캡처가 통째로 빠진다.


func _check_sheet_size() -> void:
	var want := Vector2i(CELL, CELL * DIRS.size())
	if _image.get_size() != want:
		_fails.append("시트 크기가 %s 인데 %s 여야 한다" % [_image.get_size(), want])


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
			_fails.append("%s: 빈 칸이다" % DIRS[row])
			continue
		if box.position.x < 1 or box.position.y < 1 \
				or box.end.x > CELL - 1 or box.end.y > CELL - 1:
			_fails.append("%s: 칸 가장자리에 붙어 잘렸다 %s — 외곽선 자리가 없다" % [DIRS[row], box])
		if box.size.y < CELL * 0.7:
			_fails.append("%s: 캐릭터가 칸에 비해 너무 작다 (높이 %d)" % [DIRS[row], box.size.y])
		print("[qa] %-5s bbox=%s" % [DIRS[row], box])

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


func _spread(what: String, values: Array[int], allowed: int) -> void:
	var lo := values[0]
	var hi := values[0]
	for v in values:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	if hi - lo > allowed:
		_fails.append("방향마다 %s가 %d~%d 로 어긋난다 (허용 %d) — 같은 캐릭터로 안 보인다"
				% [what, lo, hi, allowed])
	else:
		print("[qa] %s %d~%d (허용 폭 %d)" % [what, lo, hi, allowed])


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
		_fails.append("반투명 픽셀 %d개 — 도트는 알파가 0 아니면 255 여야 한다" % semi)
	if black > 0:
		_fails.append("순검정 픽셀 %d개 — 외곽선은 잉크색(%s)을 쓴다" % [black, INK.to_html(false)])
	if colors.size() > MAX_COLORS:
		_fails.append("색이 %d종 — 제한 팔레트(%d종 이하)를 벗어났다" % [colors.size(), MAX_COLORS])
	else:
		print("[qa] 색 %d종 (상한 %d)" % [colors.size(), MAX_COLORS])
	if not colors.has(INK.to_html(false)):
		_fails.append("잉크색(%s)이 한 픽셀도 없다 — 외곽선이 빠졌다" % INK.to_html(false))


func _check_filter() -> void:
	var filter: int = ProjectSettings.get_setting(
			"rendering/textures/canvas_textures/default_texture_filter", -1)
	if filter != 0:
		_fails.append("텍스처 필터가 %d — nearest(0) 가 아니면 도트가 흐려진다" % filter)


func _process(_delta: float) -> bool:
	_frames += 1
	# 상태를 만든 직후 바로 찍으면 한 프레임 전이 찍힌다 (docs/GOTCHAS.md).
	if _frames < 3:
		return false
	_shoot()
	_report()
	return true


## 눈으로 볼 몫. 실제 게임 배율(3배)로, 지형 색 위에 4방향을 나란히 그려 캡처한다.
func _build_board() -> void:
	var texture: Texture2D = load(SHEET_PATH)
	var board := ColorRect.new()
	board.color = COLOR_LAND
	board.size = Vector2(CELL * SCALE * DIRS.size() + 160, CELL * SCALE + 80)
	root.add_child(board)
	for row in DIRS.size():
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(0, row * CELL, CELL, CELL)
		var view := TextureRect.new()
		view.texture = atlas
		view.position = Vector2(40 + row * (CELL * SCALE + 32), 40)
		view.size = Vector2(CELL, CELL) * SCALE
		view.stretch_mode = TextureRect.STRETCH_SCALE
		board.add_child(view)


func _shoot() -> void:
	var vp := root.get_texture()
	if vp == null:
		print("[qa] 캡처 건너뜀 — --headless 로 돌렸다(뷰포트 텍스처 없음)")
		return
	var shot := vp.get_image()
	var path := "%s/80_player_idle.png" % SHOTS
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
