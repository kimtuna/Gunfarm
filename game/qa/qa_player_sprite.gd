extends SceneTree

## 플레이어 idle 스프라이트 시트 자체 QA (INBOX #8, 머리모양 4종으로 확장 #11).
##
## 실행 (캡처까지 하려면 `--headless` 를 빼야 한다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_player_sprite.gd
##
## **머리모양은 지금 시트가 있는 것만 본다** (2026-09-08, INBOX #57). 2026-09-08 에
## 캐릭터 파이프라인이 ComfyUI + 리그로 바뀌면서 시트가 `farmer` 한 벌만 남았다
## (`docs/CHARACTER.md`). 이름 네 개를 박아두면 **아직 안 만든 것**을 불합격으로
## 적게 되므로, 화면이 내놓는 목록(`character_appearance.gd`)을 그대로 따라간다.
## **칸 크기도 상수로 안 믿는다** — 시트에서 읽는다(`player_frames.cell_of()`).
##
## 확인하는 것:
##   1) 시트 규격 — 칸이 정사각이고 행이 방향 4개, **머리모양끼리 칸이 같다**
##      (다르면 커스터마이징에서 고를 때마다 캐릭터 크기가 바뀐다). 화면 배율은
##      `scale_of()` 가 정하고 정수다 (docs/STYLE_GUIDE.md 1번).
##   2) **방향 4개의 캐릭터 크기가 어긋나지 않는다** — 높이/폭/발밑 y 가 서로
##      가까워야 한다 (docs/DESIGN.md 「캐릭터 애니메이션」의 크기 규칙).
##   3) 칸 안에서 잘리지 않았다 — 사방에 여백이 남아 있어야 외곽선이 살아 있다.
##   4) 도트가 뭉개질 여지가 없다 — 반투명 픽셀이 없고(알파는 0 아니면 255),
##      색 수가 제한 팔레트 범위 안이며, **외곽선이 한 색으로 둘러져 있고 그 색이
##      순검정이 아니다**(STYLE_GUIDE 2번: "외곽선은 순검정을 쓰지 않는다").
##   5) 프로젝트 텍스처 필터가 nearest 다 — 풀리면 도트가 흐려진다.
##
## 그림이 "보기 좋은가"는 코드가 판정할 수 없다. 이 스크립트는 **기계로 판정할 수
## 있는 것만** 보고, 눈으로 볼 몫은 `user://qa_shots/` 에 캡처를 남긴다.

const PlayerFrames := preload("res://scripts/player_frames.gd")
const Appearance := preload("res://scripts/character_appearance.gd")

const SHOTS := "user://qa_shots"
const DIRS := ["down", "left", "right", "up"]

## 팔레트 상한 — 리그가 시트 한 장을 굽는 팔레트 크기(`game/tools/gen_player.py` 의
## `COLORS` 32) + **외곽선 잉크 한 색**. 넘으면 도트가 아니라 「축소한 그림」이다.
const MAX_COLORS := 33

## 방향끼리 폭이 어긋나도 되는 정도를 **칸의 비율로** 잡는다. 옆모습은 뼈대에서
## 어깨·골반을 접어야 옆으로 보이므로 정면보다 마른 것이 정상이고(`docs/CHARACTER.md`
## 3-b 「그래도 안 맞는 것」), 그 차이는 칸이 커지면 같이 커진다 — 픽셀 상수로 적으면
## 칸이 17 → 32 → 96px 로 갈 때마다 사람이 다시 계산해야 한다.
const WIDTH_SPREAD := 0.15

## 배경은 실제 지형의 풀색 — 실제로 그 위에 서 있을 색이다. 색을 손으로 적지 않고
## 생성기가 내려보낸 램프에서 꺼낸다(`terrain_palettes.gd`).
const TerrainPalettes := preload("res://scripts/terrain_palettes.gd")

var _fails: Array[String] = []
var _image: Image = null
var _style := ""
## 지금 보고 있는 시트의 칸(px)과 외곽선 색 — 둘 다 **그 시트에서 읽는다.**
var _cell := 0
var _ink := Color.TRANSPARENT
## 시트가 실제로 있는 머리모양. `_initialize()` 가 채운다.
var _styles: Array[String] = []
var _frames := 0
var _board: ColorRect = null
## 캡처 순서 — 0: 머리모양 판, 그다음은 **도구 하나당 한 단계**다. **불린이 아니라
## 단계 번호다**: 판을 치웠는지로 판단하면 다음 판을 세운 순간 다시 첫 단계로
## 읽혀 무한히 돈다.
var _stage := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var cells := {}
	for option in Appearance.options("hairstyle"):
		var style := String(option["id"])
		_style = style
		var path := PlayerFrames.sheet_path("idle", style)
		var texture: Texture2D = load(path)
		if texture == null:
			# 화면이 내놓는 머리모양인데 시트가 없다 — 그건 진짜 결함이다
			# (`qa_character_customize.gd` 도 같은 것을 본다).
			_fail("커스터마이징이 내놓는 머리모양인데 시트가 없다: %s" % path)
			continue
		_styles.append(style)
		_image = texture.get_image()
		_cell = PlayerFrames.cell_of(texture)
		cells[_cell] = style
		_check_sheet_size()
		# **칠을 먼저 본다** — `_check_frames()` 의 「잘림」 검사가 외곽선 색을 알아야
		# 하는데 그 색은 `_check_pixels()` 가 시트에서 찾아낸다(`_check_outline()`).
		_check_pixels()
		_check_frames()
	if _styles.is_empty():
		_style = "머리모양"
		_fail("시트가 있는 머리모양이 하나도 없다 — 캐릭터를 그릴 수가 없다")
		_report()
		return
	if cells.size() > 1:
		_style = "머리모양"
		_fail("머리모양마다 칸이 다르다: %s — 고를 때마다 캐릭터 크기가 바뀐다" % [cells])
	_check_mixed_cells()
	_check_filter()
	_build_board()
	# 캡처는 `_process` 에서 몇 프레임 지난 뒤에 한다 — `_initialize()` 안에서
	# await 하면 그 코루틴이 끝나기 전에 `quit()` 이 먼저 돌아 캡처가 통째로 빠진다.


## 실패 메시지에 어느 머리모양인지 붙인다 — 안 붙이면 네 장 중 어느 것인지 모른다.
func _fail(message: String) -> void:
	_fails.append("[%s] %s" % [_style, message])


## 칸이 정사각이고 행이 방향 4개인가. **칸 크기 자체는 정하지 않는다** — 그건
## `docs/CHARACTER.md` 「크기」와 `qa_character_sheets.py` 가 본다. 여기서는 **이
## 시트가 그 칸으로 깔끔하게 나눠지는가**만 본다.
func _check_sheet_size() -> void:
	var size := _image.get_size()
	if size.y != _cell * DIRS.size():
		_fail("세로 %d 가 칸 %d × 방향 %d 와 안 맞는다" % [size.y, _cell, DIRS.size()])
	if _cell <= 0 or size.x % _cell != 0:
		_fail("가로 %d 가 칸 %d 로 안 나눠떨어진다" % [size.x, _cell])
	if PlayerFrames.scale_of(_cell) * _cell != 96:
		_fail("칸 %d 는 화면 96px 로 정수 배율이 안 나온다 (배율 %d)"
				% [_cell, PlayerFrames.scale_of(_cell)])


## 칸 안에서 실제로 칠해진 부분의 사각형.
func _bounds(row: int) -> Rect2i:
	var min_x := _cell
	var min_y := _cell
	var max_x := -1
	var max_y := -1
	for y in _cell:
		for x in _cell:
			if _image.get_pixel(x, row * _cell + y).a <= 0.0:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _check_frames() -> void:
	if _image.get_height() < _cell * DIRS.size():
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
		if box.size.y < _cell * 0.7:
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
	# 옆모습은 어깨가 좁아지는 게 정상이라 폭은 더 넉넉하게 본다 (위 `WIDTH_SPREAD`).
	_spread("폭", widths, maxi(1, int(_cell * WIDTH_SPREAD)))


## 칸의 네 가장자리 중 **외곽선(잉크)이 아닌 몸 픽셀이 놓인** 변의 이름.
## 없으면 빈 문자열 — 그래야 그림이 칸을 꽉 채워도 "잘리지 않았다"가 성립한다.
func _bare_edge(row: int) -> String:
	var top := row * _cell
	for x in _cell:
		if _solid_not_ink(x, top) or _solid_not_ink(x, top + _cell - 1):
			return "위/아래"
	for y in _cell:
		if _solid_not_ink(0, top + y) or _solid_not_ink(_cell - 1, top + y):
			return "좌/우"
	return ""


func _solid_not_ink(x: int, y: int) -> bool:
	var c := _image.get_pixel(x, y)
	return c.a > 0.0 and not c.is_equal_approx(_ink)


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
	for y in _image.get_height():
		for x in _image.get_width():
			var c := _image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if c.a < 1.0:
				semi += 1
			colors[c.to_html(false)] = true
	if semi > 0:
		_fail("반투명 픽셀 %d개 — 도트는 알파가 0 아니면 255 여야 한다" % semi)
	if colors.size() > MAX_COLORS:
		_fail("색이 %d종 — 제한 팔레트(%d종 이하)를 벗어났다" % [colors.size(), MAX_COLORS])
	else:
		print("[qa] %-8s 색 %d종 (상한 %d)" % [_style, colors.size(), MAX_COLORS])
	_check_outline()


## **외곽선 검사.** 실루엣의 테두리(투명과 맞닿은 몸 픽셀)가 **한 색으로 둘러져
## 있어야** 하고, 그 색이 순검정이면 안 된다(`docs/STYLE_GUIDE.md` 2번).
##
## **잉크색을 상수로 적어두지 않는다** (2026-09-08, INBOX #57). 절차 생성기 시절에는
## 우리가 그 색을 골랐지만, 지금 팔레트는 ComfyUI 그림을 줄여서 나온다 — 상수로
## 적으면 그림을 바꾼 바퀴가 여기를 같이 고쳐야 하고, 그건 반드시 잊어버린다.
## 대신 **구조를 잰다**: 테두리가 한 색이라는 것 자체가 `gen_player.add_ink()` 가
## 제대로 둘렀다는 뜻이고, 그 색이 곧 잉크색이다.
##
## **순검정을 몸 안에서까지 막지는 않는다** — STYLE_GUIDE 가 금지한 것은 **외곽선**의
## 순검정이다(화면에서 툭 튀어나온다). 눈동자처럼 안쪽의 한두 픽셀은 그 규칙의
## 대상이 아니다.
func _check_outline() -> void:
	var edge := {}
	for row in DIRS.size():
		var top := row * _cell
		for y in _cell:
			for x in _image.get_width():
				if _image.get_pixel(x, top + y).a <= 0.0:
					continue
				if _is_edge(x, top + y, top):
					edge[_image.get_pixel(x, top + y).to_html(false)] = true
	if edge.is_empty():
		_fail("실루엣 테두리를 못 찾았다 — 빈 시트인가")
		return
	if edge.size() > 1:
		_fail("외곽선이 %d색이다 %s — 한 색으로 둘러져 있어야 한다" % [edge.size(), edge.keys()])
		return
	_ink = Color(String(edge.keys()[0]))
	if _ink.r8 == 0 and _ink.g8 == 0 and _ink.b8 == 0:
		_fail("외곽선이 순검정이다 — 화면에서 툭 튀어나온다 (STYLE_GUIDE 2번)")
	else:
		print("[qa] %-8s 외곽선 #%s 한 색" % [_style, _ink.to_html(false)])


## 이 몸 픽셀이 실루엣의 테두리인가 — 4-이웃 중 하나라도 투명하거나 칸 밖이면 그렇다.
func _is_edge(x: int, y: int, top: int) -> bool:
	for step: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var nx := x + step.x
		var ny := y + step.y
		if nx < 0 or nx >= _image.get_width() or ny < top or ny >= top + _cell:
			return true
		if _image.get_pixel(nx, ny).a <= 0.0:
			return true
	return false


## **칸이 다른 시트가 한 `SpriteFrames` 에 섞여도** 각자 제 칸으로 잘리고 발밑 줄이
## 맞는가 (2026-09-07, INBOX #46 — idle 만 32px 이고 걷기·도구는 17px 인 샘플 상태).
##
## 이 검사가 값을 하는 이유: 칸 크기를 상수 하나로 믿으면 칸이 다른 시트는 조각나거나
## (칸이 작으면) 빈 칸이 되는데(칸이 크면), **그래도 게임은 안 죽는다** — 화면을
## 눈으로 보기 전엔 모른다. 그리고 발밑 보정(`feet_offset()`)도 칸마다 달라야 해서,
## 한 번만 넣어두면 칸이 다른 모션으로 넘어가는 순간 캐릭터가 땅에 묻히거나 뜬다.
##
## **모든 시트의 칸이 다시 같아져도(= 이사가 끝나도) 이 검사는 그대로 값을 한다** —
## 그때는 "시트마다 칸을 읽는다"가 "전부 같은 칸이 나온다"로 통과할 뿐이다.
func _check_mixed_cells() -> void:
	_style = "섞인 칸"
	var frames := PlayerFrames.build(_styles[0])
	if frames == null:
		_fail("모든 모션을 담은 SpriteFrames 를 못 만들었다")
		return
	var seen := {}
	for motion: String in PlayerFrames.motions():
		var sheet: Texture2D = load(PlayerFrames.sheet_path(motion, _styles[0]))
		if sheet == null:
			_fail("%s 시트를 못 읽었다" % motion)
			continue
		var cell := PlayerFrames.cell_of(sheet)
		seen[cell] = true
		var columns := maxi(1, sheet.get_width() / cell)
		if cell * columns != sheet.get_width():
			_fail("%s: 폭 %d 가 칸 %d 로 안 나눠떨어진다" % [motion, sheet.get_width(), cell])
		for dir: String in DIRS:
			var anim := "%s_%s" % [motion, dir]
			var got := PlayerFrames.anim_cell(frames, anim)
			if got != cell:
				_fail("%s 를 칸 %d 로 잘랐다 — 그 시트의 칸은 %d 다" % [anim, got, cell])
			if frames.get_frame_count(anim) != columns:
				_fail("%s 가 %d프레임인데 시트는 %d열이다"
						% [anim, frames.get_frame_count(anim), columns])
		_check_feet_line(sheet.get_image(), motion, cell, columns)
	var cells: Array = seen.keys()
	cells.sort()
	print("[qa] 한 SpriteFrames 안의 칸 크기: %s" % [cells])


## 그 시트의 **발밑 줄이 `feet_offset()` 과 맞는가.** 그림의 맨 아랫줄이 발이 닿는
## 줄 바로 위에 와야 노드 원점이 발밑이 된다 — 칸이 달라도 이 관계는 같아야 한다.
## 한 줄 아래까지는 봐준다(낫의 날처럼 발보다 조금 내려오는 프레임이 있다).
func _check_feet_line(image: Image, motion: String, cell: int, columns: int) -> void:
	var feet := PlayerFrames.feet_y(cell)
	for row in DIRS.size():
		for column in columns:
			var bottom := -1
			for y in range(cell - 1, -1, -1):
				for x in cell:
					if image.get_pixel(column * cell + x, row * cell + y).a > 0.0:
						bottom = y
						break
				if bottom >= 0:
					break
			if bottom < 0:
				_fail("%s_%s #%d: 빈 칸이다" % [motion, DIRS[row], column])
			elif bottom < feet - 2 or bottom > feet:
				_fail("%s_%s #%d: 그림이 %d줄까지인데 발밑 줄은 %d 다 (칸 %d) — 땅에서 뜨거나 묻힌다"
						% [motion, DIRS[row], column, bottom, feet, cell])


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
	if _stage == 0:
		_shoot("80_player_idle_hairstyles")
	elif _stage == 1:
		_shoot("81_player_tools_on_grass")
	else:
		_shoot("82_player_use_%s" % PlayerFrames.TOOLS[_stage - 2])
	# 다음 판은 앞의 것을 치우고 새로 세운다 — 뷰포트를 통째로 찍으므로
	# 겹쳐두면 둘이 한 장에 섞인다.
	_board.queue_free()
	if _stage >= PlayerFrames.TOOLS.size() + 1:
		_report()
		return true
	if _stage == 0:
		_build_hold_board()
	else:
		_build_tool_board(PlayerFrames.TOOLS[_stage - 1])
	_stage += 1
	_frames = 0
	return false


## 눈으로 볼 몫. 실제 게임 배율로, 지형 색 위에 **머리모양 × 방향 4개**를 격자로
## 그려 캡처한다 — 나란히 놓지 않으면 서로 어울리는지 판단할 수 없다.
func _build_board() -> void:
	var keys: Array[String] = []
	for style in _styles:
		keys.append("idle")
	_grid("idle 머리모양", _styles, keys, 24)


## **도구 7종을 한 장에 나란히 놓는다** — 맨손 idle 이 맨 왼쪽이다. 「도구를 들었더니
## 다른 캐릭터가 됐는가」와 「도구끼리 실루엣이 겹치는가」는 나란히 놓아야 보인다
## (`docs/STYLE_GUIDE.md` 7번 6항). 도구가 7종이라 1 + 7 = 8칸이다.
func _build_hold_board() -> void:
	var keys: Array[String] = ["idle"]
	for tool: String in PlayerFrames.TOOLS:
		keys.append("hold_%s" % tool)
	var styles: Array[String] = []
	for key in keys:
		styles.append(_styles[0])
	_grid("도구 들고 있기", styles, keys, 12)


## **도구를 든 모습을 실제 지형 색 위에 실제 배율로** 늘어놓는다
## (2026-09-07, INBOX #24 — `docs/STYLE_GUIDE.md` 7번 6항: 기존 자산과 나란히
## 놓고 팔레트·도트 크기·외곽선이 어울리는지 보는 자리다).
## 행 = 방향, 열 = 맨손 idle · 이 도구를 들고 있기 · 이 도구의 사용 프레임들.
##
## **도구마다 한 장씩 찍는다**(2026-09-07, INBOX #32) — 한 장에 다 넣으면 뷰포트를
## 넘어 잘린다. **도구 전부의 「들고 있기」는 위 `_build_hold_board()` 가 한 장에
## 모아 찍는다**(2026-09-08, INBOX #57): 칸이 32 → 96px 이 되면서 여기에 7종을 같이
## 넣으면 14칸 × 108 = 1512px 로 창(1280)을 넘어 오른쪽이 통째로 잘렸다. 나눠도
## 「나란히 비교」는 그 판에서 그대로 된다.
func _build_tool_board(tool: String) -> void:
	var keys: Array[String] = ["idle", "hold_%s" % tool]
	if PlayerFrames.has_use(tool):
		keys.append("use_%s" % tool)
	var styles: Array[String] = []
	for key in keys:
		styles.append(_styles[0])
	_grid(tool, styles, keys, 12)


## 판 하나를 세운다. `styles[i]`/`keys[i]` 가 i번째 **묶음**(시트 한 장)이고, 그 시트의
## 열 수만큼 칸이 늘어난다. 행은 언제나 방향 4개다.
##
## **칸과 배율은 시트에서 읽는다** (2026-09-08, INBOX #57) — 상수로 적어두면 칸이
## 바뀐 순간 엉뚱한 자리를 잘라 판이 통째로 조각난다(96px 시트를 32 로 잘랐다).
func _grid(what: String, styles: Array[String], keys: Array[String], gap: int) -> void:
	var sheets: Array[Texture2D] = []
	for i in keys.size():
		var texture: Texture2D = load(PlayerFrames.sheet_path(keys[i], styles[i]))
		if texture != null:
			sheets.append(texture)
	var board := ColorRect.new()
	board.color = TerrainPalettes.color_of("grass", 1)
	root.add_child(board)
	_board = board
	if sheets.is_empty():
		return
	var cell := PlayerFrames.cell_of(sheets[0])
	var zoom := PlayerFrames.scale_of(cell)
	# 칸 수는 **실제로 그릴 것에서 센다** — 미리 더해두면 도구가 늘 때 풀밭이 그림보다
	# 좁아진다.
	var columns := 0
	for texture in sheets:
		columns += maxi(1, texture.get_width() / cell)
	var step := cell * zoom + gap
	board.size = Vector2(step * columns + gap * 2, step * DIRS.size() + gap * 2)
	if board.size.x > root.get_visible_rect().size.x:
		_fails.append("[%s] 판이 %dpx 라 창(%d)을 넘는다 — 캡처가 잘린다"
				% [what, board.size.x, root.get_visible_rect().size.x])
	for row in DIRS.size():
		var column := 0
		for texture in sheets:
			for f in maxi(1, texture.get_width() / cell):
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(f * cell, row * cell, cell, cell)
				var view := TextureRect.new()
				view.texture = atlas
				view.position = Vector2(gap + column * step, gap + row * step)
				view.size = Vector2(cell, cell) * zoom
				view.stretch_mode = TextureRect.STRETCH_SCALE
				board.add_child(view)
				column += 1


func _shoot(shot_name: String) -> void:
	var vp := root.get_texture()
	if vp == null:
		print("[qa] 캡처 건너뜀 — --headless 로 돌렸다(뷰포트 텍스처 없음)")
		return
	var shot := vp.get_image()
	var path := "%s/%s.png" % [SHOTS, shot_name]
	shot.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, shot.get_width(), shot.get_height()])


func _report() -> void:
	if _fails.is_empty():
		print("[qa] PASS — 시트 규격 / 방향 간 크기 / 섞인 칸 크기 + 발밑 / 팔레트 / 텍스처 필터 정상")
		quit()
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)
