"""코어키퍼풍 캐릭터 절차 생성 — 슈퍼샘플 + 입체 음영 + 팔레트 디더링.

실행: `.venv/bin/python game/tools/gen_character.py` (시스템 python3 에는 numpy 가 없다)

왜 이렇게 하나 (`docs/STYLE_GUIDE.md` 「권장 파이프라인」):
  도트를 한 픽셀씩 직접 찍으면 "평평"해진다(테두리에만 음영이 걸림). 대신
  1) 캐릭터를 입체 덩어리(구/캡슐/둥근상자)의 합으로 정의하고
  2) 12배 해상도에서 각 덩어리의 높이장(height field)에서 법선을 구해 램버트 조명을 계산하고
  3) 네이티브 17px 로 줄이고 (재질·부위는 최빈값, 명도는 평균)
  4) 재질별 팔레트 램프(4단계)에 순서 디더링으로 양자화한 뒤 내부선 → 외곽선.

**팔레트는 커스터마이징 색에서 만들어진다.** `game/scripts/character_appearance.gd` 의
피부/머리/옷 색 하나를 넣으면 그 색을 기준으로 4단계 램프가 생성된다 — 형태를 다시
그리지 않고 램프만 갈아끼우는 게 색상 확장 방식이다(STYLE_GUIDE 2번).

크기: 네이티브 17px, 게임 화면 51px = 정확히 3배(정수 배율).
**2026-09-07 (INBOX #19) 에 캔버스를 34px 에서 절반으로 줄였다** — 사람 피드백
"캐릭터를 작게 만들어줘 … 지금의 반으로 줄여도 될것같아". 씬 스케일(3배)은
건드리지 않았다: 스케일을 낮추면 캐릭터의 아트 픽셀만 타일(아트 16px × 3배)의
절반이 되어 도트 크기 단위가 어긋난다(`docs/DESIGN.md` 「아이템/오브젝트 크기 표준」).
**넓이가 1/4 이라 옛 값을 그냥 반으로 나눌 수 없다** — 아래 `CFG` 는 17px 격자
위에서 다시 잡은 실측값이고, 눈·옷 포인트처럼 "몇 개를 넣을 것인가"가 달라진
것들은 `docs/STYLE_GUIDE.md` 「자연스러움」이 함께 바뀌었다.
"""
import os

import numpy as np
from PIL import Image

N = 17          # 네이티브 캔버스 (2026-09-07, INBOX #19 — 34px 에서 절반)
SS = 24         # 슈퍼샘플 배율. 캔버스를 반으로 줄이면서 두 배로 올렸다 —
                # 슈퍼샘플 해상도(N × SS = 408)를 그대로 두어야 0.2px 단위로 잡은
                # 형태가 축소 전에 뭉개지지 않는다.
H = N * SS
OUT = os.environ.get("GEN_OUT") or os.path.dirname(os.path.abspath(__file__))
# 기본은 스크립트 옆. 저장소를 더럽히지 않으려면 GEN_OUT 으로 임시 폴더를 준다.

INK = (38, 28, 44)          # 공통 잉크색 #261C2C — 순검정을 쓰지 않는다
GLINT = (247, 240, 232)     # 눈 하이라이트

# `character_appearance.gd` 의 기본 선택지 = 이번 기준색 1벌.
# id 도 같이 들고 있는다 — 게임이 "이 PNG 는 어떤 색으로 구워졌나"를 알아야
# 그 색을 출발점으로 다른 색으로 바꿔치기할 수 있다(`export_palettes()`).
BASE_SKIN_ID, BASE_SKIN = "light", "f0c8a0"       # 밝은
BASE_HAIR_ID, BASE_HAIR = "black", "211c1a"       # 검정
BASE_CLOTH_ID, BASE_CLOTH = "grass", "4e7a3a"     # 풀색

# 바지/신발 색은 옷색에서 **색상(hue)까지 옮겨서** 만든다 (2026-09-06, INBOX #13).
# 전에는 옷색을 그냥 어둡게 썼는데, 그러면 상의와 하의의 색상이 같아서 몸이 초록
# 기둥 하나로 뭉쳤다(사람 피드백: "상하의가 너무 단색이라서 그런 것 같기도 하다").
# `docs/STYLE_GUIDE.md` 「자연스러움」: **상의와 하의는 서로 다른 색상.**
#
# 고정 각도로 색상환을 돌리지 않는다 — 옷색에 따라 형광 분홍 바지가 나온다.
# 대신 **바지다운 색 두 개(흙빛/데님)** 를 두고, 옷색에서 먼 쪽에 붙인 뒤 옷색을
# 조금 섞어 상의와 이어지게 한다. 팔레트가 늘어나지는 않는다(여전히 옷색 하나에서
# 셔츠/바지/신발이 나온다 — DESIGN.md 「캐릭터 커스터마이징 항목」).
PANTS_WARM = (110, 80, 52)      # 흙빛 — 초록·파랑·자주처럼 차가운 옷색에 붙는다
PANTS_COOL = (62, 76, 108)      # 데님 — 옷색이 이미 흙빛일 때(주홍·흙색)
PANTS_MIX = 0.25                # 옷색을 이만큼 섞는다. 더 섞으면 색상차가 사라진다
PANTS_NEAR = 46.0               # 옷색이 흙빛과 이만큼 안쪽이면 데님으로 간다(도)

# 도구 재질 2종 — **커스터마이징과 무관한 고정색이다.** 자루(나무)와 날(쇠)로
# 나눠 두는 이유가 둘이다: (1) 17px 에서 도끼가 도끼로 읽히려면 자루와 날이 색으로
# 갈려야 하고(형태만으로는 몇 px 안 된다), (2) `character_sprite.gd` 의 색 바꿔치기는
# **기준색 램프에 있는 색만** 갈아끼우므로, 이 두 램프는 어떤 외형을 골라도 그대로
# 남는다 — 도구가 옷색을 따라 변하면 안 된다.
# 앞으로 붙는 도구 6종(총/곡괭이/낫/괭이/물뿌리개/낚싯대)도 이 두 램프를 그대로 쓴다.
HELVE = (146, 104, 62)      # 물푸레나무 자루
BLADE = (150, 156, 164)     # 쇠 날 — 채도가 낮아 옷·피부 어느 색과도 안 붙는다
HELVE_BAND = 118.0          # 바지(셔츠×0.70 ≈ 103)와 겹치지 않게 한 단 위로 띄운다
BLADE_BAND = 152.0

MATS = ["skin", "hair", "shirt", "pants", "boot", "helve", "blade",
        "blush", "eye", "glint"]

BAYER4 = np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], dtype=np.float32) / 16.0


# ── 팔레트 ────────────────────────────────────────────────────────────────
def _hex(s):
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


WARM = (255, 240, 205)      # 밝은면이 향하는 색 (따뜻한 햇빛)
COOL = (196, 206, 232)      # 검은 머리처럼 무채색에 가까운 재질의 밝은면
DUSK = (74, 58, 104)        # 그늘이 향하는 색 (차가운 자주) — 그늘이 회색이 되지 않게


def luma(rgb):
    """지각 명도(Rec.601). **재질을 구분하는 건 색상이 아니라 이 값이다.**"""
    r, g, b = (float(c) for c in rgb)
    return 0.299 * r + 0.587 * g + 0.114 * b


def set_luma(rgb, target):
    """색상은 유지한 채 명도만 목표값으로 맞춘다.

    곱하기만 하면 밝은 목표에서 채널이 255 에 걸려 명도가 모자란다 — 걸리면
    부족한 만큼 흰색 쪽으로 섞어서 채운다(그때만 채도가 빠진다).
    """
    v = np.array(rgb, dtype=np.float32)
    cur = luma(v)
    if cur < 1e-3:
        return np.full(3, target, np.float32)
    v = np.clip(v * (target / cur), 0, 255)
    for _ in range(4):                       # 클리핑으로 모자란 만큼만 흰색을 섞는다
        gap = target - luma(v)
        if gap <= 0.5:
            break
        head = 255.0 - luma(v)
        if head <= 1e-3:
            break
        v = np.clip(v + (255.0 - v) * (gap / head), 0, 255)
    return v


def _chroma(rgb, k):
    """명도는 그대로 두고 채도만 k 배. k>1 이면 쨍해진다."""
    v = np.array(rgb, dtype=np.float32)
    g = luma(v)
    return np.clip(g + (v - g) * k, 0, 255)


def _mix(rgb, other, t):
    return np.array(rgb, np.float32) + (np.array(other, np.float32) - np.array(rgb, np.float32)) * t


# 램프 4단계의 **목표 명도 배율**(기본 단계 = 1.0). 예전처럼 채널을 통째로
# 곱하지 않는다 — 곱셈은 어두운 재질을 잉크(명도 33) 아래로 떨어뜨려서 신발이
# 검은 구멍이 됐다. 명도로 잡으면 재질마다 폭이 같아진다.
RAMP = (1.26, 1.0, 0.80, 0.63)
INK_LUMA = luma(INK)        # 32.8
FLOOR = INK_LUMA + 7.0      # 램프 맨 아래도 외곽선보다는 확실히 밝아야 한다
HAIR_FLOOR = INK_LUMA + 2.0  # 검은 머리만 여유를 줄인다 — 그래도 잉크 위다


CEIL = 242.0                # 램프 맨 위 한계 — 이 위는 순백으로 뭉개진다


def make_ramp(base, target, hi_to=WARM, hi_mix=0.24, sat=(0.92, 1.0, 1.14, 1.24),
              ramp=RAMP, floor=FLOOR, ceil=CEIL):
    """기준색 + **목표 명도** → 밝은면/기본/그늘/가장어두움 4단계.

    값을 치르고 알아낸 것(되돌리지 말 것):
      - **재질 구분은 목표 명도(`target`)로 못박는다.** 옷색을 0.46 배로 곱해
        바지를 만들었더니, 옷색이 무엇이냐에 따라 상의와 값이 겹치기도 하고
        신발이 외곽선보다 어두워지기도 했다. 명도를 직접 지정하면 어떤
        커스터마이징 색을 넣어도 재질 사이 명도 차가 유지된다.
      - **어두워질수록 채도를 올린다**(`sat`). 명도만 낮추면 그늘이 진흙색이
        된다 — 코어키퍼풍의 "탁하지 않은" 느낌은 여기서 나온다.
      - **그늘은 자주(DUSK) 쪽으로, 밝은면은 햇빛(WARM) 쪽으로** 살짝 민다.
      - 맨 아래 단계도 `floor`(잉크 명도 + 여유) 아래로 못 내려간다.
      - **맨 위 단계도 `ceil` 위로 못 올라간다**(2026-09-06, INBOX #11). 램프
        배율은 검정 머리 기준이라 금발·은발에 곱하면 목표 명도가 255 를 넘고,
        그러면 `set_luma()` 가 흰색을 섞어 채워서 밝은면이 **순백 덩어리**가
        된다 — 색을 골랐는데 하이라이트만 보면 금발과 은발이 똑같아진다.
    """
    steps = []
    for i, mul in enumerate(ramp):
        t = min(max(target * mul, floor if i else 0.0), ceil)
        c = _chroma(base, sat[i])
        if i == 0:
            c = _mix(c, hi_to, hi_mix)
        elif i >= 2:
            c = _mix(c, DUSK, 0.10 * (i - 1))
        steps.append(set_luma(c, t))
    return [tuple(int(round(v)) for v in s) for s in steps]


def darken(rgb, f):
    return tuple(int(round(c * f)) for c in rgb)


def hue_of(rgb):
    """색상환 각도(도). 무채색이면 None — 돌릴 색상이 없다는 뜻이다."""
    r, g, b = (float(c) for c in rgb)
    mx, mn = max(r, g, b), min(r, g, b)
    if mx - mn < 10.0:
        return None
    if mx == r:
        h = 60.0 * (((g - b) / (mx - mn)) % 6.0)
    elif mx == g:
        h = 60.0 * ((b - r) / (mx - mn) + 2.0)
    else:
        h = 60.0 * ((r - g) / (mx - mn) + 4.0)
    return h % 360.0


def hue_gap(a, b):
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


def pants_color(cloth_rgb):
    """옷색 → 바지색. **명도가 아니라 색상을 옮기는 게 요점이다.**

    옷색이 이미 흙빛이면(주홍·흙색) 흙빛 바지는 상의와 붙어 보이므로 데님으로
    간다. 명도는 여기서 정하지 않는다 — `bands_for()` 의 목표 명도가 정한다.
    """
    h = hue_of(cloth_rgb)
    warm = hue_of(PANTS_WARM)
    anchor = PANTS_COOL if (h is not None and hue_gap(h, warm) < PANTS_NEAR) else PANTS_WARM
    return tuple(int(round(v)) for v in _mix(anchor, cloth_rgb, PANTS_MIX))


def blush_color(skin_rgb):
    """볼 홍조 — 피부색에 장미빛을 섞고 살짝 어둡게. 피부 램프와 겹치지 않는다."""
    return tuple(int(round(v)) for v in
                 set_luma(_mix(skin_rgb, (214, 92, 96), 0.42), max(luma(skin_rgb) * 0.93, 74.0)))


# ── 재질별 **기본 단계 목표 명도**(=밴드) ─────────────────────────────────
# 이 값들이 "옷과 바지가 한눈에 구분되는가"를 혼자 결정한다. 두 부류를 다르게 다룬다:
#
#  * **옷 계열(shirt/pants/boot)은 옷색 하나에서 세 재질이 갈라져 나온다.** 그래서
#    계단을 코드가 보장해야 한다 — 셔츠 명도를 정하고 바지/신발은 그 비율로 내린다.
#    (#8 은 "옷색 × 0.46" 식이라 옷색에 따라 상의와 값이 겹치거나 신발이 잉크보다
#    어두워졌다.)
#  * **피부/머리는 플레이어가 고른 색의 명도가 곧 의미다** — 금발은 밝고 검정은
#    어둡다. 여기에 고정 밴드를 못박으면 커스터마이징이 통째로 무의미해진다
#    (실제로 한 번 그렇게 만들었더니 은발도 가장 짙은 피부도 전부 같은 값으로
#    나왔다). 그래서 **하한만** 준다.
SHIRT_GAIN = 1.45           # 옷색 명도 → 셔츠 명도
SHIRT_RANGE = (138.0, 168.0)
PANTS_RATIO = 0.70          # 셔츠 대비 — 이 비율이 상하의를 가르는 계단이다
BOOT_RATIO = 0.45
SKIN_MIN = 88.0             # 가장 짙은 피부도 이 아래로는 안 내려간다(형태가 안 읽힌다)
HAIR_MIN = 56.0             # 검정 머리는 색이 아니라 광택 단차로 읽힌다 — 램프를
                            # 띄울 자리가 필요하다


def bands_for(skin_rgb, hair_rgb, cloth_rgb):
    """커스터마이징 색 3개 → 재질별 목표 명도."""
    shirt = min(max(luma(cloth_rgb) * SHIRT_GAIN, SHIRT_RANGE[0]), SHIRT_RANGE[1])
    return {
        "skin": max(luma(skin_rgb), SKIN_MIN),
        "hair": max(luma(hair_rgb), HAIR_MIN),
        "shirt": shirt,
        "pants": shirt * PANTS_RATIO,
        "boot": shirt * BOOT_RATIO,
    }


def palette(skin=BASE_SKIN, hair=BASE_HAIR, cloth=BASE_CLOTH, bands=None):
    """커스터마이징 색 3개 → 재질별 램프. 이 함수만 갈아끼우면 색 확장이 끝난다."""
    skin_rgb, hair_rgb, cloth_rgb = _hex(skin), _hex(hair), _hex(cloth)
    band = dict(bands_for(skin_rgb, hair_rgb, cloth_rgb), **(bands or {}))
    return {
        # 피부는 밝은면을 세게 주면 표백돼 보인다 — 밝은면 혼합을 낮게.
        "skin": make_ramp(skin_rgb, band["skin"], hi_mix=0.14, sat=(0.88, 1.0, 1.20, 1.32),
                          ramp=(1.16, 1.0, 0.82, 0.66)),
        # 머리는 차가운 밝은면 + 넓은 램프. 검정 머리는 색이 아니라 **광택 단차**로
        # 읽힌다 — 램프를 좁히면 통째로 검은 덩어리가 된다.
        # **어떤 재질도 잉크보다 어두워지지 않는다** — 검은 머리라도 그 아래로
        # 내려가면 외곽선에 먹혀서 머리가 통째로 구멍이 된다(#8 이 그랬다).
        # 대신 램프를 넓게 잡아 **광택 단차**로 검은 머리의 형태를 만든다.
        "hair": make_ramp(hair_rgb, band["hair"], hi_to=COOL, hi_mix=0.22,
                          ramp=(1.52, 1.0, 0.78, 0.62), floor=HAIR_FLOOR),
        "shirt": make_ramp(cloth_rgb, band["shirt"], hi_mix=0.26),
        # 바지·신발은 **색상을 옮긴** 바지색에서 나온다(`pants_color()`). 둘은 같은
        # 계열이고(신발이 바지와 따로 놀면 발만 떠 보인다) 목표 명도로 갈린다.
        "pants": make_ramp(pants_color(cloth_rgb), band["pants"], hi_mix=0.14),
        "boot": make_ramp(pants_color(cloth_rgb), band["boot"], hi_mix=0.12,
                          ramp=(1.30, 1.0, 0.88, 0.80)),
        # 도구 2종은 **커스터마이징 색을 보지 않는다** — 어떤 외형을 골라도 도끼는
        # 같은 도끼다. 그래서 `bands_for()` 를 거치지 않고 고정 밴드를 쓴다.
        "helve": make_ramp(HELVE, HELVE_BAND, hi_mix=0.20),
        "blade": make_ramp(BLADE, BLADE_BAND, hi_to=COOL, hi_mix=0.30,
                           sat=(0.80, 1.0, 1.10, 1.20)),
        # 볼 홍조는 단계가 하나다 — 1~2px 이라 램프를 줘봐야 쓸 자리가 없다.
        "blush": [blush_color(skin_rgb)],
        "eye": [INK] * 4,
        "glint": [GLINT] * 4,
    }


# ── 좌표 격자 (네이티브 단위, 슈퍼샘플 해상도) ──────────────────────────────
_yy, _xx = np.mgrid[0:H, 0:H].astype(np.float32)
GX = (_xx + 0.5) / SS
GY = (_yy + 0.5) / SS


ROUND = 0.55    # 덩어리를 얼마나 둥글게 볼 것인가 (높이 = ROUND × 반지름)


def ellipsoid(cx, cy, rx, ry, squash=None):
    """구/타원체. 반환: (마스크, 높이)

    **높이를 반지름에 비례시키는 게 핵심이다.** 높이를 1 로 고정하면 가운데가
    거의 평평한 얇은 판이 되어, 조명이 테두리에만 걸린 "납작한 도트"가 나온다.
    """
    if squash is None:
        squash = ROUND * min(rx, ry)
    dx = (GX - cx) / rx
    dy = (GY - cy) / ry
    d2 = dx * dx + dy * dy
    m = d2 <= 1.0
    h = np.sqrt(np.clip(1.0 - d2, 0, 1)) * squash
    return m, h * m


def rbox(x0, y0, x1, y1, r=1.2, dome=None, axis="x"):
    """둥근 모서리 상자. 한 축으로만 부푼 원기둥 느낌의 높이장."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hw, hh = (x1 - x0) / 2, (y1 - y0) / 2
    r = min(r, hw - 1e-3, hh - 1e-3)
    if dome is None:
        dome = ROUND * (hw if axis == "x" else hh)
    qx = np.abs(GX - cx) - (hw - r)
    qy = np.abs(GY - cy) - (hh - r)
    d = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
    m = d <= 0
    if axis == "x":
        t = np.clip(np.abs(GX - cx) / max(hw, 1e-6), 0, 1)
    else:
        t = np.clip(np.abs(GY - cy) / max(hh, 1e-6), 0, 1)
    h = np.sqrt(np.clip(1 - t * t, 0, 1)) * dome
    return m, h * m


def capsule(x0, y0, x1, y1, r0, r1=None, dome=None):
    """두 점을 잇는 **아무 각도나 되는** 둥근 막대. 굵기는 r0 → r1 로 변한다.

    `rbox`/`_fall_shape` 는 축에 붙어 있어서(세로로만 흐른다) 비스듬한 도구 자루를
    못 만든다. 도구는 방향마다 기울기가 다르므로 이 원시 도형이 필요하다 —
    **앞으로 붙는 도구 6종(총열·곡괭이 자루·낚싯대)도 이걸 쓴다.**

    높이는 축에서 멀어질수록 낮아지는 원기둥이라 가운데가 밝고 양옆이 그늘진다 —
    머리 껍데기·팔과 같은 입체감이라 도구만 납작해 보이지 않는다.
    """
    if r1 is None:
        r1 = r0
    dx, dy = x1 - x0, y1 - y0
    t = np.clip(((GX - x0) * dx + (GY - y0) * dy) / max(dx * dx + dy * dy, 1e-6), 0.0, 1.0)
    d = np.hypot(GX - (x0 + t * dx), GY - (y0 + t * dy))
    r = r0 + (r1 - r0) * t
    m = d <= r
    # `dome` 을 주면 높이를 굵기에서 떼어낸다 — **가늘면서도 볼록한** 막대를
    # 만들 때 쓴다(곡괭이 갈래). 굵기로만 높이를 정하면 가는 쇠붙이가 납작해져서
    # 옆에 붙은 나무 자루와 명도가 같아진다(`qa_sprite_check.py` 「대비」).
    h = (np.sqrt(np.clip(1.0 - (d / np.maximum(r, 1e-6)) ** 2, 0, 1))
         * (ROUND * max(r0, r1) if dome is None else dome))
    return m, h * m


def wedge(x0, y0, x1, y1, h0, h1, bulge=0.0):
    """축을 따라 **넓어지다가 끝이 잘리는** 쐐기. 도끼날처럼 "날 선 끝"이 필요한
    도구에 쓴다 (`capsule` 과 달리 끝이 둥근 뚜껑이 아니다).

    `capsule` 로 날을 만들면 바깥 끝이 **반원**이라 도끼가 아니라 **망치**로 읽힌다
    (실제로 첫 후보가 그랬다 — 17px 에서 도끼날은 몇 px 뿐이라 그 반원이 전부다).
    여기서는 축 방향 `t` 를 1 에서 끊어 **날(bit)이 곧은 변**으로 남는다.

    `bulge` 는 그 변을 가운데만 볼록하게 민다 — 실제 벌목 도끼의 날이 활처럼
    휜 것이고, 완전히 곧으면 이 크기에서 **벽돌**로 보인다.

    높이는 `capsule` 과 같은 원기둥 단면이라 도구끼리 입체감이 어긋나지 않는다.
    **앞으로 붙는 도구 6종 중 날붙이(낫·곡괭이 끝)도 이걸 쓴다.**
    """
    dx, dy = x1 - x0, y1 - y0
    l2 = max(dx * dx + dy * dy, 1e-6)
    t = ((GX - x0) * dx + (GY - y0) * dy) / l2
    perp = ((GX - x0) * (-dy) + (GY - y0) * dx) / np.sqrt(l2)
    half = h0 + (h1 - h0) * np.clip(t, 0.0, 1.0)
    q = np.abs(perp) / np.maximum(half, 1e-6)
    m = (t >= 0) & (q <= 1.0) & (t <= 1.0 + bulge * np.clip(1.0 - q * q, 0, 1))
    h = np.sqrt(np.clip(1.0 - q * q, 0, 1)) * (ROUND * max(h0, h1))
    return m, h * m


def crescent(cx, cy, r, dx, dy, r2, dome=None):
    """원에서 **어긋나게 겹친 원을 도려낸** 초승달. 낫날처럼 "휜 날붙이"에 쓴다.

    `capsule` 토막을 베지에를 따라 이어 붙이는 쪽으로도 곡선은 나오지만, 17px 에서
    그건 **굵기가 일정한 철사**로 읽힌다(실제로 그렇게 나왔다) — 날처럼 보이려면
    바깥은 볼록하고 안쪽은 오목해서 **가운데가 두껍고 양끝이 뾰족해야** 한다.
    두 원의 차집합이 그 형태를 공짜로 준다.

    높이는 **두 경계까지의 거리 중 작은 쪽**으로 잡는다 — 초승달의 한가운데를 따라
    능선이 서고 양끝으로 갈수록 낮아진다. 바깥 원 중심을 기준으로 잡으면 그 중심이
    도려낸 쪽에 있어서 날 전체가 한쪽으로 기울어 납작해진다.
    """
    d1 = np.hypot(GX - cx, GY - cy)
    d2 = np.hypot(GX - (cx + dx), GY - (cy + dy))
    m = (d1 <= r) & (d2 >= r2)
    w = np.minimum(r - d1, d2 - r2)                  # 가까운 쪽 경계까지의 거리
    t = max(r - np.hypot(dx, dy) + r2, 1e-6) * 0.5   # 초승달의 가장 두꺼운 곳의 절반
    if dome is None:
        dome = ROUND * r
    h = np.sqrt(np.clip(w / t, 0, 1)) * dome
    return m, h * m


def head_shape(cx, cy, rx, ry, p_top=1.6, p_bot=2.4, squash=None):
    """치비 머리 — 정수리는 좁고 **턱은 넓은** 달걀. (마스크, 높이)

    **완전한 원을 쓰지 않는다**(2026-09-06, INBOX #13). 지름 14px 짜리 원은 옆선이
    7~8줄 내리 정확히 같은 자리에 놓여서 — 원의 가운데는 거의 수직이다 — 실루엣이
    각져 보인다(`qa_sprite_check.py` 「각짐」). 위아래 지수를 따로 준다:
      `p_top` < 2  정수리가 좁아지고 옆선이 매 줄 조금씩 움직인다
      `p_bot` > 2  턱이 넓게 남는다. 아래도 2 미만으로 하면 **턱이 뾰족해져서
                   목처럼 보인다**(실제로 한 번 그렇게 나왔다)
    """
    t = np.clip((GY - cy) / ry, -1.0, 1.0)
    at = np.abs(t)
    p = np.where(t < 0, p_top, p_bot)
    w = rx * np.power(np.clip(1.0 - np.power(at, p), 0, 1), 1.0 / p)
    dx = np.abs(GX - cx)
    m = (dx <= w) & (np.abs((GY - cy) / ry) < 1.0)
    if squash is None:
        squash = ROUND * min(rx, ry)
    # 높이는 (초타원이 아니라) 타원체로 잡는다 — 실루엣 안쪽에서 매끄러운 돔이 된다.
    h = np.sqrt(np.clip(1.0 - (dx / rx) ** 2 - t * t, 0, 1)) * squash
    return m, h * m


def below(curve):
    """y <= curve(x) 인 영역. 머리카락 앞머리를 비스듬히 자를 때 쓴다."""
    return GY <= curve


class Build:
    """재질 id / 높이장 / 부위 id 를 페인터 순서로 쌓는다.

    부위 id 를 따로 두는 이유: 팔과 몸통은 같은 'shirt' 재질이라 재질만으로는
    경계가 사라진다. 도트에서는 그 경계에 한 단계 어두운 내부선을 넣어야 형태가
    읽힌다 — 그 판정에 부위 id 를 쓴다.
    """

    def __init__(self):
        self.mat = np.full((H, H), -1, dtype=np.int8)
        self.hgt = np.zeros((H, H), dtype=np.float32)
        self.part = np.full((H, H), -1, dtype=np.int16)
        self._n = 0

    def add(self, shape, mat, mask=None, part=None, lift=0.0, blend="over"):
        """`mask` 로 도형 일부만, `part` 로 앞서 그린 부위와 같은 덩어리로 묶는다.

        `lift` 는 높이장을 통째로 올린다 — 앞머리처럼 얼굴보다 앞으로 나와야
        하는 것에 쓴다(같은 높이면 조명이 이어져서 경계가 사라진다).

        `blend="max"` 는 실루엣만 넓히고 이미 더 높은 곳은 건드리지 않는다.
        같은 덩어리에 작은 혹을 덧붙일 때(헤어라인 물결) 이걸 써야 한다 — "over"
        로 덮으면 덩어리 안쪽의 높은 부분이 혹의 낮은 높이로 눌려서 평평해진다.
        """
        m, h = shape
        if mask is not None:
            m = m & mask
        if part is None:
            self._n += 1
            part = self._n
        self.mat[m] = MATS.index(mat)
        if blend == "max":
            self.hgt[m] = np.maximum(self.hgt[m], h[m] + lift)
        else:
            self.hgt[m] = h[m] + lift
        self.part[m] = part
        return part


def light(hgt, mat, key=0.62, amb=0.42, rim=0.18):
    """높이장의 기울기로 법선을 만들고 램버트 + 환경광으로 명도를 낸다."""
    gy, gx = np.gradient(hgt.astype(np.float32), 1.0 / SS)
    nz = np.ones_like(hgt)
    nl = np.sqrt(gx * gx + gy * gy + nz * nz)
    nx, ny, nz = -gx / nl, -gy / nl, nz / nl

    L = np.array([-0.55, -0.68, 0.49], dtype=np.float32)   # 왼쪽 위 앞 (광원 고정)
    L /= np.linalg.norm(L)
    lam = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)

    lum = np.clip(key * lam + amb + rim * np.clip(nz, 0, 1), 0, 1)
    lum[mat < 0] = 0
    return lum


def _blocks(a):
    return a.reshape(N, SS, N, SS).transpose(0, 2, 1, 3).reshape(N, N, SS * SS)


def downsample_part(part):
    """부위 id 는 최빈값으로 줄인다(평균이 의미 없는 라벨이므로)."""
    p4 = _blocks(part)
    out = np.full((N, N), -1, dtype=np.int16)
    best = np.zeros((N, N), dtype=np.int32)
    for v in np.unique(part):
        if v < 0:
            continue
        cnt = (p4 == v).sum(axis=2)
        win = cnt > best
        best = np.where(win, cnt, best)
        out = np.where(win, v, out)
    return out


def downsample(mat, lum, cover=0.55):
    """네이티브 해상도로 줄인다. 재질은 최빈값, 명도는 평균."""
    m4 = _blocks(mat)
    l4 = _blocks(lum)

    best = np.zeros((N, N), dtype=np.int32)
    best_i = np.full((N, N), -1, dtype=np.int32)
    for i in range(len(MATS)):
        cnt = (m4 == i).sum(axis=2)
        win = cnt > best
        best = np.where(win, cnt, best)
        best_i = np.where(win, i, best_i)
    # 절반 이상이 비어있으면 그 칸은 비운다(가장자리가 지저분해지지 않게)
    empty = (m4 < 0).sum(axis=2) > (SS * SS * cover)
    out_m = np.where(empty, -1, best_i).astype(np.int8)

    out_l = np.zeros((N, N), dtype=np.float32)
    for i in range(len(MATS)):
        sel = m4 == i
        cnt = sel.sum(axis=2)
        s = (l4 * sel).sum(axis=2)
        take = (out_m == i) & (cnt > 0)
        out_l[take] = (s / np.maximum(cnt, 1))[take]
    return out_m, out_l


def quantize(mat, lum, pal, dither=0.0):
    """재질별 4단계 램프로 떨어뜨린다. 단계 사이는 Bayer 순서 디더링."""
    rgb = np.zeros((N, N, 4), dtype=np.uint8)
    by = np.tile(BAYER4, (N // 4 + 1, N // 4 + 1))[:N, :N]
    for i, name in enumerate(MATS):
        ramp = np.array(pal[name], dtype=np.uint8)
        sel = mat == i
        if not sel.any():
            continue
        t = np.clip(1.0 - lum, 0, 1) * (len(ramp) - 1)
        d = 0.0 if name in ("eye", "glint") else (by - 0.5) * dither
        idx = np.clip(np.floor(t + d), 0, len(ramp) - 1).astype(np.int32)
        rgb[sel] = np.concatenate(
            [ramp[idx][sel], np.full((int(sel.sum()), 1), 255, np.uint8)], axis=1)
    return rgb


def inner_lines(rgb, mat, part, pal, skip=None):
    """다른 부위와 맞닿은 안쪽 픽셀을 한 단계 어둡게 해서 경계를 살린다.

    팔과 몸통은 같은 'shirt' 재질이라 음영만으로는 경계가 사라진다. 바깥
    외곽선처럼 잉크로 긋지 않고 **그 재질 램프의 가장 어두운 색**을 쓰는 게
    핵심이다 — 잉크로 그으면 캐릭터가 조각조각 잘려 보인다.

    **같은 재질끼리 맞닿은 자리에만 긋는다**(2026-09-07, INBOX #19). 재질이
    다르면 램프가 이미 갈라놓았는데 거기까지 한 단계 더 어둡게 하면, 17px 에서는
    바지도 신발도 두 줄뿐이라 **그 중 한 줄이 통째로 가장 어두운 단계**가 되어
    줄무늬 양말처럼 보인다. 34px 때는 한 줄이 1/4 이라 티가 안 났다.

    `skip` 은 **덩어리가 아니라 나중에 칠한 줄무늬**(허리띠)다. 그런 자리는 내부선을
    받지도 만들지도 않는다 — 허리띠는 이미 가장 어두운 단계인데, 그 아래 허벅지
    줄까지 같은 재질(바지)이라 통째로 한 단계 더 어두워져서 허리 아래가 검은 띠
    두 줄이 됐다(2026-09-07, INBOX #20 — 걷기에서 손이 허리띠 줄을 비우자 드러났다).
    """
    filled = (mat >= 0) if skip is None else ((mat >= 0) & ~skip)
    p = part
    # 광원이 왼쪽 위이므로 그늘은 경계의 **오른쪽/아래** 픽셀에 떨어진다.
    # (반대쪽에 찍으면 밝은 면에 선이 그어져서 형태가 거꾸로 읽힌다.)
    # **재질까지 같은 경계에만** 긋는다 — 방향마다 따로 봐야 한다(가로는 같은
    # 재질인데 세로는 다른 재질인 자리가 실제로 있다: 턱 아래 상의의 맨 윗줄).
    diff = np.zeros((N, N), dtype=bool)
    diff[:, 1:] |= (filled[:, :-1] & filled[:, 1:] & (p[:, :-1] != p[:, 1:])
                    & (mat[:, :-1] == mat[:, 1:]))
    diff[1:, :] |= (filled[:-1, :] & filled[1:, :] & (p[:-1, :] != p[1:, :])
                    & (mat[:-1, :] == mat[1:, :]))
    for i, name in enumerate(MATS):
        if name in ("eye", "glint"):
            continue
        sel = diff & (mat == i)
        if sel.any():
            rgb[sel] = np.concatenate([np.array(pal[name][-1], np.uint8), [255]])
    return rgb


def outline(rgb, mat):
    """칠해진 영역 바깥에 1px 잉크 테두리."""
    filled = mat >= 0
    pad = np.pad(filled, 1, constant_values=False)
    near = (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:])
    edge = near & ~filled
    rgb[edge] = np.concatenate([np.array(INK, np.uint8), [255]])
    return rgb


# ── 캐릭터 정의 ────────────────────────────────────────────────────────────
# 비율 (2026-09-07, INBOX #19 — 17px 캔버스에서 다시 잡았다. 옛 34px 값을 반으로
# 나눈 게 아니라 격자 위에서 후보를 비교해 고른 값이다):
#   머리 1~6(6px, 전체 14px 의 43%) / 몸통 7~9 / 허리띠 10 / 다리 11~12 / 신발 13~14
# 사람 피드백대로 **머리를 47%→43% 로 낮추고 다리를 23%→21% 로 줄였다**. 몸통은
# 5px→3px 로 오히려 짧아졌다(비율만 오른다 — 총 높이가 30px→14px 이라서다).
# **머리(폭 8)가 어깨+팔(폭 6)보다 넓다** — 이게 치비의 핵심이고,
# `qa_sprite_check.py` 의 「비율」이 숫자로 지킨다.
CFG = dict(
    head_rx=4.3, head_ry=3.0, head_cy=4.0, head_p=1.6, head_pb=2.05, head_puff=0.0,
    torso_w=5.2, torso_top=6.6, torso_bot=11.0,
    side_torso_w=4.4,
    arm_w=1.5,
    arm_slant=0.32, arm_taper=0.22, leg_taper=0.28, toe=0.65, heel=0.6,
    foot_out=0.2, side_arm=1.0,
    belt=True, limb_shade=0.16, contact=0.18, cuff=0.0, collar=0.0,
    torso_r=0.7, ears=0, arm_in=0.55, shoe_lip=0.34,
    fringe=3.7, fringe_tilt=0.0, side_hair=5.6,
    eye_y=4, eye_dx=1.6, eye_style="bar", glint=False, blush=True,
    hair_shine=0.18,
    leg_top=10.3, foot_y=15.0, boot_h=2.0,
    dither=0.0, key=0.84, amb=0.17, rim=0.10,
    # ── 걷기(walk) ── **2026-09-07 (INBOX #20) 에 17px 격자 위에서 다시 잡았다.**
    # 옛 34px 값을 반으로 나눈 게 아니라, 후보를 여러 개 구워 검사(「이어짐」)를
    # 통과하는 범위 안에서 눈으로 골랐다. idle 은 `walk_pose(phase=None)` 이라
    # 이 값들을 하나도 안 쓴다.
    bob=0.0,            # **17px 에서는 몸을 가라앉히지 않는다.** 아래 `walk_pose()` 참고
    lift=1.45,          # 뒤에서 앞으로 넘어오는 발이 뜨는 높이(통과 자세에서 최대).
                        # 다리가 세 줄뿐이라 1.5 를 넘기면 든 발의 다리가 사라진다
    stride=1.6,         # 옆모습에서 다리가 앞뒤로 벌어지는 폭. 1.7 부터는 한 프레임에
                        # 바뀌는 몸 픽셀이 상한(0.30)을 넘어 순간이동으로 잡힌다
    stride_f=0.7,       # 앞/뒷모습 — 뜬 발을 안쪽으로 당기는 폭
    arm_swing=1.1,      # 옆모습 팔 앞뒤 폭 (다리와 반대 위상)
    arm_swing_f=0.85,   # 앞/뒷모습 팔 — 앞으로 나오면 짧아 보이므로 위아래로
    stance_drag=0.55,   # 옆모습 — 딛은 발이 몸 아래에서 뒤로 끌리는 폭
)

# 옷에 넣는 포인트(허리띠 / 옷깃 / 소맷부리). **17px 에서는 하나까지다**
# (2026-09-07, INBOX #19 — 34px 때는 1~2개였다). 상의가 세 줄뿐이라 옷깃과
# 허리띠를 같이 넣으면 가운데 한 줄만 남아 옷이 포인트로 꽉 찬다.
# 남긴 하나는 **허리띠**다 — 허리선이 곧 "다리가 시작하는 줄"이라 비율 검사
# (`qa_sprite_check.py` 「비율」)가 몸통과 다리를 여기서 가른다.
# `qa_sprite_check.py` 「옷포인트」가 이 함수로 개수를 센다.
CLOTH_ACCENTS = ("belt", "collar", "cuff")


def cloth_accents(cfg=None):
    """지금 켜져 있는 옷 포인트 이름들."""
    cfg = cfg or CFG
    return [k for k in CLOTH_ACCENTS if cfg.get(k)]


WALK_FRAMES = 6         # DESIGN.md 「캐릭터 애니메이션」의 4~6 프레임 규칙


def walk_phases(frames=WALK_FRAMES):
    """걷기 한 바퀴를 프레임 수로 나눈 위상들.

    **0 부터 고르게 뽑는다.** 반 칸 밀어서(`+0.5`) 뽑는 쪽도 해봤는데, 6프레임에서
    cos 이 ±0.87, 0, ∓0.87, ∓0.87, 0, ±0.87 이 되어 **가운데 두 프레임이 서로
    거의 같은 그림**이 된다(발을 든 높이만 다르다). 그러면 여섯 장 중 넉 장만
    쓰는 셈이라, 남은 네 자리에서 한 번에 크게 건너뛰어 걷기가 뚝뚝 끊긴다 —
    `qa_sprite_check.py` 「이어짐」이 이걸 숫자로 잡는다(변화량 0.55/0.53/**0.09**
    /0.53/0.54/**0.08**). 0 부터 뽑으면 cos 이 1, ½, -½, -1, -½, ½ 이라
    여섯 자세가 전부 다르고 변화량도 고르다(0.33/0.13/0.30/0.29/0.13/0.31).
    """
    return [i / frames for i in range(frames)]


def walk_pose(direction, phase, cfg):
    """걷기 위상(0~1) → 부위별 오프셋. `phase=None` 이면 idle(전부 0).

    한 바퀴를 이렇게 잡았다 — 이 위상 관계가 어긋나면 걷기로 안 보인다:
      - `cos` 로 다리를 앞뒤로 흔든다. 착지(cos=±1)에서 가장 벌어지고,
        통과 자세(cos=0)에서 두 다리가 거의 겹친다(옆모습).
      - **17px 에서는 몸을 가라앉히지 않는다**(`bob=0`, 2026-09-07 INBOX #20).
        34px 때는 착지마다 1px 내렸는데, 도트에서 내릴 수 있는 최소 단위가 1px 이라
        캔버스가 절반이 되면 **같은 1px 이 몸 높이의 1/14** 이 된다 — 목이 사라지고
        머리가 어깨에 얹혀서 튀는 게 아니라 **주저앉는** 것으로 보인다. 다리도
        세 줄뿐이라 몸만 내려가면 그 중 한 줄을 잃는다. 위아래 움직임은 대신
        **발이 뜨는 것**(`lift`)이 맡는다.
      - **발이 뜨는 건 뒤에서 앞으로 넘어오는 동안뿐이다**(sin 의 한쪽 반주기).
        양발이 동시에 뜨면 뛰는 것처럼 보인다.
      - 팔은 다리와 **반대 위상**이다.
    """
    if phase is None:
        return dict(bob=0.0, side_merge=0.0, leg_dx=(0.0, 0.0), leg_lift=(0.0, 0.0),
                    arm_dx=(0.0, 0.0), arm_dy=(0.0, 0.0))
    t = 2.0 * np.pi * float(phase)
    sw = float(np.cos(t))                       # +1 = 왼다리가 앞
    sn = float(np.sin(t))
    # **발을 드는 곡선은 sin 그대로가 아니라 제곱이다.** sin 그대로면 착지
    # 자세에서도 발이 절반쯤 떠 있어서 두 발이 같이 땅에 닿는 프레임이 한 번도
    # 없다 — 걷는 게 아니라 제자리 행진으로 보인다. 제곱하면 통과 자세에서만
    # 확실히 뜨고 나머지는 거의 땅에 붙는다.
    lift = (max(0.0, -sn) ** 2 * cfg["lift"], max(0.0, sn) ** 2 * cfg["lift"])
    # **몸이 가라앉는 깊이는 정수 픽셀로 끊는다.** 0.6px 처럼 어중간하게 내리면
    # 머리·몸통은 반 칸만 내려가는데 눈은 격자에 찍히느라 한 칸 내려가서, 눈의
    # 아랫줄이 턱/옆머리로 밀려 3×3 이 2줄로 깎인다(실제로 단발 시트가 그랬다).
    # 도트에서 몸통이 반 칸 움직이면 음영도 매 프레임 다시 양자화되어 어른거린다.
    bob = float(round(cfg["bob"] * abs(sw)))
    if direction in ("left", "right"):
        sx = 1.0 if direction == "right" else -1.0
        return dict(
            bob=bob,
            # `side_merge=1` 은 **두 다리를 한 자리에 포갠 뒤 앞뒤로만 벌린다**는 뜻이다.
            # idle 처럼 좌우로 벌려 둔 채 흔들면 한쪽 착지에서 두 다리가 정확히 겹치고
            # 반대쪽 착지에서만 벌어져서, 한 걸음은 있고 한 걸음은 없는 절뚝이 된다.
            side_merge=1.0,
            # **땅을 딛고 있는 발은 몸 아래에서 뒤로 끌린다**(`stance_drag`).
            # 제자리 걷기라 몸이 안 나가므로, 딛은 발이 뒤로 밀려야 앞으로 걷는
            # 것으로 보인다. 이게 없으면 통과 자세에서 두 다리가 정확히 겹쳐
            # 실루엣이 폭 3px 짜리 **곧은 기둥 하나**가 되고(옆선 9줄 —「각짐」),
            # 걷는 게 아니라 외다리로 미끄러지는 것처럼 보인다.
            # `1 - 든 높이/최대` 라 딛은 발에만 걸리고, 두 다리가 반 바퀴마다
            # 역할을 맞바꾸므로 좌우 착지는 그대로 대칭이다.
            leg_dx=tuple((sw * cfg["stride"] * (1 if i == 0 else -1)
                          - cfg["stance_drag"] * (1.0 - lift[i] / max(cfg["lift"], 1e-6))) * sx
                         for i in (0, 1)),
            leg_lift=lift,
            arm_dx=(-sw * cfg["arm_swing"] * sx,) * 2,
            arm_dy=(0.0, 0.0),
        )
    # 앞/뒷모습은 다리를 `cos` 으로 좌우로 흔들면 안 된다 — 한쪽 착지에서 두 다리가
    # 모이고 반대쪽 착지에서 벌어져서 **제자리 뜀뛰기**가 된다(두 착지가 대칭이
    # 아니다). 앞뒤 움직임은 어차피 안 보이므로, **뜬 발만 안쪽으로 조금 당긴다** —
    # 앞으로 나온 발이 짧아 보이는 만큼이다. 그러면 두 착지가 저절로 대칭이 된다.
    pull = tuple(cfg["stride_f"] * v / max(cfg["lift"], 1e-6) for v in lift)
    return dict(
        bob=bob,
        side_merge=0.0,
        leg_dx=(pull[0], -pull[1]),
        leg_lift=lift,
        # 앞/뒷모습에서 앞으로 나온 팔은 짧아 보인다 — **위아래로만** 흔든다.
        # 손을 좌우로도 흔들어봤는데, 손이 허벅지 옆선과 같은 자리에 오는 프레임이
        # 생겨서 몸 옆선이 7px 곧게 이어졌다(「각짐」). 위아래만으로도 상체가
        # 정지해 보이지 않는다.
        arm_dx=(0.0, 0.0),
        arm_dy=(sw * cfg["arm_swing_f"], -sw * cfg["arm_swing_f"]),
    )


def _body(b, d, cfg, pose):
    """다리/몸통/팔 — 방향에 따라 어깨 너비와 팔 배치만 달라진다.

    `pose` 는 `walk_pose()` 가 준 오프셋이다. **형태 정의는 프레임마다 다시
    쓰지 않는다** — 같은 함수에 좌표만 흔들어 넣어야 프레임 사이 크기·자세가
    어긋나지 않는다(DESIGN.md 「캐릭터 애니메이션」).
    """
    side = d in ("left", "right")
    sx = 1.0 if d == "right" else -1.0
    cx = 8.5 + (0.25 * sx if side else 0.0)
    tw = cfg["side_torso_w"] if side else cfg["torso_w"]
    bob = pose["bob"]
    top, bot = cfg["torso_top"] + bob, cfg["torso_bot"] + bob

    # 다리 — 사이를 조금 비워 두면 외곽선이 그 틈에 들어가 두 다리로 읽힌다.
    # 옆모습은 두 다리가 거의 겹치므로 간격을 좁히고 앞뒤(x)로만 벌린다.
    lw = 1.9 if not side else 1.7
    gap = 0.35 if not side else 0.0
    # 옆모습으로 걸을 때만 두 다리를 한 자리로 모은다(`side_merge`) — 그래야 앞뒤
    # 착지가 좌우 대칭이 된다. idle 은 0 이라 #13 에서 확정된 서 있는 자세 그대로다.
    spread = (lw / 2 + gap) * (1.0 - pose["side_merge"])
    far = []
    # **먼 쪽 다리(1번)를 먼저 그린다** — 나중에 그린 것이 위를 덮으므로, 순서를
    # 안 뒤집으면 뒤쪽 다리가 앞쪽 다리를 가려서 실루엣이 조각조각 끊겨 보인다.
    order = [(1, 1), (0, -1)] if pose["side_merge"] else [(0, -1), (1, 1)]
    for i, sgn in order:
        lx = cx + sgn * spread                 # 엉덩이(다리가 붙은 자리) — 안 움직인다
        step = pose["leg_dx"][i]               # 발이 그 아래에서 얼마나 벗어나는가
        foot = cfg["foot_y"] - pose["leg_lift"][i]
        # 다리도 **허벅지에서 발목으로 가늘어진다** — 폭이 일정한 상자면 옆선이
        # 다리 길이만큼 곧은 직선이 된다(「각짐」).
        ankle = lw / 2 - cfg["leg_taper"]
        # **다리는 통째로 옮기지 않고 엉덩이에서 꺾는다**(`slant`). 통째로 옮기면
        # 엉덩이가 몸통 밖으로 빠져나가고, 무엇보다 다리 옆선이 그 길이만큼 완전한
        # 수직선으로 남는다(「각짐」) — 걷는 동안 서 있는 다리도 기둥으로 보인다.
        leg = b.add(_fall_shape(lx, lw / 2, cfg["leg_top"] + bob, foot - cfg["boot_h"] + 0.2,
                                taper=cfg["leg_taper"], tip=0.35, slant=step), "pants")
        # 옆모습 신발은 **보는 쪽으로 코가 나온다** — 안 그러면 다리부터 발끝까지
        # 앞선이 한 줄로 곧게 이어진다. 뒤꿈치도 조금 나와야 한다(`heel`) —
        # 안 나오면 이번엔 **등 쪽 옆선**이 허리부터 발까지 곧게 이어진다
        # (2026-09-07, INBOX #19 — 17px 에서 그 구간이 5줄이었다).
        toe = cfg["toe"] * sx if side else 0.0
        heel = -cfg["heel"] * sx if side else 0.0
        # 앞/뒷모습 신발은 **발끝이 살짝 바깥으로** 벌어진다. 발목보다 넓어져서
        # 다리에서 발까지 곧게 이어지던 옆선이 거기서 한 칸 꺾인다(「각짐」).
        out = (0.0 if side else sgn * cfg["foot_out"]) + step
        shoe = b.add(rbox(lx + out - ankle - 0.25 + min(toe, heel), foot - cfg["boot_h"],
                          lx + out + ankle + 0.25 + max(toe, heel), foot, r=0.5), "boot")
        # 옆모습으로 걸으면 두 다리가 같은 자리에서 앞뒤로만 엇갈린다 — 색까지 같으면
        # 한 덩어리로 뭉쳐서 다리가 하나로 보인다. **먼 쪽 다리를 한 단계 어둡게** 해서
        # 앞뒤를 가른다. idle 은 두 다리가 좌우로 놓여 있어(`side_merge=0`) 해당 없다.
        if pose["side_merge"] and i == 1:
            far += [leg, shoe]

    # 목 (몸통보다 먼저 — 뒤로 간다). 짧다 — 치비는 목이 거의 없다.
    b.add(rbox(cx - 0.85, top - 1.2, cx + 0.85, top + 0.6, r=0.55), "skin")

    # 몸통
    b.add(rbox(cx - tw / 2, top, cx + tw / 2, bot, r=cfg["torso_r"]), "shirt")

    # 팔 — 몸통과 다른 부위 id 라서 경계에 내부선이 들어간다.
    # 팔은 몸통에 **살짝 파묻어야** 한다. 어깨 모서리가 둥근 만큼 바깥에 두면
    # 어깨 높이에서 몸통과 떨어져 팔만 붕 뜬 2px 조각이 된다.
    aw = cfg["arm_w"]
    off = tw / 2 + aw / 2 - cfg["arm_in"]
    xs = [sx * cfg["side_arm"]] if side else [-off, off]
    limbs = []
    hands = []                                  # 손끝 자리 — 도구를 여기에 쥐여준다
    for i, offx in enumerate(xs):
        ax = cx + offx                          # 어깨 — 다리와 같은 이유로 안 움직인다
        # **팔도 어깨에서 꺾는다 — `arm_dy` 는 손만 위아래로 움직인다**(2026-09-07,
        # INBOX #20). 어깨까지 같이 올리면 상의의 맨 윗줄이 한 줄 올라가서, 17px
        # 에서는 그것만으로 「비율」 검사의 머리 비율이 43% → 36% 로 떨어진다(머리가
        # 작아진 게 아니라 어깨가 올라간 것이다). 실제로도 걸을 때 어깨는 안 뜬다.
        arm_top = cfg["torso_top"] + 0.55 + bob
        arm_bot = cfg["torso_bot"] - 1.0 + bob + pose["arm_dy"][i]
        # 소매는 **어깨에서 손목으로 좁아지며 몸 쪽으로 기운다**(2026-09-06, INBOX #13).
        # 폭이 일정한 상자로 두면 옆선이 팔 길이만큼 완전한 수직선이 되어 각져
        # 보인다(`qa_sprite_check.py` 「각짐」). 기울이면 어깨가 자연스럽게 처진다.
        # 앞/뒷모습은 손목이 **몸 쪽으로**(어깨가 처져 보인다), 옆모습은 손목이
        # **앞쪽으로** 기운다 — 옆모습에서 뒤로 기울이면 팔·다리 앞선이 한 줄로
        # 곧게 이어져 버린다(「각짐」).
        # 팔도 어깨에서 꺾는다 — `pose["arm_dx"]` 는 **손이** 앞뒤로 나가는 폭이다.
        lean = (cfg["arm_slant"] * sx if side
                else -cfg["arm_slant"] * (1.0 if offx > 0 else -1.0)) + pose["arm_dx"][i]
        limbs.append(b.add(_fall_shape(ax, aw / 2, arm_top, arm_bot, taper=cfg["arm_taper"],
                                       tip=0.5, slant=lean), "shirt"))
        # 손은 벙어리장갑 모양 — 소매 끝에서 살짝 넓어진다
        limbs.append(b.add(ellipsoid(ax + lean, arm_bot + 0.5, 0.6, 0.58), "skin"))
        hands.append((ax + lean, arm_bot + 0.5))
    return limbs + far, hands


# ── 도구 (DESIGN.md 「새 도구를 추가하는 절차」) ────────────────────────────
# **도구는 캐릭터 옆에 아이콘으로 띄우지 않는다 — 프레임 자체에 그려 넣는다**
# (DESIGN.md 「캐릭터 애니메이션」의 못박힌 규칙). 그러면서도 **형태를 다시 정의하지
# 않는다**: 몸은 idle/걷기와 **같은 `character()`** 가 그리고, 도구는 그 결과로
# 나온 **손 자리에 얹기만** 한다(`_body()` 가 손 좌표를 돌려준다). 그래서 프레임
# 사이에서 캐릭터가 차지하는 크기가 어긋날 수가 없다.
#
# 값을 치르고 알아낸 것 — **다음 도구 6종도 여기서 출발한다**:
#  - **자루 길이는 4.6px 가 상한이다.** 그보다 길면 든 손 반대쪽으로 날이 넘어와서
#    얼굴을 덮거나(앞모습) 캔버스 밖으로 나간다(17px 은 좁다). 4.6 + 날 1.4 ≈ 6px
#    이라 화면에서 18px — `STYLE_GUIDE.md` 1번의 아트 6px 하한을 딱 지킨다.
#  - **자루는 비스듬해야 한다(68도).** 수직으로 세우면 실루엣 옆선이 자루 길이만큼
#    곧아져서 「각짐」에 걸린다. 기울이면 줄마다 한 칸씩 밀려서 곧은 구간이 3줄로 끊긴다.
#  - **날은 자루 끝에서 바깥(광원 반대쪽)으로 벌어지는 쐐기다.** 굵기가 일정한
#    막대로 붙이면 망치로 보인다 — `capsule` 의 r0 < r1 로 벌린다.
#  - **자루 끝(poll)을 반대쪽에 조금 남긴다.** 없으면 날이 자루에 얹힌 게 아니라
#    자루가 날 속으로 사라진 것처럼 보인다.
AXE = dict(
    helve=4.0, helve_r=(0.62, 0.50),
    # 날: (자루에서 바깥으로, 자루를 따라 위로) 두 점 + 그 두 점에서의 굵기.
    # **위가 좁고 아래가 넓은 세로 쐐기**여야 도끼로 읽힌다 — 자루에 수직으로
    # 뻗는 가로 막대로 만들면 망치/깃발이 되고, 굵기가 일정한 세로 판이면 벽돌이 된다.
    bit_a=(0.35, 1.10), bit_b=(2.05, -0.90), bit_r=(0.55, 1.75), bit_bulge=0.25,
    # 들고 있는 각도(도, +x 에서 반시계). **80 도 — 거의 세워 든다.**
    # 더 눕히면(60~70도) 날이 몸 쪽으로 넘어와 팔에 파묻히고, 더 세워 몸 쪽으로
    # 기울이면(100도 이상) 날이 **얼굴 위**로 올라온다(머리가 어깨보다 넓다).
    hold=80.0,
    # 도구를 든 손이 몸 옆으로 나가는 폭 / 내려가는 폭.
    reach=1.05, drop=0.25,
    # 패기 — 자루 각도가 `mid ± amp` 를 왕복한다(85도 ↔ -40도).
    # **양끝이 캔버스에 물려 있다**: 위로 더 들면(90도 넘김) 날이 얼굴 위로
    # 넘어오고(머리가 어깨보다 넓다), 아래로 더 내리면 날이 오른쪽/아래 테두리
    # 밖으로 잘린다. 17px 에 자루 5.6px 짜리 도끼를 든 대가다 —
    # **머리 위로 크게 넘기는 장작패기 동작은 이 칸에 안 들어간다.**
    swing_mid=11.0, swing_amp=71.0,
    # 패는 동안 손이 그리는 타원 (들 때 뒤·위로 / 칠 때 앞·아래로 + 위상이 90도
    # 어긋난 앞뒤 성분).
    use_rise=-1.60, swing_lift=0.60, swing_fwd=0.70, swing_loop=0.30,
    swing_sag=0.25, swing_tuck=2.20,
    # 걷는 동안 도구를 든 팔은 덜 흔든다 — 실제로도 연장을 든 팔은 잘 안 흔들고,
    # 안 줄이면 도끼가 팔을 따라 크게 움직여 「이어짐」 상한을 넘는다.
    arm_damp=0.35,
    head="axe",
)

# 곡괭이 (INBOX #26). **도끼와 같은 자루**(길이·굵기·램프)를 쓰고 **머리만 다르다** —
# 그래야 둘이 같은 손에서 나온 도구로 보인다(STYLE_GUIDE 「손에 쥔 도구」).
#
# 값을 치르고 알아낸 것:
#  - **차이는 자루가 아니라 머리의 대칭성이다.** 도끼는 한쪽으로만 넓은 쐐기라
#    실루엣이 자루 한쪽에 쏠려 있고, 곡괭이는 **양쪽으로 뾰족한 두 갈래**라 자루를
#    가운데 두고 좌우가 같다. 17px 에서 이 좌우 대칭 하나가 두 도구를 가른다 —
#    머리 모양을 아무리 다듬어도 한쪽에만 달려 있으면 도끼로 읽힌다.
#  - **갈래는 곧은 쐐기가 아니라 끝만 꺾이는 갈고리다.** `wedge` 로 뿌리에서 끝까지
#    곧게 좁혀봤더니 갈래가 삼각형이 되어 머리 전체가 **화살촉/뿔**로 읽혔다.
#    실제로 곡괭이를 곡괭이로 만드는 것은 **크로스바 한 줄 + 그 양끝에서 한 칸
#    떨어진 갈래 끝** 두 점이다(끝만 떨어지려면 곡선이어야 한다 — `_bez`).
#  - **뾰족함은 굵기가 아니라 그 한 칸의 빈틈에서 나온다.** 17px 에서 갈래 끝을
#    아무리 가늘게 해도(반지름 0.3 이하) 축소하면서 통째로 사라진다. 굵기는
#    한 칸을 유지할 만큼만 두고, 끝을 크로스바에서 **대각선으로 떨어뜨려**
#    사이에 빈 칸이 보이게 하는 쪽이 훨씬 잘 읽힌다.
#  - **갈래를 도끼날만큼 길게 뽑을 수 없다.** 도끼는 한쪽으로 2.05 였는데 곡괭이는
#    양쪽으로 그만큼 나가면 머리 폭이 앞모습에서 얼굴을, 옆모습에서 칸 테두리를
#    친다(「잘림」). 한쪽 2.4 로 잡아 크로스바가 4px, 갈래 끝까지 6px 다.
PICKAXE = dict(
    AXE,
    # 갈래 한 짝의 2차 베지에: 뿌리 → **제어점** → 끝 (자루에서 바깥으로, 자루를
    # 따라 위로). 좌우 두 벌이 자동으로 만들어진다(바깥 방향만 뒤집는다).
    # **제어점이 뿌리 높이에 가까이 있어야** 갈래가 앞쪽 2/3 을 가로로 뻗다가
    # 끝에서만 한 칸 떨어진다 — 그 갈고리가 곡괭이의 전부다.
    tine_a=(0.15, 0.35), tine_c=(1.90, 0.55), tine_b=(2.40, -1.40),
    tine_r=(0.62, 0.36),
    # **갈래의 볼록함은 굵기에서 떼어낸다.** 굵기(0.62)로 높이를 정하면 갈래가
    # 납작해져서 바로 옆 나무 자루와 명도가 붙는다 — 17px 에서 곡괭이가 곡괭이로
    # 읽히는 것은 형태가 아니라 **쇠와 나무의 명도차**다(도끼도 같은 이유로
    # 날이 두껍다). 도끼날의 볼록함(0.55 × 1.75 ≈ 0.96)에 맞춰 잡았다.
    tine_dome=0.95,
    # 자루가 머리를 뚫고 올라온 부분(자루 방향 길이). 손에 쥔 크기에서는 그 한
    # 칸이 머리를 두 조각으로 끊어서 쓰지 않는다 — 아이콘에서만 쓴다.
    eye=0.0,
    # **거의 세워 든다(86도).** 도끼(80도)보다 세운 것은 머리가 좌우 대칭이기
    # 때문이다 — 자루를 기울이면 크로스바가 같이 기울어 한쪽 갈래만 한 칸 내려가고,
    # 17px 에서 그건 "휜 곡괭이"가 아니라 **부러진 도구**로 보인다.
    hold=86.0,
    # 머리가 어깨 높이에 오도록 도끼(0.25)보다 내려 잡는다 — 세워 든 만큼 머리가
    # 위로 가서, 안 내리면 안쪽 갈래가 턱을 문다.
    reach=1.05, drop=0.80,
    # 채광은 벌목보다 **덜 크게 휘두르고 앞으로 찍는다** — 바위벽을 향해 치는
    # 동작이라 머리 위로 크게 넘기지 않는다.
    swing_mid=5.0, swing_amp=64.0,
    # 드는 동안 손이 **덜 올라가고 더 앞으로 나간다**(도끼: rise -1.60 / fwd 0.70
    # / lift 0.60). 곡괭이 머리는 좌우 대칭이라 **안쪽 갈래가 얼굴 쪽으로 돌아온다** —
    # 도끼처럼 손을 얼굴 옆까지 들어올리면 그 갈래가 눈을 덮는다(「눈」이 잡는다).
    # 앞으로 밀어 그 갈래를 얼굴 앞을 지나 바깥으로 보낸다.
    # **통과 구간을 표로 뽑아 가운데를 골랐다**: rise -1.2~-1.0 / fwd 1.0~1.2 /
    # lift 0.22~0.38. 위로는 「눈」, 아래로는 「대비」(자루와 갈래가 겹쳐 붙는다)와
    # 「이어짐」이 벽이다.
    use_rise=-1.10, swing_fwd=1.15, swing_lift=0.30,
    head="pick",
)

# 낫 (INBOX #27). 도끼/곡괭이와 같은 자루 램프·같은 손 자리를 쓰지만 **자루가 짧고
# 머리가 휘었다** — 그 둘이 낫을 낫으로 만든다.
#
# 값을 치르고 알아낸 것:
#  - **자루를 도끼(4.0)보다 짧게(2.6) 한 것이 실루엣의 절반이다.** 낫은 한 손으로
#    풀을 움켜쥐고 베는 도구라 자루가 짧다. 길게 두면 날이 캔버스 밖으로 나가고
#    (「잘림」), 무엇보다 자루가 길수록 **곡괭이와 실루엣이 겹친다** — 17px 에서
#    "긴 막대 끝의 쇳덩이"는 셋 다 같은 그림이다.
#  - **휨은 "굽었다"가 아니라 "끝이 자루 쪽으로 돌아왔다"로 읽힌다.** 활처럼
#    완만하게 휜 후보는 축소 뒤에 전부 비스듬한 막대였다. 끝(`blade_b`)의 바깥
#    거리를 제어점(`blade_c`)보다 **작게** 잡아 안쪽에 빈 칸을 만들어야 초승달이
#    된다 — 그 빈 칸이 오목한 안쪽 날이다.
#  - **가로로 벤다.** 도끼는 자루를 세웠다 내리찍고(82도 ↔ -60도), 낫은 자루가
#    **거의 눕는 채로**(swing_mid/amp 가 작다) 손이 몸 앞을 가로지른다. 그래서
#    각도 진폭 대신 **손의 가로 이동**(`swing_fwd`)이 크다.
SICKLE = dict(
    AXE,
    # 짧은 자루. 굵기·램프는 도끼/곡괭이 그대로다 — 같은 손에서 나온 도구로 보이려면
    # 자루가 같아야 한다(STYLE_GUIDE 「손에 쥔 도구」).
    helve=2.8,
    # 초승달 — 자루 끝을 원점으로 한 (바깥, 자루 방향) 좌표. `moon_cut` 만큼
    # 어긋난 반지름 `moon_r2` 짜리 원을 도려낸다. **도려내는 방향이 곧 오목한
    # 안쪽 날의 방향**이고, 자루 쪽(왼쪽 아래, 220도)을 보게 잡았다.
    moon_c=(0.60, 1.50), moon_r=2.70, moon_cut=(-0.73, -0.61), moon_r2=2.32,
    # 볼록함은 굵기에서 떼어낸다 — 도끼날·곡괭이 갈래와 같은 값이라야 쇠붙이끼리
    # 밝기가 어긋나지 않는다(「재질명도」).
    moon_dome=0.95,
    # 들고 있는 각도. 도끼(80)/곡괭이(86)보다 조금 눕혀 든다 — 낫은 날이 위로 솟은
    # 도구가 아니라 손 앞에 걸린 초승달이다. 자루가 짧아 눕혀도 팔에 안 묻힌다.
    # 도끼(0.25)·곡괭이(0.80)보다 더 내려 잡는다 — 초승달이 도끼날보다 위로
    # 넓어서, 안 내리면 **옆모습에서 날이 눈에 닿는다**(「눈」이 "눈 없음"으로
    # 잡는다 — 눈이 피부가 아니라 쇠붙이에 둘러싸이기 때문이다).
    hold=78.0, reach=1.05, drop=0.90,
    # **가로베기.** 도끼는 자루를 세웠다 내리찍지만(11도 ± 71도) 낫은 자루가
    # 수평 언저리를 오가며 **손이 몸 앞을 가로지른다**. 각도 진폭이 작은 대신
    # 손의 앞뒤 이동(`swing_fwd`)이 도끼의 두 배가 넘는다.
    # **통과 구간을 표로 뽑아 골랐다**(216 조합 중 33 개만 통과). 벽은 「잘림」
    # 하나다 — 자루 2.8 + 초승달 4 ≈ 7px 짜리 도구가 수평에 가까워지는 순간
    # 칸을 넘는다. 그래서 **팔꿈치를 도끼(2.2)보다 훨씬 깊게 접고**(3.4) 손을
    # 몸 앞으로 당겨야만 날이 칸 안에 남는다.
    swing_mid=10.0, swing_amp=34.0,
    # `swing_fwd` 가 **음수**인 것이 가로베기다 — 날이 내려갈수록(up 이 -1 로
    # 갈수록) 손이 앞으로 나간다. 도끼는 반대로(양수) 들 때 손이 앞으로 나가고
    # 내려칠 때 몸쪽으로 당긴다(내리찍기).
    use_rise=-0.90, swing_lift=0.25, swing_fwd=-0.80, swing_loop=1.10,
    swing_sag=0.30, swing_tuck=4.00,
    head="sickle",
)

TOOLS = {"axe": AXE, "pickaxe": PICKAXE, "sickle": SICKLE}

## 도구를 쥔 손. 앞/뒷모습은 **화면 오른쪽 손**(팔 두 개 중 1번), 옆모습은 보이는
## 손 하나뿐이다. 방향이 바뀌어도 도구가 화면 같은 쪽에 있어야 덜 어지럽다.
def tool_hand(direction):
    return 0 if direction in ("left", "right") else 1


def tool_sx(direction):
    """도구가 놓이는 쪽. 옆모습은 바라보는 쪽, 앞/뒷모습은 화면 오른쪽이다."""
    return -1.0 if direction == "left" else 1.0


def tool_pose(direction, motion, phase, cfg, tool):
    """도구 모션의 부위 오프셋 + 자루 각도.

    `motion` 은 `hold` / `use` / `walk` 다. **걷기는 걷기 자세 그대로**(`walk_pose`)
    이고 도구를 든 팔만 덜 흔들며, **패기는 서 있는 자세**(다리는 idle)에서 팔과
    자루만 움직인다 — 패면서 다리가 걷고 있으면 안 된다.

    어느 모션이든 도구를 든 손은 **몸에서 한 칸 바깥으로** 나간다(`reach`).
    17px 에서 몸통은 x 6~11 을 쓰고 머리는 4~13 까지 퍼져 있어서, 손을 몸 옆에
    붙인 채로 도구를 세우면 자루가 팔에 파묻혀 **막대기 하나로** 보인다(실제로
    첫 후보가 그랬다). 바깥으로 한 칸 내보내면 자루가 빈 자리(x 12~15)에 선다.
    """
    pose = dict(walk_pose(direction, phase if motion == "walk" else None, cfg))
    hand = tool_hand(direction)
    sx = tool_sx(direction)
    angle = tool["hold"]
    arm_dx, arm_dy = list(pose["arm_dx"]), list(pose["arm_dy"])
    if motion == "walk":
        arm_dx[hand] *= tool["arm_damp"]
        arm_dy[hand] *= tool["arm_damp"]
    arm_dx[hand] += tool["reach"] * sx
    arm_dy[hand] += tool["drop"]
    if motion == "use" and phase is not None:
        t = 2.0 * np.pi * float(phase)
        up, fwd = float(np.cos(t)), float(np.sin(t))
        angle = tool["swing_mid"] + tool["swing_amp"] * up
        # 손은 **타원을 그린다** — 들 때 앞·위로, 칠 때 뒤·아래로(`up`), 거기에
        # 90도 어긋난 `fwd` 로 앞뒤를 한 번 더 준다. **드는 순간 손이 앞으로
        # 나가는 것**(`swing_fwd`)은 옆모습 때문이다: 손을 몸 쪽에 둔 채 자루를
        # 세우면 자루가 **눈을 덮는다**(얼굴이 폭 8px 인데 손이 그 한가운데 온다). 순수 진자(각도와 손이 같은
        # 위상)로 두면 올라갈 때와 내려올 때가 **같은 그림**이 되어 6장 중 넉 장만
        # 쓰는 셈이 된다 — 걷기에서 위상을 반 칸 밀었을 때와 같은 실패다.
        # **팔꿈치가 접힌다**(`swing_tuck`) — 자루가 수평에 가까울수록 손을 몸
        # 쪽으로 당긴다. 17px 칸에서 손 바깥으로 남은 자리는 3px 뿐이라, 팔을
        # 뻗은 채로 자루를 눕히면 날이 **칸 밖으로 잘려나간다**(「잘림」).
        # 실제로도 휘두르는 중간에는 팔꿈치가 접혀 손이 몸에 붙는다.
        tuck = tool["swing_tuck"] * abs(float(np.cos(np.radians(angle))))
        arm_dx[hand] += (tool["swing_fwd"] * up + tool["swing_loop"] * fwd - tuck) * sx
        arm_dy[hand] += (tool["use_rise"] - tool["swing_lift"] * up
                         + tool["swing_sag"] * fwd)
    pose["arm_dx"], pose["arm_dy"] = tuple(arm_dx), tuple(arm_dy)
    pose["tool_angle"] = angle
    return pose


def _head_axe(b, at, tool, lift):
    """도끼머리 — 자루 끝에서 **바깥으로 벌어지다 끝이 잘리는 쐐기**(`wedge`) 하나.

    `capsule` 을 쓰면 바깥 끝이 반원이라 **망치**로 읽힌다 — 실제로 그렇게 나왔다.
    자루에 수직인 막대(굵기 일정)로 붙여도 망치고, 자루와 나란한 판으로 붙이면
    벽돌이다. **한쪽에만 달려 있는 것**이 곡괭이와 갈리는 자리다.
    """
    b.add(wedge(*at(*tool["bit_a"]), *at(*tool["bit_b"]),
                *tool["bit_r"], bulge=tool["bit_bulge"]), "blade", lift=lift + 0.05)


## 휜 쇠붙이(곡괭이 갈래 · 낫날)를 몇 토막으로 나눠 그릴 것인가. 토막마다 굵기가
## 줄어드는 `capsule` 을 이어 붙여 **곡선**을 만든다 — `wedge` 는 곧아서 갈고리가
## 안 된다. 8토막이면 24배 해상도에서 토막 사이 각이 계단으로 안 보인다.
CURVE_STEPS = 8


def _bez(pts, t):
    """2차 베지에 한 점. 곡괭이 갈래의 휨을 제어점 하나로 정한다."""
    (x0, y0), (x1, y1), (x2, y2) = pts
    u = 1.0 - t
    return (u * u * x0 + 2 * u * t * x1 + t * t * x2,
            u * u * y0 + 2 * u * t * y1 + t * t * y2)


def _curve(b, at, pts, radii, dome, lift, part=None):
    """2차 베지에를 따라가는 **굵기가 변하는 곡선 쇠붙이** 한 덩어리.

    `wedge` 는 곧아서 갈고리·초승달이 안 되고, `capsule` 하나는 직선이다 —
    토막을 이어 붙이는 수밖에 없다. **`part` 를 하나로 묶어서** 토막 경계마다
    내부선이 그어지지 않게 하는 것이 이 함수의 핵심이다(2026-09-07, INBOX #26).

    곡괭이 갈래와 낫날이 같은 코드다 — 휜 쇠붙이가 도구마다 다른 방식으로
    그려지면 같은 손에서 나온 도구로 안 보인다.
    """
    r0, r1 = radii
    for i in range(CURVE_STEPS):
        t0, t1 = i / CURVE_STEPS, (i + 1) / CURVE_STEPS
        part = b.add(capsule(*at(*_bez(pts, t0)), *at(*_bez(pts, t1)),
                             r0 + (r1 - r0) * t0, r0 + (r1 - r0) * t1, dome=dome),
                     "blade", part=part, lift=lift)
    return part


def _head_pick(b, at, tool, lift):
    """곡괭이머리 — 자루를 가운데 두고 **좌우로 뻗는 뾰족한 갈래 두 개**.

    도끼머리와 정확히 뒤집힌 쐐기다(뿌리가 굵고 끝이 뾰족하다). 좌우 대칭이라
    17px 에서도 도끼와 실루엣이 겹치지 않는다 — INBOX #26 이 요구한 구별이 여기서
    나온다. 두 갈래의 뿌리가 가운데서 겹쳐 **곡괭이눈**(자루가 꿰이는 덩어리)이
    저절로 생기므로 따로 그리지 않는다.
    """
    # 자루가 머리를 뚫고 조금 올라온 끝. **갈래보다 먼저 그린다** — 나중에 그리면
    # 머리 한가운데 나무색 한 칸이 남아서 머리가 두 조각으로 끊겨 보인다.
    if tool["eye"] > 0:
        b.add(capsule(*at(0.0, 0.0), *at(0.0, tool["eye"]), tool["helve_r"][1] * 0.9),
              "helve", lift=lift + 0.03)
    r0, r1 = tool["tine_r"]
    # **두 갈래를 한 덩어리(`part`)로 묶는다.** 토막마다 새 부위 id 가 붙으면
    # `inner_lines()` 가 토막 경계마다 가장 어두운 단계를 그어서 머리가 통째로
    # 검게 칠해진다(실제로 그렇게 나왔다 — 머리 34px 중 21px 이 최암부였다).
    # 갈래는 한 쇳덩이라 안에 내부선이 있을 이유가 없다.
    head_part = None
    for side in (1.0, -1.0):
        pts = [(side * ox, oy) for ox, oy in
               (tool["tine_a"], tool["tine_c"], tool["tine_b"])]
        # **곧은 쐐기로는 곡괭이가 안 된다** — 뿌리에서 끝까지 곧게 벌어지면
        # 갈래가 삼각형이 되어 화살촉/뿔로 읽힌다. 17px 에서 곡괭이를 곡괭이로
        # 만드는 것은 **끝만 아래로 꺾이는 갈고리**다(가운데 제어점이 그 꺾임을
        # 늦춘다 — 앞쪽 2/3 은 가로로 뻗고 마지막에 한 칸 떨어진다).
        head_part = _curve(b, at, pts, tool["tine_r"], tool["tine_dome"],
                           lift + 0.05, part=head_part)


def _head_sickle(b, at, tool, lift):
    """낫날 — 자루 끝에 얹힌 **초승달**(`crescent`) 하나.

    도끼(한쪽으로 넓은 곧은 쐐기)·곡괭이(좌우 대칭 갈고리)와 갈리는 자리는 **휨**
    이다. 그런데 17px 에서 곡선은 계단 두 칸으로 뭉개지기 쉬워서, **휨이 읽히는
    최소 크기**를 찾는 것이 이 도구의 전부였다(INBOX #27):

    - **곡선을 `capsule` 토막으로 이어 그리면 안 된다.** 곡괭이 갈래는 그렇게
      그렸지만, 그건 굵기가 일정해도 되는 **뾰족한 갈고리**였다. 낫은 날이라
      같은 방법으로 그리면 **굵기가 일정한 철사**로 읽힌다 — 실제로 후보를 열몇
      개 뽑는 동안 전부 옷걸이/물음표였다.
    - **날로 읽히려면 바깥은 볼록하고 안쪽은 오목해야 한다** — 가운데가 두껍고
      양끝이 뾰족한 형태다. 원에서 어긋난 원을 도려낸 초승달이 그것을 공짜로 준다.
    - **오목한 쪽(안쪽 날)은 자루 쪽을 본다.** 자루와 날 사이에 빈 칸이 한 줄
      생기는데, 17px 에서 "휘었다"를 읽게 하는 것이 바로 그 빈 칸이다.
    """
    cx, cy = at(*tool["moon_c"])
    ox, oy = at(tool["moon_c"][0] + tool["moon_cut"][0],
                tool["moon_c"][1] + tool["moon_cut"][1])
    b.add(crescent(cx, cy, tool["moon_r"], ox - cx, oy - cy, tool["moon_r2"],
                   dome=tool["moon_dome"]), "blade", lift=lift + 0.05)


HEADS = {"axe": _head_axe, "pick": _head_pick, "sickle": _head_sickle}


def draw_tool(b, gx, gy, angle_deg, sx, tool, lift=0.16):
    """손 자리(gx, gy)에 도구를 쥐여준다. `sx` 가 -1 이면 좌우가 뒤집힌다.

    **자루는 모든 도구가 공유하고 머리만 갈린다**(`tool["head"]` → `HEADS`) —
    자루 굵기·길이·램프가 도구마다 달라지면 같은 손에서 나온 도구로 안 보인다
    (STYLE_GUIDE 「손에 쥔 도구와 그 아이템 아이콘」).

    **손보다 반 칸 위에서 시작한다** — 정확히 손 위에서 시작하면 자루가 손을 통째로
    덮어서 팔이 자루 속으로 사라진다. 반 칸 띄우면 손끝 한 칸이 남아 쥔 것으로 읽힌다.
    """
    a = np.radians(angle_deg)
    ux, uy = np.cos(a) * sx, -np.sin(a)          # 자루 방향(손 → 머리)
    nx, ny = np.sin(a) * sx, np.cos(a)           # 머리가 벌어지는 쪽(자루의 바깥)
    L = tool["helve"]
    x0, y0 = gx - ux * 0.55, gy - uy * 0.55      # 손 아래로 조금 삐져나온 자루 끝
    hx, hy = gx + ux * L, gy + uy * L
    b.add(capsule(x0, y0, hx, hy, *tool["helve_r"]), "helve", lift=lift)

    # 머리 좌표는 **자루 끝을 원점으로 한 (바깥, 자루 방향)** 으로 적는다 —
    # 방향/각도가 바뀌어도 머리 모양이 자루에 대해 그대로다.
    def at(out, along):
        return hx + nx * out + ux * along, hy + ny * out + uy * along

    HEADS[tool["head"]](b, at, tool, lift)


def _fall_shape(cx, hw, y0, y1, taper=1.0, tip=1.3, slant=0.0, wave=0.0):
    """아래로 흘러내리는 머리단 — 아래로 갈수록 좁아지고 끝이 둥근 기둥.

    `rbox` 로는 못 만든다(폭이 일정하다). 도트에서 머리단이 "붙인 판자"로 안
    보이려면 **끝이 좁아지고 둥글어야** 한다. 높이는 x 방향으로 부푼 원기둥이라
    가운데가 밝고 양옆이 그늘진다 — 머리 껍데기와 같은 입체감이 나온다.
    """
    t = np.clip((GY - y0) / max(y1 - y0, 1e-6), 0.0, 1.0)
    half = np.maximum(hw - taper * t, 0.6)
    # `slant` 는 아래로 갈수록 옆으로 기울고, `wave` 는 좌우로 한 번 굼실거린다 —
    # 긴 머리단은 곧게 떨어뜨리면 옆선이 자로 그은 직선이 된다(「각짐」).
    dx = np.abs(GX - (cx + slant * t + wave * np.sin(2.0 * np.pi * t)))
    body = (GY >= y0) & (GY <= y1 - tip) & (dx <= half)
    # 끝동 — 잘린 자리가 자로 그은 듯 반듯하면 가발처럼 보인다
    ty = np.clip((GY - (y1 - tip)) / tip, 0.0, 1.0)
    cap = (GY > y1 - tip) & (GY <= y1) & (dx <= half * np.sqrt(np.clip(1 - ty * ty, 0, 1)))
    m = body | cap
    h = np.sqrt(np.clip(1 - (dx / np.maximum(half, 1e-6)) ** 2, 0, 1)) * (ROUND * hw)
    return m, h * m


def _tail(b, part, cx, y0, y1, lift, w=1.1, slant=0.0):
    """묶은 꼬리 — 아래로 좁아지며 살짝 휘는 갈래.

    폭이 일정한 막대기로 만들면 꼬리가 아니라 손잡이로 보이고, 큰 타원으로
    만들면 **옆선이 10줄 내리 같은 자리**에 놓여 각져 보인다(「각짐」).
    머리 껍데기와 겹치게 시작해서 실루엣을 잇는다."""
    return b.add(_fall_shape(cx, w, y0, y1, taper=w * 0.62, tip=0.8, slant=slant),
                 "hair", part=part, lift=lift)


# ── 머리모양 4종 ──────────────────────────────────────────────────────────
# id 는 `game/scripts/character_appearance.gd` 의 HAIRSTYLE 과 같아야 한다.
# **형태만 다르고 팔레트·비율·광원은 전부 같다** — 그래야 네 개를 나란히 놓아도
# 같은 캐릭터로 읽힌다(DESIGN.md 「그래픽 파이프라인」 1) 어울림).
#
#   sides   옆머리(구레나룻)가 내려오는 깊이 보정. 음수면 귀 위에서 끊긴다
#   fall    옆머리 아래로 더 흘러내리는 머리단 길이 (앞/옆모습에서 보이는 것)
#   fw      그 머리단의 반폭. **단발은 길이가 아니라 이 폭으로 구별된다** —
#           짧게만 자르면 「짧은머리」와 붙어 보이고, 길게 늘이면 「긴머리」와 붙는다
#   back    뒤통수 아래로 이어지는 머리단 길이 (뒷/옆모습에서 보이는 덩어리)
#   bw      그 머리단의 반폭(뒷모습). **머리 껍데기와 같은 폭으로 두면 안 된다** —
#           17px 에서는 어깨가 7칸뿐이라 상의가 통째로 가려져서 뒷모습에 옷이
#           사라진다(비율 검사가 "재질 없음"으로 잡는다). 긴머리는 좁게 흘려서
#           양옆으로 상의가 보이게 한다
#   strand  앞머리에 결 한 줄을 넣을지 (좌우대칭을 깨서 밋밋함을 없앤다)
#   ftop    그 머리단이 시작하는 높이(머리 중심 기준). **눈을 덮으면 안 된다** —
#           폭이 넓은 단발은 눈보다 아래(광대)에서 시작해야 얼굴이 열린다
#   wave    그 머리단이 좌우로 굼실거리는 폭. 긴 머리는 곧게 떨어뜨리면 커튼이 된다
#   tail    묶은 꼬리 길이. 0 이면 없다
HAIR_STYLES = {
    "short":    dict(sides=0.0,  fall=0.0, fw=0.0,  ftop=0.5, wave=0.0,  back=0.0,
                     strand=True,  tail=0.0),
    "bob":      dict(sides=1.2,  fall=0.6, fw=1.3,  ftop=1.8, wave=0.0,  back=0.6,
                     bw=3.7, strand=False, tail=0.0),
    "long":     dict(sides=1.0,  fall=2.9, fw=0.95, ftop=0.5, wave=0.5,  back=2.6,
                     bw=2.6, strand=False, tail=0.0),
    "ponytail": dict(sides=-0.6, fall=0.0, fw=0.0,  ftop=0.5, wave=0.0,  back=0.0,
                     strand=False, tail=2.2),
}


def base_up(shell, nape):
    """뒷모습에서 결을 얹을 바탕 — 머리단이 있으면 그 덩어리까지 합친 것."""
    if nape is None:
        return shell
    return (shell[0] | nape[0], np.maximum(shell[1], nape[1]))


def _hair(b, d, cfg, hx, hy, rx, ry, style, bob=0.0):
    """머리카락. 앞머리는 얼굴보다 앞으로 lift 해서 경계가 살아나게 한다.

    **덧붙이는 갈래는 전부 머리 껍데기(shell) 안으로 잘라 넣는다** — 안 그러면
    실루엣 밖으로 혹처럼 튀어나온다. 껍데기 **밖으로** 나가는 것(흘러내린 머리단,
    묶은 꼬리)은 예외인데, 그때는 반드시 껍데기와 겹치게 시작해야 실루엣이 한
    덩어리로 남는다(`qa_sprite_check.py` 「실루엣」).
    """
    st = HAIR_STYLES.get(style, HAIR_STYLES["short"])
    grow = 0.12 if d == "up" else 0.16  # 뒷모습은 얼굴이 없어 껍데기가 곧 실루엣이다
    shell = head_shape(hx, hy, rx + grow, ry, p_top=cfg["head_p"], p_bot=cfg["head_pb"])
    side = d in ("left", "right")
    sx = 1.0 if d == "right" else -1.0
    if cfg["head_puff"]:
        # 귀 옆 머리 볼륨. 두 가지 일을 한다 — (1) 머리를 어깨보다 확실히 넓게
        # 만들고, (2) **실루엣 옆선이 여러 줄 내리 같은 자리에 놓이는 것을 깬다**
        # (「각짐」). 옆모습은 뒤통수 쪽에만 붙인다(얼굴 앞에 혹이 나면 이상하다).
        pr = cfg["head_puff"]
        # 옆모습은 뒤통수 쪽을 크게, 관자놀이 쪽을 작고 높게 준다 — 앞에 큰 혹이
        # 나면 이상하지만, 아무것도 없으면 얼굴 앞선이 6줄 곧게 이어진다.
        offs = [(-sx, 1.0, 0.7)] if side else [(-1.0, 1.0, 0.7), (1.0, 1.0, 0.7)]
        pm, ph = np.zeros_like(shell[0]), np.zeros_like(shell[1])
        for s, k, dy in offs:
            mm, hh = ellipsoid(hx + s * (rx + grow - 0.45), hy + dy, pr * k, pr * k * 1.2,
                               squash=ROUND * (rx + grow) * 0.9)
            pm |= mm
            ph = np.maximum(ph, hh)
        shell = (shell[0] | pm, np.maximum(shell[1], ph))
    sm = shell[0]
    # 머리카락 끝(헤어라인)을 물결지게 만드는 작은 덩어리들 — 실루엣 아랫변이
    # 완전한 원호면 머리가 헬멧처럼 보인다. 도트에서 "머리카락"으로 읽히는 건
    # 색이 아니라 이 들쭉날쭉한 끝선이다.
    def scallop(cy, offs, r=0.85):
        m = np.zeros_like(sm)
        h = np.zeros_like(shell[1])
        for i, off in enumerate(offs):
            mm, hh = ellipsoid(hx + off, cy, r, r * 1.05, squash=ROUND * (rx + grow))
            m |= mm
            h = np.maximum(h, hh)
        return m, h
    LIFT = 0.10

    if d == "up":
        # 뒷모습 — 머리 전체가 머리카락. 아랫변을 물결지게 해서 헬멧처럼 안 보이게.
        cap = b.add(shell, "hair", lift=LIFT)
        # **17px 에서는 정수리 가마를 얹지 않는다**(2026-09-07, INBOX #19). 뒤통수가
        # 여섯 줄뿐이라, 높이를 올린 자리가 위쪽 네 줄을 통째로 가장 밝은 단계로
        # 밀어올려 머리가 회색 판때기가 됐다. 껍데기 돔만으로도 윗면 하이라이트 띠는
        # 이미 생긴다(STYLE_GUIDE 「자연스러움」).
        # 뒤로 이어지는 머리단(단발/긴머리) — 껍데기와 겹치게 시작한다.
        # 아래로 갈수록 좁아지는 사다리꼴이라야 어깨에 얹힌 것처럼 보인다.
        nape = None
        if st["back"] > 0.0:
            nape = _fall_shape(hx, st.get("bw", rx + grow - 0.35), hy,
                               hy + ry + 0.25 + st["back"], taper=1.2)
            b.add(nape, "hair", part=cap, lift=LIFT)
        if st["tail"] > 0.0:
            # 뒷모습 — 꼬리는 **머리보다 확실히 좁아야** 묶인 것으로 읽힌다.
            # 넓게 잡았더니 머리와 이어진 한 덩어리가 되어 긴머리처럼 보였다.
            ty0, ty1 = hy + 2.1, hy + ry + 0.25 + st["tail"]
            tail = _fall_shape(hx, 1.1, ty0, ty1, taper=0.6, tip=0.75)
            b.add(tail, "hair", part=cap, lift=LIFT)
            b.add(tail, "hair", mask=GX > hx + 0.2, lift=LIFT)   # 결 한 줄
        # 머리결 — **덩어리(가르마) 두 개**를 얹는다. 부위 id 가 다르므로 그 경계에
        # 내부선이 들어가 머리카락 가닥이 된다. 매끈한 타원 하나면 뒷모습이 회색
        # 달걀(=민머리/헬멧)로 보인다.
        # **폭이 일정한 세로 띠로 하지 않는다**(2026-09-06, INBOX #13) — 곧은 세로
        # 선 몇 개가 나란히 그이면 머리가 아니라 **빗자루**로 보인다. 아래로 갈수록
        # 벌어지는 둥근 덩어리라야 경계가 휘어서 머리카락 결로 읽힌다.
        # **17px 에서는 갈래가 하나다**(2026-09-07, INBOX #19). 뒤통수가 여섯 줄뿐이라
        # 갈래를 둘 얹으면 경계선이 네 줄 생겨서 머리가 아니라 **빗자루**가 된다
        # (34px 때 폭 일정한 세로 띠로 같은 실패를 했다). 하나만 비스듬히 얹으면
        # 좌우대칭이 깨지면서 결 한 줄이 남는다.
        # 결 한 줄. **17px 에서는 이렇게밖에 못 넣는다**(2026-09-07, INBOX #19):
        #  - 갈래 모양의 높이장을 덮어씌우면 그 자리가 통째로 납작해져서 결이 아니라
        #    **어두운 띠**가 된다 → 껍데기의 높이를 그대로 쓰고 **부위 id 만** 바꾼다.
        #  - 안쪽에 뜬 갈래는 좌우 두 곳에 경계가 생겨 **어두운 줄이 두 개** 난다.
        #    9칸짜리 뒤통수에서 그건 오른쪽 1/3 이 통째로 어두워지는 것이다 →
        #    **실루엣 오른쪽 끝까지 가는 반평면**으로 잘라 경계를 하나만 만든다.
        #  - 그 경계를 수직선으로 두면 34px 때와 같은 **빗자루**가 된다 → 기울인다.
        b.add(base_up(shell, nape), "hair",
              mask=(GX - hx) > 0.55 + 0.42 * (GY - hy) / ry, lift=LIFT)
        return

    # 앞머리를 비스듬히 자른다 — 수평으로 자르면 바가지머리가 된다
    tilt = cfg["fringe_tilt"] * (sx if side else 1.0)
    edge = cfg["fringe"] + bob + tilt * (GX - hx) / rx
    cap = b.add(shell, "hair", mask=below(edge), lift=LIFT)

    # 옆머리(구레나룻) — 얼굴 옆을 감싸 내려온다
    down = cfg["side_hair"] + bob + st["sides"]
    for s in (-1, 1):
        if side and s == sx:
            continue                          # 옆모습에서 얼굴 쪽 옆머리는 없다
        b.add(shell, "hair",
              mask=(np.abs(GX - hx) > rx - 0.42) & (GY <= down) & (GX * s > hx * s),
              part=cap, lift=LIFT)

    if side:
        # 뒤통수는 목까지 덮는다
        b.add(shell, "hair",
              mask=((GX - hx) * sx < -(rx - 1.2)) & (GY <= down + 0.7),
              part=cap, lift=LIFT)

    # 옆머리 끝을 물결지게 — 자른 자리가 자로 그은 듯 반듯하면 가발처럼 보인다
    ends = [-(rx - 0.3), rx - 0.3] if not side else [-sx * (rx - 0.3)]
    b.add(scallop(down - 0.45, ends, r=0.7), "hair", mask=sm, part=cap, lift=LIFT, blend="max")

    # 흘러내리는 머리단(단발/긴머리). 앞모습은 양옆으로, 옆모습은 뒤통수 뒤로
    # 한 갈래만 — 옆에서 보면 반대쪽 머리단은 몸에 가린다.
    if st["fall"] > 0.0:
        hw = st["fw"]
        # **머리단은 머리 옆선에 붙여 둔다.** 한 칸 안으로 넣어봤는데(2026-09-07,
        # INBOX #19) 머리단이 턱보다 넓어지면서 옆선의 곧은 구간이 오히려 한 줄
        # 길어졌다 — 17px 에서는 안으로 넣을 자리가 없다.
        edge_x = rx + grow - hw
        xs = [hx - sx * edge_x] if side else [hx - edge_x, hx + edge_x]
        for i, fx in enumerate(xs):
            out = 1.0 if fx > hx else -1.0
            fall = _fall_shape(fx, hw, hy + st["ftop"], down + st["fall"], taper=hw * 0.75,
                               slant=-0.5 * out, wave=st["wave"] * out)
            b.add(fall, "hair", part=cap, lift=LIFT)
            # 결 한 줄 — 넓은 면이 통짜로 남으면 판자처럼 보인다
            b.add(fall, "hair", mask=GX > fx + 0.18, lift=LIFT)

    # 뒤통수 아래로 이어지는 덩어리 — 옆모습에서 단발/긴머리의 부피를 만든다
    if st["back"] > 0.0 and side:
        nw = st["fw"] + 0.6
        nape = _fall_shape(hx - sx * (rx + grow - nw), nw, hy + 0.5,
                           hy + ry + 0.25 + st["back"], taper=nw * 0.75, slant=0.4 * sx)
        b.add(nape, "hair", part=cap, lift=LIFT)

    if st["tail"] > 0.0:
        # **묶은 꼬리는 머리 실루엣 밖으로 나와야 읽힌다.** 안쪽에 두면 앞머리와
        # 한 덩어리가 되어 바가지머리로 보인다(실제로 한 번 그렇게 나왔다).
        # 앞모습은 옆으로 흘러내린 곁꼬리, 옆모습은 뒤통수 뒤로 나온다.
        if side:
            _tail(b, cap, hx - sx * (rx + grow - 0.25), hy - 0.5,
                  down + st["tail"] * 1.6, LIFT, w=1.05, slant=0.55 * sx)
        else:
            _tail(b, cap, hx + (rx + grow - 0.5), hy - 0.7,
                  down + st["tail"] * 1.2, LIFT, w=0.95, slant=-0.45)

    if st["strand"]:
        # 앞머리 한 갈래 — 뒷모습의 결과 같은 방법이다(부위 id 만 다른 같은 껍데기를
        # **실루엣 끝까지 가는 기울인 반평면**으로 잘라 넣어 경계를 하나만 만든다).
        # 좌우대칭이 깨져서 밋밋함이 사라진다.
        tip = 1.0 if not side else sx
        b.add(shell, "hair", mask=sm & below(edge)
              & ((GX - hx) * tip > 0.9 + 0.35 * (GY - hy) / ry), lift=LIFT)


def character(direction="down", hair="short", pal=None, cfg=None, phase=None,
              tool=None, motion="walk", **over):
    """한 프레임을 그린다. `phase=None` 이면 서 있는 자세, 0~1 이면 그 모션의 위상.

    `tool` 을 주면 그 도구를 **손에 쥔 채** 그린다(`motion` 은 `hold`/`use`/`walk`).
    몸은 도구가 있든 없든 **같은 코드가 그린다** — 도구는 손 자리에 얹히기만 한다.
    """
    cfg = dict(CFG, **(cfg or {}))
    cfg.update(over)
    pal = pal or palette()
    kit = TOOLS.get(tool)
    pose = (tool_pose(direction, motion, phase, cfg, kit) if kit
            else walk_pose(direction, phase, cfg))
    bob = pose["bob"]
    b = Build()

    limbs, hands = _body(b, direction, cfg, pose)
    side = direction in ("left", "right")
    sx = 1.0 if direction == "right" else -1.0
    cx = 8.5 + (0.25 * sx if side else 0.0)

    hx = cx + (0.35 * sx if side else 0.0)
    hy, rx, ry = cfg["head_cy"] + bob, cfg["head_rx"], cfg["head_ry"]
    if side:
        rx -= 0.2
    b.add(head_shape(hx, hy, rx, ry, p_top=cfg["head_p"], p_bot=cfg["head_pb"]), "skin")
    if side:
        # 코 — 실루엣 밖으로 살짝 나온 1px 돌기. 옆모습을 결정적으로 알아보게 한다
        b.add(ellipsoid(hx + sx * (rx - 0.15), hy + 1.9, 0.62, 0.58), "skin")
    elif cfg["ears"] and direction == "down":
        # 귀는 **실루엣 밖으로 거의 나오지 않게** 붙인다. 조금만 내밀어도 34px
        # 에서는 1px 돌기 + 그 바깥의 외곽선까지 2px 가 되어 요정 귀가 된다.
        er = cfg["ears"]
        for es in (-1, 1):
            b.add(ellipsoid(hx + es * (rx - 0.4), hy + 1.0, er, er * 1.25), "skin")
    _hair(b, direction, cfg, hx, hy, rx, ry, hair, bob)

    # 도구는 **맨 나중에** 얹는다 — 손에 쥔 것이므로 몸/머리보다 앞이다.
    if kit:
        gx, gy = hands[tool_hand(direction)]
        draw_tool(b, gx, gy, pose["tool_angle"], -1.0 if direction == "left" else 1.0, kit)

    lum = light(b.hgt, b.mat, key=cfg["key"], amb=cfg["amb"], rim=cfg["rim"])
    m, l = downsample(b.mat, lum)
    pm = downsample_part(b.part)

    # 눈은 축소 뒤에 네이티브 격자에 직접 찍는다 — 줄이면서 뭉개지면 안 되므로.
    # **2026-09-07 (INBOX #19) 에 기준이 바뀌었다** — 사람 피드백 "눈이 너무 커서
    # 줄여주고". 옛 기준은 "최소 3×3"이었는데, 17px 캔버스의 얼굴은 폭이 7px 라
    # 3×3 이면 눈 하나가 얼굴의 절반을 덮는다. 새 기준은 **1×2 또는 2×2**이고
    # **하이라이트는 2×2 일 때만 1px** 이다(STYLE_GUIDE 「자연스러움」).
    # 각진 눈매·눈썹·기울어진 윗선은 여전히 넣지 않는다 — 째려보는 인상이 되면
    # 다른 걸 아무리 고쳐도 살아나지 않는다.
    # `.`=그대로(피부) `e`=잉크 `*`=하이라이트
    EYE_ART = {
        # 2×2 + 광원 쪽(왼쪽 위) 하이라이트 1px — 눈망울로 읽힌다
        "bead": ("*e", "ee"),
        # 1×2 잉크. 하이라이트를 넣지 않는다 — 두 칸 중 한 칸이 흰색이 되면
        # 눈이 아니라 점 두 개로 읽힌다
        "dot": ("e", "e"),
        # 2×1 잉크. 얼굴이 세 줄뿐이라 세로로 두 줄을 쓰면 눈이 얼굴 높이의 2/3 가 된다
        "bar": ("ee",),
    }

    def eye(x, y, flip=False):
        art = EYE_ART[cfg["eye_style"]]
        for dy, line in enumerate(art):
            for dx, ch in enumerate(line[::-1] if flip else line):
                yy, xx = y + dy, x + dx
                if ch == "." or not (0 <= yy < N and 0 <= xx < N):
                    continue
                if m[yy, xx] != MATS.index("skin"):
                    continue
                # 하이라이트는 광원 쪽(왼쪽 위) — 다른 자산과 광원이 같아야 한다.
                m[yy, xx] = MATS.index("glint" if ch == "*" and cfg["glint"] else "eye")
                l[yy, xx] = 1.0 if ch == "*" else 0.0

    def blush(x, y, w=1):
        """볼 홍조 — 눈 아래 바깥쪽으로 1px. 입은 그리지 않는다.
        17px 에서는 2px 이면 볼이 아니라 뺨 전체가 분홍이 된다."""
        for dx in range(w):
            if 0 <= y < N and 0 <= x + dx < N and m[y, x + dx] == MATS.index("skin"):
                m[y, x + dx] = MATS.index("blush")
                l[y, x + dx] = 0.5

    # 팔/손은 몸통과 같은 재질이라 밝기가 같으면 실루엣에 녹는다 — 한 단계 그늘로.
    l[np.isin(pm, limbs)] -= cfg["limb_shade"]

    SKIN, SHIRT, HAIR, BOOT = (MATS.index(x) for x in ("skin", "shirt", "hair", "boot"))

    # 앞머리가 이마에 드리우는 그림자 / 턱이 상의에 드리우는 그림자 —
    # 도트에서 "붙어있는 두 덩어리"를 떼어놓는 가장 싼 방법이다.
    if cfg["contact"]:
        above = np.zeros((N, N), dtype=bool)
        above[1:] = m[:-1] == HAIR
        l[(m == SKIN) & above] -= cfg["contact"]
        above[1:] = m[:-1] == SKIN
        l[(m == SHIRT) & above] -= cfg["contact"]

    # 소맷부리 — 소매의 맨 아랫줄을 한 단계 어둡게 해서 손과 옷을 갈라놓는다.
    # **17px 에서는 꺼져 있다**(`CLOTH_ACCENTS` — 포인트는 하나까지다). 팔 길이가
    # 세 줄뿐이라 아랫줄을 어둡게 하면 소매의 1/3 이 띠가 된다.
    if cfg["cuff"]:
        sleeve = (m == SHIRT) & np.isin(pm, limbs)
        last = sleeve & ~np.pad(sleeve, ((0, 1), (0, 0)))[1:]
        l[last] -= cfg["cuff"]

    # 신발 입구 — 바지도 신발도 어두워서 경계가 묻힌다. 신발 맨 윗줄만 한 단계 밝게.
    if cfg["shoe_lip"]:
        boot = m == BOOT
        first = boot & ~np.pad(boot, ((1, 0), (0, 0)))[:-1]
        l[first] += cfg["shoe_lip"]

    # 옷깃 — 상의 맨 윗줄(어깨선)을 한 단계 밝게. **17px 에서는 꺼져 있다** —
    # 상의가 세 줄뿐이라 옷깃과 허리띠를 같이 넣으면 가운데 한 줄만 남는다
    # (`CLOTH_ACCENTS`). 옷이 "색칠한 사각형"이 되지 않게 하는 몫은 허리띠가 맡는다.
    if cfg["collar"]:
        chest = (m == SHIRT) & ~np.isin(pm, limbs)
        first = chest & ~np.pad(chest, ((1, 0), (0, 0)))[:-1]
        l[first] += cfg["collar"]

    # 허리띠 — 상의 맨 아랫줄을 **바지 재질의 가장 어두운 단계**로 찍는다.
    # 재질을 바지로 두는 이유가 둘이다: (1) 색상이 옮겨진 바지색이라 상의와 확실히
    # 갈린다, (2) 허리선이 곧 "다리가 시작하는 줄"이라 비율 검사(`qa_sprite_check.py`
    # 「비율」)가 몸통/다리를 여기서 가른다.
    beltm = np.zeros((N, N), dtype=bool)
    if cfg["belt"]:
        row = int(round(cfg["torso_bot"] + bob)) - 1
        # **소매는 띠에 넣지 않는다**(2026-09-07, INBOX #20). 허리띠는 몸통을 두르는
        # 것이지 팔을 가로지르지 않는다. idle 은 팔이 이 줄 위에서 끝나서 티가 안
        # 났는데, 걷기에서 손이 내려오는 프레임이 생기자 소매 끝이 통째로 띠 색이
        # 되어 바지 재질의 가장 어두운 단계가 84% 까지 올라갔다(「단색」).
        sel = (m[row] == SHIRT) & ~np.isin(pm[row], limbs)
        m[row][sel] = MATS.index("pants")
        l[row][sel] = 0.0
        beltm[row] = sel

    # 머리 하이라이트 띠 — 정수리 쪽 밝은면을 한 단계 더 올린다. 검은 머리는
    # 색이 아니라 이 광택으로 읽힌다(STYLE_GUIDE 「자연스러움」: 윗면에 밝은 띠).
    if cfg["hair_shine"]:
        crown = (m == HAIR) & (np.arange(N)[:, None] <= int(round(hy - ry * 0.35)))
        top_row = crown & ~np.pad(crown, ((1, 0), (0, 0)))[:-1]
        l[np.pad(top_row, ((1, 0), (0, 0)))[:-1] & crown] += cfg["hair_shine"]

    ey = cfg["eye_y"] + int(round(bob))
    ew = len(EYE_ART[cfg["eye_style"]][0])

    def eye_x(center):
        """눈 덩어리의 왼쪽 칸. 중심 좌표를 칸 격자에 앉힌다."""
        return int(np.floor(center - ew * 0.5 + 0.5))

    if direction == "down":
        # **왼쪽 눈을 찍고 오른쪽은 그 거울상으로 잡는다.** 앞모습은 좌우대칭이라
        # 양쪽을 따로 반올림하면 한 칸이 어긋나서 눈이 짝짝이가 된다.
        left = eye_x(hx - cfg["eye_dx"])
        right = N - 1 - (left + ew - 1)
        eye(left, ey)
        eye(right, ey, flip=True)
        if cfg["blush"]:
            blush(left - 1, ey + 1)
            blush(right + ew, ey + 1)
    elif side:
        ax = eye_x(hx + sx * cfg["eye_dx"] * 0.55)
        eye(ax, ey, flip=sx < 0)
        if cfg["blush"]:
            blush(ax - 1 if sx < 0 else ax + ew, ey + 1)

    return outline(inner_lines(quantize(m, l, pal, cfg["dither"]), m, pm, pal, skip=beltm), m)


# ── 후보 비교용 유틸 ───────────────────────────────────────────────────────
def to_img(rgb, scale=1):
    im = Image.fromarray(rgb, "RGBA")
    return im.resize((N * scale, N * scale), Image.NEAREST) if scale != 1 else im


def strip(imgs, pad=8, bg=(30, 28, 34, 255)):
    w = sum(i.width for i in imgs) + pad * (len(imgs) + 1)
    h = max(i.height for i in imgs) + pad * 2
    s = Image.new("RGBA", (w, h), bg)
    x = pad
    for im in imgs:
        s.alpha_composite(im, (x, pad))
        x += im.width + pad
    return s


def stack(imgs, pad=8, bg=(30, 28, 34, 255)):
    w = max(i.width for i in imgs) + pad * 2
    h = sum(i.height for i in imgs) + pad * (len(imgs) + 1)
    s = Image.new("RGBA", (w, h), bg)
    y = pad
    for im in imgs:
        s.alpha_composite(im, (pad, y))
        y += im.height + pad
    return s


DIRS = ["down", "left", "right", "up"]   # 시트의 행 순서 — QA/씬이 이 순서를 믿는다

# 실제 게임 자산이 나가는 자리. 시트는 **행 = 방향, 열 = 프레임**이다 —
# 걷기(프레임 4~6장)가 붙어도 시트가 옆으로만 늘어나서 행 규칙이 그대로 유지된다.
SPRITES = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites"))


def sheet(frames_of, pal=None, **over):
    """`frames_of(direction) -> [rgb, ...]` 를 받아 행=방향 시트를 만든다."""
    cols = max(len(frames_of(d)) for d in DIRS)
    im = Image.new("RGBA", (N * cols, N * len(DIRS)), (0, 0, 0, 0))
    for r, d in enumerate(DIRS):
        for c, f in enumerate(frames_of(d)):
            im.alpha_composite(to_img(f), (N * c, N * r))
    return im


def idle_sheet(pal=None, **over):
    return sheet(lambda d: [character(d, pal=pal, **over)])


def walk_sheet(pal=None, **over):
    """걷기 시트 — 행 = 방향, 열 = `WALK_FRAMES` 개의 위상.

    **idle 과 같은 `character()` 를 부른다** — 프레임마다 형태를 다시 정의하지
    않고 `walk_pose()` 가 준 오프셋만 넣는다. 그래야 프레임 사이에서 캐릭터가
    차지하는 크기와 자세가 어긋나지 않는다(DESIGN.md 「캐릭터 애니메이션」).
    """
    phases = walk_phases()
    return sheet(lambda d: [character(d, phase=ph, pal=pal, **over) for ph in phases])


## 패기 한 바퀴 프레임 수. 걷기와 같은 6장이다 — `qa_sprite_check.py` 의 「이어짐」이
## 한 프레임에 바뀌는 몸 픽셀을 0.30 으로 자르는데, 도끼가 도는 각도(82도)를 넉 장에
## 나누면 그 상한을 넘는다. **4장으로 줄이면 올라갈 때와 내려올 때가 같은 그림이
## 되기도 한다**(cos 이 0 인 두 자리) — 걷기에서 위상을 반 칸 밀었을 때와 같은 실패다.
USE_FRAMES = 6


def use_phases(frames=USE_FRAMES):
    return [i / frames for i in range(frames)]


def hold_sheet(tool, pal=None, **over):
    """도구를 들고 서 있기 — idle 과 같은 1프레임이다."""
    return sheet(lambda d: [character(d, pal=pal, tool=tool, motion="hold", **over)])


def use_sheet(tool, pal=None, **over):
    return sheet(lambda d: [character(d, phase=ph, pal=pal, tool=tool, motion="use", **over)
                            for ph in use_phases()])


def tool_walk_sheet(tool, pal=None, **over):
    return sheet(lambda d: [character(d, phase=ph, pal=pal, tool=tool, motion="walk", **over)
                            for ph in walk_phases()])


def tool_motions(tool):
    """도구 하나가 만드는 모션 3종 (DESIGN.md 「새 도구를 추가하는 절차」 1)."""
    return (("hold_%s" % tool, lambda **kw: hold_sheet(tool, **kw)),
            ("use_%s" % tool, lambda **kw: use_sheet(tool, **kw)),
            ("walk_%s" % tool, lambda **kw: tool_walk_sheet(tool, **kw)))


# 아이콘은 같은 도끼를 **캔버스 가득** 그린 것이다 — 손에 쥔 것(자루 5.3px)을 그대로
# 키우면 칸 안에서 좁쌀만 하게 보인다. 같은 램프·같은 광원·같은 `wedge` 라 손에
# 쥔 것과 같은 도끼로 읽히고, **날을 몸통 대비 크게** 잡는다(17px 칸 하나에 도끼
# 하나뿐이라 날이 작으면 무슨 도구인지 안 읽힌다).
#
# **자루를 거의 세운다(76도).** 45~58도로 눕히면 날의 축이 그만큼 기울어서 **날의
# 곧은 변이 대각선**이 되는데, 5px 짜리 날에서 대각선 변은 계단 두 칸이라 쐐기가
# 안 읽히고 깃발처럼 보인다(실제로 50/58/66/74도를 나란히 뽑아 비교했다).
# 세우면 날의 변이 세로에 가까워져 도끼로 읽힌다 — **아이콘은 실루엣이 전부라
# 「각짐」(캐릭터 옆선 규칙)을 여기에 적용하지 않는다.**
ICON_AXE = dict(AXE, helve=8.6, helve_r=(0.95, 0.75),
                bit_a=(-0.7, 0.6), bit_b=(3.6, -0.2), bit_r=(0.75, 3.4), bit_bulge=0.26)
# 곡괭이 아이콘 (INBOX #26). **도끼 아이콘과 같은 자루 굵기·같은 여백**이라야 칸에
# 나란히 놓였을 때 하나만 커 보이지 않는다(STYLE_GUIDE 10번 `item_axe_x6.png`).
# 머리는 손에 쥔 것과 같은 두 갈래인데, **아이콘에서는 갈래를 더 길고 가늘게**
# 뽑는다 — 칸 하나에 곡괭이 하나뿐이라 뭉툭하면 망치로 읽힌다.
# **자루를 도끼보다 더 세운다(84도).** 머리가 좌우 대칭이라 자루를 기울이면 두 갈래의
# 높이가 어긋나서 한쪽만 달린 것처럼(=도끼처럼) 보인다 — 세워야 대칭이 살아난다.
# **아이콘의 갈래는 손에 쥔 것보다 굵다.** 가늘게 뽑았더니 갈래가 어두워져서
# (가는 원기둥은 윗면이 좁아 광원을 거의 못 받는다) 옆 칸의 도끼날보다 한 단계
# 탁해 보였다 — 「어울림」이 깨진다. 굵히면 윗면이 넓어져 도끼날과 같은 밝기가
# 나오고, 뾰족함은 굵기가 아니라 **끝이 크로스바에서 대각선으로 떨어진 것**이
# 만든다(손에 쥔 것과 같은 이유).
ICON_PICKAXE = dict(PICKAXE, helve=8.2, helve_r=(0.95, 0.75),
                    tine_a=(0.3, 0.7), tine_c=(2.8, 1.2), tine_b=(4.9, -3.4),
                    tine_r=(1.45, 0.80), tine_dome=0.85, eye=1.2)
# 낫 아이콘 (INBOX #27). 자루 굵기·여백은 도끼/곡괭이 아이콘 그대로다. 다른 것은
# **자루가 짧고 날이 크다** — 손에 쥔 낫과 같은 비율이라야 칸 안의 그림과 손에 쥔
# 그림이 같은 도구로 보인다. 칸 하나에 낫 하나뿐이라 날은 손에 쥔 것보다 **굵게**
# 뽑는다(곡괭이 아이콘과 같은 이유 — 가는 원기둥은 윗면이 좁아 광원을 거의 못
# 받아서 옆 칸의 도끼날보다 탁해 보인다).
ICON_SICKLE = dict(SICKLE, helve=4.8, helve_r=(0.95, 0.78),
                   moon_c=(1.2, 3.0), moon_r=5.6, moon_cut=(-1.39, -0.98), moon_r2=4.6,
                   moon_dome=0.85)
ICONS = {"axe": dict(kit=ICON_AXE, grip=(4.6, 13.2), angle=74.0),
         # 낫은 자루가 짧고 날이 위로 크게 감기므로 손잡이를 **칸 아래쪽**에
         # 둔다. 자루를 세우는 것은 도끼/곡괭이와 같다 — 눕히면 날의 감긴 축이
         # 대각선이 되어 초승달이 계단으로 뭉개진다.
         "sickle": dict(kit=ICON_SICKLE, grip=(5.2, 14.8), angle=84.0),
         # 곡괭이는 머리가 좌우 대칭이라 **자루를 칸 한가운데 세운다**(도끼는 날이
         # 한쪽으로만 나가서 자루를 왼쪽에 붙였다). 84도 — 여기서 더 눕히면
         # 크로스바가 기울어 한쪽 갈래만 내려간다.
         "pickaxe": dict(kit=ICON_PICKAXE, grip=(8.2, 14.2), angle=84.0)}


def tool_icon(tool="axe", pal=None):
    """인벤토리 칸에 보일 도구 아이콘 한 장(17px).

    **월드의 도끼와 같은 파이프라인으로 그린다** — 같은 램프, 같은 광원(왼쪽 위),
    같은 잉크 외곽선. 아이콘만 따로 그리면 칸 안의 그림과 손에 쥔 그림이 다른
    손에서 나온 것처럼 보인다(DESIGN.md 「그래픽 파이프라인」 1) 어울림).
    화면에서는 2배(34px)로 그려서 「아이템/오브젝트 크기 표준」의 16px 하한을 넘긴다.
    """
    spec = ICONS[tool]
    pal = pal or palette()
    b = Build()
    draw_tool(b, spec["grip"][0], spec["grip"][1], spec["angle"], 1.0, spec["kit"], lift=0.0)
    lum = light(b.hgt, b.mat, key=CFG["key"], amb=CFG["amb"], rim=CFG["rim"])
    m, l = downsample(b.mat, lum)
    pm = downsample_part(b.part)
    return outline(inner_lines(quantize(m, l, pal, 0.0), m, pm, pal), m)


def icon_path(tool):
    return f"{SPRITES}/item_{tool}.png"


def motion_path(motion, style):
    """머리모양 하나당 시트 하나. `player_frames.gd` 의 `sheet_path()` 와 같은 규칙이다."""
    return f"{SPRITES}/player_{motion}_{style}.png"


def idle_path(style):
    return motion_path("idle", style)


def walk_path(style):
    return motion_path("walk", style)


# ── Godot 쪽 팔레트 표 ─────────────────────────────────────────────────────
# 게임은 **기준색으로 구운 시트 한 장의 색을 바꿔치기해서** 나머지 색을 만든다
# (STYLE_GUIDE 2번 — 형태를 다시 그리지 않는다). 그러려면 Godot 이 램프 색을
# 알아야 하는데, 위 `make_ramp()` 를 GDScript 로 옮겨 적으면 반드시 어긋난다.
# 그래서 **여기서 계산한 값을 GDScript 상수 파일로 뽑아준다**(손으로 고치지 말 것).
PALETTE_GD = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "character_palettes.gd"))

# `character_appearance.gd` 의 팔레트와 같아야 한다. 여기만 늘리면 화면에는 안
# 뜨고, 저기만 늘리면 램프가 없어서 색이 안 바뀐다 — `qa_character_customize.gd`
# 가 둘이 같은지 검사한다.
SKIN_IDS = [("light", "f0c8a0"), ("warm", "d9a066"), ("tan", "b07a4a"),
            ("brown", "7a4a2b"), ("deep", "4e2e1c")]
HAIR_IDS = [("black", "211c1a"), ("brown", "6b4a2a"), ("blond", "d8b25c"),
            ("auburn", "93402a"), ("silver", "b9bdb6"), ("indigo", "3e5c7a")]
CLOTH_IDS = [("grass", "4e7a3a"), ("sky", "3e6e9e"), ("earth", "7a5230"),
             ("plum", "7a3b5e"), ("ash", "5a5f58"), ("ember", "b4543a")]


def _rgb_hex(c):
    return "%02x%02x%02x" % tuple(int(v) for v in c)


def export_palettes(path=PALETTE_GD):
    """커스터마이징 선택지별 램프를 GDScript 상수로 뽑는다.

    **밴드가 항목마다 독립이라 이렇게 쪼갤 수 있다** — 피부 램프는 피부색만,
    머리 램프는 머리색만, 셔츠/바지/신발 램프는 옷색만 보고 정해진다
    (`bands_for()`). 그래서 5×6×6 조합을 다 굽지 않고 5+6+6 줄이면 된다.
    """
    def ramps(mat, table, **kw):
        rows = []
        for cid, hexcolor in table:
            pal = palette(**{kw["key"]: hexcolor})
            mats = kw["mats"]
            if len(mats) == 1:
                body = "[%s]" % ", ".join('"%s"' % _rgb_hex(c) for c in pal[mats[0]])
            else:
                body = "{%s}" % ", ".join(
                    '"%s": [%s]' % (m, ", ".join('"%s"' % _rgb_hex(c) for c in pal[m]))
                    for m in mats)
            rows.append('\t"%s": %s,' % (cid, body))
        return "\n".join(rows)

    text = '''extends RefCounted

## **자동 생성 파일이다 — 손으로 고치지 말 것.**
## `game/tools/gen_character.py` 의 `export_palettes()` 가 만든다
## (`.venv/bin/python game/tools/gen_character.py`).
##
## 왜 이런 게 필요한가: 캐릭터 스프라이트는 **기준색 1벌로만 굽고**, 나머지 색은
## 그 PNG 의 색을 바꿔치기해서 만든다(`docs/STYLE_GUIDE.md` 2번 — 형태를 다시
## 그리지 않는다). 그러려면 게임이 재질별 4단계 램프의 실제 색을 알아야 하는데,
## 램프를 만드는 계산(`make_ramp()`)을 GDScript 로 옮겨 적으면 생성기와 어긋난다.
## 그래서 **생성기가 계산한 값을 그대로 여기에 적어 내려보낸다.**
##
## 항목마다 램프가 독립이라 5×6×6 조합을 다 적을 필요가 없다 — 피부색은 피부
## 램프만, 머리색은 머리 램프만, 옷색은 셔츠/바지/신발 램프를 정한다.

## 시트를 구울 때 쓴 기준색. 색 바꿔치기의 **출발점**이다.
## 키는 `character_appearance.gd` 의 항목 이름과 같다.
const BASE := {"skin": "%s", "hair_color": "%s", "clothes_color": "%s"}

## 공통 잉크색(외곽선·눈)과 눈 하이라이트 — 커스터마이징과 무관하게 고정이다.
const INK := "%s"
const GLINT := "%s"

## 피부색 하나가 피부 램프와 **볼 홍조** 색을 함께 정한다(홍조는 단계가 하나다).
const SKIN := {
%s
}

const HAIR := {
%s
}

## 옷색 하나가 셔츠/바지/신발 세 재질의 램프를 함께 정한다.
const CLOTHES := {
%s
}
''' % (BASE_SKIN_ID, BASE_HAIR_ID, BASE_CLOTH_ID, _rgb_hex(INK), _rgb_hex(GLINT),
       ramps("skin", SKIN_IDS, key="skin", mats=["skin", "blush"]),
       ramps("hair", HAIR_IDS, key="hair", mats=["hair"]),
       ramps("cloth", CLOTH_IDS, key="cloth", mats=["shirt", "pants", "boot"]))
    with open(path, "w") as f:
        f.write(text)
    return path


# 이번에 다시 굽는 모션. 2026-09-07 (INBOX #20) 에 걷기가 돌아왔다 — `CFG` 의
# 걷기 진폭을 17px 격자에서 다시 잡아서 idle 과 같은 칸 크기로 굽는다.
MOTIONS_NOW = (("idle", idle_sheet), ("walk", walk_sheet))
for _t in TOOLS:                      # 도구가 늘면 `TOOLS` 한 줄만 늘어난다
    MOTIONS_NOW = MOTIONS_NOW + tool_motions(_t)

if __name__ == "__main__":
    for style in HAIR_STYLES:
        for motion, make in MOTIONS_NOW:
            p = motion_path(motion, style)
            make(hair=style).save(p)
            print("saved", p)
    for tool in ICONS:
        to_img(tool_icon(tool)).save(icon_path(tool))
        print("saved", icon_path(tool))
    print("saved", export_palettes())
    if os.environ.get("GEN_OUT"):     # 후보 비교용 — 저장소를 더럽히지 않는다
        strip([to_img(character(d), 6) for d in DIRS]).save(f"{OUT}/idle_x6.png")
        strip([to_img(character(d), 3) for d in DIRS]).save(f"{OUT}/idle_x3.png")
        stack([strip([to_img(character(d, hair=s), 6) for d in DIRS])
               for s in HAIR_STYLES]).save(f"{OUT}/hairstyles_x6.png")
        stack([strip([to_img(character(d, hair=s), 3) for d in DIRS])
               for s in HAIR_STYLES]).save(f"{OUT}/hairstyles_x3.png")
        # 걷기는 **idle 을 맨 앞에 붙여서** 본다 — 프레임끼리 이어지는지만이 아니라
        # idle 에서 걷기로 넘어갈 때 자세가 뚝 끊기지 않는지도 같이 봐야 한다
        # (DESIGN.md 「캐릭터 애니메이션」).
        if any(m == "walk" for m, _ in MOTIONS_NOW):
            for scale in (6, 3):
                stack([strip([to_img(character(d), scale)]
                             + [to_img(character(d, phase=ph), scale) for ph in walk_phases()])
                       for d in DIRS]).save(f"{OUT}/walk_x{scale}.png")
        # 도구 — **맨 앞 칸이 맨손 idle 이다.** 도구를 들었다고 다른 캐릭터가 되지
        # 않았는지는 나란히 놓아야 보인다(DESIGN.md 「캐릭터 애니메이션」의 "이어짐").
        for tool in TOOLS:
            for scale in (6, 3):
                stack([strip([to_img(character(d), scale),
                              to_img(character(d, tool=tool, motion="hold"), scale)])
                       for d in DIRS]).save(f"{OUT}/{tool}_hold_x{scale}.png")
                # 맨 앞 두 칸이 **맨손 idle · 그 도구를 들고 서 있기**다 — 도구를
                # 들었다고 다른 캐릭터가 됐는지, 그리고 들고 있기에서 그 모션으로
                # 자연스럽게 넘어가는지는 나란히 놓아야 보인다.
                for name, phases in (("use", use_phases()), ("walk", walk_phases())):
                    stack([strip([to_img(character(d), scale),
                                  to_img(character(d, tool=tool, motion="hold"), scale)]
                                 + [to_img(character(d, tool=tool, motion=name, phase=ph), scale)
                                    for ph in phases])
                           for d in DIRS]).save(f"{OUT}/{tool}_{name}_x{scale}.png")
            for scale in (12, 6, 3):
                to_img(tool_icon(tool), scale).save(f"{OUT}/{tool}_icon_x{scale}.png")
