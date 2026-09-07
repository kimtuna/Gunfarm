extends Control

## 총 UI — 탄창에 남은 발수와 지금 든 탄종 (docs/DESIGN.md 「총기 스탯」, INBOX #35).
##
## **총을 들고 있을 때만 나온다.** 「총기 스탯」이 "탄창에 남은 발수는 총을 들고 있을
## 때만 화면에 표시한다"고 정해뒀고, 「인벤토리 / 장비」가 "지금 화면에 상시로 두는
## 것은 핫바 하나다"라고 못 박아뒀다 — 보이고 감추는 판정은 조준선과 **같은 한 줄**
## 에 있다(`world.gd` 의 `_process`), 그래야 총을 내렸을 때 선과 UI 가 따로 놀지 않는다.
##
## **여기는 그리기만 한다** — 남은 발수도 든 탄종도 `gun_ammo.gd`(플레이어 코어가 든
## 순수 클래스)의 것이다 (docs/DESIGN.md 「서버 권위」). 이 파일에는 상태가 없다.
##
## 그림은 두 줄이다:
## - 윗줄: 탄종 이름(왼쪽) + 남은 발수(오른쪽). 재장전 중에는 숫자 대신 "재장전…".
## - 아랫줄: 탄창 8칸. **찬 칸과 빈 칸을 자리는 그대로 두고 색으로 가른다** — 칸이
##   사라지면 남은 발수를 눈으로 세는 게 아니라 길이를 재게 된다.
##
## **재장전은 칸이 왼쪽부터 하나씩 차오르는 것으로 보인다**(진행 막대를 따로 두지
## 않는다). 탄창이 채워지는 그림 자체가 진행도라 새 요소가 필요 없고, 다 차오른
## 순간이 곧 다시 쏠 수 있게 되는 순간이라 어긋날 자리가 없다.

const ItemTypes := preload("res://scripts/item_types.gd")
const GunAmmo := preload("res://scripts/gun_ammo.gd")

## 탄창 칸 하나의 크기와 사이 간격(화면 px). 핫바 칸(56)보다 한참 작아야 핫바와
## 경쟁하지 않는다 — 이건 읽는 것이지 누르는 것이 아니다.
const PIP := Vector2(16.0, 24.0)
const PIP_GAP := 6.0

## 윗줄(글자)의 높이와 아랫줄과의 사이.
const TEXT_H := 24.0
const ROW_GAP := 6.0

const NAME_FONT_SIZE := 19
const COUNT_FONT_SIZE := 21

## 빈 칸 색 — 인벤토리 빈 칸(`inventory_panel.gd` 의 `SLOT_BG`/`SLOT_BORDER`)과 같은
## 색이다. 같은 화면에 나란히 놓이는 UI 라 여기서 다른 회색을 새로 만들지 않는다.
const EMPTY_BG := Color(0.086, 0.098, 0.078)
const EMPTY_BORDER := Color(0.278, 0.310, 0.243)

## 글자색도 인벤토리·핫바가 쓰는 것 그대로다.
const LABEL_COLOR := Color(0.851, 0.761, 0.478)
const COUNT_COLOR := Color(0.965, 0.949, 0.898)
const COUNT_SHADOW := Color(0.039, 0.045, 0.035)
## 탄창이 비었을 때의 숫자색 — "좌클릭해도 안 나간다"가 한눈에 보여야 한다.
const EMPTY_COUNT_COLOR := Color(0.898, 0.373, 0.318)
## 재장전 중의 글자색. 비어 있음(빨강)과 갈라져야 한다.
const RELOAD_COLOR := Color(0.639, 0.741, 0.518)

## 지금 채워지고 있는 칸을 살짝 밝게 — 재장전이 멈춰 있지 않다는 신호다.
const FILLING_LIGHTEN := 0.35

## 총알 한 칸 안쪽의 밝은 띠/그림자 두께 — 아이템 자리표시(`inventory_panel.gd` 의
## `_draw_placeholder`)와 같은 방식이라 화면 안에서 결이 같아 보인다.
const SHINE := 4.0

## 플레이어 코어(`player_motion.gd`). **`gun` 하나만 읽는다.**
var motion: RefCounted = null

var _drawn := ""


func _ready() -> void:
	custom_minimum_size = panel_size()


## 이 Control 이 차지하는 크기. 씬의 상자 크기(`world.tscn` 의 `GunHud`)가 이 값에서
## 나왔다 — 칸 수나 크기를 바꾸면 여기 하나만 보면 된다.
func panel_size() -> Vector2:
	var width := GunAmmo.MAG_SIZE * PIP.x + (GunAmmo.MAG_SIZE - 1) * PIP_GAP
	return Vector2(width, TEXT_H + ROW_GAP + PIP.y)


func setup(player_motion: RefCounted) -> void:
	motion = player_motion
	_drawn = ""
	queue_redraw()


## 탄창 칸 하나가 이 Control 안에서 차지하는 사각형. **자체 QA 도 이 함수로 자리를
## 묻는다** — 그림과 검사가 같은 계산을 쓰므로 배치를 바꿔도 어긋날 데가 없다
## (`inventory_panel.gd` 의 `slot_rect()` 와 같은 방식).
func pip_rect(index: int) -> Rect2:
	return Rect2(Vector2(index * (PIP.x + PIP_GAP), TEXT_H + ROW_GAP), PIP)


## 지금 화면에 보여야 하는 상태를 한 문자열로 — 이게 바뀔 때만 다시 그린다.
func _state() -> String:
	if motion == null or motion.gun == null:
		return ""
	var gun: RefCounted = motion.gun
	return "%s/%d/%d" % [gun.kind, gun.loaded(), gun.reload_ticks_left]


func _process(_delta: float) -> void:
	var now := _state()
	if now != _drawn:
		queue_redraw()


func _draw() -> void:
	if motion == null or motion.gun == null:
		return
	_drawn = _state()
	var gun: RefCounted = motion.gun
	var font := get_theme_default_font()
	# 탄종 이름과 색은 **아이템 표에서 그대로 읽는다** — 탄종 id 가 곧 아이템 id 라
	# (`gun_ammo.gd`) 이름을 여기 또 적어두면 두 곳이 어긋난다.
	var tint: Color = ItemTypes.color_of(gun.kind)
	draw_string(font, Vector2(1.0, NAME_FONT_SIZE), ItemTypes.name_of(gun.kind),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FONT_SIZE, LABEL_COLOR)
	_draw_count(font, gun)
	# 재장전 중에는 남은 발수가 아니라 **차오르는 중인 칸 수**를 그린다 — 다 차오른
	# 순간이 곧 다시 쏠 수 있게 되는 순간이다.
	var filled: int = gun.loaded()
	var filling := -1
	if gun.is_reloading():
		filled = int(floor(gun.reload_progress() * float(GunAmmo.MAG_SIZE)))
		filling = mini(filled, GunAmmo.MAG_SIZE - 1)
	for index in GunAmmo.MAG_SIZE:
		_draw_pip(pip_rect(index), index < filled, index == filling, tint)


## 오른쪽 끝의 숫자. 재장전 중에는 숫자가 의미가 없으므로 글자로 바꾼다.
func _draw_count(font: Font, gun: RefCounted) -> void:
	var text := "재장전…"
	var color := RELOAD_COLOR
	if not gun.is_reloading():
		text = "%d / %d" % [gun.loaded(), GunAmmo.MAG_SIZE]
		color = COUNT_COLOR if gun.loaded() > 0 else EMPTY_COUNT_COLOR
	var at := Vector2(size.x - 1.0, COUNT_FONT_SIZE)
	at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, COUNT_FONT_SIZE).x
	draw_string(font, at + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			COUNT_FONT_SIZE, COUNT_SHADOW)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, COUNT_FONT_SIZE, color)


## 탄창 칸 하나. 빈 칸도 자리를 지킨다 — 사라지면 남은 발수를 세는 게 아니라 길이를
## 재게 된다.
func _draw_pip(rect: Rect2, full: bool, filling: bool, tint: Color) -> void:
	if not full:
		draw_rect(rect, EMPTY_BG)
		draw_rect(rect, EMPTY_BORDER, false, 2.0)
		return
	var base := tint.lightened(FILLING_LIGHTEN) if filling else tint
	draw_rect(rect, base)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, SHINE)), base.lightened(0.25))
	draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - SHINE), Vector2(rect.size.x, SHINE)),
			base.darkened(0.35))
	draw_rect(rect, base.darkened(0.6), false, 2.0)
