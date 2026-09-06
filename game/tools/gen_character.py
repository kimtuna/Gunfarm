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

# `character_appearance.gd` 의 기본 선택지 = 이번 기준색 1벌
BASE_SKIN = "f0c8a0"        # 밝은
BASE_HAIR = "211c1a"        # 검정
BASE_CLOTH = "4e7a3a"       # 풀색

# 바지/신발은 옷색을 어둡게 쓴다 — 팔레트를 늘리지 않고 상하의를 구분한다
# (DESIGN.md 「캐릭터 커스터마이징 항목」). 상의와 값이 확실히 갈리도록 잡았다.
PANTS_DARKEN = 0.46
SHOES_DARKEN = 0.26

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


WARM = (255, 244, 214)      # 밝은면이 향하는 색 (따뜻한 햇빛)
COOL = (198, 204, 224)      # 검은 머리처럼 무채색에 가까운 재질의 밝은면

def make_ramp(base, hi=0.28, hi_to=WARM, shade=(0.72, 0.66, 0.76),
              dark=(0.46, 0.40, 0.55), min_v=0):
    """기준색 하나 → 밝은면/기본/그늘/가장어두움 4단계.

    **HLS 로 명도를 깎지 않고 곱셈으로 그늘을 만든다.** HLS 에서 명도만 낮추면
    채도가 폭발해서(밝은 피부색이 형광 주황이 된다) 램프가 무너진다. 그늘 계수의
    파랑을 빨강보다 크게 두면 어두워질수록 보라 쪽으로 도는 — 도트에서 흔한 —
    따뜻한 빛/차가운 그늘 대비가 공짜로 나온다.

    `min_v` 는 **아주 어두운 기준색(검정 머리)** 을 위한 것이다. 기준색을 그대로
    기본 단계로 쓰면 잉크 외곽선(38,28,44)보다 어두워져서 실루엣이 통째로 검은
    구멍이 되고 단차도 안 보인다.
    """
    b = np.array(base, dtype=np.float32)
    if min_v > 0 and b.max() < min_v:
        b = b * (min_v / max(b.max(), 1.0))
    steps = [
        b + (np.array(hi_to, np.float32) - b) * hi,
        b,
        b * np.array(shade, np.float32),
        b * np.array(dark, np.float32),
    ]
    return [tuple(int(round(v)) for v in np.clip(s, 0, 255)) for s in steps]


def darken(rgb, f):
    return tuple(int(round(c * f)) for c in rgb)


def palette(skin=BASE_SKIN, hair=BASE_HAIR, cloth=BASE_CLOTH):
    """커스터마이징 색 3개 → 재질별 램프. 이 함수만 갈아끼우면 색 확장이 끝난다."""
    skin_rgb, hair_rgb, cloth_rgb = _hex(skin), _hex(hair), _hex(cloth)
    return {
        # 피부는 밝은면을 세게 주면 표백돼 보인다 — 낮게.
        "skin": make_ramp(skin_rgb, hi=0.20),
        # 머리는 차가운 밝은면 + min_v 로, 검정 머리도 단차가 보이게 한다.
        "hair": make_ramp(hair_rgb, hi=0.17, hi_to=COOL, min_v=40),
        "shirt": make_ramp(cloth_rgb, hi=0.30),
        # 바지·신발은 옷색을 어둡게 쓴 것이라 밝은면까지 세면 상의와 값이 겹친다.
        "pants": make_ramp(darken(cloth_rgb, PANTS_DARKEN), hi=0.15, min_v=34),
        "boot": make_ramp(darken(cloth_rgb, SHOES_DARKEN), hi=0.13, min_v=26),
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
    torso_r=3.4, ears=True, shoe_lip=0.30,
    fringe=6.9, fringe_tilt=1.5, side_hair=10.6,
    eye_y=12, eye_dx=2, glint=True,
    dither=0.0, key=0.72, amb=0.38, rim=0.12,
)


def _body(b, d, cfg):
    """다리/몸통/팔 — 방향에 따라 어깨 너비와 팔 배치만 달라진다."""
    side = d in ("left", "right")
    sx = 1.0 if d == "right" else -1.0
    cx = 17.0 + (0.5 * sx if side else 0.0)
    tw = cfg["side_torso_w"] if side else cfg["torso_w"]
    top, bot = cfg["torso_top"], cfg["torso_bot"]

    # 다리 — 사이를 1.2px 비워 두면 외곽선이 그 틈에 들어가 두 다리로 읽힌다
    lw = 3.9 if not side else 3.7
    for s in (-1, 1):
        lx = cx + s * (lw / 2 + 0.6)
        b.add(rbox(lx - lw / 2, 23.2, lx + lw / 2, 29.3, r=1.3), "pants")
        b.add(rbox(lx - lw / 2 - 0.4, 28.8, lx + lw / 2 + 0.4, 31.5, r=1.0), "boot")

    # 목 (몸통보다 먼저 — 뒤로 간다)
    b.add(rbox(cx - 1.6, 12.8, cx + 1.6, top + 1.2, r=1.1), "skin")

    # 몸통
    b.add(rbox(cx - tw / 2, top, cx + tw / 2, bot, r=cfg["torso_r"]), "shirt")

    # 팔 — 몸통과 다른 부위 id 라서 경계에 내부선이 들어간다
    aw = cfg["arm_w"]
    arm_top, arm_bot = top + 1.1, bot - 1.6
    xs = [sx * 2.0] if side else [-(tw / 2 + aw / 2 - 0.5), (tw / 2 + aw / 2 - 0.5)]
    limbs = []
    for off in xs:
        ax = cx + off
        limbs.append(b.add(rbox(ax - aw / 2, arm_top, ax + aw / 2, arm_bot, r=1.25), "shirt"))
        # 손은 벙어리장갑 모양 — 소매 끝에서 살짝 넓어진다
        limbs.append(b.add(ellipsoid(ax, arm_bot + 1.15, 1.55, 1.5), "skin"))
    return limbs


def _hair(b, d, cfg, hx, hy, rx, ry, style):
    """머리카락. 앞머리는 얼굴보다 앞으로 lift 해서 경계가 살아나게 한다.

    **덧붙이는 갈래는 전부 머리 껍데기(shell) 안으로 잘라 넣는다** — 안 그러면
    실루엣 밖으로 혹처럼 튀어나온다.
    """
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
        return

    # 앞머리를 비스듬히 자른다 — 수평으로 자르면 바가지머리가 된다
    tilt = cfg["fringe_tilt"] * (sx if side else 1.0)
    edge = cfg["fringe"] + tilt * (GX - hx) / rx
    cap = b.add(shell, "hair", mask=below(edge), lift=LIFT)

    # 옆머리(구레나룻) — 얼굴 옆을 감싸 내려온다
    down = cfg["side_hair"]
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

    if style == "short":
        # 앞머리 한 갈래 — 위와 같은 방법(부위 id 만 다른 같은 껍데기)으로 결 한 줄.
        # 좌우대칭이 깨져서 밋밋함이 사라진다.
        tip = 1.0 if not side else sx
        b.add(shell, "hair", mask=sm & below(edge)
              & (np.abs(GX - (hx + tip * 2.3)) < 1.2), lift=LIFT)


def character(direction="down", hair="short", pal=None, cfg=None, **over):
    cfg = dict(CFG, **(cfg or {}))
    cfg.update(over)
    pal = pal or palette()
    b = Build()

    limbs = _body(b, direction, cfg)
    side = direction in ("left", "right")
    sx = 1.0 if direction == "right" else -1.0
    cx = 17.0 + (0.5 * sx if side else 0.0)

    hx = cx + (0.7 * sx if side else 0.0)
    hy, rx, ry = cfg["head_cy"], cfg["head_rx"], cfg["head_ry"]
    if side:
        rx -= 0.4
    b.add(ellipsoid(hx, hy, rx, ry), "skin")
    if side:
        # 코 — 실루엣 밖으로 살짝 나온 1px 돌기. 옆모습을 결정적으로 알아보게 한다
        b.add(ellipsoid(hx + sx * (rx - 0.45), hy + 2.0, 1.0, 0.9), "skin")
    elif cfg["ears"] and direction == "down":
        for es in (-1, 1):
            b.add(ellipsoid(hx + es * (rx - 0.35), hy + 1.6, 1.15, 1.45), "skin")
    _hair(b, direction, cfg, hx, hy, rx, ry, hair)

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
        row = int(cfg["torso_bot"]) - 1
        sel = m[row] == MATS.index("shirt")
        m[row][sel] = MATS.index("boot")
        l[row][sel] = 0.20

    ex, ey = int(round(hx)), cfg["eye_y"]
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


if __name__ == "__main__":
    path = f"{SPRITES}/player_idle.png"
    idle_sheet().save(path)
    print("saved", path)
    if os.environ.get("GEN_OUT"):     # 후보 비교용 — 저장소를 더럽히지 않는다
        strip([to_img(character(d), 6) for d in DIRS]).save(f"{OUT}/idle_x6.png")
        strip([to_img(character(d), 3) for d in DIRS]).save(f"{OUT}/idle_x3.png")
