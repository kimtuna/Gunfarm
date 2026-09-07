extends RefCounted

## 지형 타일 시트(`assets/sprites/terrain_tiles.png`)의 **배치 규칙을 아는 유일한
## 곳**이다 (INBOX #12). 그림을 만드는 쪽은 `game/tools/gen_terrain.py` 이고,
## 아래 상수·함수는 그 파일의 같은 이름과 **글자 그대로 같아야 한다** —
## 어긋나면 엉뚱한 칸이 그려진다. `qa_terrain_view.gd` 가 그걸 검사한다.
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) —
## 화면 없이 헤드리스로도 규칙을 검증할 수 있어야 하기 때문이다.
##
## 시트 한 칸의 번호:
##
##     변주(0~7) × 512 + (중심이 땅이면 256) + 이웃 8칸의 땅 비트마스크
##
## 그래서 **칸 하나를 한 번 그리면 밑그림과 해안이 같이 온다** — 반투명 오버레이를
## 겹치지 않는다(생성기 맨 위 주석 참고).

const TerrainPalettes := preload("res://scripts/terrain_palettes.gd")

const SHEET_PATH := "res://assets/sprites/terrain_tiles.png"

## 아트 한 칸(px). × 씬 스케일 1 = 화면 48px = `WorldGen.TILE_SIZE`
## (docs/STYLE_GUIDE.md 1번: 배율은 정수여야 도트가 안 뭉개진다).
##
## 이력: 16(배율 3) → 24(배율 2) → **48(배율 1), 2026-09-08 저녁.**
## **도트 하나의 화면 크기가 캐릭터와 같아야 한다.** 캐릭터를 ComfyUI 그림에서
## 만들기로 하면서 캐릭터 칸이 96px 이 됐고(48px 로 줄이면 눈이 1px 이 되어 얼굴이
## 죽는다 — 실측), 96px 칸의 씬 배율은 1 이다(`player_frames.scale_of`). 그래서
## 타일도 배율 1 로 맞춘다. **화면에서 보이는 크기는 하나도 안 바뀐다** —
## 타일 48px, 캐릭터 96px(타일 두 칸) 그대로고, 그 안의 도트 수만 늘었다.
const TILE_ART := 48
const SCALE := 1

## 같은 지형의 무늬 변주 수. 좌표 해시로 고른다 — `x % 3` 같은 규칙으로 고르면
## 무늬가 일정 간격으로 되풀이돼서 벽지처럼 보인다(생성기 주석 참고).
const VARIANTS := 8
const SHEET_COLS := 64

## 이웃 8칸의 비트 순서 — `gen_terrain.py` 의 `NEIGHBORS` 와 같아야 한다.
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## 시트를 못 읽었을 때의 대체 칠, 그리고 지형 위에 무언가를 얹어보는 자체 QA 의
## 배경색. **색을 손으로 적지 않는다** — 생성기가 내려보낸 램프에서 꺼낸다.
static func color_grass() -> Color:
	return TerrainPalettes.color_of("grass", 1)


static func color_sea() -> Color:
	return TerrainPalettes.color_of("deep", 1)


## 타일 좌표 → 무늬 변주. `gen_terrain.py` 의 `variant_at()` 과 같은 식이다.
## 음수 좌표(지도 밖)도 들어오므로 `posmod` 로 받는다 — `%` 는 음수를 그대로 돌려준다.
static func variant_at(x: int, y: int) -> int:
	return posmod((x * 73856093) ^ (y * 19349663), VARIANTS)


## 이웃 8칸 중 땅인 칸의 비트마스크. 지도 밖은 `WorldGen.at()` 이 바다로 답한다.
static func mask_at(world: RefCounted, x: int, y: int) -> int:
	var mask := 0
	for bit in NEIGHBORS.size():
		var step: Vector2i = NEIGHBORS[bit]
		if world.is_land(x + step.x, y + step.y):
			mask |= 1 << bit
	return mask


static func tile_index(variant: int, center_land: bool, mask: int) -> int:
	return variant * 512 + (256 if center_land else 0) + mask


## 시트 안에서 그 칸이 놓인 사각형(아트 픽셀).
static func region_of(index: int) -> Rect2:
	return Rect2((index % SHEET_COLS) * TILE_ART, (index / SHEET_COLS) * TILE_ART,
			TILE_ART, TILE_ART)


## 월드의 한 칸을 그리는 데 필요한 시트 사각형. 쓰는 쪽은 이 한 줄이면 된다.
static func region_at(world: RefCounted, x: int, y: int) -> Rect2:
	return region_of(tile_index(variant_at(x, y), world.is_land(x, y), mask_at(world, x, y)))
