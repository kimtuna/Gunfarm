extends RefCounted

## 아이템 종류 표 (docs/DESIGN.md 「아이템 카테고리 / 제작(크래프팅) 테크」).
##
## Godot 노드를 상속하지 않는 순수 클래스다 (DESIGN.md 「시뮬레이션 구조」) — 나중에
## 서버가 화면 없이 같은 표를 읽는다.
##
## **여기 있는 것은 DESIGN.md 가 이미 이름을 적어둔 아이템뿐이다.** 없는 아이템을
## 지어내지 않는다(PROMPT.md). 실제로 얻는 경로(채집/드롭/제작)는 그 자원을 만드는
## 바퀴가 붙인다 — 이 표는 "이런 아이템이 있다"는 정의만 갖는다.
##
## **아이콘 그림은 아직 없다.** 인벤토리 칸에는 `color` 로 칠한 자리표시를 그린다 —
## 진짜 아이콘은 DESIGN.md 「새 도구를 추가하는 절차」 6번대로 그 도구의 [DESIGN]
## 바퀴가 같이 만든다. 그때 이 표에 `icon` 을 한 줄 늘리면 된다.

# --- 카테고리 (docs/DESIGN.md 「카테고리」) -------------------------------------
const CAT_RAW := "원재료"
const CAT_PROCESSED := "가공물"
const CAT_PRODUCT := "완성품"
const CAT_FOOD_GRAIN := "식재료 (곡물)"
const CAT_FOOD_MEAT := "식재료 (육류)"
const CAT_COOKED := "가공식품"
const CAT_DISH := "요리"

## 겹쳐 쌓을 수 있는 최대 수량. **도구/장비는 1**이고 나머지는 이 값이다.
## (2026-09-07 INBOX #23 에서 정한 값 — DESIGN.md 에 요약을 적었다.)
const MAX_STACK := 99
const MAX_STACK_UNIQUE := 1

# --- 장비 종류 (docs/DESIGN.md 「인벤토리 / 장비」의 장비 슬롯 9칸) --------------
## 장비 슬롯이 받는 종류. 아이템의 `equip` 가 이 중 하나면 그 칸에만 들어간다.
const EQUIP_NONE := ""
const EQUIP_HAT := "hat"
const EQUIP_SHIRT := "shirt"
const EQUIP_PANTS := "pants"
const EQUIP_SHOES := "shoes"
const EQUIP_NECKLACE := "necklace"
const EQUIP_RING := "ring"
const EQUIP_BAG := "bag"

## 장비 종류 → 칸에 적을 이름(비어 있을 때 흐리게 보여준다).
const EQUIP_NAMES := {
	EQUIP_HAT: "모자",
	EQUIP_SHIRT: "상의",
	EQUIP_PANTS: "하의",
	EQUIP_SHOES: "신발",
	EQUIP_NECKLACE: "목걸이",
	EQUIP_RING: "반지",
	EQUIP_BAG: "가방",
}

## 아이템 하나의 정의.
##   name     — 화면에 보이는 이름
##   category — 위 카테고리 상수
##   color    — 아이콘이 생기기 전까지 칸에 칠할 자리표시 색
##   stack    — 없으면 MAX_STACK
##   equip    — 없으면 EQUIP_NONE (장비 슬롯에 안 들어간다)
const ITEMS := {
	# 도구 7종 (docs/DESIGN.md 「생활 스킬 — 채집 계열」의 도구 표).
	# 도구는 「카테고리」의 완성품이고, 한 칸에 하나씩만 들어간다.
	"gun": {"name": "기본 소총", "category": CAT_PRODUCT, "color": Color(0.42, 0.45, 0.49), "stack": MAX_STACK_UNIQUE},
	"axe": {"name": "도끼", "category": CAT_PRODUCT, "color": Color(0.60, 0.42, 0.24), "stack": MAX_STACK_UNIQUE},
	"pickaxe": {"name": "곡괭이", "category": CAT_PRODUCT, "color": Color(0.49, 0.52, 0.55), "stack": MAX_STACK_UNIQUE},
	"sickle": {"name": "낫", "category": CAT_PRODUCT, "color": Color(0.66, 0.68, 0.70), "stack": MAX_STACK_UNIQUE},
	"hoe": {"name": "괭이", "category": CAT_PRODUCT, "color": Color(0.55, 0.56, 0.47), "stack": MAX_STACK_UNIQUE},
	"watering_can": {"name": "물뿌리개", "category": CAT_PRODUCT, "color": Color(0.42, 0.58, 0.57), "stack": MAX_STACK_UNIQUE},
	"fishing_rod": {"name": "낚싯대", "category": CAT_PRODUCT, "color": Color(0.69, 0.55, 0.33), "stack": MAX_STACK_UNIQUE},

	# 원재료
	"wood": {"name": "목재", "category": CAT_RAW, "color": Color(0.54, 0.36, 0.20)},
	"stone": {"name": "돌", "category": CAT_RAW, "color": Color(0.49, 0.50, 0.48)},
	"iron_ore": {"name": "철광석", "category": CAT_RAW, "color": Color(0.44, 0.38, 0.34)},
	"sulfur_ore": {"name": "유황광석", "category": CAT_RAW, "color": Color(0.72, 0.66, 0.23)},

	# 가공물
	"plank": {"name": "판자", "category": CAT_PROCESSED, "color": Color(0.69, 0.48, 0.27)},
	"stone_block": {"name": "석재", "category": CAT_PROCESSED, "color": Color(0.60, 0.61, 0.59)},
	"iron": {"name": "철", "category": CAT_PROCESSED, "color": Color(0.73, 0.75, 0.78)},
	"charcoal": {"name": "숯", "category": CAT_PROCESSED, "color": Color(0.23, 0.23, 0.22)},
	"gunpowder": {"name": "화약", "category": CAT_PROCESSED, "color": Color(0.35, 0.33, 0.30)},

	# 완성품 (건축물 / 탄약 / 가방)
	"wood_wall": {"name": "나무벽", "category": CAT_PRODUCT, "color": Color(0.48, 0.33, 0.19)},
	"wood_door": {"name": "나무문", "category": CAT_PRODUCT, "color": Color(0.59, 0.41, 0.23)},
	"stone_wall": {"name": "석제벽", "category": CAT_PRODUCT, "color": Color(0.52, 0.53, 0.51)},
	"steel_wall": {"name": "강철벽", "category": CAT_PRODUCT, "color": Color(0.56, 0.59, 0.62)},
	"steel_door": {"name": "강철문", "category": CAT_PRODUCT, "color": Color(0.62, 0.65, 0.68)},
	"window": {"name": "창문", "category": CAT_PRODUCT, "color": Color(0.47, 0.62, 0.66)},
	"ammo_basic": {"name": "기본탄", "category": CAT_PRODUCT, "color": Color(0.70, 0.60, 0.30)},
	"ammo_tranq": {"name": "마취탄", "category": CAT_PRODUCT, "color": Color(0.50, 0.62, 0.42)},
	# 가방은 DESIGN.md 「새 테크 라인」의 "가방(장비 슬롯에 이미 자리는 있음)" 이다.
	# 효과는 범위 밖 — 지금은 장비 칸에 넣고 뺄 수 있기만 하면 된다.
	"bag": {"name": "가방", "category": CAT_PRODUCT, "color": Color(0.54, 0.42, 0.27),
			"stack": MAX_STACK_UNIQUE, "equip": EQUIP_BAG},

	# 식재료 / 가공식품 / 요리
	"rice": {"name": "벼", "category": CAT_FOOD_GRAIN, "color": Color(0.80, 0.72, 0.40)},
	"meat": {"name": "고기", "category": CAT_FOOD_MEAT, "color": Color(0.68, 0.35, 0.31)},
	"cooked_rice": {"name": "밥", "category": CAT_COOKED, "color": Color(0.88, 0.85, 0.75)},
	"cooked_meat": {"name": "익힌고기", "category": CAT_COOKED, "color": Color(0.72, 0.44, 0.25)},
	"steak": {"name": "스테이크", "category": CAT_DISH, "color": Color(0.78, 0.47, 0.28)},
}


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func of(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func name_of(id: String) -> String:
	return String(of(id).get("name", id))


static func category_of(id: String) -> String:
	return String(of(id).get("category", ""))


static func color_of(id: String) -> Color:
	return of(id).get("color", Color(0.5, 0.5, 0.5))


## 이 아이템이 한 칸에 몇 개까지 쌓이는가. 모르는 아이템은 0 — 넣을 자리가 없다는 뜻이라
## 「인벤토리 안전」이 저절로 지켜진다(조용히 사라지는 대신 안 들어간다).
static func max_stack(id: String) -> int:
	if not exists(id):
		return 0
	return int(of(id).get("stack", MAX_STACK))


## 이 아이템이 들어갈 수 있는 장비 칸 종류. 빈 문자열이면 장비가 아니다.
static func equip_kind(id: String) -> String:
	return String(of(id).get("equip", EQUIP_NONE))


## 칸에 그릴 짧은 이름(아이콘이 생기기 전의 자리표시). 두 글자면 56px 칸에 읽힌다.
static func short_name(id: String) -> String:
	var full := name_of(id)
	return full if full.length() <= 2 else full.substr(0, 2)
