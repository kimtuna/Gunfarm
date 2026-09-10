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
  * **풀잎은 사이를 띄운 세로 획 몇 장**이다. 붙여서 부채꼴로 그리면 풀이 아니라
    작은 삼각형(=멀리 있는 나무)으로 읽힌다. 물결은 반대로 **가로 획**이라야
    물처럼 보인다 — 등방 얼룩으로 채우면 물이 아니라 자갈밭이 된다.
  * **얹는 양은 개수가 아니라 칸 넓이당으로 적는다**(2026-09-08, INBOX #60).
    개수를 상수로 박아두면 칸 크기를 바꾼 바퀴가 반드시 잊는다 — 칸이 16 → 48px 로
    커지는 동안 개수가 그대로여서 땅 픽셀의 **98.9% 가 한 색**이 됐다. 아래
    `GRASS_TUFTS` / `SEA_WAVES` 참고.
  * **그런데 밀도를 맞춰도 「보이는」 것은 아니다**(2026-09-08, INBOX #62).
    넓이당 개수를 맞춘 뒤에도 잎이 **4 × 1px 짜리 45개**라 풀밭이 **균일한 잡티**
    였다 — 배율이 1이라 아트 px 이 곧 화면 px 이다. **획의 크기를 화면에서 읽히는
    크기로 잡고**(잎 8~14px · 굵기 2~3px) 개수를 그만큼 줄인다.
  * **칸이 세어지는 것은 「덤불 + 맨땅」이 만든다.** 굵어진 획을 칸에 고르게 뿌리면
    굵은 잡티일 뿐이라 화면이 끝없이 이어지는 한 장의 무늬가 된다 — 풀은 포기를
    **덤불**로 몬다(`CLUMP_SPREAD`). **바다는 몰지 않는다**: 물결은 칸의 절반을
    넘게 길어서 몰면 맨물이 타일 모서리에 걸려 이음매가 보인다(그 자리 주석 참고).
  * **덤불을 모으는 것만으로는 벽지를 못 벗는다**(2026-09-10, #d2). 칸마다 덤불을
    똑같이 하나씩 놓으면 변주 8종의 **자리**만 다르고 **양**이 같다 — 실측 18.4~24.9%.
    덤불 **수**를 변주마다 0~3 으로 벌려야 맨땅과 우거진 데가 섞인다(`GRASS_CLUMPS`).
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
    # **깊은 바다만 램프 폭이 넓다**(밝은면 ×1.80). 다른 램프는 1.2~1.3배인데,
    # 바다는 기본 명도가 56 이라 1.32배로는 밝은면이 74 밖에 안 되어 **물마루가
    # 안 보인다** — 물결을 아무리 굵게 그려도 화면에서는 남색 한 판이었다
    # (2026-09-08, INBOX #62. 실측: 1.32 → 명도 표준편차 5.4 / 1.80 → 8.3).
    # 기본·그늘·최암부는 그대로라 **바다의 평균 명도는 55~56 으로 안 바뀐다.**
    deep = gen.make_ramp(gen._hex(DEEP_BASE), DEEP_LUMA, hi_to=gen.COOL, hi_mix=0.26,
                         sat=(0.94, 1.0, 1.10, 1.20), ramp=(1.80, 1.0, 0.80, 0.62))
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
## 무늬 밀도 — **개수가 아니라 칸 넓이당(1000px²) 비율로 적는다.**
## (2026-09-08, INBOX #60) 한때 포기·물결 개수를 상수 몇 개로 박아뒀는데, 칸이
## 16 → 24 → 48px 로 커지는 동안 그 개수가 안 따라와서 **넓이당 무늬가 9분의 1** 로
## 줄었다 — 땅 한가운데 칸 픽셀의 **98.9% 가 `#4d793c` 한 색**이 되어 풀밭이 점
## 몇 개 흩뿌려진 초록 평면이 됐다. 넓이로 적어두면 칸 크기를 바꾼 바퀴가 잊어도
## 밀도가 따라온다. 검사는 `qa_sprite_check.py` 의 「무늬」다.
def _per_tile(per_kpx):
    return int(round(per_kpx * TILE * TILE / 1000.0))


## **획의 굵기와 길이는 화면에서 읽히는 크기로 잡는다** (2026-09-08, INBOX #62).
## 배율이 1이라 아트 px 이 곧 화면 px 이다 — 여기 적은 숫자가 그대로 화면 크기다.
## 그전에는 잎이 **4×1px 짜리가 칸에 45개**여서, 밀도(넓이당 비율)는 맞는데
## 무늬 하나하나가 눈에 안 잡히는 **균일한 잡티**였다. 잡티는 아무리 깔아도
## 「한 칸」의 경계를 못 만들어서, 화면에서 크기를 잴 기준이 사라진다.
##
## **굵게 · 크게 · 적게.** 잎을 8~14px 로 키우고 굵기를 2~3px 로 주는 대신
## 개수를 1/5 로 줄였다 — 덮는 넓이는 비슷한데 **덩어리가 세어진다.**

## 풀포기 — (램프 단계, 아래 그늘, 1000px² 당 개수, 잎 길이, 잎 수, 밑동 굵기).
## **어두운 포기를 먼저, 밝은 포기를 나중에** 얹는다(겹치면 밝은 쪽이 위로 와야 한다).
GRASS_TUFTS = ((2, None, 2.7, (9, 14), (3, 5), 3),     # 큰 포기 — 칸의 주인공이다
               (0, 2, 2.7, (6, 10), (2, 4), 2),        # 밝은 포기 (그늘을 깔고 얹는다)
               (3, None, 1.9, (4, 7), (2, 3), 2))      # 가장 어두운 잔포기
BLADE_GAP = 1           # 잎 **사이의 빈 칸** — 굵기에 더해진다(붙여 그리면 삼각형이 된다)
TUFT_TAPER = 0.20       # 바깥 잎이 가운데보다 이만큼씩 짧다 — 다발이 포기로 읽힌다

## 물결 — (1000px² 당 개수, 길이, 굵기, 램프 단계, 마루를 얹는가).
##
## **바다는 「골 + 마루」 한 쌍이라야 물결로 읽힌다** (2026-09-08, INBOX #62).
## 그전에는 1px 짜리 가로 획 열몇 개가 흩뿌려져 있어서 물결이 아니라 **긁힌 자국**
## 이었다. 어두운 골 위에 밝은 마루를 한 줄 얹으면 그 한 쌍이 곧 물결 하나가 되고,
## 획이 길어진 만큼 개수를 줄일 수 있다(칸에 열몇 개 → 네댓 개).
SEA_WAVES = ((2.0, (18, 30), 3, 3, True),      # 큰 물마루 — 칸의 주인공
             (2.0, (8, 16), 2, 2, False))      # 잔물결


def _blade(idx, x, y, height, width, tone, lean, under=None):
    """풀잎 하나 — 밑동은 곧고 굵고, **끝으로 갈수록 휘며 가늘어진다.**
    타일 밖은 반대편으로 감긴다.

    끝 한 칸만 밀면(옛 `_stroke` 의 `lean`) 4px 을 넘는 잎이 곧은 막대가 된다.
    **굵기도 같은 문제를 갖는다**(2026-09-08, INBOX #62): 굵기를 세로로 일정하게
    두면 잎이 아니라 **각목**이라, 밑동에서 끝으로 한 칸씩 줄여야 잎으로 읽힌다.
    """
    if under is not None:
        # 뿌리 아래 한 칸이 그늘이다 — 광원이 왼쪽 위라 그늘은 언제나 아래다
        # (STYLE_GUIDE 4번). 잎보다 **먼저** 찍어야 잎이 안 덮인다.
        for j in range(width):
            idx[(y + 1) % TILE, (x + j) % TILE] = under
    for k in range(height):
        t = k / max(height - 1, 1)
        bend = int(round(lean * t ** 1.6))
        w = max(1, int(round(width - (width - 1) * t)))
        for j in range(w):
            idx[(y - k) % TILE, (x + bend + j) % TILE] = tone


## **무늬를 칸마다 한두 군데로 모은다** (2026-09-08, INBOX #62).
## 같은 크기의 획을 칸 전체에 고르게 뿌리면, 획을 아무리 굵게 키워도 화면은
## **끝없이 이어지는 한 장의 무늬**가 된다 — 눈이 「한 칸」의 경계를 못 찾는다.
## 포기를 한두 덤불로 모으고 사이를 비워두면 그 덤불 간격이 곧 타일 간격이라,
## 화면에서 **칸이 세어진다.** 덤불 자리·개수는 변주가 가르므로 이웃 칸과 다르다.
## **덤불 하나의 크기는 안 줄인다.** 총량을 그대로 둔 채 두 군데로 나눠본 후보는
## 덤불이 그만큼 작아져서 화면에서 도로 잡티가 됐고(실측 후보 C2), 퍼짐을 0.30 까지
## 넓힌 것은 아예 고르게 뿌린 것과 같아졌다. 퍼짐은 **덤불이 칸을 다 먹지 않을
## 만큼**이라야 사이의 맨땅이 남아서 덤불 간격 = 칸 간격이 보인다.
## **덤불이 몇 개 놓이는지는 변주가 가른다**(2026-09-10, #d2 — `GRASS_CLUMPS`).
## C2 와 다른 점: C2 는 **모든 칸**을 두 덤불로 쪼개 총량을 유지했고, 이쪽은 덤불
## 크기를 그대로 둔 채 **칸마다 덤불 수를 0~3 으로 벌린다.**
##
## **바다는 몰지 않는다 — 몰면 이음매가 보인다.** 물결은 길이가 18~30px 이라 이미
## 칸의 절반을 넘는데, 그걸 한 군데로 더 몰면 칸 안에 **넓은 맨물**이 남고 그 자리가
## 곧잘 타일 모서리에 걸린다 — 이웃 칸의 물결 띠와 나란히 놓여 가로줄이 비친다.
## 실측(「이음매」, 상한 1.10): 몰기 0.17 → **1.31** / x 로만 몰기 → 1.17~1.23 /
## 고르게 뿌리기 → **0.61**. 풀은 포기가 작고 세로라 몰아도 0.94 로 통과한다.
## 바다의 「한 칸」은 **물결 하나의 크기**가 대신 말한다(물결 하나 ≈ 칸의 절반).
CLUMP_SPREAD = 0.13     # 풀 — 덤불 둘레로 퍼지는 폭 (타일 대비. 48px 에서 ±6px)

## **덤불 「수」를 변주마다 벌린다** (2026-09-10, #d2).
##
## INBOX #62 가 포기를 한 덤불로 몬 것까지는 옳았다. 틀린 것은 **그 덤불을 칸마다
## 똑같이 하나씩** 놓은 것이다 — 변주 8종의 덤불 **자리**만 다르고 **양**이 같아서,
## 실측하면 덮인 넓이가 18.4~24.9% 로 전부 한 덩어리였다. 눈에는 「같은 그림이
## 자리만 옮겨 다니는 것」으로 보이고, 그게 사람이 말한 **벽지**다
## (*"초원 표현도 드문드문 풀이 있어야지 하나만 만드니까 너무 별로야"*).
##
## **덤불 하나의 크기는 그대로 두고**(잎 8~14px · 굵기 2~3px · 포기 5~7 — INBOX #62
## 가 값을 치르고 올린 값이라 줄이면 잡티로 되돌아간다) **덤불이 몇 개 놓이는지만**
## 0~3 으로 벌린다. 그래야 맨땅이 드러난 칸과 우거진 칸이 섞여 「드문드문」이 읽힌다.
##
## **0 이 반드시 하나 있어야 한다.** 전부 1개 이상이면 화면에 빈 데가 없어서, 덤불
## 자리를 아무리 흔들어도 밀도가 고르게 보인다 — 그게 지금까지의 문제였다.
## 대신 0 을 여럿 두지 않는다: 8종 중 둘이 비면 25% 가 민무늬라 이번엔 **땜빵**으로
## 보인다. 아래는 한쪽으로 안 치우친 분포다(0 이 1종 · 1이 4종 · 2가 2종 · 3이 1종).
GRASS_CLUMPS = (0, 1, 1, 2, 1, 3, 1, 2)


def _clump_spot(rng):
    """이 칸에서 무늬가 모일 자리. 칸 안 어디든 좋다(무늬가 타일 밖으로 감기므로)."""
    return (float(rng.integers(0, TILE)), float(rng.integers(0, TILE)))


def _near(rng, spot, spread):
    """덤불 자리 둘레의 한 점. 타일 밖으로 나가면 반대편으로 감긴다."""
    cx, cy = spot
    s = spread * TILE
    return (int(round(cx + rng.normal(0.0, s))) % TILE,
            int(round(cy + rng.normal(0.0, s))) % TILE)


def _tuft(idx, rng, tone, under, height, blades, width, at):
    """풀포기 — **사이를 띄운** 잎 몇 장. 붙여 그리면 삼각형(=멀리 있는 나무)이 된다.

    가운데 잎이 가장 길고 바깥으로 갈수록 짧아지며 바깥쪽으로 휜다 — 그래야
    잎 몇 개가 아니라 **포기 하나**로 뭉쳐 보인다.
    """
    x, y = at
    n = int(rng.integers(blades[0], blades[1] + 1))
    tall = int(rng.integers(height[0], height[1] + 1))
    step = width + BLADE_GAP
    mid = (n - 1) / 2.0
    for i in range(n):
        off = i - mid
        h = max(3, int(round(tall * (1.0 - TUFT_TAPER * abs(off)))))
        # 바깥 잎은 바깥으로 휜다(가운데 잎은 곧게 선다).
        lean = int(np.sign(off)) * int(rng.integers(1, 3)) if off else int(rng.integers(-1, 2))
        _blade(idx, x + int(round(off * step)), y + int(rng.integers(0, 2)),
               h, max(1, width - (abs(off) > 1)), tone, lean=lean, under=under)


def grass_index(seed):
    """풀밭 한 칸의 램프 단계 지도 (`TILE`×`TILE`).

    바탕은 기본 단계 한 색이고, 그 위에 **풀포기**만 얹는다. 얼룩(노이즈)으로
    바탕을 갈라놓는 쪽은 전부 위장무늬처럼 보여서 버렸다 — 도트에서는 바탕이
    깨끗해야 얹은 획이 풀로 읽힌다. **얹는 양은 `GRASS_TUFTS` 가 넓이로 정한다.**
    """
    idx = np.ones((TILE, TILE), np.int8)
    rng = np.random.default_rng(seed + 900)
    # **덤불 수가 변주를 가른다** (2026-09-10, #d2 — 위 `GRASS_CLUMPS` 참고).
    # 0 이면 이 칸은 민무늬 풀밭이고, 그런 칸이 섞여야 「드문드문」이 읽힌다.
    spots = [_clump_spot(rng) for _ in range(GRASS_CLUMPS[seed % VARIANTS])]
    for tone, under, per_kpx, height, blades, width in GRASS_TUFTS:
        # **한 덤불에 들어가는 포기 수는 안 건드린다** — 이 값이 곧 덤불의 크기이고,
        # 줄이면 덤불이 화면에서 도로 잡티가 된다(2026-09-08, INBOX #62 의 후보 C2).
        # `seed % 3` 은 같은 덤불 수끼리도 조금 다르게 만드는 잔변주로 남긴다.
        per_clump = max(1, _per_tile(per_kpx) + seed % 3 - 1)
        for spot in spots:
            for _ in range(per_clump):
                _tuft(idx, rng, tone, under, height, blades, width,
                      _near(rng, spot, CLUMP_SPREAD))
    return idx


def sea_index(seed):
    """바다 한 칸의 램프 단계 지도 — 물마루(골 + 마루) 몇 줄 + 잔물결.

    풀과 같은 밀도·덤불 규칙을 쓰되 **획이 가로**다 — 세로 획으로 채우면 물이
    아니라 잔디가 되고, 등방 얼룩으로 채우면 자갈밭이 된다.
    """
    idx = np.ones((TILE, TILE), np.int8)
    rng = np.random.default_rng(seed + 300)
    for per_kpx, run, thick, tone, crest in SEA_WAVES:
        for _ in range(max(1, _per_tile(per_kpx) + seed % 3 - 1)):
            # 풀과 달리 **고르게 뿌린다** — 이유는 `CLUMP_SPREAD` 위 주석.
            at = (int(rng.integers(0, TILE)), int(rng.integers(0, TILE)))
            _wave(idx, rng, tone, crest, run, thick, at)
    return idx


def _wave(idx, rng, tone, crest, run, thick, at):
    """물결 한 줄 — 굵은 가로 획. **양끝은 한 칸으로 가늘어지고** 가운데가 두껍다.

    (2026-09-08, INBOX #62) 1px 짜리 가로 획은 48px 칸에서 물결이 아니라 **긁힌
    자국**이다. 굵기를 주되 **끝을 뾰족하게 남겨야** 각목이 안 된다 — 잎과 같은
    이유다. 그리고 획이 길어진 만큼 **가운데를 한 칸 내려** 물결의 골을 만든다.

    `crest` 면 그 골 **바로 위에 가장 밝은 단계를 한 줄** 얹는다 — 물결이 물결로
    읽히는 것은 획 하나가 아니라 「어두운 골 + 밝은 마루」 한 쌍이다.
    """
    x, y = at
    length = int(rng.integers(run[0], run[1] + 1))
    lean = int(rng.integers(-1, 2))
    sag = int(rng.integers(0, 2))       # 가운데가 한 칸 처지는가 (물결의 골)
    for k in range(length):
        t = k / max(length - 1, 1)
        # 끝 두 칸은 한 겹으로 가늘어진다.
        w = thick if 1 <= k < length - 1 else 1
        shift = (lean if k >= length - 1 else 0) + (sag if 0.3 <= t <= 0.7 else 0)
        px = (x + k) % TILE
        for j in range(w):
            idx[(y + shift + j) % TILE, px] = tone
        # 마루는 골보다 짧다 — 끝까지 얹으면 두 줄짜리 띠가 되어 물결이 아니라 자막이다.
        if crest and 2 <= k < length - 2:
            idx[(y + shift - 1) % TILE, px] = 0


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
