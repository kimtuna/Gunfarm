extends RefCounted

## 시드 기반 절차적 월드 생성 1단계 — 땅/바다 지형과 스폰 지점만
## (docs/DESIGN.md "월드 생성"). 나무/채광 포인트/낚시 스팟 같은 자원 배치는
## 그 자원을 실제로 만드는 바퀴가 여기에 덧붙인다.
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md "시뮬레이션 구조") —
## 서버가 화면 없이 같은 시드로 같은 월드를 재현할 수 있어야 하기 때문이다.
## **같은 시드는 항상 같은 월드**여야 하므로 이 파일 안에서는 `randi()` 류의
## 전역 난수를 절대 쓰지 않는다(전부 시드에서 결정된다).

## 지도 한 변의 타일 수. 12288×12288 월드 단위 = 논리 해상도(1280×720) 기준으로
## 가로 약 9.6 화면 분량이다.
const MAP_TILES := 256

## 타일 한 칸의 월드 단위. 아트 16px × 씬 스케일 3 = 48 — 캐릭터(캔버스 34px ×
## 3 = 102px)와 같은 도트 크기 단위를 쓰려고 이 값으로 잡았다
## (docs/DESIGN.md "아이템/오브젝트 크기 표준"). **배율은 정수여야 한다** —
## 소수 배율은 화면에서 아트 픽셀이 들쭉날쭉해져 도트가 뭉개진다.
const TILE_SIZE := 48

enum { SEA = 0, LAND = 1 }

# --- 생성 파라미터 (여기 숫자를 바꾸면 같은 시드라도 다른 월드가 나온다) ---------

const NOISE_FREQUENCY := 0.022
const NOISE_OCTAVES := 5
## 노이즈를 얼마나 늘려 쓰는가. 이게 작으면 섬 감쇠가 지형을 지배해서 해안선이 그냥
## 동그란 원이 되어버린다 — 만/반도/앞바다 섬은 전부 이 값에서 나온다.
const NOISE_GAIN := 2.5
## 높을수록 땅이 는다.
const LAND_BIAS := 0.70
## 섬 감쇠 `거리^power`. 낮으면 중심부터 깎여서 섬이 작아지고, 높으면 가장자리만 깎인다.
const FALLOFF_POWER := 3.0
## 지도 테두리 몇 칸은 무조건 바다로 둔다 — 월드 밖으로 걸어나갈 수 없게.
const EDGE_SEA_TILES := 4

var world_seed: int = 0
var tiles := PackedByteArray()
var spawn_tile := Vector2i.ZERO


## 월드를 만든다. 쓰는 쪽은 `WorldGen.new().build(시드)` 한 줄이면 된다.
func build(seed_value: int) -> void:
	world_seed = seed_value
	tiles = _make_terrain(seed_value)
	spawn_tile = _find_spawn()


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
			# 노이즈 높이에서 중심으로부터의 거리 감쇠를 뺀다 — 가운데는 그대로 남고
			# 가장자리로 갈수록 깎여서 "섬 하나 + 앞바다 작은 섬 몇 개" 모양이 된다.
			var height := noise.get_noise_2d(float(x), float(y)) * NOISE_GAIN + LAND_BIAS
			out[i] = LAND if height - pow(dist, FALLOFF_POWER) > 0.0 else SEA
	return out


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
	return context.finish().hex_encode()
