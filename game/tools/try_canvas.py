"""캔버스 크기를 바꿔보는 **시험** 도구 — 게임 자산을 만들지 않는다.

실행: `.venv/bin/python game/tools/try_canvas.py`
결과: `docs/design_reference/canvas_26_vs_17.png` (사람이 보고 판단할 비교 이미지)

2026-09-07, INBOX #44. 사람 요청으로 **캔버스 26px 이 참고작 수준의 디테일을
담을 수 있는지**만 확인한다 — **아무것도 채택하지 않는다.** `gen_character.py` 의
`canvas_scale()` 이 여기서 처음 쓰인다: 설계 좌표(17칸)는 그대로 두고 격자만 다시
깔아서, **같은 형태를 더 촘촘한 픽셀에** 찍는다.

이 파일이 보여주는 것은 셋이다:
  1. 실제 게임에서 보이는 크기 — 17px × 3배(51px) 대 26px × 2배(52px). 화면
     크기를 맞추려면 **배율이 3배에서 2배로 내려간다.**
  2. 6배 확대 — 도트 하나하나가 어떻게 놓이는지.
  3. 늘어난 칸으로 **무엇을 넣을 수 있는지**(흰자 · 옷깃 · 앞섶 단추 · 넓은 볼
     홍조)와 **무엇은 26px 에서도 안 되는지**(눈썹 · 손가락).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_character as G                                       # noqa: E402

REF = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "design_reference"))
OUT = os.environ.get("GEN_OUT") or REF

N26 = 26
K = N26 / float(G.DESIGN_N)     # 1.529 — 설계 단위 하나가 26px 칸에서 몇 px 인가

# **26px 에서 다시 잡아야 하는 값들.** `gen_character.CFG_KIND` 의 "grid" 갈래 —
# 축소가 끝난 네이티브 격자에 칸을 세어 찍는 것들이라 캔버스가 바뀌면 안 따라온다.
# 나머지(설계 길이 · 무차원 비율)는 한 줄도 손대지 않았다.
TUNED26 = dict(
    # 눈 — 얼굴이 세 줄에서 **네 줄**, 폭이 9 에서 **14px** 이 되면서 3칸짜리 눈이
    # 들어간다. 3칸이면 바깥 한 칸을 **흰자**로 비울 수 있다(17px 은 두 칸뿐이라
    # 절반이 흰색이 되어 못 했다 — STYLE_GUIDE 「자연스러움」의 "하이라이트는 눈이
    # 2×2 일 때만").
    eye_style="sclera3",
    eye_y=7 / K,            # 26px 격자에서 7행 — 앞머리 끝(5행)과 한 칸 떨어진다
    blush_w=2,              # 볼 홍조도 한 칸에서 두 칸으로
    # 옷 포인트가 **둘**이 된다. 상의가 세 줄에서 일곱 줄이 되어 허리띠 + 옷깃이
    # 가운데 줄을 다 먹지 않는다(17px 의 「옷포인트」 상한 1개가 풀린다).
    collar=0.22,
    buttons=3,              # 앞섶 단추 — 17px 에는 찍을 자리 자체가 없다
)

DIRS = G.DIRS


def _font(size):
    for p in ("/System/Library/Fonts/AppleSDGothicNeo.ttc",
              "/System/Library/Fonts/Supplemental/AppleGothic.ttf"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return ImageFont.load_default()


def frames(n, zoom, over):
    """idle 4방향 + 도끼 든 4방향을 `zoom` 배로."""
    with G.canvas_scale(n):
        out = [G.character(d, **over) for d in DIRS]
        out += [G.character(d, tool="axe", motion="hold", **over) for d in DIRS]
        return [G.to_img(f, zoom) for f in out]


def band(label, rows, width=None, caps=None,
         pad=10, gap=18, bg=(30, 28, 34, 255), fg=(226, 222, 232, 255)):
    """`rows` = [(줄이름, [이미지…]), …] 을 이름표와 함께 한 덩어리로.

    `caps` 를 주면 칸마다 그 아래에 작은 글씨를 단다(칸끼리 다른 것을 견줄 때).
    """
    f, fs, fc = _font(15), _font(19), _font(13)
    name_w = max(max(f.getbbox(t)[2] for t, _ in rows), 150) + 12
    cap_h = 20 if caps else 0
    row_h = [max(i.height for i in ims) + cap_h for _, ims in rows]
    need = name_w + max(sum(i.width + gap for i in ims) for _, ims in rows) + pad * 2
    w = max(width or 0, need)
    h = sum(row_h) + gap * len(rows) + 34 + pad
    im = Image.new("RGBA", (w, h), bg)
    d = ImageDraw.Draw(im)
    d.text((pad, pad), label, font=fs, fill=(255, 214, 122, 255))
    y = pad + 30
    for (name, ims), rh in zip(rows, row_h):
        d.text((pad, y + rh // 2 - 8), name, font=f, fill=fg)
        x = pad + name_w
        for i, im1 in enumerate(ims):
            im.alpha_composite(im1, (x, y + (rh - cap_h - im1.height) // 2))
            if caps:
                d.text((x, y + rh - 16), caps[i], font=fc, fill=(178, 174, 188, 255))
            x += im1.width + gap
        y += rh + gap
    return im


def head(n, zoom, over):
    """얼굴만 잘라 크게 — 표정에 들어가는 것은 이 몇 줄이 전부다."""
    with G.canvas_scale(n):
        im = G.to_img(G.character("down", **over))
    top, bot = 0, int(round(n * 10.5 / G.DESIGN_N))
    return im.crop((0, top, n, bot)).resize((n * zoom, (bot - top) * zoom), Image.NEAREST)


def main():
    bands = [
        band("1) 실제 게임에서 보이는 크기 — 왼쪽 넷 idle 4방향 / 오른쪽 넷 도끼 들고",
             [("지금 17px × 3배 = 51px", frames(G.DESIGN_N, 3, {})),
              ("26px × 2배 = 52px", frames(N26, 2, TUNED26))]),
        band("2) 6배 확대",
             [("지금 17px", frames(G.DESIGN_N, 6, {})),
              ("26px — 같은 형태 그대로", frames(N26, 6, {})),
              ("26px — 늘어난 칸을 쓴 것", frames(N26, 6, TUNED26))]),
        band("3) 늘어난 칸으로 무엇이 되고 무엇은 26px 에서도 안 되나 (얼굴만 14배)",
             [("", [head(G.DESIGN_N, 14, {}),
                    head(N26, 14, dict(TUNED26, eye_style="bar")),
                    head(N26, 14, dict(TUNED26, collar=0.0, buttons=0)),
                    head(N26, 14, TUNED26),
                    head(N26, 14, dict(TUNED26, brow=(1, 3)))])],
             caps=["17px 지금", "26px 눈은 그대로(2칸)", "3칸 눈 + 흰자",
                   "+ 옷깃 · 앞섶 단추", "+ 눈썹 — 앞머리에 붙는다"]),
    ]
    w = max(i.width for i in bands)
    bands = [band_pad(i, w) for i in bands]
    out = Image.new("RGBA", (w, sum(i.height for i in bands) + 12 * len(bands)),
                    (22, 20, 26, 255))
    y = 0
    for i in bands:
        out.alpha_composite(i, (0, y))
        y += i.height + 12
    path = os.path.join(OUT, "canvas_26_vs_17.png")
    out.save(path)
    print("saved", path)
    return path


def band_pad(im, w):
    if im.width >= w:
        return im
    out = Image.new("RGBA", (w, im.height), im.getpixel((0, im.height - 1)))
    out.alpha_composite(im, (0, 0))
    return out


if __name__ == "__main__":
    main()
