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

MATS = ["skin", "hair", "shirt", "pants", "boot", "blush", "eye", "glint"]

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
    return limbs + far


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


def character(direction="down", hair="short", pal=None, cfg=None, phase=None, **over):
    """한 프레임을 그린다. `phase=None` 이면 idle, 0~1 이면 걷기 위상."""
    cfg = dict(CFG, **(cfg or {}))
    cfg.update(over)
    pal = pal or palette()
    pose = walk_pose(direction, phase, cfg)
    bob = pose["bob"]
    b = Build()

    limbs = _body(b, direction, cfg, pose)
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

if __name__ == "__main__":
    for style in HAIR_STYLES:
        for motion, make in MOTIONS_NOW:
            p = motion_path(motion, style)
            make(hair=style).save(p)
            print("saved", p)
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
