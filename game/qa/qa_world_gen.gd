extends SceneTree

## INBOX #5 자체 QA (1) — 월드 생성 로직. 화면이 필요 없으므로 헤드리스로 돈다.
##
## 실행:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script qa/qa_world_gen.gd
##
## 확인하는 것 (docs/DESIGN.md "월드 생성"):
##   1) **같은 시드는 항상 같은 월드** — 같은 시드로 두 번 만들면 지형/스폰이 완전히 같고,
##      다른 시드는 다른 월드가 나온다. (실행 사이의 재현성은 아래 지문 파일로 확인한다.)
##   2) 지도 테두리는 전부 바다다 — 월드 밖으로 걸어나갈 수 없어야 한다.
##   3) 바다 비율이 어느 시드에서나 기록해둔 범위 안에 들어온다.
##   4) 스폰 지점은 땅이고, **가장 큰 육지 덩어리 안**이다 (외딴 1칸 섬에 갇히면 안 된다).
##   5) **육지가 하나로 이어져 있다** — 연결 요소가 정확히 1개. 두 조각으로 갈리면
##      걸어서 못 가는 땅이 생긴다 (INBOX #61).
##   6) **모든 물이 섬 바깥 바다 하나로 이어져 있다** — 갇힌 웅덩이가 하나도 없다.
##      "육지를 하나의 섬으로 뭉치고 바깥을 바다로 두른다"의 나머지 절반이다 (INBOX #61).
##   7) **섬이 지도 테두리에 닿지 않는다** — 앞바다 여백이 있어야 「두른 바다」로 보인다.
##      테두리에 붙으면 섬이 아니라 네모로 잘린 대륙이 된다.
##   8) **해안선이 그냥 동그란 원이 아니다** — 노이즈보다 섬 마스크가 세면 시드를 바꿔도
##      똑같이 생긴 원형 섬만 나온다. 실제로 한 번 그렇게 됐던 자리라 수치로 막아둔다.
##   9) 생성이 충분히 빠르다(입장할 때 눈에 띄게 멈추면 안 된다).
##  10) **월드 오브젝트(나무·바위·덤불)가 규칙대로 놓인다** (INBOX #63):
##      바다 위에 없고, 물가(이웃 8칸에 바다가 있는 칸)에 없고, 스폰 둘레를 안 막고,
##      같은 시드면 같은 자리에 같은 종류가 나고, 밀도가 기록해둔 범위 안이다.
##      그림 시트가 실제로 있고 칸 크기가 `world_objects.gd` 의 표와 맞는지도 본다.

const WorldGen := preload("res://scripts/world_gen.gd")
const WorldObjects := preload("res://scripts/world_objects.gd")

## 실행 사이에 같은 결과가 나오는지 비교하려고 남기는 지문 파일.
const FINGERPRINT_PATH := "user://qa_world_fingerprints.json"

const SEEDS: Array[int] = [1, 7, 42, 1234, 999999, 20260906, 3, 88, 555, 31337]

## 파라미터를 손보면 이 범위도 같이 갱신하고 docs/DESIGN.md "월드 생성"에도 반영할 것.
## 2026-09-08 (INBOX #61) 실측: 시드 15개에서 50.6~56.4%.
const SEA_RATIO_MIN := 0.46
const SEA_RATIO_MAX := 0.62
## **해안선 길이 ÷ 같은 넓이 원의 둘레.** 완벽한 원이면 1.0 이다.
## 옛 기준(해안 칸 ÷ 땅 칸)을 버린 이유: 그 값은 **섬이 클수록 저절로 작아진다**
## (둘레는 반지름에, 넓이는 제곱에 비례한다). 게다가 옛 지도는 육지에 뚫린 웅덩이
## 테두리가 전부 「해안」으로 세어져서 10% 가 나왔던 것이라, 웅덩이를 메우자마자
## 같은 섬이 4~6% 로 떨어진다 — **넓이로 정규화한 이 비**라야 "얼마나 원에서 먼가"만
## 잰다. 2026-09-08 실측: 시드 15개에서 2.00~2.79.
const COAST_VS_CIRCLE_MIN := 1.60
## 땅이 지도 테두리에서 최소한 이만큼은 떨어져 있어야 한다(칸). 실측 11~12.
const OCEAN_MARGIN_MIN := 6

## 오브젝트가 땅 칸에서 차지하는 비율. **아래가 있는 이유**가 위만큼 중요하다 —
## 화면에 크기를 견줄 것이 없으면 캐릭터가 거인처럼 보인다(docs/DESIGN.md
## 「카메라 / 해상도」). 2026-09-08 실측: 시드 10개에서 23.1~24.4%.
const OBJECT_SHARE_MIN := 0.15
const OBJECT_SHARE_MAX := 0.32
## 나무가 오브젝트에서 차지하는 비율 — 바위·덤불만 남으면 「크기를 견줄 것」이
## 사라진다(둘 다 타일 한 칸이라 캐릭터보다 작다). 실측 0.72~0.76.
const TREE_SHARE_MIN := 0.50

var _fails: Array[String] = []


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var fingerprints := {}
	for seed_value in SEEDS:
		var world: RefCounted = WorldGen.new()
		world.build(seed_value)
		fingerprints[str(seed_value)] = world.fingerprint()
		_check_same_seed_is_same_world(seed_value, world)
		_check_edges_are_sea(seed_value, world)
		_check_sea_ratio(seed_value, world)
		_check_spawn(seed_value, world)
		_check_island_shape(seed_value, world)
		_check_one_island_surrounded_by_sea(seed_value, world)
		_check_objects(seed_value, world)
	var elapsed := Time.get_ticks_msec() - started
	print("[qa] 월드 %d개 생성에 %dms (한 개당 약 %dms)" % [SEEDS.size(), elapsed, elapsed / SEEDS.size()])
	if elapsed / SEEDS.size() > 500:
		_fails.append("월드 하나 만드는 데 %dms — 입장할 때 눈에 띄게 멈춘다" % (elapsed / SEEDS.size()))

	_check_object_sheets()
	_check_seeds_differ(fingerprints)
	_check_across_runs(fingerprints)

	if _fails.is_empty():
		print("[qa] PASS — 시드 재현성 / 섬 하나 + 두른 바다 / 바다 비율 / 스폰 지점 전부 정상")
		quit()
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)


## 1) 같은 시드로 두 번 만들면 완전히 같아야 한다.
func _check_same_seed_is_same_world(seed_value: int, world: RefCounted) -> void:
	var again: RefCounted = WorldGen.new()
	again.build(seed_value)
	if again.tiles != world.tiles:
		_fails.append("시드 %d: 같은 시드로 두 번 만들었는데 지형이 다르다" % seed_value)
	if again.spawn_tile != world.spawn_tile:
		_fails.append("시드 %d: 같은 시드인데 스폰이 %s / %s 로 다르다" % [
			seed_value, world.spawn_tile, again.spawn_tile])
	# **오브젝트도 같이 본다** (INBOX #63) — 지형만 견주면 나무 자리가 매번 달라져도
	# "같은 월드"로 통과한다.
	if again.objects != world.objects:
		_fails.append("시드 %d: 같은 시드로 두 번 만들었는데 오브젝트 배치가 다르다" % seed_value)


## 10) 월드 오브젝트 배치.
##
## **같은 시드면 같은 배치**는 위 1)이 이미 본다 — `_check_same_seed_is_same_world`
## 가 `objects` 까지 견주고, 실행 사이의 재현성은 `fingerprint()` 가 오브젝트를 함께
## 해싱하므로 아래 `_check_across_runs` 가 본다.
func _check_objects(seed_value: int, world: RefCounted) -> void:
	var counts := {}
	for kind in WorldObjects.ALL:
		counts[kind] = 0
	var land := 0
	var bad_sea := 0
	var bad_shore := 0
	var bad_kind := 0
	var bad_spawn := 0
	var spawn: Vector2i = world.spawn_tile
	for y in WorldGen.MAP_TILES:
		for x in WorldGen.MAP_TILES:
			if world.is_land(x, y):
				land += 1
			var kind: int = world.object_at(x, y)
			if kind == WorldObjects.NONE:
				continue
			if not counts.has(kind):
				bad_kind += 1
				continue
			counts[kind] += 1
			if not world.is_land(x, y):
				bad_sea += 1
			elif not world._is_open(x, y):
				bad_shore += 1
			if maxi(absi(x - spawn.x), absi(y - spawn.y)) <= world.OBJECT_SPAWN_CLEAR:
				bad_spawn += 1
	var total: int = counts[WorldObjects.TREE] + counts[WorldObjects.ROCK] \
			+ counts[WorldObjects.BUSH]
	print("[qa] 시드 %d → 나무 %d / 바위 %d / 덤불 %d (땅 칸의 %.1f%%)" % [
		seed_value, counts[WorldObjects.TREE], counts[WorldObjects.ROCK],
		counts[WorldObjects.BUSH], 100.0 * float(total) / maxf(float(land), 1.0)])
	if bad_sea > 0:
		_fails.append("시드 %d: 오브젝트 %d개가 바다 위에 있다" % [seed_value, bad_sea])
	if bad_shore > 0:
		_fails.append("시드 %d: 오브젝트 %d개가 물가에 있다 — 이웃 8칸이 전부 땅인 칸에만 둔다" % [seed_value, bad_shore])
	if bad_spawn > 0:
		_fails.append("시드 %d: 오브젝트 %d개가 스폰 둘레 %d칸 안에 있다" % [seed_value, bad_spawn, world.OBJECT_SPAWN_CLEAR])
	if bad_kind > 0:
		_fails.append("시드 %d: 알 수 없는 오브젝트 종류가 %d칸 있다" % [seed_value, bad_kind])
	var share := float(total) / maxf(float(land), 1.0)
	if share < OBJECT_SHARE_MIN or share > OBJECT_SHARE_MAX:
		_fails.append("시드 %d: 오브젝트가 땅의 %.1f%% — 기록해둔 %.0f~%.0f%% 밖이다" % [
			seed_value, share * 100.0, OBJECT_SHARE_MIN * 100.0, OBJECT_SHARE_MAX * 100.0])
	var tree_share := float(counts[WorldObjects.TREE]) / maxf(float(total), 1.0)
	if tree_share < TREE_SHARE_MIN:
		_fails.append("시드 %d: 오브젝트 중 나무가 %.0f%%뿐이다 — 캐릭터보다 큰 것이 있어야 크기가 읽힌다" % [
			seed_value, tree_share * 100.0])


## 그림 시트가 실제로 있고, 칸 크기가 `world_objects.gd` 의 표와 맞는가.
## **어긋나면 시트를 엉뚱한 자리에서 잘라 쓴다** — 그림 생성기(`gen_objects.py`)의
## `SIZES`/`VARIANTS` 를 바꾼 바퀴가 게임 쪽 표를 안 고치면 여기서 잡힌다.
func _check_object_sheets() -> void:
	for kind in WorldObjects.ALL:
		var path: String = WorldObjects.sheet_path(kind)
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			_fails.append("오브젝트 시트를 못 읽었다: %s — `--import` 를 안 돌렸을 수 있다" % path)
			continue
		var cell: Vector2i = WorldObjects.CELL[kind]
		var want := Vector2i(cell.x * WorldObjects.VARIANTS, cell.y)
		if texture.get_size() != Vector2(want):
			_fails.append("%s 이 %s — %s 여야 한다 (칸 %s × 변주 %d)" % [
				path, texture.get_size(), want, cell, WorldObjects.VARIANTS])


## 2) 지도 테두리는 전부 바다.
func _check_edges_are_sea(seed_value: int, world: RefCounted) -> void:
	var last: int = WorldGen.MAP_TILES - 1
	for i in WorldGen.MAP_TILES:
		if world.is_land(i, 0) or world.is_land(i, last) or world.is_land(0, i) or world.is_land(last, i):
			_fails.append("시드 %d: 지도 테두리에 땅이 있다 (%d번째 칸) — 월드 밖으로 나갈 수 있다" % [seed_value, i])
			return


## 3) 바다 비율.
func _check_sea_ratio(seed_value: int, world: RefCounted) -> void:
	var ratio: float = world.sea_ratio()
	if ratio < SEA_RATIO_MIN or ratio > SEA_RATIO_MAX:
		_fails.append("시드 %d: 바다 비율 %.1f%% — 기록해둔 %.0f~%.0f%% 밖이다" % [
			seed_value, ratio * 100.0, SEA_RATIO_MIN * 100.0, SEA_RATIO_MAX * 100.0])


## 4) 스폰은 땅이고 가장 큰 육지 덩어리 안이다.
func _check_spawn(seed_value: int, world: RefCounted) -> void:
	var spawn: Vector2i = world.spawn_tile
	if not world.is_land(spawn.x, spawn.y):
		_fails.append("시드 %d: 스폰 %s 이 바다다" % [seed_value, spawn])
		return
	var main: PackedInt32Array = world._largest_land_component()
	var index := spawn.y * WorldGen.MAP_TILES + spawn.x
	if main.find(index) < 0:
		_fails.append("시드 %d: 스폰 %s 이 가장 큰 육지 덩어리 밖이다 — 외딴 섬에 갇힌다" % [seed_value, spawn])
	var reach := float(main.size()) / float(WorldGen.MAP_TILES * WorldGen.MAP_TILES)
	print("[qa] 시드 %d → 바다 %.1f%%  스폰 %s  본섬 %d칸(지도의 %.1f%%)" % [
		seed_value, world.sea_ratio() * 100.0, spawn, main.size(), reach * 100.0])


## 7) + 8) 앞바다 여백과 해안선 복잡도.
func _check_island_shape(seed_value: int, world: RefCounted) -> void:
	var last: int = WorldGen.MAP_TILES - 1
	var land := 0
	var coast := 0
	var margin: int = WorldGen.MAP_TILES
	for y in WorldGen.MAP_TILES:
		for x in WorldGen.MAP_TILES:
			if not world.is_land(x, y):
				continue
			land += 1
			margin = mini(margin, mini(mini(x, y), mini(last - x, last - y)))
			if not (world.is_land(x + 1, y) and world.is_land(x - 1, y) \
					and world.is_land(x, y + 1) and world.is_land(x, y - 1)):
				coast += 1
	if land == 0:
		_fails.append("시드 %d: 땅이 하나도 없다" % seed_value)
		return
	# 같은 넓이의 원이라면 둘레가 이만큼이다. 해안선을 이걸로 나눠서 "원에서 얼마나 먼가"를 잰다.
	var circle := 2.0 * sqrt(PI * float(land))
	var wiggle := float(coast) / circle
	print("[qa] 시드 %d → 해안선이 같은 넓이 원의 %.2f배  앞바다 여백 %d칸" % [seed_value, wiggle, margin])
	if wiggle < COAST_VS_CIRCLE_MIN:
		_fails.append("시드 %d: 해안선이 같은 넓이 원의 %.2f배뿐이다 (>= %.2f 여야 함) — 섬이 밋밋한 원이다" % [
			seed_value, wiggle, COAST_VS_CIRCLE_MIN])
	if margin < OCEAN_MARGIN_MIN:
		_fails.append("시드 %d: 땅이 지도 테두리에서 %d칸밖에 안 떨어져 있다 (>= %d) — 섬이 아니라 네모로 잘린 대륙이다" % [
			seed_value, margin, OCEAN_MARGIN_MIN])


## 5) + 6) **하나의 섬 + 그것을 두른 바다 하나**인지 (INBOX #61 이 요구한 두 가지).
## 육지 연결 요소가 여럿이면 걸어서 못 가는 땅이 생기고, 테두리에서 못 닿는 물이
## 남아 있으면 그게 바로 "호수처럼 흩어진 웅덩이"다.
func _check_one_island_surrounded_by_sea(seed_value: int, world: RefCounted) -> void:
	var size: int = WorldGen.MAP_TILES
	var islands := 0
	var seen := PackedByteArray()
	seen.resize(size * size)
	for start in size * size:
		if seen[start] == 1 or world.tiles[start] != WorldGen.LAND:
			continue
		islands += 1
		_flood(world, seen, PackedInt32Array([start]), WorldGen.LAND)
	if islands != 1:
		_fails.append("시드 %d: 육지 덩어리가 %d개다 (1개여야 함) — 걸어서 못 가는 땅이 있다" % [seed_value, islands])

	# 테두리에서 물길로 닿는 바다를 칠하고, 안 칠해진 물이 남으면 갇힌 웅덩이다.
	var wet := PackedByteArray()
	wet.resize(size * size)
	var edges := PackedInt32Array()
	for i in size:
		for index in [i, (size - 1) * size + i, i * size, i * size + size - 1]:
			if world.tiles[index] == WorldGen.SEA and wet[index] == 0:
				wet[index] = 1
				edges.append(index)
	_flood(world, wet, edges, WorldGen.SEA)
	var trapped := 0
	for i in size * size:
		if world.tiles[i] == WorldGen.SEA and wet[i] == 0:
			trapped += 1
	if trapped > 0:
		_fails.append("시드 %d: 바깥 바다에 안 이어진 물이 %d칸 있다 — 섬을 두른 바다가 아니라 웅덩이다" % [
			seed_value, trapped])


## 이미 칠해둔 시작점들에서 같은 값끼리 4방향으로 번져나간다.
func _flood(world: RefCounted, seen: PackedByteArray, stack: PackedInt32Array, want: int) -> void:
	var size: int = WorldGen.MAP_TILES
	for index in stack:
		seen[index] = 1
	var head := 0
	while head < stack.size():
		var index := stack[head]
		head += 1
		var x := index % size
		var y := index / size
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + step.x
			var ny: int = y + step.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			var ni: int = ny * size + nx
			if seen[ni] == 0 and world.tiles[ni] == want:
				seen[ni] = 1
				stack.append(ni)


## 다른 시드는 다른 월드여야 한다 (시드가 실제로 먹히는지).
func _check_seeds_differ(fingerprints: Dictionary) -> void:
	var seen := {}
	for key in fingerprints:
		var hash_value: String = fingerprints[key]
		if seen.has(hash_value):
			_fails.append("시드 %s 와 %s 가 같은 월드를 만든다 — 시드가 안 먹히고 있다" % [seen[hash_value], key])
		seen[hash_value] = key


## 실행(프로세스)이 달라져도 같은 시드가 같은 월드를 만드는지 — 서버가 월드를 재현할 수
## 있어야 한다는 요구가 이것이다. 처음 돌릴 때는 지문을 기록만 하고, 그 다음부터 비교한다.
func _check_across_runs(fingerprints: Dictionary) -> void:
	if FileAccess.file_exists(FINGERPRINT_PATH):
		var file := FileAccess.open(FINGERPRINT_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			var before: Dictionary = parsed
			var compared := 0
			for key in fingerprints:
				if not before.has(key):
					continue
				compared += 1
				if String(before[key]) != String(fingerprints[key]):
					_fails.append("시드 %s: 지난 실행과 다른 월드가 나왔다 (%s → %s)" % [
						key, String(before[key]).substr(0, 12), String(fingerprints[key]).substr(0, 12)])
			print("[qa] 지난 실행과 지문 %d개 비교" % compared)
		else:
			_fails.append("지문 파일이 깨졌다: %s" % FINGERPRINT_PATH)
	else:
		print("[qa] 지문 파일이 없어 이번 실행 것을 기록만 한다 — 한 번 더 돌리면 실행 간 재현성까지 확인된다.")
	var out := FileAccess.open(FINGERPRINT_PATH, FileAccess.WRITE)
	out.store_string(JSON.stringify(fingerprints, "\t"))
	out.close()
