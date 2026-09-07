#!/usr/bin/env python3
"""지형 타일 생성기 — 땅(풀)/바다 2종과 그 둘이 만나는 해안 (INBOX #12).

    .venv/bin/python game/tools/gen_terrain.py                  # 게임 자산을 다시 굽는다
    GEN_OUT=/tmp/t .venv/bin/python game/tools/gen_terrain.py    # 후보 비교용 그림도 남긴다

만드는 것: `game/assets/sprites/terrain_tiles.png` **한 장**. 아트 16px 타일
4096칸을 64×64 로 눕혔다(1024×1024). 칸 번호는

    변주(0~7) × 512 + (중심이 땅이면 256) + 이웃 8칸의 땅 비트마스크

이고, 이 규칙을 아는 곳은 여기와 `game/scripts/terrain_tiles.gd` 둘뿐이다.

값을 치르고 알아낸 것 (고칠 때 되돌리지 말 것):

  * **무늬는 타일 한 칸 안에서 이음매 없이 감긴다**(주기 16px). 그래서 어느 타일
    옆에 어느 타일이 와도 무늬가 끊기지 않는다("인접한 같은 지형끼리 이어져
    보여야 한다").
  * **변주는 좌표 해시로 고른다 — `x%3` 같은 규칙으로 고르면 안 된다.** 실제로
    3×3 블록 방식을 먼저 만들었더니, 눈에 띄는 무늬가 화면 144px 마다 정확히
    되풀이돼서 풀밭이 **벽지**로 보였다. 해시로 고르면 격자가 사라진다.
  * **풀잎은 사이를 띄운 세로 획 2~3장**이다. 붙여서 부채꼴로 그리면 풀이 아니라
    작은 삼각형(=멀리 있는 나무)으로 읽힌다. 물결은 반대로 **가로 획**이라야
    물처럼 보인다 — 등방 얼룩으로 채우면 물이 아니라 자갈밭이 된다.
  * **해안선은 타일 사각형을 그대로 쓰지 않는다.** 땅/바다 사각형에서 구한 부호
    거리장에 **16px 주기 노이즈**를 더해 경계를 흔든다. 주기가 타일 한 칸이라 이
    잡음은 **월드 좌표의 함수**가 되고, 그래서 따로 구운 이웃 타일끼리도 경계에서
    정확히 이어진다. 이게 없으면 해안이 화면 48px 계단이 되어 곧바로 티가 난다.
  * **흔들림은 땅이 커지는 쪽으로 치우쳐 있다**(`SHORE_BIAS`). 이동 충돌은 타일
    단위라(`player_motion.gd`) 그림의 땅이 논리 타일보다 **작아지면 물 위를 걷는
    것처럼 보인다.** 반대로 커지는 쪽은 "못 밟는 물가"가 조금 생길 뿐이고 그건
    테두리·물거품에 가려 안 보인다. 남은 잠식 폭은 테두리(`RIM_W`) 안에 숨는다.
  * **밑그림과 해안을 한 칸에 같이 굽는다.** 해안을 반투명 오버레이로 따로 두면
    땅이 바다 타일 쪽으로 불거진 자리에 밑그림이 없어서 풀을 그릴 수가 없다.
  * **해안은 색을 덮어쓰는 게 아니라 램프를 갈아끼우는 것이다.** 여울은 물결
    무늬의 단계 그대로 `shallow` 램프를, 땅쪽 테두리는 풀 무늬의 단계 그대로
    `rim` 램프를 쓴다 — 그래서 물결과 풀결이 띠 안에서도 끊기지 않는다.

팔레트는 `gen_character.py` 의 `make_ramp()` 를 그대로 불러 쓴다 — 램프를 만드는
방식이 캐릭터와 같아야 같은 그림으로 보인다(STYLE_GUIDE 2번).
"""
import os
import sys

import numpy as np
import opensimplex
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_character as gen  # noqa: E402  (같은 폴더의 캐릭터 생성기 — 팔레트를 공유한다)

from scipy import ndimage  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SPRITES = os.path.join(ROOT, "assets", "sprites")
OUT = os.environ.get("GEN_OUT")

SHEET_NAME = "terrain_tiles.png"

TILE = 48               # 아트 한 칸 (× 씬 스케일 1 = 화면 48px)
# 이력: 16 → 24 (2026-09-08 아침) → **48 (2026-09-08 저녁)**.
# **도트 하나의 화면 크기가 캐릭터와 같아야 한다**(STYLE_GUIDE 1번).
# 저녁에 캐릭터를 ComfyUI 그림에서 만들기로 정하면서 칸이 48 → 96px 이 됐다
# (48px 로 줄이면 머리가 캐릭터의 1/4 이라 얼굴이 7px, 눈이 1px 이 되어 죽는다 —
# 실측). 캐릭터 칸이 96 이면 씬 배율은 1 이므로(`player_frames.scale_of`) 캐릭터
# 도트가 화면 1px 이고, 타일도 배율 1 로 맞추려면 아트가 화면 크기와 같은 48 이어야
# 한다. **화면 타일 크기 48px 과 캐릭터 화면 높이 96px(= 타일 두 칸)은 그대로다** —
# 바뀐 것은 그 안에 도트가 몇 개 들어가느냐뿐이다.
VARIANTS = 8            # 같은 지형의 무늬 변주 수
WINDOW = TILE * 3       # 해안을 계산하는 3×3 창

## 이웃 8칸의 비트 순서. **`scripts/terrain_tiles.gd` 와 반드시 같아야 한다.**
NEIGHBORS = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

SHEET_COLS = 64
SHEET_ROWS = 64
TILE_COUNT = VARIANTS * 512


# ── 팔레트 ────────────────────────────────────────────────────────────────
# 재질마다 4단계 램프(STYLE_GUIDE 2번). 목표 명도는 **캐릭터와 겹치지 않게** 잡았다:
# 기준색 셔츠가 명도 147 이라 풀은 그보다 확실히 아래(101)여야 캐릭터가 배경에
# 묻히지 않고, 바다는 더 아래(56)라 땅/바다가 색상뿐 아니라 명도로도 갈린다.
GRASS_BASE = "4d7a3c"
DEEP_BASE = "23608c"
SHALLOW_BASE = "3f9aa8"
FOAM_BASE = "dcefef"

GRASS_LUMA = 101.0
DEEP_LUMA = 56.0
SHALLOW_LUMA = 116.0
FOAM_LUMA = 208.0


def palette():
    """재질 → 4단계 램프. `qa_sprite_check.py` 가 이 함수를 그대로 불러 검사한다."""
    grass = gen.make_ramp(gen._hex(GRASS_BASE), GRASS_LUMA, hi_mix=0.18,
                          sat=(0.90, 1.0, 1.16, 1.28), ramp=(1.24, 1.0, 0.84, 0.70))
    deep = gen.make_ramp(gen._hex(DEEP_BASE), DEEP_LUMA, hi_to=gen.COOL, hi_mix=0.26,
                         sat=(0.94, 1.0, 1.10, 1.20), ramp=(1.32, 1.0, 0.84, 0.70))
    shallow = gen.make_ramp(gen._hex(SHALLOW_BASE), SHALLOW_LUMA, hi_to=gen.COOL,
                            hi_mix=0.22, ramp=(1.22, 1.0, 0.86, 0.74))
    foam = gen.make_ramp(gen._hex(FOAM_BASE), FOAM_LUMA, hi_mix=0.10,
                         sat=(0.88, 1.0, 1.06, 1.12), ramp=(1.04, 1.0, 0.92, 0.84))
    # 땅쪽 테두리 — 풀 램프를 잉크 쪽으로 민 것. 순수 잉크로 두르면 지도에 매직으로
    # 선을 그은 것처럼 튄다(캐릭터와 달리 지형은 면적이 넓어서 잉크가 그대로
    # 배경색이 되어버린다). 램프 단계를 그대로 물려받아 **풀결이 테두리 안에서도
    # 이어지게** 한다.
    rim = [tuple(int(round(v)) for v in gen._mix(c, gen.INK, t))
           for c, t in zip(grass, (0.56, 0.60, 0.64, 0.68))]
    return {"grass": grass, "deep": deep, "shallow": shallow, "foam": foam, "rim": rim}


PAL = palette()


# ── 심리스 노이즈 ─────────────────────────────────────────────────────────
def torus_noise(size, period, wave_x, wave_y=None, seed=0):
    """`period` 픽셀마다 **이음매 없이** 반복되는 (size, size) 노이즈 (-1~1).

    2D 좌표를 4D 토러스(원 두 개)에 감아서 뽑는다 — 그래야 양 끝이 실제로 같은
    값이 된다. `wave_x != wave_y` 면 무늬가 한쪽으로 늘어난다.
    """
    wave_y = wave_x if wave_y is None else wave_y
    opensimplex.seed(seed)
    rx = period / (2.0 * np.pi * wave_x)
    ry = period / (2.0 * np.pi * wave_y)
    out = np.empty((size, size), np.float32)
    for j in range(size):
        v = 2.0 * np.pi * j / period
        zc, zs = ry * np.cos(v), ry * np.sin(v)
        for i in range(size):
            u = 2.0 * np.pi * i / period
            out[j, i] = opensimplex.noise4(rx * np.cos(u), rx * np.sin(u), zc, zs)
    return out


def fbm(size, period, wave_x, wave_y=None, seed=0, octaves=2, gain=0.4):
    """옥타브를 겹친 심리스 노이즈. **결과를 ±1 로 정규화한다** — 심플렉스는 이론
    최대치까지 안 올라가서, 정규화를 빼면 진폭이 실제로 3분의 1 토막 난다
    (해안선을 흔드는 폭을 숫자로 잡을 수가 없어진다)."""
    total = np.zeros((size, size), np.float32)
    amp = 1.0
    for o in range(octaves):
        total += amp * torus_noise(size, period, wave_x / 2 ** o,
                                   None if wave_y is None else wave_y / 2 ** o,
                                   seed + o * 101)
        amp *= gain
    return total / np.abs(total).max()


# ── 밑그림: 풀 / 바다 (둘 다 램프 단계 지도를 돌려준다) ────────────────────
def _stroke(idx, x, y, length, tone, lean=0, vertical=True, under=None):
    """획 하나. 타일 밖으로 나가면 반대편으로 감긴다(타일이 스스로 이음매가 없다).

    `under` 는 획 **아래에 한 줄** 깔리는 반대 명암이다 — 획을 찍는 루프 안에서
    같이 찍으면 다음 픽셀이 앞 픽셀을 덮어써서 획이 1px 로 뭉개진다.
    """
    cells = []
    for k in range(length):
        shift = lean if k >= length - 1 else 0
        if vertical:
            cells.append(((x + shift) % TILE, (y - k) % TILE))
        else:
            cells.append(((x + k) % TILE, (y + shift) % TILE))
    if under is not None:
        # 세로 획은 뿌리 한 칸만, 가로 획은 아래 줄 전체 — 광원이 왼쪽 위라
        # 그늘은 언제나 아래쪽이다(STYLE_GUIDE 4번).
        base = cells[:1] if vertical else cells
        for px, py in base:
            idx[(py + 1) % TILE, px] = under
    for px, py in cells:
        idx[py, px] = tone


def grass_index(seed):
    """16×16 풀밭의 램프 단계 지도.

    바탕은 기본 단계 한 색이고, 그 위에 **풀포기**만 몇 개 얹는다. 얼룩(노이즈)으로
    바탕을 갈라놓는 쪽은 전부 위장무늬처럼 보여서 버렸다 — 도트에서는 바탕이
    깨끗해야 얹은 획이 풀로 읽힌다.
    """
    idx = np.ones((TILE, TILE), np.int8)
    rng = np.random.default_rng(seed + 900)
    # 어두운 포기 먼저, 밝은 포기를 나중에 — 겹치면 밝은 쪽이 위로 올라와야 한다.
    _tuft(idx, rng, tone=2, under=None)
    for _ in range(1 + seed % 2):
        _tuft(idx, rng, tone=0, under=2)
    if seed % 3 == 0:                      # 가끔 짙은 포기 하나 — 단조로움을 깬다
        _tuft(idx, rng, tone=3, under=None)
    return idx


def _tuft(idx, rng, tone, under):
    """풀포기 — **사이를 띄운** 세로 획 2~3장. 붙여 그리면 삼각형이 된다."""
    x, y = int(rng.integers(0, TILE)), int(rng.integers(0, TILE))
    offsets = [-2, 0, 2][:int(rng.integers(2, 4))]
    for dx in offsets:
        _stroke(idx, x + dx, y, int(rng.integers(2, 5)), tone,
                lean=int(rng.integers(-1, 2)), under=under)


def sea_index(seed):
    """16×16 바다의 램프 단계 지도 — 잔물결(가로 획) + 드문 물마루."""
    idx = np.ones((TILE, TILE), np.int8)
    rng = np.random.default_rng(seed + 300)
    for _ in range(2):
        _ripple(idx, rng, tone=2, under=None)
    if seed % 4 == 0:                      # 깊은 자리 — 넷 중 하나꼴
        _ripple(idx, rng, tone=3, under=None)
    for _ in range(1 + seed % 2):
        _ripple(idx, rng, tone=0, under=3)
    return idx


def _ripple(idx, rng, tone, under):
    """물결 한 줄 — 가로 획 + 끝을 한 칸 올려 굽힌다(직선이면 자막처럼 보인다)."""
    x, y = int(rng.integers(0, TILE)), int(rng.integers(0, TILE))
    run = int(rng.integers(3, 7))
    _stroke(idx, x, y, run, tone, vertical=False, under=under)
    if rng.random() < 0.6:
        idx[(y - 1) % TILE, (x + run) % TILE] = tone


# ── 해안 ──────────────────────────────────────────────────────────────────
## 해안선을 얼마나 뭉갤 것인가. 타일 사각형에서 그대로 구한 거리장은 모서리가
## 직각이라 화면 48px 계단이 그대로 보인다 — 거리장을 흐려서 모서리를 둥글린다.
##
## **해안선을 흔드는 잡음(`WOBBLE`)에 기대지 말 것.** 잡음의 주기는 타일 한 칸(16px)
## 이라 — 이웃 타일과 이어지려면 그래야 한다 — 세게 주면 곧게 뻗은 해안에 **같은
## 물결이 48px 마다 정확히 되풀이돼서** 레이스 장식처럼 보인다(실제로 그렇게
## 만들었다가 되돌렸다). 해안의 변화는 잡음이 아니라 **이웃 배치(마스크)가 만든다** —
## 흐리기를 세게, 잡음은 약하게 주는 쪽이 훨씬 자연스럽다.
SMOOTH = 2.7
WOBBLE = 1.2        # 해안선을 흔드는 폭(px)
SHORE_BIAS = 0.8    # 흔들림을 땅이 커지는 쪽으로 민다 (맨 위 주석 참고)
RIM_W = 1.8         # 땅쪽 테두리 — 남은 잠식 폭(WOBBLE-SHORE_BIAS)보다 넓어야 한다
FOAM_W = 0.6        # 물거품 기본 폭. 잡음이 이걸 오르내려서 **끊겼다 이어진다** —
FOAM_JITTER = 0.9   # 한 줄로 쭉 두르면 스티커 테두리처럼 보인다
FOAM_SOFT = 1.5     # 물거품 바깥의 옅은 단계 폭
SHALLOW_W = 8.5     # 여울 → 깊은 바다
SHALLOW_JITTER = 0.8


def _shore_noise():
    """해안을 흔드는 잡음 세 장 — **16px 주기**라 월드 좌표의 함수가 된다.
    (해안선 / 여울 바깥 경계 / 물거품 — 셋이 같은 잡음이면 띠가 나란히 출렁여서
    무늬가 보인다.)"""
    return (fbm(WINDOW, TILE, 7.0, seed=4410),
            fbm(WINDOW, TILE, 9.0, seed=9713),
            fbm(WINDOW, TILE, 5.0, seed=2255))


def shore_field(center_land, mask, noise):
    """3×3 창(48×48)의 부호 거리장. 물 쪽이 양수, 땅 쪽이 음수.

    `None` 이면 창이 통째로 한 지형이라 해안이 없다.
    """
    land = np.zeros((WINDOW, WINDOW), bool)
    if center_land:
        land[TILE:2 * TILE, TILE:2 * TILE] = True
    for bit, (dx, dy) in enumerate(NEIGHBORS):
        if mask >> bit & 1:
            land[(dy + 1) * TILE:(dy + 2) * TILE, (dx + 1) * TILE:(dx + 2) * TILE] = True
    if not land.any() or land.all():
        return None
    sd = ndimage.distance_transform_edt(~land) - ndimage.distance_transform_edt(land)
    sd = ndimage.gaussian_filter(sd, SMOOTH, mode="nearest")
    return sd + WOBBLE * noise[0] - SHORE_BIAS


def tile_pixels(grass_i, sea_i, sd, center_land, noise):
    """타일 한 칸(16×16 RGB). 밑그림 + 해안을 한 번에 그린다."""
    grass_w = np.tile(grass_i, (3, 3))     # 타일이 스스로 심리스라 이어붙이면 된다
    sea_w = np.tile(sea_i, (3, 3))
    grass = np.array(PAL["grass"], np.uint8)[grass_w]
    sea = np.array(PAL["deep"], np.uint8)[sea_w]
    if sd is None:
        base = grass if center_land else sea
        return base[TILE:2 * TILE, TILE:2 * TILE]

    out = np.where((sd < -RIM_W)[..., None], grass, sea)
    foam = FOAM_W + FOAM_JITTER * noise[2]
    soft = foam + FOAM_SOFT
    # 여울의 바깥 경계도 흔든다. 안 그러면 해안을 따라 굵기가 일정한 띠가 둘려서
    # 그림이 아니라 등고선처럼 보인다.
    outer = np.maximum(SHALLOW_W + SHALLOW_JITTER * noise[1], soft)
    for where, color in (
            ((sd >= -RIM_W) & (sd < 0.0), np.array(PAL["rim"], np.uint8)[grass_w]),
            ((sd >= 0.0) & (sd < foam), np.array(PAL["foam"], np.uint8)[1]),
            ((sd >= np.maximum(foam, 0.0)) & (sd < soft), np.array(PAL["foam"], np.uint8)[3]),
            ((sd >= np.maximum(soft, 0.0)) & (sd < outer),
             np.array(PAL["shallow"], np.uint8)[sea_w])):
        out[where] = color[where] if np.ndim(color) == 3 else color
    return out[TILE:2 * TILE, TILE:2 * TILE]


# ── 시트 ──────────────────────────────────────────────────────────────────
def tile_index(variant, center_land, mask):
    return variant * 512 + (256 if center_land else 0) + mask


def build():
    """게임이 쓰는 시트 한 장(RGB). 두 번 돌려도 같은 결과다(전부 고정 시드)."""
    noise = _shore_noise()
    grass = [grass_index(v) for v in range(VARIANTS)]
    sea = [sea_index(v) for v in range(VARIANTS)]
    sheet = np.zeros((SHEET_ROWS * TILE, SHEET_COLS * TILE, 3), np.uint8)
    for center in (0, 1):
        for mask in range(256):
            sd = shore_field(bool(center), mask, noise)
            for variant in range(VARIANTS):
                index = tile_index(variant, bool(center), mask)
                r, c = divmod(index, SHEET_COLS)
                sheet[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE] = \
                    tile_pixels(grass[variant], sea[variant], sd, bool(center), noise)
    return sheet


def variant_at(x, y):
    """타일 좌표 → 무늬 변주. **`terrain_tiles.gd` 의 같은 이름 함수와 같아야 한다.**"""
    return ((x * 73856093) ^ (y * 19349663)) % VARIANTS


def mask_at(kinds, x, y):
    """`kinds[y][x]` (1=땅) 에서 이웃 8칸 비트마스크. 지도 밖은 바다다."""
    h, w = len(kinds), len(kinds[0])
    m = 0
    for bit, (dx, dy) in enumerate(NEIGHBORS):
        nx, ny = x + dx, y + dy
        if 0 <= nx < w and 0 <= ny < h and kinds[ny][nx]:
            m |= 1 << bit
    return m


def compose(kinds, sheet=None):
    """타일 종류 2차원 배열 → 화면에 나올 그림(아트 해상도).

    **`terrain_view.gd` 가 하는 일과 같다** — 칸마다 시트에서 한 조각을 떠다 붙인다.
    미리 보고 검사하려고 파이썬에도 둔다(`qa_sprite_check.py` 의 「이음매」).
    """
    sheet = build() if sheet is None else sheet
    h, w = len(kinds), len(kinds[0])
    img = np.zeros((h * TILE, w * TILE, 3), np.uint8)
    for y in range(h):
        for x in range(w):
            index = tile_index(variant_at(x, y), bool(kinds[y][x]), mask_at(kinds, x, y))
            r, c = divmod(index, SHEET_COLS)
            img[y * TILE:(y + 1) * TILE, x * TILE:(x + 1) * TILE] = \
                sheet[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE]
    return img


def demo_map(w, h, seed=7, gain=2.4, bias=0.30, scale=0.16):
    """미리보기용 섬 — `world_gen.gd` 와 같은 방식(노이즈 + 거리 감쇠)의 축소판."""
    opensimplex.seed(seed)
    n = opensimplex.noise2array(np.arange(w) * scale, np.arange(h) * scale)
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    gy, gx = np.mgrid[0:h, 0:w]
    dist = np.sqrt(((gx - cx) / (w / 2.0)) ** 2 + ((gy - cy) / (h / 2.0)) ** 2)
    return (n * gain + bias - dist ** 2.0 > 0).astype(int).tolist()


PALETTE_GD = os.path.join(ROOT, "scripts", "terrain_palettes.gd")


def export_palettes(path=PALETTE_GD):
    """재질별 램프를 GDScript 상수로 뽑는다 (`gen_character.py` 와 같은 방식).

    게임/자체 QA 쪽에서 지형 색을 알아야 할 때가 있는데(화면에서 이 픽셀이 땅인가
    바다인가 같은 판정), 램프 계산을 GDScript 로 옮겨 적으면 반드시 생성기와
    어긋난다. 그래서 **계산한 값을 그대로 내려보낸다.**
    """
    rows = "\n".join('\t"%s": [%s],' % (mat, ", ".join('"%02x%02x%02x"' % c for c in ramp))
                     for mat, ramp in PAL.items())
    text = '''extends RefCounted

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
%s
}

## 화면의 한 픽셀이 땅인지 바다인지 — 자체 QA 가 스크린샷을 판정할 때 쓴다.
const LAND_MATERIALS := ["grass", "rim"]
const SEA_MATERIALS := ["deep", "shallow", "foam"]


static func color_of(material: String, step: int) -> Color:
	return Color(RAMPS[material][step])
''' % rows
    with open(path, "w") as f:
        f.write(text)
    return path


def main():
    sheet = build()
    path = os.path.join(SPRITES, SHEET_NAME)
    Image.fromarray(sheet, "RGB").save(path)
    print("wrote %s %dx%d (%d칸)" % (path, sheet.shape[1], sheet.shape[0], TILE_COUNT))
    print("wrote %s" % export_palettes())
    if OUT:
        os.makedirs(OUT, exist_ok=True)
        field = compose(demo_map(30, 20), sheet)
        Image.fromarray(field).resize((field.shape[1] * 3, field.shape[0] * 3),
                                      Image.NEAREST).save(os.path.join(OUT, "field_x3.png"))
        print("wrote %s/field_x3.png" % OUT)


if __name__ == "__main__":
    main()
