"""캐릭터 캔버스 **32px** 를 시험만 해보는 도구 — 게임 자산을 만들지 않는다.

실행: `.venv/bin/python game/tools/try_canvas32.py`
결과: `docs/design_reference/canvas_32_vs_17.png` (사람이 보고 판단할 비교 이미지)

2026-09-07, INBOX #45. `try_canvas.py`(#44, 26px)와 **같은 방식이다** — 게임 자산을
한 바이트도 바꾸지 않고 비교 이미지와 사실만 남긴다. 그리는 유틸(`band`/`_font`)은
그 파일 것을 그대로 부른다.

26px 때와 다른 것이 둘이다:

  1. **배율이 안 바뀐다.** 26px 은 화면 크기를 맞추려고 3배 → 2배로 내려야 했지만,
     32px 은 배율 3배 그대로 두고 화면에서 51 → **96px** 이 된다. 그게 이 시험의
     목적이다 — `DESIGN.md` 「크기 표준」의 **캐릭터는 타일 두 칸**(타일 아트 16px ×
     3배 = 48px, 캐릭터 32px × 3배 = 96px = 정확히 2칸).
  2. 그래서 **1번 띠를 진짜 지형 타일 위에 그린다.** 재는 것이 캐릭터 혼자의 크기가
     아니라 타일과의 비이므로, 타일 없이 나란히 놓으면 볼 것이 없다.

고른 값은 `gen_character.IDLE_OVER` 다 — **2026-09-07 (INBOX #46) 부터 게임의 idle
시트가 실제로 그 값으로 구워진다.** 이 파일은 그 값을 지금 17px 과 나란히 보여준다.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_character as G                                       # noqa: E402
import gen_terrain as T                                         # noqa: E402
from try_canvas import REF, _font, band, band_pad               # noqa: E402

OUT = os.environ.get("GEN_OUT") or REF
SPRITES = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites"))

N32 = 32
K = N32 / float(G.DESIGN_N)     # 1.882 — 설계 단위 하나가 32px 칸에서 몇 px 인가
ZOOM = 3                        # 씬 스케일. **32px 에서는 이게 안 바뀐다**

# ── 32px 에서 다시 잡은 값들 ────────────────────────────────────────────────
# `gen_character.CFG_KIND` 의 "grid" 갈래 + 눈을 옮기느라 같이 밀린 코(`nose_*`).
# 설계 길이와 무차원 비율은 **한 줄도 손대지 않았다** — 그래서 머리가 전체에서
# 차지하는 비율이 17px 과 같고, 늘어난 칸은 전부 디테일로 갔다(지시 (4)).
# **이 바퀴에 고른 값은 이제 생성기가 들고 있다** — 2026-09-07 (INBOX #46) 에 사람이
# 32px idle 을 실제로 게임에 넣기로 정하면서 `gen_character.IDLE_OVER` 로 옮겼다.
# 여기에 사본을 두면 비교 이미지와 게임에 들어간 그림이 조용히 갈라진다.
TUNED32 = G.IDLE_OVER

DIRS = G.DIRS


def frames(n, zoom, over, tool=None):
    """idle 4방향(+도구를 주면 그 도구를 든 4방향)을 `zoom` 배로."""
    with G.canvas_scale(n):
        out = [G.character(d, **over) for d in DIRS]
        if tool:
            out += [G.character(d, tool=tool, motion="hold", **over) for d in DIRS]
        return [G.to_img(f, zoom) for f in out]


def head(n, zoom, over, frac=13.0):
    """얼굴만 잘라 크게 — 표정에 들어가는 것은 이 몇 줄이 전부다."""
    with G.canvas_scale(n):
        im = G.to_img(G.character("down", **over))
    bot = int(round(n * frac / G.DESIGN_N))
    return im.crop((0, 0, n, bot)).resize((n * zoom, bot * zoom), Image.NEAREST)


def hand(n, zoom):
    """손만 잘라 아주 크게 — 손가락을 가를 수 있는지 보는 자리다."""
    with G.canvas_scale(n):
        im = G.to_img(G.character("down"))
    def q(v):
        return int(round(n * v / G.DESIGN_N))
    x0, x1, y0, y1 = q(3.0), q(9.0), q(8.0), q(13.0)
    return im.crop((x0, y0, x1, y1)).resize(
        ((x1 - x0) * zoom, (y1 - y0) * zoom), Image.NEAREST)


def grass(cols, rows):
    """진짜 지형 타일로 깐 풀밭(아트 해상도). 시트는 게임 자산을 그대로 읽는다."""
    sheet = np.array(Image.open(os.path.join(SPRITES, "terrain_tiles.png")).convert("RGB"))
    kinds = [[1] * (cols + 2) for _ in range(rows + 2)]     # 테두리는 잘라낸다
    img = T.compose(kinds, sheet)[T.TILE:(rows + 1) * T.TILE, T.TILE:(cols + 1) * T.TILE]
    return Image.fromarray(img).convert("RGBA").resize(
        (cols * T.TILE * ZOOM, rows * T.TILE * ZOOM), Image.NEAREST)


TILE = T.TILE * ZOOM        # 48px — **캐릭터 캔버스가 바뀌어도 이 값은 안 바뀐다**
ROWS, STEP, GROUND = 4, 3, 3     # 풀밭 4칸, 캐릭터 사이 3칸, 발이 닿는 줄


def on_tiles(n, over, tool=None):
    """풀밭 위에 선 캐릭터 + 타일 칸금. 재는 것은 캐릭터가 아니라 **타일과의 비**다.

    발을 **칸금 위에** 세운다 — 그래야 「캐릭터가 타일 몇 칸인가」를 눈으로 셀 수 있다.
    """
    ims = frames(n, ZOOM, over, tool)
    cols = STEP * len(ims) + 1
    bg = grass(cols, ROWS)
    d = ImageDraw.Draw(bg)
    for i in range(1, ROWS):
        d.line([(0, i * TILE), (bg.width, i * TILE)], fill=(255, 255, 255, 40))
    for i in range(1, cols):
        d.line([(i * TILE, 0), (i * TILE, bg.height)], fill=(255, 255, 255, 40))
    # 캔버스 맨 아랫줄은 걷기에서 몸이 가라앉는 여유라 비어 있다 — 발바닥은 그 위다
    foot = int(round(n * 15.6 / G.DESIGN_N)) * ZOOM
    for i, im in enumerate(ims):
        x = (1 + STEP * i) * TILE - im.width // 2
        bg.alpha_composite(im, (x, GROUND * TILE - foot))
    return bg


def ruler(h):
    """왼쪽에 세우는 「타일 몇 칸인가」 자. 발이 닿는 줄에서 위로 잰다."""
    f = _font(13)
    im = Image.new("RGBA", (96, h), (22, 20, 26, 255))
    d = ImageDraw.Draw(im)
    base = GROUND * TILE
    for k, col in ((1, (255, 214, 122, 255)), (2, (150, 214, 255, 255))):
        x = 10 + (k - 1) * 30
        d.line([(x, base - k * TILE), (x, base)], fill=col, width=2)
        for y in (base - k * TILE, base):
            d.line([(x - 4, y), (x + 4, y)], fill=col, width=2)
        d.text((x + 6, base - k * TILE + 2), f"{k}칸", font=f, fill=col)
    return im


def main():
    b1 = on_tiles(G.DESIGN_N, {}, tool="axe")
    b2 = on_tiles(N32, TUNED32, tool="axe")
    bands = [
        band("1) 실제 게임 크기 — 진짜 지형 타일(아트 16px × 3배 = 48px) 위에. "
             "**배율은 양쪽 다 3배다** / 왼쪽 넷 idle 4방향, 오른쪽 넷 도끼 들고",
             [(f"지금 17px × 3배 = 51px — 타일 {51 / TILE:.2f}칸",
               [ruler(b1.height), b1]),
              (f"32px × 3배 = {N32 * ZOOM}px — 타일 {N32 * ZOOM / TILE:.2f}칸",
               [ruler(b2.height), b2])], gap=0),
        band("2) 6배 확대 — 왼쪽 넷 idle 4방향 / 오른쪽 넷 도끼 들고",
             [("지금 17px", frames(G.DESIGN_N, 6, {}, "axe")),
              ("32px — 픽셀만 늘리고 같은 그림", frames(N32, 6, {}, "axe")),
              ("32px — 늘어난 칸을 쓴 것", frames(N32, 6, TUNED32, "axe"))]),
        band("3) 늘어난 칸으로 무엇이 되고 무엇은 32px 에서도 안 되나 (얼굴 12배)",
             [("", [head(G.DESIGN_N, 22, {}),
                    head(N32, 12, {}),
                    head(N32, 12, dict(TUNED32, brow=None, collar=0.0, buttons=0)),
                    head(N32, 12, dict(TUNED32, collar=0.0, buttons=0)),
                    head(N32, 12, TUNED32),
                    head(N32, 12, dict(TUNED32, brow=(2, 4, 0.30)))])],
             caps=["17px 지금", "32px 픽셀만 늘림", "3×2 눈 + 하이라이트",
                   "+ 눈썹(머리색, 옅게)", "+ 옷깃 · 앞섶 단추",
                   "눈썹을 눈만큼 진하게 — 째려본다"]),
        band("4) 32px 에서도 안 되는 것 — 손가락 (왼손만 확대)",
             [("", [hand(G.DESIGN_N, 50), hand(N32, 28)])],
             caps=["17px — 손 2×1px",
                   "32px — 손 2×2px. 가르려면 빈 칸이 한 줄 있어야 하니 손이 3px, "
                   "곧 캔버스가 43px 은 돼야 한다"], width=1400),
    ]
    w = max(i.width for i in bands)
    bands = [band_pad(i, w) for i in bands]
    out = Image.new("RGBA", (w, sum(i.height for i in bands) + 12 * len(bands)),
                    (22, 20, 26, 255))
    y = 0
    for i in bands:
        out.alpha_composite(i, (0, y))
        y += i.height + 12
    path = os.path.join(OUT, "canvas_32_vs_17.png")
    out.save(path)
    print("saved", path)
    return path


if __name__ == "__main__":
    main()
