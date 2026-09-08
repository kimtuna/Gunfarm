extends RefCounted

## **자동 생성 파일이다 — 손으로 고치지 말 것.**
## `game/tools/gen_terrain.py` 의 `export_palettes()` 가 만든다
## (`.venv/bin/python game/tools/gen_terrain.py`).
##
## 지형 시트를 구울 때 쓴 재질별 4단계 램프다. 램프를 만드는 계산(`make_ramp()`)을
## GDScript 로 옮겨 적으면 생성기와 어긋나므로, 계산한 값을 그대로 적어 내려보낸다
## (`character_palettes.gd` 과 같은 이유).
##
## `rim` 은 땅쪽 테두리, `shallow`/`foam` 은 해안의 여울과 물거품이다.

const RAMPS := {
	"grass": ["6e8c59", "4d793c", "3f6633", "35552c"],
	"deep": ["456d8e", "18415f", "13334e", "122d47"],
	"shallow": ["5e9faf", "398b98", "2e7888", "276778"],
	"foam": ["d0dcd9", "c4d5d5", "b5c3c7", "a5b1b9"],
	"rim": ["464d40", "364132", "2f372f", "2b2e2c"],
}

## 화면의 한 픽셀이 땅인지 바다인지 — 자체 QA 가 스크린샷을 판정할 때 쓴다.
const LAND_MATERIALS := ["grass", "rim"]
const SEA_MATERIALS := ["deep", "shallow", "foam"]


static func color_of(material: String, step: int) -> Color:
	return Color(RAMPS[material][step])
