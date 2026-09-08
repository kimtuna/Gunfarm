extends RefCounted

## 시드 기반 절차적 월드 생성 — 땅/바다 지형, 스폰 지점, **월드 오브젝트**
## (docs/DESIGN.md "월드 생성"). 채광 포인트·낚시 같은 자원 배치는 그 자원을
## 실제로 만드는 바퀴가 여기에 덧붙인다.
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md "시뮬레이션 구조") —
## 서버가 화면 없이 같은 시드로 같은 월드를 재현할 수 있어야 하기 때문이다.
## **같은 시드는 항상 같은 월드**여야 하므로 이 파일 안에서는 `randi()` 류의
## 전역 난수를 절대 쓰지 않는다(전부 시드에서 결정된다).

## 지도 한 변의 타일 수. 12288×12288 월드 단위 = 논리 해상도(1440×810) 기준으로
## 가로 약 8.5 화면 분량이다.
const MAP_TILES := 256

## 타일 한 칸의 월드 단위. 아트 16px × 씬 스케일 3 = 48 — 캐릭터(캔버스 17px ×
## 3 = 51px)와 같은 도트 크기 단위를 쓰려고 이 값으로 잡았다. **맞춰야 하는 것은
## 캐릭터의 전체 크기가 아니라 배율(3배)이라** 2026-09-07 에 캐릭터 캔버스가
## 절반이 됐어도 이 값은 그대로다
## (docs/DESIGN.md "아이템/오브젝트 크기 표준"). **배율은 정수여야 한다** —
## 소수 배율은 화면에서 아트 픽셀이 들쭉날쭉해져 도트가 뭉개진다.
const TILE_SIZE := 48

enum { SEA = 0, LAND = 1 }

## 오브젝트 종류 번호는 `world_objects.gd` 가 원본이다 — 그리는 쪽과 같은 표를 봐야
## "1번이 나무"라는 약속이 한 곳에만 있다.
const WorldObjects := preload("res://scripts/world_objects.gd")

# --- 생성 파라미터 (여기 숫자를 바꾸면 같은 시드라도 다른 월드가 나온다) ---------

const NOISE_FREQUENCY := 0.024
const NOISE_OCTAVES := 5
## 노이즈를 0~1 높이로 옮길 때의 대비. 1보다 크면 위아래가 잘려서 **속이 꽉 찬 땅과
## 트인 바다**가 넓게 생기고, 그 사이의 해안선만 들쭉날쭉해진다. 작을수록 밋밋해진다.
const NOISE_CONTRAST := 1.3
## 섬 마스크가 0 이 되는 반지름(지도 반폭 기준). **이 값 바깥에는 어떤 노이즈로도 땅이
## 생길 수 없다** — 앞바다 여백이 여기서 나온다. 1.0 을 넘는 것은 지도가 정사각형이라
## 모서리 쪽 거리가 1.41 까지 가기 때문이다.
const ISLAND_RADIUS := 1.02
## 땅이 되는 문턱. 높을수록 섬이 작아진다.
const LAND_THRESHOLD := 0.10
## 지도 테두리 몇 칸은 무조건 바다로 둔다 — 월드 밖으로 걸어나갈 수 없게.
const EDGE_SEA_TILES := 4

# --- 월드 오브젝트 (2026-09-08, INBOX #63) -----------------------------------
#
# **나무를 고르게 뿌리지 않는다.** 칸마다 같은 확률로 굴리면 숲도 빈터도 없는
# 「고르게 흩어진 점」이 되어, 화면이 어디를 봐도 똑같아진다 — 무늬를 칸 전체에
# 고르게 뿌렸을 때와 같은 실패다(docs/STYLE_GUIDE.md 6번). 낮은 주파수 노이즈로
# **숲 구역**을 먼저 정하고 그 안에서만 굴린다.
const GROVE_FREQUENCY := 0.045
## 숲 노이즈가 이 위인 칸에만 나무가 난다. 높일수록 숲이 작고 드문드문해진다.
const GROVE_THRESHOLD := -0.05
## 숲 구역 안에서 한 칸에 나무가 설 확률.
const TREE_CHANCE := 0.34
## 나무가 안 선 칸에서 굴리는 확률. 바위·덤불은 숲과 무관하게 온 섬에 흩어진다.
const ROCK_CHANCE := 0.020
const BUSH_CHANCE := 0.055

## 스폰 칸에서 이 거리(체비셰프, 타일) 안에는 아무것도 두지 않는다.
## 캐릭터가 나무 속에서 시작하면 처음 보는 화면이 잎사귀뿐이다.
const OBJECT_SPAWN_CLEAR := 4

## 해시에 섞는 소금 — 같은 칸에서 종류마다 다른 값을 뽑으려고 갈라둔다.
const SALT_TREE := 0x5bd1
const SALT_ROCK := 0x2f9d
const SALT_BUSH := 0x71c3
const SALT_VARIANT := 0x1a37
## 숲 노이즈의 시드를 월드 시드에서 갈라놓는다 — 지형 노이즈와 같은 시드를 쓰면
## 숲 경계가 해안선을 그대로 따라간다.
const GROVE_SEED_SALT := 0x3f6b

var world_seed: int = 0
var tiles := PackedByteArray()
var spawn_tile := Vector2i.ZERO
## 타일마다 오브젝트 한 개(0 = 없음). **종류와 좌표를 월드 상태로 들고 있는 자리**다
## (INBOX #63 — 나중에 벌목·채광이 붙을 때 여기를 지우면 된다).
var objects := PackedByteArray()


## 월드를 만든다. 쓰는 쪽은 `WorldGen.new().build(시드)` 한 줄이면 된다.
func build(seed_value: int) -> void:
	world_seed = seed_value
	tiles = _make_terrain(seed_value)
	_keep_only_main_island()
	_fill_enclosed_water()
	spawn_tile = _find_spawn()
	# **오브젝트는 맨 마지막이다** — 스폰 칸을 알아야 그 둘레를 비울 수 있고,
	# 섬을 다듬기 전 지형에 심으면 지워진 조각섬 위에 나무가 남는다.
	_place_objects()


# --- 지형 --------------------------------------------------------------------

func _make_terrain(seed_value: int) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed_value
	noise.frequency = NOISE_FREQUENCY
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = NOISE_OCTAVES

	var out := PackedByteArray()
	out.resize(MAP_TILES * MAP_TILES)
	var center := (MAP_TILES - 1) * 0.5
	var radius := center
	for y in MAP_TILES:
		for x in MAP_TILES:
			var i := y * MAP_TILES + x
			if x < EDGE_SEA_TILES or y < EDGE_SEA_TILES \
					or x >= MAP_TILES - EDGE_SEA_TILES or y >= MAP_TILES - EDGE_SEA_TILES:
				out[i] = SEA
				continue
			var dist := Vector2(x - center, y - center).length() / radius
			# 노이즈 높이에 **가장자리로 갈수록 0 이 되는 마스크를 곱한다**(빼지 않는다).
			# 곱하면 마스크가 0 인 바깥쪽은 노이즈가 아무리 높아도 바다라 앞바다 여백이
			# 보장되고, 마스크가 서서히 줄어드는 구간에서는 땅이 될 확률만 낮아져서
			# 해안선이 원호가 아니라 노이즈 모양 그대로 들쭉날쭉하게 끝난다.
			var mask := clampf(1.0 - dist / ISLAND_RADIUS, 0.0, 1.0)
			var height := clampf(0.5 + noise.get_noise_2d(float(x), float(y)) * NOISE_CONTRAST, 0.0, 1.0)
			out[i] = LAND if height * mask > LAND_THRESHOLD else SEA
	return out


# --- 하나의 섬으로 다듬기 -----------------------------------------------------
#
# 노이즈는 본섬 말고도 앞바다에 조각섬을, 섬 안쪽에는 웅덩이를 얼마든지 만든다.
# 마스크만으로는 그게 안 없어져서 지도가 "풀밭에 구멍이 뚫린 모양"이 된다
# (docs/DESIGN.md "월드 생성"). **두 번 훑어서 섬 하나 + 그 바깥 바다 하나로 만든다.**
# 둘 다 시드에서 나온 지형만 보고 도므로 재현성은 그대로다.

## 가장 큰 육지 덩어리만 남기고 나머지 조각섬은 바다로 지운다.
## 그래야 **걸어서 갈 수 없는 땅**이 아예 생기지 않는다.
func _keep_only_main_island() -> void:
	var main := _largest_land_component()
	var keep := PackedByteArray()
	keep.resize(tiles.size())
	for index in main:
		keep[index] = 1
	for i in tiles.size():
		if tiles[i] == LAND and keep[i] == 0:
			tiles[i] = SEA


## 지도 테두리에서 물길로 닿지 못하는 물(= 갇힌 웅덩이)을 땅으로 메운다.
## 남는 물은 전부 **섬을 두른 바깥 바다 하나**가 된다.
func _fill_enclosed_water() -> void:
	var wet := PackedByteArray()
	wet.resize(tiles.size())
	var stack := PackedInt32Array()
	var last := MAP_TILES - 1
	for i in MAP_TILES:
		for index in [i, last * MAP_TILES + i, i * MAP_TILES, i * MAP_TILES + last]:
			if tiles[index] == SEA and wet[index] == 0:
				wet[index] = 1
				stack.append(index)
	while not stack.is_empty():
		var index := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var x := index % MAP_TILES
		var y := index / MAP_TILES
		for step in NEIGHBORS:
			var nx: int = x + step.x
			var ny: int = y + step.y
			if nx < 0 or ny < 0 or nx >= MAP_TILES or ny >= MAP_TILES:
				continue
			var ni: int = ny * MAP_TILES + nx
			if wet[ni] == 0 and tiles[ni] == SEA:
				wet[ni] = 1
				stack.append(ni)
	for i in tiles.size():
		if tiles[i] == SEA and wet[i] == 0:
			tiles[i] = LAND


# --- 월드 오브젝트 ------------------------------------------------------------
#
# **전역 난수를 쓰지 않는다** — 칸 좌표와 월드 시드만으로 값을 뽑으므로, 같은
# 시드면 몇 번을 다시 만들어도 같은 자리에 같은 것이 난다(docs/DESIGN.md
# "같은 시드는 항상 같은 월드를 만들어야 한다"). 실행 사이의 재현성은
# `fingerprint()` 가 오브젝트까지 같이 해싱해서 자체 QA 가 확인한다.

func _place_objects() -> void:
	objects = PackedByteArray()
	objects.resize(MAP_TILES * MAP_TILES)
	var grove := FastNoiseLite.new()
	grove.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grove.seed = world_seed ^ GROVE_SEED_SALT
	grove.frequency = GROVE_FREQUENCY
	for y in MAP_TILES:
		for x in MAP_TILES:
			# **싼 판정부터 순서대로 거른다.** 65,536칸을 도는 반복문이라, 이웃
			# 8칸을 보는 `_is_open()` 을 먼저 부르면 월드 하나 만드는 시간이 두 배가
			# 된다(자체 QA 의 500ms 상한에 닿는다). 바다 칸에서 바로 빠져나가면
			# 그 호출이 절반 이하로 준다.
			if tiles[y * MAP_TILES + x] != LAND:
				continue
			if not _can_hold_object(x, y):
				continue
			var kind := WorldObjects.NONE
			if grove.get_noise_2d(float(x), float(y)) > GROVE_THRESHOLD \
					and _tile_random(x, y, SALT_TREE) < TREE_CHANCE:
				kind = WorldObjects.TREE
			elif _tile_random(x, y, SALT_ROCK) < ROCK_CHANCE:
				kind = WorldObjects.ROCK
			elif _tile_random(x, y, SALT_BUSH) < BUSH_CHANCE:
				kind = WorldObjects.BUSH
			objects[y * MAP_TILES + x] = kind


## 이 칸에 오브젝트를 둘 수 있는가.
## **물가를 비우는 방법이 "이웃 8칸이 전부 땅"이다** — 해안 타일은 그림의 땅이
## 논리 타일보다 작아서(`gen_terrain.py` 의 해안선), 거기 나무를 세우면 밑동이
## 물 위에 뜬다.
func _can_hold_object(x: int, y: int) -> bool:
	if maxi(absi(x - spawn_tile.x), absi(y - spawn_tile.y)) <= OBJECT_SPAWN_CLEAR:
		return false
	if x < 1 or y < 1 or x >= MAP_TILES - 1 or y >= MAP_TILES - 1:
		return false
	# `_is_open()` 과 같은 판정이지만 **인덱스로 직접 읽는다** — 65,536칸을 도는
	# 자리라 함수 호출 아홉 번이 그대로 월드 생성 시간이 된다.
	for row in 3:
		var i := (y - 1 + row) * MAP_TILES + x
		if tiles[i - 1] != LAND or tiles[i] != LAND or tiles[i + 1] != LAND:
			return false
	return true


func object_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= MAP_TILES or y >= MAP_TILES:
		return WorldObjects.NONE
	return objects[y * MAP_TILES + x]


## 이 칸의 오브젝트가 어느 변주인가. **좌표 해시로 고른다** — `x % 3` 류로 고르면
## 같은 나무가 일정 간격으로 되풀이돼서 숲이 벽지가 된다(지형 무늬와 같은 이유).
func object_variant_at(x: int, y: int) -> int:
	return _hash_tile(x, y, SALT_VARIANT) % WorldObjects.VARIANTS


## 좌표 + 시드 → 0 이상의 정수. 곱셈이 넘쳐도 그대로 감기므로(64비트) 결과는
## 실행마다 같다. Godot 의 `hash()` 를 쓰지 않는 이유: 버전이 바뀌면 값이 달라질 수
## 있는데, 월드는 **세이브를 넘어** 같아야 한다.
func _hash_tile(x: int, y: int, salt: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ ((world_seed ^ salt) * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


func _tile_random(x: int, y: int, salt: int) -> float:
	return float(_hash_tile(x, y, salt)) / 2147483647.0


func object_count() -> int:
	var n := 0
	for v in objects:
		if v != WorldObjects.NONE:
			n += 1
	return n


func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= MAP_TILES or y >= MAP_TILES:
		return SEA
	return tiles[y * MAP_TILES + x]


func is_land(x: int, y: int) -> bool:
	return at(x, y) == LAND


func land_ratio() -> float:
	var land := 0
	for v in tiles:
		if v == LAND:
			land += 1
	return float(land) / float(tiles.size())


func sea_ratio() -> float:
	return 1.0 - land_ratio()


# --- 스폰 지점 ---------------------------------------------------------------

## 스폰은 **가장 큰 육지 덩어리** 안에서 지도 중심에 가장 가까운 칸이다.
## 근거: 노이즈는 1~2칸짜리 외딴 섬을 얼마든지 만든다 — 단순히 "중심에서 가장 가까운
## 땅"으로 고르면 사방이 바다인 점 하나에 갇힌 채로 시작할 수 있다.
## 주변 8칸이 전부 땅인 칸을 우선하고, 그런 칸이 없을 때만 아무 칸이나 쓴다.
func _find_spawn() -> Vector2i:
	var component := _largest_land_component()
	if component.is_empty():
		return Vector2i(MAP_TILES / 2, MAP_TILES / 2)  # 땅이 하나도 없는 월드 — 있을 수 없지만 안전장치.

	var center := Vector2((MAP_TILES - 1) * 0.5, (MAP_TILES - 1) * 0.5)
	var best := Vector2i(-1, -1)
	var best_score := INF
	var best_open := false
	for index in component:
		var tile := Vector2i(index % MAP_TILES, index / MAP_TILES)
		var open := _is_open(tile.x, tile.y)
		var score: float = Vector2(tile).distance_squared_to(center)
		# 8칸이 다 땅인 칸이 항상 우선. 같은 조건이면 중심에 가까운 쪽.
		if best.x < 0 or (open and not best_open) or (open == best_open and score < best_score):
			best = tile
			best_score = score
			best_open = open
	return best


func _is_open(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not is_land(x + dx, y + dy):
				return false
	return true


const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## 4방향으로 이어진 육지 덩어리 중 가장 큰 것의 타일 인덱스 목록.
func _largest_land_component() -> PackedInt32Array:
	var seen := PackedByteArray()
	seen.resize(tiles.size())
	var best := PackedInt32Array()
	for start in tiles.size():
		if seen[start] == 1 or tiles[start] != LAND:
			continue
		var component := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		while not stack.is_empty():
			var index := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			component.append(index)
			var x := index % MAP_TILES
			var y := index / MAP_TILES
			for step in NEIGHBORS:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx < 0 or ny < 0 or nx >= MAP_TILES or ny >= MAP_TILES:
					continue
				var ni: int = ny * MAP_TILES + nx
				if seen[ni] == 0 and tiles[ni] == LAND:
					seen[ni] = 1
					stack.append(ni)
		if component.size() > best.size():
			best = component
	return best


# --- 좌표 변환 ---------------------------------------------------------------

## 타일 칸의 한가운데 월드 좌표.
static func tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE


static func world_to_tile(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))


static func world_size() -> Vector2:
	return Vector2(MAP_TILES, MAP_TILES) * TILE_SIZE


## 같은 시드로 만든 월드가 정말 같은지 확인할 때 쓰는 지문
## (자체 QA 가 실행 사이에 비교한다).
func fingerprint() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(tiles)
	# **오브젝트도 지문에 넣는다** — 지형만 해싱하면 나무 자리가 실행마다 달라져도
	# 재현성 검사가 초록불이다(2026-09-08, INBOX #63).
	context.update(objects)
	return context.finish().hex_encode()
