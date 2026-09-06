extends RefCounted

## 캐릭터 외형(피부/머리/옷색 + 머리모양) → 실제 스프라이트 시트 텍스처.
##
## **형태는 다시 그리지 않는다 — 색만 바꿔치기한다** (`docs/STYLE_GUIDE.md` 2번).
## 시트는 기준색 1벌(밝은 피부 / 검정 머리 / 풀색 옷)로만 구워져 있고, 여기서
## 그 PNG 의 픽셀 색을 **기준 램프 색 → 고른 색의 램프 색**으로 통째로 갈아끼운다.
## 색 하나가 아니라 재질별 4단계 램프 전체가 한 벌로 바뀌므로 음영이 그대로 남는다.
##
## 왜 색 바꿔치기인가: 5(피부) × 6(머리) × 6(옷) × 4(머리모양) = 720 벌을 구워둘
## 수는 없다. 머리모양만 시트를 나누고(형태가 다르므로) 색은 실행 중에 만든다.
##
## 램프 색의 원본은 그림을 만든 생성기다 — `character_palettes.gd` 는
## `game/tools/gen_character.py` 가 뽑아준 자동 생성 파일이다(손으로 고치지 말 것).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」).

const Appearance := preload("res://scripts/character_appearance.gd")
const Palettes := preload("res://scripts/character_palettes.gd")
const PlayerFrames := preload("res://scripts/player_frames.gd")

## 재질 순서는 의미가 없다 — 램프끼리 색이 겹치지만 않으면 된다.
## (겹치면 바꿔치기가 모호해진다. `qa_character_sprite.gd` 가 그걸 검사한다.)
const MATERIALS := ["skin", "hair", "shirt", "pants", "boot"]


## 한 외형의 재질별 램프(4단계). 키는 `MATERIALS`, 값은 `PackedColorArray`.
static func ramps(appearance: Dictionary) -> Dictionary:
	var a := Appearance.normalize(appearance)
	var out := {
		"skin": _ramp(Palettes.SKIN, String(a["skin"]), String(Palettes.BASE["skin"])),
		"hair": _ramp(Palettes.HAIR, String(a["hair_color"]), String(Palettes.BASE["hair_color"])),
	}
	var cloth: Dictionary = _pick(Palettes.CLOTHES, String(a["clothes_color"]),
		String(Palettes.BASE["clothes_color"]))
	for mat in ["shirt", "pants", "boot"]:
		out[mat] = _to_colors(cloth[mat])
	return out


## 기준색 시트의 색 → 고른 외형의 색. 키는 32비트 RGB 정수다(Color 를 키로 쓰면
## 부동소수 비교가 되어 미묘하게 안 맞는다).
static func recolor_map(appearance: Dictionary) -> Dictionary:
	var base := ramps(Palettes.BASE)
	var want := ramps(appearance)
	var map := {}
	for mat in MATERIALS:
		var from: PackedColorArray = base[mat]
		var to: PackedColorArray = want[mat]
		for i in from.size():
			map[_key(from[i])] = to[i]
	return map


## 머리모양에 맞는 시트를 읽어 고른 색으로 칠한 텍스처. 실패하면 null.
static func idle_texture(appearance: Dictionary) -> ImageTexture:
	var a := Appearance.normalize(appearance)
	var sheet: Texture2D = load(PlayerFrames.sheet_path("idle", String(a["hairstyle"])))
	if sheet == null:
		push_error("캐릭터 시트를 못 읽었다 — `--import` 를 안 돌렸을 수 있다")
		return null
	return ImageTexture.create_from_image(recolored(sheet.get_image(), a))


## 기준색 이미지 한 장을 고른 색으로 칠한 새 이미지.
##
## 픽셀을 하나씩 `get_pixel()` 로 도는 대신 **바이트 배열을 통째로** 훑는다 —
## 34×34 칸이 16장이면 1만 8천 픽셀이라, 커스터마이징 화면에서 색을 넘길 때마다
## 도는 비용이 눈에 띌 수 있다.
static func recolored(source: Image, appearance: Dictionary) -> Image:
	var image := Image.new()
	image.copy_from(source)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var map := recolor_map(appearance)
	var bytes := image.get_data()
	# 같은 색이 수천 번 나오므로 한 번 만든 바이트 3개를 재사용한다.
	var cache := {}
	var i := 0
	while i < bytes.size():
		if bytes[i + 3] != 0:
			var key: int = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2]
			var swapped = cache.get(key)
			if swapped == null:
				var target = map.get(key)
				swapped = _bytes(target) if target != null else null
				cache[key] = swapped if swapped != null else 0
			if swapped is PackedByteArray:
				bytes[i] = swapped[0]
				bytes[i + 1] = swapped[1]
				bytes[i + 2] = swapped[2]
		i += 4
	return Image.create_from_data(image.get_width(), image.get_height(), false,
		Image.FORMAT_RGBA8, bytes)


static func _ramp(table: Dictionary, id: String, fallback: String) -> PackedColorArray:
	return _to_colors(_pick(table, id, fallback))


static func _pick(table: Dictionary, id: String, fallback: String):
	return table[id] if table.has(id) else table[fallback]


static func _to_colors(hexes: Array) -> PackedColorArray:
	var out := PackedColorArray()
	for h in hexes:
		out.append(Color(String(h)))
	return out


static func _key(color: Color) -> int:
	return (_c(color.r) << 16) | (_c(color.g) << 8) | _c(color.b)


static func _bytes(color: Color) -> PackedByteArray:
	return PackedByteArray([_c(color.r), _c(color.g), _c(color.b)])


static func _c(v: float) -> int:
	return clampi(int(round(v * 255.0)), 0, 255)
