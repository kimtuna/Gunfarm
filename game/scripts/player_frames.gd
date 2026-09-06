extends RefCounted

## 플레이어 스프라이트 시트 → `SpriteFrames` (docs/DESIGN.md 「캐릭터 애니메이션」).
##
## **시트의 배치 규칙을 아는 유일한 곳**이다 — 행 = 방향(down/left/right/up),
## 열 = 프레임, 칸 34px. 걷기(INBOX #13)처럼 프레임이 늘어나는 시트가 생기면
## 여기만 고치면 되고 플레이어 노드는 손대지 않는다.

const SHEET_IDLE := "res://assets/sprites/player_idle.png"

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


## 이 시트로 만든 `SpriteFrames`. 애니메이션 이름은 `idle_down` 처럼 `<모션>_<방향>` 이다.
static func build() -> SpriteFrames:
	var texture: Texture2D = load(SHEET_IDLE)
	if texture == null:
		push_error("플레이어 시트를 못 읽었다: %s — `--import` 를 안 돌렸을 수 있다" % SHEET_IDLE)
		return null
	return _slice(texture, "idle", IDLE_FPS)


## 스프라이트를 발밑 기준으로 올리기 위한 `AnimatedSprite2D.offset` (아트 픽셀 단위).
static func feet_offset() -> Vector2:
	return Vector2(0.0, -(float(FEET_Y) - CELL * 0.5))


static func _slice(texture: Texture2D, motion: String, fps: float) -> SpriteFrames:
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
