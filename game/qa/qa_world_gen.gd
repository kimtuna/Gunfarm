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
##   5) 본섬이 육지의 대부분을 차지한다 (섬이 잘게 부서지면 걸어서 갈 곳이 없다).
##   6) **해안선이 그냥 동그란 원이 아니다** — 노이즈보다 섬 감쇠가 세면 시드를 바꿔도
##      똑같이 생긴 원형 섬만 나온다. 실제로 한 번 그렇게 됐던 자리라 수치로 막아둔다.
##   7) 생성이 충분히 빠르다(입장할 때 눈에 띄게 멈추면 안 된다).

const WorldGen := preload("res://scripts/world_gen.gd")

## 실행 사이에 같은 결과가 나오는지 비교하려고 남기는 지문 파일.
const FINGERPRINT_PATH := "user://qa_world_fingerprints.json"

const SEEDS: Array[int] = [1, 7, 42, 1234, 999999, 20260906, 3, 88, 555, 31337]

## 파라미터를 손보면 이 범위도 같이 갱신하고 docs/DESIGN.md "월드 생성"에도 반영할 것.
const SEA_RATIO_MIN := 0.40
const SEA_RATIO_MAX := 0.55
## 본섬이 전체 육지에서 차지하는 최소 비율.
const MAIN_ISLAND_SHARE_MIN := 0.80
## 해안선 복잡도 = (바다에 닿은 땅 칸) / (전체 땅 칸). 완벽한 원이면 2~4% 밖에 안 나온다.
const COAST_RATIO_MIN := 0.07

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
	var elapsed := Time.get_ticks_msec() - started
	print("[qa] 월드 %d개 생성에 %dms (한 개당 약 %dms)" % [SEEDS.size(), elapsed, elapsed / SEEDS.size()])
	if elapsed / SEEDS.size() > 500:
		_fails.append("월드 하나 만드는 데 %dms — 입장할 때 눈에 띄게 멈춘다" % (elapsed / SEEDS.size()))

	_check_seeds_differ(fingerprints)
	_check_across_runs(fingerprints)

	if _fails.is_empty():
		print("[qa] PASS — 시드 재현성 / 테두리 바다 / 바다 비율 / 스폰 지점 전부 정상")
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


## 5) + 6) 본섬 비중과 해안선 복잡도.
func _check_island_shape(seed_value: int, world: RefCounted) -> void:
	var land := 0
	var coast := 0
	for y in range(1, WorldGen.MAP_TILES - 1):
		for x in range(1, WorldGen.MAP_TILES - 1):
			if not world.is_land(x, y):
				continue
			land += 1
			if not (world.is_land(x + 1, y) and world.is_land(x - 1, y) \
					and world.is_land(x, y + 1) and world.is_land(x, y - 1)):
				coast += 1
	if land == 0:
		_fails.append("시드 %d: 땅이 하나도 없다" % seed_value)
		return
	var coast_ratio := float(coast) / float(land)
	var share: float = float(world._largest_land_component().size()) / float(land)
	print("[qa] 시드 %d → 해안선 복잡도 %.1f%%  본섬이 육지의 %.1f%%" % [
		seed_value, coast_ratio * 100.0, share * 100.0])
	if coast_ratio < COAST_RATIO_MIN:
		_fails.append("시드 %d: 해안선 복잡도 %.1f%% (>= %.0f%% 여야 함) — 섬이 밋밋한 원이다" % [
			seed_value, coast_ratio * 100.0, COAST_RATIO_MIN * 100.0])
	if share < MAIN_ISLAND_SHARE_MIN:
		_fails.append("시드 %d: 본섬이 육지의 %.1f%% 뿐이다 (>= %.0f%%) — 섬이 잘게 부서졌다" % [
			seed_value, share * 100.0, MAIN_ISLAND_SHARE_MIN * 100.0])


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
