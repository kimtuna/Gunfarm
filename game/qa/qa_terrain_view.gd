extends SceneTree

## 지형 타일 스프라이트 자체 QA (INBOX #12).
##
## 실행 (캡처까지 하려면 `--headless` 를 빼야 한다 — docs/GOTCHAS.md):
##   /Applications/Godot.app/Contents/MacOS/Godot --path game --script qa/qa_terrain_view.gd
##
## 확인하는 것 (기계가 판정할 수 있는 것만):
##   1) 시트 규격 — 아트 16px × 4096칸(64×64). 아트 16px × 씬 3배 = 화면 48px
##      = `WorldGen.TILE_SIZE` (docs/STYLE_GUIDE.md 1번).
##   2) **번호 규칙이 생성기와 같다** — 손으로 만든 작은 지도에서 칸 번호를 직접
##      계산해 시트 사각형과 맞춰본다. 여기가 어긋나면 엉뚱한 칸이 그려지는데,
##      화면만 봐서는 "무늬가 좀 이상하네" 정도로 보여서 놓치기 쉽다.
##   3) 무늬 변주가 좌표에 따라 실제로 갈린다(한 종류만 나오면 벽지가 된다).
##   4) 시트 안의 칸들이 서로 다르다 — 같은 그림이 4096번 들어있지 않다.
##   5) 텍스처 필터가 nearest 다 — 풀리면 도트가 흐려진다.
##
## 눈으로 볼 몫은 `user://qa_shots/` 에 남긴다:
##   `60_terrain_field` 실제 월드 한 화면, `61_terrain_with_player` 그 위에
##   캐릭터 4방향을 세운 것(어울리는지 나란히 놓고 보는 용도 — INBOX #12).

const WorldGen := preload("res://scripts/world_gen.gd")
const TerrainTiles := preload("res://scripts/terrain_tiles.gd")
const TerrainPalettes := preload("res://scripts/terrain_palettes.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")

const SHOTS := "user://qa_shots"
const SEED := 20260906
const DIRS := ["down", "left", "right", "up"]

var _fails: Array[String] = []
var _image: Image = null
var _frames := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var texture: Texture2D = load(TerrainTiles.SHEET_PATH)
	if texture == null:
		_fail("지형 시트를 못 읽었다: %s — `--import` 를 안 돌렸을 수 있다"
				% TerrainTiles.SHEET_PATH)
		_report()
		return
	_image = texture.get_image()
	_check_sheet_size()
	_check_index_rule()
	_check_variants()
	_check_cells_differ()
	_check_filter()
	_build_board(texture)


func _fail(message: String) -> void:
	_fails.append(message)


func _check_sheet_size() -> void:
	var want := TerrainTiles.TILE_ART * TerrainTiles.SHEET_COLS
	if _image.get_size() != Vector2i(want, want):
		_fail("시트 크기가 %s 인데 %dx%d 여야 한다" % [_image.get_size(), want, want])
	if TerrainTiles.TILE_ART * TerrainTiles.SCALE != WorldGen.TILE_SIZE:
		_fail("아트 %dpx × %d배 = %d 인데 타일 크기는 %d 다 — 배율이 정수로 안 떨어진다"
				% [TerrainTiles.TILE_ART, TerrainTiles.SCALE,
				TerrainTiles.TILE_ART * TerrainTiles.SCALE, WorldGen.TILE_SIZE])


## 손으로 만든 작은 지도에서 마스크·번호를 직접 계산해 본다.
## `_FakeWorld` 는 `is_land()` 만 있으면 되는 자리다.
func _check_index_rule() -> void:
	var world := _FakeWorld.new([
		"..#..",
		".###.",
		"..#..",
	])
	# 가운데(2,1) 는 사방이 땅 아니고 대각이 비었다: 이웃 순서대로
	# (-1,-1)=. (0,-1)=# (1,-1)=. (-1,0)=# (1,0)=# (-1,1)=. (0,1)=# (1,1)=.
	var want_mask := (1 << 1) | (1 << 3) | (1 << 4) | (1 << 6)
	var mask := TerrainTiles.mask_at(world, 2, 1)
	if mask != want_mask:
		_fail("이웃 마스크가 %d — %d 여야 한다 (비트 순서가 생성기와 어긋났다)"
				% [mask, want_mask])
	var index := TerrainTiles.tile_index(TerrainTiles.variant_at(2, 1), true, want_mask)
	if index != TerrainTiles.variant_at(2, 1) * 512 + 256 + want_mask:
		_fail("칸 번호 규칙이 깨졌다: %d" % index)
	var region := TerrainTiles.region_of(index)
	if region.size != Vector2(TerrainTiles.TILE_ART, TerrainTiles.TILE_ART) \
			or region.end.x > _image.get_width() or region.end.y > _image.get_height():
		_fail("칸 %d 의 시트 사각형 %s 이 시트 밖이다" % [index, region])
	# 지도 밖은 바다여야 한다 — 안 그러면 지도 가장자리에 가짜 해안이 생긴다.
	if TerrainTiles.mask_at(world, 0, 0) & 1 != 0:
		_fail("지도 밖(-1,-1)을 땅으로 봤다")
	print("[qa] 마스크/번호 규칙 ok (mask=%d index=%d region=%s)" % [mask, index, region])


func _check_variants() -> void:
	var seen := {}
	for y in 16:
		for x in 16:
			var v := TerrainTiles.variant_at(x, y)
			if v < 0 or v >= TerrainTiles.VARIANTS:
				_fail("변주 번호가 범위 밖이다: %d" % v)
			seen[v] = true
	if seen.size() < TerrainTiles.VARIANTS:
		_fail("16×16 칸에서 변주가 %d종밖에 안 나왔다 (%d종이어야 한다)"
				% [seen.size(), TerrainTiles.VARIANTS])
	# 음수 좌표(지도 밖)에서도 범위 안이어야 한다 — `%` 는 음수를 그대로 돌려준다.
	for x in range(-8, 0):
		if TerrainTiles.variant_at(x, -3) < 0:
			_fail("음수 좌표에서 변주가 음수다 (posmod 를 안 썼다)")
			break
	print("[qa] 무늬 변주 %d종" % seen.size())


## 시트의 칸들이 실제로 다른 그림인지. 지문을 모아 몇 종인지 센다.
func _check_cells_differ() -> void:
	var prints := {}
	var art := TerrainTiles.TILE_ART
	for index in [0, 1, 255, 256, 257, 511, 512, 1024, 2048, 4095]:
		var region := TerrainTiles.region_of(index)
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(_image.get_region(Rect2i(region)).get_data())
		prints[context.finish().hex_encode()] = index
	if prints.size() < 8:
		_fail("표본 10칸 중 서로 다른 그림이 %d종뿐이다 — 시트가 제대로 안 구워졌다"
				% prints.size())
	# 바다 한가운데(마스크 0, 중심 바다)와 땅 한가운데(마스크 255, 중심 땅)는
	# 해안이 전혀 없어야 한다 — 물거품 색이 한 픽셀도 없어야 한다.
	_check_no_foam(TerrainTiles.tile_index(0, false, 0), "바다 한가운데")
	_check_no_foam(TerrainTiles.tile_index(0, true, 255), "땅 한가운데")
	print("[qa] 시트 표본 %d종" % prints.size())


func _check_no_foam(index: int, what: String) -> void:
	var region := TerrainTiles.region_of(index)
	var cell := _image.get_region(Rect2i(region))
	var foam := TerrainPalettes.color_of("foam", 1)
	for y in cell.get_height():
		for x in cell.get_width():
			if cell.get_pixel(x, y).is_equal_approx(foam):
				_fail("%s 칸에 물거품 색이 있다 — 해안이 없어야 하는 칸이다" % what)
				return


func _check_filter() -> void:
	var filter: int = ProjectSettings.get_setting(
			"rendering/textures/canvas_textures/default_texture_filter", -1)
	if filter != 0:
		_fail("텍스처 필터가 %d — nearest(0) 가 아니면 도트가 흐려진다" % filter)


## 눈으로 볼 몫 — 실제 월드의 해안을 한 화면 그리고, 그 위에 캐릭터를 세운다.
func _build_board(sheet: Texture2D) -> void:
	var world := WorldGen.new()
	world.build(SEED)
	var coast := _find_coast(world)
	var view := TerrainBoard.new()
	view.sheet = sheet
	view.world = world
	view.origin = coast - Vector2i(13, 7)
	root.add_child(view)

	# 캐릭터 4방향을 풀 위에 세운다 — 팔레트·도트 크기가 어울리는지는 **나란히
	# 놓고** 봐야 판단할 수 있다 (INBOX #12).
	var texture: Texture2D = load(PlayerFrames.sheet_path("idle", PlayerFrames.DEFAULT_HAIRSTYLE))
	if texture == null:
		return
	for row in DIRS.size():
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(0, row * PlayerFrames.CELL, PlayerFrames.CELL, PlayerFrames.CELL)
		var sprite := TextureRect.new()
		sprite.texture = atlas
		sprite.size = Vector2(PlayerFrames.CELL, PlayerFrames.CELL) * PlayerFrames.SCALE
		sprite.position = Vector2(180 + row * 150, 300)
		root.add_child(sprite)


func _find_coast(world: RefCounted) -> Vector2i:
	var spawn: Vector2i = world.spawn_tile
	var best := spawn
	var best_distance := INF
	var margin := 12
	for y in range(margin, WorldGen.MAP_TILES - margin):
		for x in range(margin, WorldGen.MAP_TILES - margin):
			if not world.is_land(x, y):
				continue
			if world.is_land(x + 1, y) and world.is_land(x - 1, y) \
					and world.is_land(x, y + 1) and world.is_land(x, y - 1):
				continue
			var distance: float = Vector2(Vector2i(x, y) - spawn).length_squared()
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	return best


func _process(_delta: float) -> bool:
	_frames += 1
	# 상태를 만든 직후 바로 찍으면 한 프레임 전이 찍힌다 (docs/GOTCHAS.md).
	if _frames < 3:
		return false
	_shoot()
	_report()
	return true


func _shoot() -> void:
	var texture := root.get_texture()
	if texture == null:
		print("[qa] 캡처 없음 — --headless 로 돌리면 화면이 없다 (docs/GOTCHAS.md)")
		return
	var image := texture.get_image()
	var path := "%s/61_terrain_with_player.png" % SHOTS
	image.save_png(path)
	print("[qa] shot %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _report() -> void:
	if _fails.is_empty():
		print("[qa] PASS — 지형 타일 시트")
		quit(0)
		return
	for message in _fails:
		print("[qa] FAIL %s" % message)
	quit(1)


## 시트에서 칸을 떠다 붙여 지형을 그린다 — `terrain_view.gd` 와 같은 방식이지만
## 카메라 없이 화면 좌표에 바로 그린다(캡처만이 목적이라 월드에 붙이지 않는다).
class TerrainBoard:
	extends Node2D

	var sheet: Texture2D = null
	var world: RefCounted = null
	var origin := Vector2i.ZERO

	func _draw() -> void:
		var size := float(WorldGen.TILE_SIZE)
		for y in 16:
			for x in 28:
				var tile := origin + Vector2i(x, y)
				draw_texture_rect_region(sheet, Rect2(x * size, y * size, size, size),
						TerrainTiles.region_at(world, tile.x, tile.y))


## `is_land()` 만 흉내 내는 가짜 월드 — 마스크 규칙을 손으로 만든 지도로 검증한다.
class _FakeWorld:
	extends RefCounted

	var rows: Array = []

	func _init(map_rows: Array) -> void:
		rows = map_rows

	func is_land(x: int, y: int) -> bool:
		if y < 0 or y >= rows.size():
			return false
		var row: String = rows[y]
		if x < 0 or x >= row.length():
			return false
		return row[x] == "#"
