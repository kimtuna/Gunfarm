extends RefCounted

## 플레이어 스프라이트 시트 → `SpriteFrames` (docs/DESIGN.md 「캐릭터 애니메이션」).
##
## **시트의 배치 규칙을 아는 유일한 곳**이다 — 행 = 방향(down/left/right/up),
## 열 = 프레임, 칸 34px. 걷기(INBOX #13)처럼 프레임이 늘어나는 시트가 생기면
## 여기만 고치면 되고 플레이어 노드는 손대지 않는다.

## 시트는 **머리모양마다 한 장**이다 — 색은 팔레트 교체로 만들 수 있지만
## (`character_sprite.gd`) 머리모양은 형태가 달라서 다시 그려야 하기 때문이다
## (DESIGN.md 「캐릭터 커스터마이징 항목」의 "머리모양은 모양마다 …따로 필요하다").
const SHEET_DIR := "res://assets/sprites"

## 기본 머리모양 — `character_appearance.gd` 의 첫 번째 선택지와 같아야 한다.
const DEFAULT_HAIRSTYLE := "short"

## 아트 한 칸(px). 아트 34px × 씬 스케일 3 = 화면 102px
## (docs/DESIGN.md 「아이템/오브젝트 크기 표준」).
const CELL := 34
const SCALE := 3

## 칸 안에서 발이 닿는 y(아트 픽셀, 아래 경계). 이 줄이 노드 원점에 오게 스프라이트를
## 올린다 — **원점 = 발밑**이라야 타일 점유와 앞뒤(Y) 정렬이 자연스럽다.
const FEET_Y := 33

## 시트의 행 순서. `player_motion.gd` 의 방향 enum 과 같은 순서여야 한다.
const DIR_NAMES := ["down", "left", "right", "up"]

## idle 은 지금 1프레임뿐이라 속도는 의미가 없다 — 프레임이 늘어날 때를 위한 값.
const IDLE_FPS := 4.0


## `<모션>` × `<머리모양>` 한 벌이 놓인 자리. 생성기(`gen_character.py` 의
## `idle_path()`)와 같은 규칙이다 — 한쪽만 고치면 파일을 못 찾는다.
static func sheet_path(motion: String, hairstyle: String) -> String:
	return "%s/player_%s_%s.png" % [SHEET_DIR, motion, hairstyle]


## 이 시트로 만든 `SpriteFrames`. 애니메이션 이름은 `idle_down` 처럼 `<모션>_<방향>` 이다.
static func build(hairstyle: String = DEFAULT_HAIRSTYLE) -> SpriteFrames:
	var path := sheet_path("idle", hairstyle)
	var texture: Texture2D = load(path)
	if texture == null:
		push_error("플레이어 시트를 못 읽었다: %s — `--import` 를 안 돌렸을 수 있다" % path)
		return null
	return slice_sheet(texture, "idle", IDLE_FPS)


## 스프라이트를 발밑 기준으로 올리기 위한 `AnimatedSprite2D.offset` (아트 픽셀 단위).
static func feet_offset() -> Vector2:
	return Vector2(0.0, -(float(FEET_Y) - CELL * 0.5))


## 시트 한 장(행 = 방향, 열 = 프레임)을 `<모션>_<방향>` 애니메이션으로 자른다.
## **색을 갈아끼운 텍스처를 그대로 넘겨도 된다** — 팔레트 교체는 알파를 건드리지
## 않으므로 칸 배치가 그대로다 (`character_sprite.gd` 의 `idle_frames()`).
static func slice_sheet(texture: Texture2D, motion: String, fps: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var columns := maxi(1, texture.get_width() / CELL)
	for row in DIR_NAMES.size():
		var anim := "%s_%s" % [motion, DIR_NAMES[row]]
		frames.add_animation(anim)
		frames.set_animation_loop(anim, true)
		frames.set_animation_speed(anim, fps)
		for column in columns:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(column * CELL, row * CELL, CELL, CELL)
			frames.add_frame(anim, atlas)
	return frames
