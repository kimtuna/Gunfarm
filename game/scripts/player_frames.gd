extends RefCounted

## 플레이어 스프라이트 시트 → `SpriteFrames` (docs/DESIGN.md 「캐릭터 애니메이션」).
##
## **시트의 배치 규칙을 아는 유일한 곳**이다 — 행 = 방향(down/left/right/up),
## 열 = 프레임이고, **칸 크기는 시트마다 텍스처에서 읽는다**(`cell_of()`).
## 걷기(INBOX #15)처럼 프레임이 늘어나는 시트가 생겨도
## 여기만 고치면 되고 플레이어 노드는 손대지 않는다.

## 시트는 **머리모양마다 한 장**이다 — 색은 팔레트 교체로 만들 수 있지만
## (`character_sprite.gd`) 머리모양은 형태가 달라서 다시 그려야 하기 때문이다
## (DESIGN.md 「캐릭터 커스터마이징 항목」의 "머리모양은 모양마다 …따로 필요하다").
const SHEET_DIR := "res://assets/sprites"

## 기본 머리모양 — `character_appearance.gd` 의 첫 번째 선택지와 같아야 한다.
const DEFAULT_HAIRSTYLE := "farmer"

## 아트 한 칸(px) — **이름값이고, 시트마다 다를 수 있다**(아래 `cell_of()`).
## 아트 32px × 씬 스케일 3 = 화면 96px = 지형 타일(아트 16px × 3배 = 48px) **두 칸**
## (docs/DESIGN.md 「아이템/오브젝트 크기 표준」).
##
## **2026-09-07 (INBOX #46) 에 17 → 32 가 됐다. 스케일은 그대로 3이다** — 스케일을
## 건드리면 캐릭터의 아트 픽셀만 타일과 달라져 도트 크기 단위가 어긋난다.
## (그전 이력: 34 → 17 은 INBOX #19.)
##
## **지금은 idle 만 32px 이고 걷기·도구 시트는 17px 그대로다** — 사람이 게임에서
## 직접 보고 이사 여부를 정하는 **샘플 상태**이지 이사가 아니다(INBOX #46). 그래서
## 이 파일은 칸 크기를 상수 하나로 믿지 않고 **시트마다 텍스처에서 읽는다.**
const CELL := 32
const SCALE := 3

## 발이 닿는 줄 — **설계 공간(17칸)에서 15.6번째**다. 이 줄이 노드 원점에 오게
## 스프라이트를 올린다 — **원점 = 발밑**이라야 타일 점유와 앞뒤(Y) 정렬이 자연스럽다.
## 칸 크기가 시트마다 다르므로 픽셀값 상수로는 못 적는다(`feet_y()`).
## 생성기(`gen_character.py` 의 `CFG["foot_y"]` + 신발 외곽선)와 같은 줄이다.
const DESIGN_N := 17.0
const DESIGN_FEET_Y := 15.6

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
## **사용 모션이 없는 도구는 2종이다** — 아래 `NO_USE_TOOLS`.
const TOOLS := ["axe", "pickaxe", "sickle", "gun", "hoe", "watering_can",
	"fishing_rod"]

## **사용 모션(`use_<도구>`)이 없는 도구.** 낚싯대뿐이다 (2026-09-07 사람 결정,
## INBOX #31): 낚시의 피드백은 캐릭터 자세가 아니라 **찌가 날아가 물에 떨어지는
## 것**이라, 던지기 로직이 붙는 2단계까지는 그릴 자세가 없다. `DESIGN.md`
## 「생활 스킬 — 채집 계열」의 도구 표에서 낚싯대만 "대상 없이 휘두르기 X" 인 것과
## 같은 자리다. **생성기(`gen_character.py` 의 `has_use()`)와 같은 목록이어야 한다** —
## 여기만 늘리면 없는 시트를 읽으려 하고, 저기만 늘리면 시트가 안 구워진다.
const NO_USE_TOOLS := ["fishing_rod"]


## 이 도구에 사용 모션이 있는가 (위 `NO_USE_TOOLS`).
static func has_use(tool: String) -> bool:
	return not NO_USE_TOOLS.has(tool)


## 한 캐릭터가 가진 모션과 그 재생 속도. **여기 한 줄을 늘리면** 시트가 자동으로
## 같이 실려서 `<모션>_<방향>` 애니메이션이 생긴다(도구별 모션이 그렇게 붙는다).
##
## **2026-09-08 — 캐릭터 시트를 전부 지우고 idle 한 장부터 다시 시작했다.**
## 사람이 "지금까지 있던 거 싹 다 없애고 캐릭터를 싹 다 삭제해. ComfyUI 로 그린 걸
## 도안으로 해서 다시 그려서 하나만 만들어 게임에 적용해봐" 라고 정했다.
## **같은 날 저녁에 리그로 다시 지었다** — `game/tools/rig.py` 가 ComfyUI 그림을
## 부품으로 잘라 관절 각도로 모든 모션을 조립한다(`docs/CHARACTER.md`). 걷기도
## 도구 모션도 거기서 나온다. **도구가 늘면 위 `TOOLS` 와 `rig.TOOLS` 에 한 줄씩만
## 늘리면 시트가 같이 구워지고 여기서 자동으로 실린다.**
static func motions() -> Dictionary:
	var out := {"idle": IDLE_FPS, "walk": WALK_FPS}
	for tool in TOOLS:
		out["hold_%s" % tool] = IDLE_FPS
		if has_use(tool):
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


## 시트 한 장의 칸 크기(px). **행이 방향 4개로 고정**이라 높이만 보면 알 수 있다 —
## 그래서 17px 시트와 32px 시트가 한 `SpriteFrames` 에 섞여도 각자 제 칸으로 잘린다
## (2026-09-07, INBOX #46). 상수 하나로 자르면 안 맞는 시트가 조각나거나 빈 칸이 된다.
## **칸 크기마다 씬 배율이 다르다** (2026-09-08). 캐릭터는 화면에서 늘 96px = 타일 두
## 칸이어야 하므로 `배율 = 96 / 칸` 이다 — 32px→3배, 48px→2배, 96px→1배. 전부 정수라
## 도트가 뭉개지지 않는다(`STYLE_GUIDE.md` 1번). 64px 은 1.5배라 쓸 수 없다.
static func scale_of(cell: int) -> int:
	return maxi(1, 96 / maxi(1, cell))


static func cell_of(texture: Texture2D) -> int:
	return maxi(1, texture.get_height() / DIR_NAMES.size())


## **칸을 세로로 다 쓰는 시트** — 발밑 줄이 칸의 아래 모서리다 (아래 `feet_y()`).
## 지금은 32px idle 하나뿐이다. 32px 로 이사한 시트가 늘면 여기가 아니라
## `feet_y()` 의 규칙 자체를 손볼 자리가 된다.
const FULL_CELL := 32

## 그 칸 크기에서 발이 닿는 줄(아트 픽셀). 정수로 떨어뜨린다 — 반 픽셀이 남으면
## 스프라이트가 도트 격자에서 밀려 아트 픽셀 크기가 균일하지 않게 보인다.
##
## **32px 시트만 다르다**(2026-09-08, INBOX #47). 그 칸의 idle 은 스타듀 농부처럼
## **세로 32칸을 외곽선까지 다 쓰도록** 다시 그려서(1 : 2 비율) 그림의 맨 아랫줄이
## 31 이다 — 설계 공간의 15.6번째 줄(= 29)을 그대로 쓰면 캐릭터가 땅에 2px 묻힌다.
## 17px 시트는 여전히 아랫줄 하나가 비어 있어 옛 규칙 그대로다.
## `qa_player_sprite.gd` 의 `_check_feet_line()` 이 시트마다 이 값을 그림과 견준다.
static func feet_y(cell: int) -> int:
	if cell >= FULL_CELL:
		return cell    # 32·48·96px 시트는 칸을 세로로 다 쓴다 — 아랫줄이 곧 발밑이다
	return roundi(cell * DESIGN_FEET_Y / DESIGN_N)


## 스프라이트를 발밑 기준으로 올리기 위한 `AnimatedSprite2D.offset` (아트 픽셀 단위).
## **칸 크기마다 값이 다르다** — 섞인 시트를 쓰면 애니메이션이 바뀔 때마다 다시 넣어야
## 캐릭터가 땅에 묻히거나 뜨지 않는다(`player.gd` 의 `_update_animation()`).
static func feet_offset(cell: int = CELL) -> Vector2:
	return Vector2(0.0, -(float(feet_y(cell)) - cell * 0.5))


## 이 애니메이션의 칸 크기. 첫 프레임이 시트에서 잘라온 자리(`AtlasTexture.region`)를
## 그대로 읽는다 — 어느 시트에서 왔는지 따로 기억해 둘 필요가 없다.
static func anim_cell(frames: SpriteFrames, anim: String) -> int:
	if frames == null or not frames.has_animation(anim) or frames.get_frame_count(anim) == 0:
		return CELL
	var atlas := frames.get_frame_texture(anim, 0) as AtlasTexture
	return CELL if atlas == null else maxi(1, int(atlas.region.size.y))


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
	# **칸 크기는 이 시트에서 읽는다** — `CELL` 을 쓰면 다른 칸의 시트가 조각난다.
	var cell := cell_of(texture)
	var columns := maxi(1, texture.get_width() / cell)
	for row in DIR_NAMES.size():
		var anim := "%s_%s" % [motion, DIR_NAMES[row]]
		frames.add_animation(anim)
		frames.set_animation_loop(anim, not plays_once(motion))
		frames.set_animation_speed(anim, fps)
		for column in columns:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(column * cell, row * cell, cell, cell)
			frames.add_frame(anim, atlas)


## 시트 한 장만으로 `SpriteFrames` 를 만든다 (한 모션만 필요할 때).
static func slice_sheet(texture: Texture2D, motion: String, fps: float) -> SpriteFrames:
	var frames := new_frames()
	add_motion(frames, texture, motion, fps)
	return frames
