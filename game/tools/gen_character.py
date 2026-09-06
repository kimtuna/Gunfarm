"""코어키퍼풍 캐릭터 절차 생성 — 슈퍼샘플 + 입체 음영 + 팔레트 디더링.

실행: `.venv/bin/python game/tools/gen_character.py` (시스템 python3 에는 numpy 가 없다)

왜 이렇게 하나 (`docs/STYLE_GUIDE.md` 「권장 파이프라인」):
  도트를 한 픽셀씩 직접 찍으면 "평평"해진다(테두리에만 음영이 걸림). 대신
  1) 캐릭터를 입체 덩어리(구/캡슐/둥근상자)의 합으로 정의하고
  2) 12배 해상도에서 각 덩어리의 높이장(height field)에서 법선을 구해 램버트 조명을 계산하고
  3) 네이티브 34px 로 줄이고 (재질·부위는 최빈값, 명도는 평균)
  4) 재질별 팔레트 램프(4단계)에 순서 디더링으로 양자화한 뒤 내부선 → 외곽선.

**팔레트는 커스터마이징 색에서 만들어진다.** `game/scripts/character_appearance.gd` 의
피부/머리/옷 색 하나를 넣으면 그 색을 기준으로 4단계 램프가 생성된다 — 형태를 다시
그리지 않고 램프만 갈아끼우는 게 색상 확장 방식이다(STYLE_GUIDE 2번).

크기: 네이티브 34px, 게임 화면 102px = 정확히 3배(정수 배율).
"""
import os

import numpy as np
from PIL import Image

N = 34          # 네이티브 캔버스
SS = 12         # 슈퍼샘플 배율
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

# 바지/신발은 옷색을 어둡게 쓴다 — 팔레트를 늘리지 않고 상하의를 구분한다
# (DESIGN.md 「캐릭터 커스터마이징 항목」). 실제 어두워지는 정도는 아래 BANDS 의
# 목표 명도가 정한다 — 여기 계수는 "무슨 색을 어둡게 쓸 것인가"(색상)만 정한다.
PANTS_DARKEN = 0.62
SHOES_DARKEN = 0.44

MATS = ["skin", "hair", "shirt", "pants", "boot", "eye", "glint"]

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
HAIR_MIN = 50.0             # 검정 머리는 색이 아니라 광택 단차로 읽힌다 — 램프를
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
        # 바지·신발은 같은 옷색을 쓰되 목표 명도로 밴드를 갈라놓는다.
        "pants": make_ramp(darken(cloth_rgb, PANTS_DARKEN), band["pants"], hi_mix=0.14),
        "boot": make_ramp(darken(cloth_rgb, SHOES_DARKEN), band["boot"], hi_mix=0.12,
                          ramp=(1.30, 1.0, 0.88, 0.80)),
        "eye": [INK] * 4,
        "glint": [GLINT] * 4,
    }


# ── 좌표 격자 (네이티브 단위, 슈퍼샘플 해상도) ──────────────────────────────
_yy, _xx = np.mgrid[0:H, 0:H].astype(np.float32)
GX = (_xx + 0.5) / SS
GY = (_yy + 0.5) / SS


# 뒷머리 헤어라인 물결 (반지름, y 오프셋, x 위치들). 크게 하면 덤불처럼 보인다 —
# 뒷모습은 얼굴이 없어서 실루엣이 전부이므로 여기서 과하면 곧바로 티가 난다.
_UP = (1.25, -2.2, (-3.8, -1.9, 0.0, 1.9, 3.8))
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


def inner_lines(rgb, mat, part, pal):
    """다른 부위와 맞닿은 안쪽 픽셀을 한 단계 어둡게 해서 경계를 살린다.

    팔과 몸통은 같은 'shirt' 재질이라 음영만으로는 경계가 사라진다. 바깥
    외곽선처럼 잉크로 긋지 않고 **그 재질 램프의 가장 어두운 색**을 쓰는 게
    핵심이다 — 잉크로 그으면 캐릭터가 조각조각 잘려 보인다.
    """
    filled = mat >= 0
    p = part
    # 광원이 왼쪽 위이므로 그늘은 경계의 **오른쪽/아래** 픽셀에 떨어진다.
    # (반대쪽에 찍으면 밝은 면에 선이 그어져서 형태가 거꾸로 읽힌다.)
    diff = np.zeros((N, N), dtype=bool)
    diff[:, 1:] |= filled[:, :-1] & filled[:, 1:] & (p[:, :-1] != p[:, 1:])
    diff[1:, :] |= filled[:-1, :] & filled[1:, :] & (p[:-1, :] != p[1:, :])
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
# 비율(STYLE_GUIDE 3번): 머리 2~15.5 / 몸통 15~24 / 다리 24~29 / 신발 29~31.5
CFG = dict(
    head_rx=6.0, head_ry=6.5, head_cy=8.8,
    torso_w=10.2, torso_top=15.2, torso_bot=23.6,
    side_torso_w=8.4,
    arm_w=2.7,
    belt=True, limb_shade=0.18, contact=0.18, cuff=0.30,
    torso_r=2.3, ears=0, arm_in=0.95, shoe_lip=0.30,
    fringe=9.2, fringe_tilt=1.5, side_hair=13.2,
    eye_y=11, eye_dx=2, glint=True,
    dither=0.0, key=0.84, amb=0.17, rim=0.10,
    # ── 걷기(walk) ── 진폭은 전부 **네이티브 34px 단위**다. 1 = 화면에서 3px.
    bob=1.0,            # 몸이 가라앉는 깊이. 착지에서 최대, 통과 자세에서 0
    lift=1.6,           # 뒤에서 앞으로 넘어오는 발이 뜨는 높이
    stride=1.7,         # 옆모습에서 다리가 앞뒤로 벌어지는 폭
    stride_f=0.75,      # 앞/뒷모습 — 앞뒤 움직임이 안 보이므로 좌우로만 조금
    arm_swing=1.5,      # 옆모습 팔 앞뒤 폭 (다리와 반대 위상)
    arm_swing_f=0.9,    # 앞/뒷모습 팔 — 앞으로 나오면 짧아 보이므로 위아래로
)

WALK_FRAMES = 6         # DESIGN.md 「캐릭터 애니메이션」의 4~6 프레임 규칙


def walk_pose(direction, phase, cfg):
    """걷기 위상(0~1) → 부위별 오프셋. `phase=None` 이면 idle(전부 0).

    한 바퀴를 이렇게 잡았다 — 이 위상 관계가 어긋나면 걷기로 안 보인다:
      - `cos` 로 다리를 앞뒤로 흔든다. 착지(cos=±1)에서 가장 벌어지고,
        통과 자세(cos=0)에서 두 다리가 겹친다.
      - **몸은 통과 자세에서 가장 높고 착지에서 가라앉는다.** 위로 띄우지 않고
        아래로 내리는 쪽을 골랐다 — idle 이 이미 칸 위쪽 1px 만 남기고 꽉 차서,
        올리면 머리 외곽선이 칸 밖으로 잘린다.
      - **발이 뜨는 건 뒤에서 앞으로 넘어오는 동안뿐이다**(sin 의 한쪽 반주기).
        양발이 동시에 뜨면 뛰는 것처럼 보인다.
      - 팔은 다리와 **반대 위상**이다.
    """
    if phase is None:
        return dict(bob=0.0, leg_dx=(0.0, 0.0), leg_lift=(0.0, 0.0),
                    arm_dx=(0.0, 0.0), arm_dy=(0.0, 0.0))
    t = 2.0 * np.pi * float(phase)
    sw = float(np.cos(t))                       # +1 = 왼다리가 앞
    sn = float(np.sin(t))
    lift = (max(0.0, -sn) * cfg["lift"], max(0.0, sn) * cfg["lift"])
    bob = cfg["bob"] * (1.0 - abs(sn))
    if direction in ("left", "right"):
        sx = 1.0 if direction == "right" else -1.0
        return dict(
            bob=bob,
            leg_dx=(sw * cfg["stride"] * sx, -sw * cfg["stride"] * sx),
            leg_lift=lift,
            arm_dx=(-sw * cfg["arm_swing"] * sx,) * 2,
            arm_dy=(0.0, 0.0),
        )
    return dict(
        bob=bob,
        leg_dx=(sw * cfg["stride_f"], -sw * cfg["stride_f"]),
        leg_lift=lift,
        arm_dx=(0.0, 0.0),
        # 앞/뒷모습에서 앞으로 나온 팔은 짧고 살짝 올라가 보인다
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
    cx = 17.0 + (0.5 * sx if side else 0.0)
    tw = cfg["side_torso_w"] if side else cfg["torso_w"]
    bob = pose["bob"]
    top, bot = cfg["torso_top"] + bob, cfg["torso_bot"] + bob

    # 다리 — 사이를 1.2px 비워 두면 외곽선이 그 틈에 들어가 두 다리로 읽힌다.
    # 옆모습은 두 다리가 거의 겹치므로 간격을 좁히고 앞뒤(x)로만 벌린다.
    lw = 3.9 if not side else 3.7
    gap = 0.6 if not side else 0.0
    for i, sgn in enumerate((-1, 1)):
        lx = cx + sgn * (lw / 2 + gap) + pose["leg_dx"][i]
        foot = 31.5 - pose["leg_lift"][i]
        b.add(rbox(lx - lw / 2, 23.2 + bob, lx + lw / 2, foot - 2.2, r=1.3), "pants")
        b.add(rbox(lx - lw / 2 - 0.4, foot - 2.7, lx + lw / 2 + 0.4, foot, r=1.0), "boot")

    # 목 (몸통보다 먼저 — 뒤로 간다)
    b.add(rbox(cx - 1.6, 12.8 + bob, cx + 1.6, top + 1.2, r=1.1), "skin")

    # 몸통
    b.add(rbox(cx - tw / 2, top, cx + tw / 2, bot, r=cfg["torso_r"]), "shirt")

    # 팔 — 몸통과 다른 부위 id 라서 경계에 내부선이 들어간다.
    # 팔은 몸통에 **살짝 파묻어야** 한다. 어깨 모서리가 둥근 만큼 바깥에 두면
    # 어깨 높이에서 몸통과 떨어져 팔만 붕 뜬 2px 조각이 된다.
    aw = cfg["arm_w"]
    off = tw / 2 + aw / 2 - cfg["arm_in"]
    xs = [sx * 2.0] if side else [-off, off]
    limbs = []
    for i, offx in enumerate(xs):
        ax = cx + offx + pose["arm_dx"][i]
        ay = bob + pose["arm_dy"][i]
        arm_top, arm_bot = cfg["torso_top"] + 1.1 + ay, cfg["torso_bot"] - 1.6 + ay
        limbs.append(b.add(rbox(ax - aw / 2, arm_top, ax + aw / 2, arm_bot, r=1.25), "shirt"))
        # 손은 벙어리장갑 모양 — 소매 끝에서 살짝 넓어진다
        limbs.append(b.add(ellipsoid(ax, arm_bot + 1.15, 1.55, 1.5), "skin"))
    return limbs


def _fall_shape(cx, hw, y0, y1, taper=1.0, tip=1.3):
    """아래로 흘러내리는 머리단 — 아래로 갈수록 좁아지고 끝이 둥근 기둥.

    `rbox` 로는 못 만든다(폭이 일정하다). 도트에서 머리단이 "붙인 판자"로 안
    보이려면 **끝이 좁아지고 둥글어야** 한다. 높이는 x 방향으로 부푼 원기둥이라
    가운데가 밝고 양옆이 그늘진다 — 머리 껍데기와 같은 입체감이 나온다.
    """
    t = np.clip((GY - y0) / max(y1 - y0, 1e-6), 0.0, 1.0)
    half = np.maximum(hw - taper * t, 0.6)
    dx = np.abs(GX - cx)
    body = (GY >= y0) & (GY <= y1 - tip) & (dx <= half)
    # 끝동 — 잘린 자리가 자로 그은 듯 반듯하면 가발처럼 보인다
    ty = np.clip((GY - (y1 - tip)) / tip, 0.0, 1.0)
    cap = (GY > y1 - tip) & (GY <= y1) & (dx <= half * np.sqrt(np.clip(1 - ty * ty, 0, 1)))
    m = body | cap
    h = np.sqrt(np.clip(1 - (dx / np.maximum(half, 1e-6)) ** 2, 0, 1)) * (ROUND * hw)
    return m, h * m


def _tail(b, part, cx, y0, y1, lift, w=2.2):
    """묶은 꼬리 — 위아래가 뾰족한 타원. 폭이 일정한 막대기로 만들면 꼬리가
    아니라 손잡이로 보인다. 머리 껍데기와 겹치게 시작해서 실루엣을 잇는다."""
    return b.add(ellipsoid(cx, (y0 + y1) * 0.5, w, (y1 - y0) * 0.5),
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
#   strand  앞머리에 결 한 줄을 넣을지 (좌우대칭을 깨서 밋밋함을 없앤다)
#   tail    묶은 꼬리 길이. 0 이면 없다
HAIR_STYLES = {
    "short":    dict(sides=0.0,  fall=0.0, fw=0.0,  back=0.0, strand=True,  tail=0.0),
    "bob":      dict(sides=2.4,  fall=1.1, fw=2.45, back=2.4, strand=False, tail=0.0),
    "long":     dict(sides=2.0,  fall=5.8, fw=1.65, back=6.8, strand=False, tail=0.0),
    "ponytail": dict(sides=-1.2, fall=0.0, fw=0.0,  back=0.0, strand=False, tail=5.2),
}


def _hair(b, d, cfg, hx, hy, rx, ry, style, bob=0.0):
    """머리카락. 앞머리는 얼굴보다 앞으로 lift 해서 경계가 살아나게 한다.

    **덧붙이는 갈래는 전부 머리 껍데기(shell) 안으로 잘라 넣는다** — 안 그러면
    실루엣 밖으로 혹처럼 튀어나온다. 껍데기 **밖으로** 나가는 것(흘러내린 머리단,
    묶은 꼬리)은 예외인데, 그때는 반드시 껍데기와 겹치게 시작해야 실루엣이 한
    덩어리로 남는다(`qa_sprite_check.py` 「실루엣」).
    """
    st = HAIR_STYLES.get(style, HAIR_STYLES["short"])
    grow = 0.15 if d == "up" else 0.6   # 뒷모습은 얼굴이 없어 껍데기가 곧 실루엣이다
    shell = ellipsoid(hx, hy, rx + grow, ry + 0.5)
    sm = shell[0]
    # 머리카락 끝(헤어라인)을 물결지게 만드는 작은 덩어리들 — 실루엣 아랫변이
    # 완전한 원호면 머리가 헬멧처럼 보인다. 도트에서 "머리카락"으로 읽히는 건
    # 색이 아니라 이 들쭉날쭉한 끝선이다.
    def scallop(cy, offs, r=1.7):
        m = np.zeros_like(sm)
        h = np.zeros_like(shell[1])
        for i, off in enumerate(offs):
            mm, hh = ellipsoid(hx + off, cy, r, r * 1.05, squash=ROUND * (rx + grow))
            m |= mm
            h = np.maximum(h, hh)
        return m, h
    side = d in ("left", "right")
    sx = 1.0 if d == "right" else -1.0
    LIFT = 0.10

    if d == "up":
        # 뒷모습 — 머리 전체가 머리카락. 아랫변을 물결지게 해서 헬멧처럼 안 보이게.
        cap = b.add(shell, "hair", lift=LIFT)
        # 정수리 가마 — 실루엣은 건드리지 않고 높이만 살짝 올려 밝은 자리를 만든다.
        # 뒷모습에서 헤어라인을 물결지게 해봤더니 덤불처럼 보여서 이쪽을 골랐다.
        b.add(ellipsoid(hx - 1.7, hy - 2.2, 3.0, 2.7), "hair",
              mask=sm, part=cap, lift=LIFT + 0.05, blend="max")
        # 뒤로 이어지는 머리단(단발/긴머리) — 껍데기와 겹치게 시작한다.
        # 아래로 갈수록 좁아지는 사다리꼴이라야 어깨에 얹힌 것처럼 보인다.
        nape = None
        if st["back"] > 0.0:
            nape = _fall_shape(hx, rx + grow - 0.7, hy, hy + ry + 0.5 + st["back"], taper=1.4)
            b.add(nape, "hair", part=cap, lift=LIFT)
        if st["tail"] > 0.0:
            # 뒷모습 — 꼬리는 **머리보다 확실히 좁아야** 묶인 것으로 읽힌다.
            # 넓게 잡았더니 머리와 이어진 한 덩어리가 되어 긴머리처럼 보였다.
            ty0, ty1 = hy + 4.2, hy + ry + 0.5 + st["tail"]
            tail = ellipsoid(hx, (ty0 + ty1) * 0.5, 2.15, (ty1 - ty0) * 0.5)
            b.add(tail, "hair", part=cap, lift=LIFT)
            b.add(tail, "hair", mask=GX > hx + 0.4, lift=LIFT)   # 결 한 줄
        # 머리결 — **부위 id 만 다른 같은 껍데기**를 세로로 몇 줄 얹으면 그 경계에
        # 내부선이 들어가 머리카락 가닥이 된다. 이게 없으면 뒷모습이 매끈한
        # 회색 달걀(=민머리/헬멧)로 보인다. 물결진 헤어라인은 여기서도 덤불이
        # 됐고, 세로 결이 훨씬 머리카락처럼 읽혔다.
        for off in (-3.6, 0.3, 3.8):
            band = np.abs(GX - (hx + off)) < 0.9
            b.add(shell, "hair", mask=sm & band, lift=LIFT)
            if nape is not None:
                b.add(nape, "hair", mask=band, lift=LIFT)
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
              mask=(np.abs(GX - hx) > rx - 1.2) & (GY <= down) & (GX * s > hx * s),
              part=cap, lift=LIFT)

    if side:
        # 뒤통수는 목까지 덮는다
        b.add(shell, "hair",
              mask=((GX - hx) * sx < -(rx - 2.4)) & (GY <= down + 1.4),
              part=cap, lift=LIFT)

    # 옆머리 끝을 물결지게 — 자른 자리가 자로 그은 듯 반듯하면 가발처럼 보인다
    ends = [-(rx - 0.6), rx - 0.6] if not side else [-sx * (rx - 0.6)]
    b.add(scallop(down - 0.9, ends, r=1.4), "hair", mask=sm, part=cap, lift=LIFT, blend="max")

    # 흘러내리는 머리단(단발/긴머리). 앞모습은 양옆으로, 옆모습은 뒤통수 뒤로
    # 한 갈래만 — 옆에서 보면 반대쪽 머리단은 몸에 가린다.
    if st["fall"] > 0.0:
        hw = st["fw"]
        xs = [hx - sx * (rx + grow - hw)] if side \
            else [hx - (rx + grow - hw), hx + (rx + grow - hw)]
        for i, fx in enumerate(xs):
            fall = _fall_shape(fx, hw, hy + 1.0, down + st["fall"], taper=hw * 0.32)
            b.add(fall, "hair", part=cap, lift=LIFT)
            # 결 한 줄 — 넓은 면이 통짜로 남으면 판자처럼 보인다
            b.add(fall, "hair", mask=GX > fx + 0.35, lift=LIFT)

    # 뒤통수 아래로 이어지는 덩어리 — 옆모습에서 단발/긴머리의 부피를 만든다
    if st["back"] > 0.0 and side:
        nw = st["fw"] + 0.5
        nape = _fall_shape(hx - sx * (rx + grow - nw), nw, hy + 1.0,
                           hy + ry + 0.5 + st["back"], taper=nw * 0.45)
        b.add(nape, "hair", part=cap, lift=LIFT)

    if st["tail"] > 0.0:
        # **묶은 꼬리는 머리 실루엣 밖으로 나와야 읽힌다.** 안쪽에 두면 앞머리와
        # 한 덩어리가 되어 바가지머리로 보인다(실제로 한 번 그렇게 나왔다).
        # 앞모습은 옆으로 흘러내린 곁꼬리, 옆모습은 뒤통수 뒤로 나온다.
        if side:
            _tail(b, cap, hx - sx * (rx + grow - 0.5), hy - 1.0,
                  down + st["tail"] * 1.6, LIFT, w=2.1)
        else:
            _tail(b, cap, hx + (rx + grow - 1.0), hy - 1.4,
                  down + st["tail"] * 1.2, LIFT, w=1.9)

    if st["strand"]:
        # 앞머리 한 갈래 — 위와 같은 방법(부위 id 만 다른 같은 껍데기)으로 결 한 줄.
        # 좌우대칭이 깨져서 밋밋함이 사라진다.
        tip = 1.0 if not side else sx
        b.add(shell, "hair", mask=sm & below(edge)
              & (np.abs(GX - (hx + tip * 2.3)) < 1.2), lift=LIFT)


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
    cx = 17.0 + (0.5 * sx if side else 0.0)

    hx = cx + (0.7 * sx if side else 0.0)
    hy, rx, ry = cfg["head_cy"] + bob, cfg["head_rx"], cfg["head_ry"]
    if side:
        rx -= 0.4
    b.add(ellipsoid(hx, hy, rx, ry), "skin")
    if side:
        # 코 — 실루엣 밖으로 살짝 나온 1px 돌기. 옆모습을 결정적으로 알아보게 한다
        b.add(ellipsoid(hx + sx * (rx - 0.45), hy + 2.0, 1.0, 0.9), "skin")
    elif cfg["ears"] and direction == "down":
        # 귀는 **실루엣 밖으로 거의 나오지 않게** 붙인다. 조금만 내밀어도 34px
        # 에서는 1px 돌기 + 그 바깥의 외곽선까지 2px 가 되어 요정 귀가 된다.
        er = cfg["ears"]
        for es in (-1, 1):
            b.add(ellipsoid(hx + es * (rx - 0.75), hy + 2.1, er, er * 1.25), "skin")
    _hair(b, direction, cfg, hx, hy, rx, ry, hair, bob)

    lum = light(b.hgt, b.mat, key=cfg["key"], amb=cfg["amb"], rim=cfg["rim"])
    m, l = downsample(b.mat, lum)
    pm = downsample_part(b.part)

    # 눈은 축소 뒤에 네이티브 격자에 직접 찍는다 — 줄이면서 뭉개지면 안 되므로
    def eye(x, y):
        for dy in range(2):
            for dx in range(2):
                if 0 <= y + dy < N and 0 <= x + dx < N and m[y + dy, x + dx] == MATS.index("skin"):
                    m[y + dy, x + dx] = MATS.index("eye")
                    l[y + dy, x + dx] = 0.0
        if cfg["glint"] and 0 <= y < N and 0 <= x < N and m[y, x] == MATS.index("eye"):
            m[y, x] = MATS.index("glint")
            l[y, x] = 1.0

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

    # 소맷부리 — 소매의 맨 아랫줄을 한 단계 어둡게 해서 손과 옷을 갈라놓는다
    if cfg["cuff"]:
        sleeve = (m == SHIRT) & np.isin(pm, limbs)
        last = sleeve & ~np.pad(sleeve, ((0, 1), (0, 0)))[1:]
        l[last] -= cfg["cuff"]

    # 신발 입구 — 바지도 신발도 어두워서 경계가 묻힌다. 신발 맨 윗줄만 한 단계 밝게.
    if cfg["shoe_lip"]:
        boot = m == BOOT
        first = boot & ~np.pad(boot, ((1, 0), (0, 0)))[:-1]
        l[first] += cfg["shoe_lip"]

    # 허리띠 — 상의와 바지가 색 계열이 같아서 이게 없으면 몸이 초록 기둥 하나로 읽힌다.
    # 3D 덩어리로 넣으면 윗면이 빛을 받아 오히려 밝은 띠가 되므로 축소 뒤 한 줄로 찍는다.
    if cfg["belt"]:
        row = int(round(cfg["torso_bot"] + bob)) - 1
        sel = m[row] == MATS.index("shirt")
        m[row][sel] = MATS.index("boot")
        l[row][sel] = 0.20

    ex, ey = int(round(hx)), cfg["eye_y"] + int(round(bob))
    if direction == "down":
        eye(ex - cfg["eye_dx"] - 1, ey)
        eye(ex + cfg["eye_dx"] - 1, ey)
    elif side:
        eye(ex + int(round(sx * 1.5)) - (1 if sx > 0 else 0), ey)

    return outline(inner_lines(quantize(m, l, pal, cfg["dither"]), m, pm, pal), m)


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


def idle_path(style):
    """머리모양 하나당 시트 하나. `player_frames.gd` 의 `sheet_path()` 와 같은 규칙이다."""
    return f"{SPRITES}/player_idle_{style}.png"


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
       ramps("skin", SKIN_IDS, key="skin", mats=["skin"]),
       ramps("hair", HAIR_IDS, key="hair", mats=["hair"]),
       ramps("cloth", CLOTH_IDS, key="cloth", mats=["shirt", "pants", "boot"]))
    with open(path, "w") as f:
        f.write(text)
    return path


if __name__ == "__main__":
    for style in HAIR_STYLES:
        p = idle_path(style)
        idle_sheet(hair=style).save(p)
        print("saved", p)
    print("saved", export_palettes())
    if os.environ.get("GEN_OUT"):     # 후보 비교용 — 저장소를 더럽히지 않는다
        strip([to_img(character(d), 6) for d in DIRS]).save(f"{OUT}/idle_x6.png")
        strip([to_img(character(d), 3) for d in DIRS]).save(f"{OUT}/idle_x3.png")
        stack([strip([to_img(character(d, hair=s), 6) for d in DIRS])
               for s in HAIR_STYLES]).save(f"{OUT}/hairstyles_x6.png")
        stack([strip([to_img(character(d, hair=s), 3) for d in DIRS])
               for s in HAIR_STYLES]).save(f"{OUT}/hairstyles_x3.png")
