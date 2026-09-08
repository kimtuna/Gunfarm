extends RefCounted

## 월드 오브젝트의 **종류 표** — 나무 · 바위 · 덤불 (docs/DESIGN.md 「월드 오브젝트」, INBOX #63).
##
## 무엇이 어디에 나는지는 `world_gen.gd` 가 정하고, 그리는 것은
## `world_objects_view.gd` 다. **이 파일은 그 둘이 공유하는 규칙만** 들고 있다 —
## 종류 번호 · 시트 이름 · 칸 크기 · 변주 수. 지형이 `terrain_tiles.gd` 한 곳에
## 칸 번호 규칙을 모아 둔 것과 같은 자리다.
##
## **여기 숫자는 그림 생성기(`game/tools/gen_objects.py`)와 반드시 같아야 한다** —
## `KINDS` 의 이름이 곧 PNG 이름이고, `CELL` 이 곧 시트를 자르는 칸이다.
## 자체 QA(`qa_world_gen.gd`)가 실제 PNG 크기와 이 표를 견준다.

## 종류 번호. **`world_gen.gd` 의 타일당 1바이트에 그대로 들어간다** — 0 은 "없음"이다.
const NONE := 0
const TREE := 1
const ROCK := 2
const BUSH := 3

const ALL: Array[int] = [TREE, ROCK, BUSH]

## 종류 → 시트 이름. `gen_objects.py` 의 `KINDS` 와 같아야 한다.
const KINDS := {TREE: "tree", ROCK: "rock", BUSH: "bush"}

## 종류 → 그림 한 칸(px). **배율이 1이라 이 값이 곧 화면 크기다.**
## 타일 한 칸이 48px 이므로 나무는 **가로 두 칸 × 세로 세 칸**, 바위·덤불은 한 칸이다
## (docs/DESIGN.md 「아이템/오브젝트 크기 표준」).
const CELL := {
	TREE: Vector2i(96, 144),
	ROCK: Vector2i(48, 48),
	BUSH: Vector2i(48, 48),
}

## 종류마다 변주 몇 벌인가. 어느 변주가 나올지는 좌표 해시가 정한다
## (지형 무늬 변주와 같은 방식 — `x % 3` 류로 고르면 일정 간격으로 되풀이된다).
const VARIANTS := 3

## 이 종류가 **걸을 수 없게 막는가**. 「플레이어 이동」의 `blocked_at()` 이 본다.
## **막는 것은 그림 전체가 아니라 그 오브젝트가 선 칸 하나다** — 나무 그림은 두 칸 ×
## 세 칸이지만 밑동이 차지하는 것은 한 칸이고, 잎까지 막으면 숲을 통째로 못 지나간다
## (docs/DESIGN.md 「월드 오브젝트」의 「막는 크기」).
const BLOCKS_WALK := {TREE: true, ROCK: true, BUSH: false}

## 이 종류가 **총알을 막는가**. `bullets.gd` 의 `blocks_bullet` 이 본다.
##
## **걷기와 다른 물음이다**(docs/DESIGN.md 「전투」의 *"총알을 막는 것과 걸을 수 없는
## 곳은 다르다"*) — 물은 걷지 못하지만 총알은 통과한다. 여기서 갈리는 것은 **덤불**이다:
## 「전투」가 총알을 막는 것으로 꼽은 *"키가 있는 것(벽·문·나무·바위)"* 에 덤불은 없다.
const BLOCKS_BULLET := {TREE: true, ROCK: true, BUSH: false}


static func sheet_path(kind: int) -> String:
	return "res://assets/sprites/object_%s.png" % KINDS[kind]


## 시트에서 그 변주가 있는 사각형. 행은 하나이고 열이 변주다.
static func region(kind: int, variant: int) -> Rect2:
	var cell: Vector2i = CELL[kind]
	return Rect2(Vector2(cell.x * (variant % VARIANTS), 0), Vector2(cell))


## 그림을 원점(밑동)에 대해 어디에 놓을 것인가 — **가로는 가운데, 세로는 위로**.
## 노드의 원점이 오브젝트가 선 자리라(플레이어 노드의 발밑과 같다) Y정렬이 저절로 맞는다.
static func draw_offset(kind: int) -> Vector2:
	var cell: Vector2i = CELL[kind]
	return Vector2(-cell.x * 0.5, -cell.y)


## `NONE`(0)을 넣어도 안전하다 — 표에 없으면 안 막는 것이다.
static func blocks_walk(kind: int) -> bool:
	return bool(BLOCKS_WALK.get(kind, false))


static func blocks_bullet(kind: int) -> bool:
	return bool(BLOCKS_BULLET.get(kind, false))
