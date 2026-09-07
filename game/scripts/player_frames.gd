extends RefCounted

## 플레이어 스프라이트 시트 → `SpriteFrames` (docs/DESIGN.md 「캐릭터 애니메이션」).
##
## **시트의 배치 규칙을 아는 유일한 곳**이다 — 행 = 방향(down/left/right/up),
## 열 = 프레임, 칸 17px. 걷기(INBOX #15)처럼 프레임이 늘어나는 시트가 생겨도
## 여기만 고치면 되고 플레이어 노드는 손대지 않는다.

## 시트는 **머리모양마다 한 장**이다 — 색은 팔레트 교체로 만들 수 있지만
## (`character_sprite.gd`) 머리모양은 형태가 달라서 다시 그려야 하기 때문이다
## (DESIGN.md 「캐릭터 커스터마이징 항목」의 "머리모양은 모양마다 …따로 필요하다").
const SHEET_DIR := "res://assets/sprites"

## 기본 머리모양 — `character_appearance.gd` 의 첫 번째 선택지와 같아야 한다.
const DEFAULT_HAIRSTYLE := "short"

## 아트 한 칸(px). 아트 17px × 씬 스케일 3 = 화면 51px
## (docs/DESIGN.md 「아이템/오브젝트 크기 표준」).
## **2026-09-07 (INBOX #19) 에 칸이 34 → 17 로 절반이 됐다. 스케일은 그대로 3이다** —
## 스케일을 낮추면 캐릭터의 아트 픽셀만 타일(아트 16px × 3배)의 절반이 되어 도트
## 크기 단위가 어긋난다.
const CELL := 17
const SCALE := 3

## 칸 안에서 발이 닿는 y(아트 픽셀, 아래 경계). 이 줄이 노드 원점에 오게 스프라이트를
## 올린다 — **원점 = 발밑**이라야 타일 점유와 앞뒤(Y) 정렬이 자연스럽다.
## 그림은 y 15 줄까지 찬다(외곽선 포함) — 그 아래 한 줄은 비어 있다.
const FEET_Y := 16

## 시트의 행 순서. `player_motion.gd` 의 방향 enum 과 같은 순서여야 한다.
const DIR_NAMES := ["down", "left", "right", "up"]

## idle 은 지금 1프레임뿐이라 속도는 의미가 없다 — 프레임이 늘어날 때를 위한 값.
const IDLE_FPS := 4.0

## 걷기(INBOX #15). 한 바퀴 6프레임이라 14fps 면 0.43초에 두 걸음 =
## 초당 약 4.7걸음이고, 이동 속도(240 = 타일 5칸/초, `player_motion.gd`)에서
## **한 걸음이 타일 1칸쯤**이다. 더 느리면 발이 땅에서 미끄러지는 것처럼 보인다.
##
## **2026-09-07 (INBOX #20) 에 10 → 14 로 올렸다.** 캔버스가 34 → 17px 로 절반이
## 되면서 그릴 수 있는 보폭도 절반이 됐는데(다리가 세 줄뿐이다) 이동 속도는 그대로라,
## 10fps 로는 한 걸음이 캐릭터 키의 1.4배(타일 1.5칸)가 되어 걷는 게 아니라 미끄러져
## 보인다. 걸음 빈도는 다리 길이의 제곱근에 반비례하므로(절반이면 √2 배) 10 × 1.41 ≈ 14
## 이고, 그러면 한 걸음이 캐릭터 키만큼(타일 1칸)으로 줄어든다.
const WALK_FPS := 14.0

## 도구를 쥔 채 쓰는 모션(패기 등)의 재생 속도. 한 바퀴 6프레임이라 12fps 면
## 0.5초에 한 번 내려친다 — 걷기(14)보다 느린 것은 도끼질이 걸음보다 무겁기
## 때문이고, 더 빠르면 도끼가 순간이동하는 것처럼 보인다.
const USE_FPS := 12.0

## 도구 하나가 붙이는 모션 3종 — 들고 있기 / 사용 / 든 채 걷기
## (`docs/DESIGN.md` 「새 도구를 추가하는 절차」 1). **도구가 늘면 아래 `TOOLS` 에
## 이름 한 줄만 늘린다** — 시트가 같이 실리고 색 바꿔치기도 따라온다.
## 생성기(`gen_character.py` 의 `TOOLS`)와 같은 목록이어야 한다.
const TOOLS := ["axe", "pickaxe"]


## 한 캐릭터가 가진 모션과 그 재생 속도. **여기 한 줄을 늘리면** 시트가 자동으로
## 같이 실려서 `<모션>_<방향>` 애니메이션이 생긴다(도구별 모션이 그렇게 붙는다).
static func motions() -> Dictionary:
	var out := {"idle": IDLE_FPS, "walk": WALK_FPS}
	for tool in TOOLS:
		out["hold_%s" % tool] = IDLE_FPS
		out["use_%s" % tool] = USE_FPS
		out["walk_%s" % tool] = WALK_FPS
	return out


## `<모션>` × `<머리모양>` 한 벌이 놓인 자리. 생성기(`gen_character.py` 의
## `motion_path()`)와 같은 규칙이다 — 한쪽만 고치면 파일을 못 찾는다.
static func sheet_path(motion: String, hairstyle: String) -> String:
	return "%s/player_%s_%s.png" % [SHEET_DIR, motion, hairstyle]


## 이 머리모양의 모든 모션을 담은 `SpriteFrames`. 애니메이션 이름은 `idle_down`,
## `walk_left` 처럼 `<모션>_<방향>` 이다.
static func build(hairstyle: String = DEFAULT_HAIRSTYLE) -> SpriteFrames:
	var frames := new_frames()
	var all := motions()
	for motion in all:
		var path := sheet_path(motion, hairstyle)
		var texture: Texture2D = load(path)
		if texture == null:
			push_error("플레이어 시트를 못 읽었다: %s — `--import` 를 안 돌렸을 수 있다" % path)
			return null
		add_motion(frames, texture, motion, all[motion])
	return frames


## 스프라이트를 발밑 기준으로 올리기 위한 `AnimatedSprite2D.offset` (아트 픽셀 단위).
static func feet_offset() -> Vector2:
	return Vector2(0.0, -(float(FEET_Y) - CELL * 0.5))


## 아무 애니메이션도 없는 빈 `SpriteFrames`. Godot 이 기본으로 넣어주는
## `default` 는 지운다 — 남겨두면 이름 없는 애니메이션이 하나 섞여 돈다.
static func new_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	return frames


## 사용 모션(`use_<도구>`)인가. **이 모션만 돌지 않는다** — 좌클릭 한 번에 한 번
## 내려치고 끝나야 하기 때문이다(docs/DESIGN.md 「캐릭터 애니메이션」의 "한 번
## 재생된 뒤 다시 hold 로 돌아온다"). 돌게 두면 다시 `hold_` 로 넘어가기 전에
## 두 번째 스윙이 시작되어 도끼가 반쯤 올라간 자세에서 그림이 튄다.
static func plays_once(motion: String) -> bool:
	return motion.begins_with("use_")


## 시트 한 장(행 = 방향, 열 = 프레임)을 `<모션>_<방향>` 애니메이션으로 잘라 넣는다.
## **색을 갈아끼운 텍스처를 그대로 넘겨도 된다** — 팔레트 교체는 알파를 건드리지
## 않으므로 칸 배치가 그대로다 (`character_sprite.gd` 의 `sprite_frames()`).
static func add_motion(frames: SpriteFrames, texture: Texture2D, motion: String,
		fps: float) -> void:
	var columns := maxi(1, texture.get_width() / CELL)
	for row in DIR_NAMES.size():
		var anim := "%s_%s" % [motion, DIR_NAMES[row]]
		frames.add_animation(anim)
		frames.set_animation_loop(anim, not plays_once(motion))
		frames.set_animation_speed(anim, fps)
		for column in columns:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(column * CELL, row * CELL, CELL, CELL)
			frames.add_frame(anim, atlas)


## 시트 한 장만으로 `SpriteFrames` 를 만든다 (한 모션만 필요할 때).
static func slice_sheet(texture: Texture2D, motion: String, fps: float) -> SpriteFrames:
	var frames := new_frames()
	add_motion(frames, texture, motion, fps)
	return frames
