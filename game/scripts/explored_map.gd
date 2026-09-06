extends RefCounted

## "가본 곳" 기록 (docs/DESIGN.md 「맵 (M)」).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) —
## 화면 없이 단독으로 돌아가야 헤드리스로 검증할 수 있다.
##
## **가진 것은 "어디를 봤는가" 하나뿐이다.** 그 자리의 지형이 무엇인지는 저장하지
## 않는다 — 시드만 있으면 `world_gen.gd` 가 언제든 다시 계산해준다. 같은 정보를 두 벌
## 가지면 둘이 어긋나는 순간 고칠 방법이 없다 (docs/DESIGN.md 「맵 (M)」).
##
## **타일 하나가 비트 하나다.** 256×256 = 65,536칸 ÷ 8 = 8,192바이트. 타일마다 JSON
## 배열 칸 하나씩(`0,`) 쓰면 그것만으로 131KB 라 16배 크고, 저장할 때마다 6만 5천 개를
## 문자열로 찍어야 한다. 실제로 파일에 들어가는 것은 이 8,192바이트를 **deflate 로 줄여
## base64 로 적은 문자열**이다 — 실측으로 처음 96자, 10% 탐험 688자, 절반 탐험 1,816자,
## 전부 탐험 44자(전부 1이면 도로 잘 줄어든다)다. 어느 쪽도 슬롯 JSON 한 줄로 충분하다.

const WorldGen := preload("res://scripts/world_gen.gd")

## 한 변의 타일 수 — 지도와 같아야 한다.
const TILES := WorldGen.MAP_TILES
## 비트 배열의 바이트 수. 타일 하나당 1비트.
const BYTES := (TILES * TILES) / 8

## 저장 문자열의 압축 방식. 형식을 바꾸면 옛 저장은 "못 읽음"이 되어 빈 지도로 시작한다
## (지형이 아니라 탐험 기록이라 잃어도 게임이 깨지지 않는다).
const COMPRESSION := FileAccess.COMPRESSION_DEFLATE

## 타일당 1비트. 인덱스는 지형 배열(`world_gen.gd` 의 `tiles`)과 같은 `y * TILES + x` 다.
var bits := PackedByteArray()

## 내용이 바뀔 때마다 오른다 — 지도 화면이 "다시 그려야 하는가"를 이걸로 판단한다
## (매 프레임 65,536칸을 다시 굽지 않으려고).
var version := 0


func _init() -> void:
	bits.resize(BYTES)


func is_explored(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= TILES or y >= TILES:
		return false
	var index := y * TILES + x
	return (bits[index >> 3] & (1 << (index & 7))) != 0


## 한 칸을 "가봤음"으로 적는다. 처음 적히는 칸이면 true.
func mark(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= TILES or y >= TILES:
		return false
	var index := y * TILES + x
	var byte := index >> 3
	var bit := 1 << (index & 7)
	if bits[byte] & bit:
		return false
	bits[byte] |= bit
	version += 1
	return true


## 플레이어 주변 **반경** 안을 전부 적는다. 새로 적힌 칸 수를 돌려준다.
##
## **시야 콘이 아니라 반경이다** (docs/DESIGN.md 「맵 (M)」) — 콘으로 적으면 제자리에서
## 마우스를 돌리는 것만으로 지도가 채워지고, 지나간 자리마다 부채꼴 자국이 남는다.
func mark_around(tile: Vector2i, radius: int) -> int:
	var added := 0
	var limit := radius * radius
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > limit:
				continue
			if mark(tile.x + dx, tile.y + dy):
				added += 1
	return added


func explored_count() -> int:
	var total := 0
	for byte in bits:
		while byte != 0:
			total += byte & 1
			byte >>= 1
	return total


func is_empty() -> bool:
	for byte in bits:
		if byte != 0:
			return false
	return true


# --- 저장 --------------------------------------------------------------------

## 슬롯 파일(JSON)에 넣을 수 있는 한 줄짜리 문자열. 위 맨 앞 주석의 계산 참고.
func to_base64() -> String:
	return Marshalls.raw_to_base64(bits.compress(COMPRESSION))


## 저장 문자열을 읽어 들인다. **읽지 못하면 빈 지도로 남기고 false 를 돌려준다** —
## 형식이 바뀌었거나 파일이 깨졌다고 캐릭터를 못 쓰게 만들 이유가 없다(탐험 기록은
## 지형과 달리 잃어도 다시 걸어서 채울 수 있다).
func load_base64(text: String) -> bool:
	if text.is_empty():
		return false
	var raw := Marshalls.base64_to_raw(text)
	if raw.is_empty():
		return false
	var decoded := raw.decompress_dynamic(BYTES, COMPRESSION)
	if decoded.size() != BYTES:
		return false
	bits = decoded
	version += 1
	return true
