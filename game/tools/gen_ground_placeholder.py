"""바닥 자리표시 더미의 무늬를 찍는다 (docs/feedback/INBOX.md #70).

**이것만 PNG 를 굽지 않는다.** 그림이 없는 아이템(원재료)이 바닥에 놓일 때 그리는
자리표시는 **색이 아이템마다 다르다**(`item_types.gd` 의 `color`) — 색 하나에서
램프 4단계를 만드는 일이 **실행 중**에 일어나야 해서, 구워진 PNG 로는 안 된다.
그래서 이 스크립트가 내놓는 것은 그림이 아니라 **램프 단계 번호가 적힌 글자 표**이고,
그것을 `ground_item_node.gd` 의 `PLACEHOLDER_ART` 에 붙여 넣는다.

| 글자 | 뜻 |
|---|---|
| `.` | 빈 칸 |
| `k` | 잉크(외곽선) — `#261C2C`, 순검정이 아니다 |
| `0`~`3` | 그 아이템 색의 램프 (밝은면 → 기본 → 그늘 → 가장 어두움) |

## 왜 손으로 안 찍고 여기서 굽는가

옛 무늬는 코드에 손으로 찍은 10 × 8 이었고, 그걸 화면에서 3배로 그려서 도트만 혼자
세 배 굵었다(INBOX #67 이 나머지를 전부 1배로 맞춘 뒤 이것만 남았다). 칸을 36 × 32 로
키우면 손으로 찍을 칸이 **11배**가 되는데, 그 크기에서 손으로 찍은 도트는 테두리에만
음영이 걸린 납작한 그림이 된다(`docs/STYLE_GUIDE.md` 6번의 첫 줄).

그래서 **덩어리 → 조명 → 축소 → 양자화 → 내부선 → 외곽선**이라는 같은 파이프라인을
`gen_character.py` 에서 그대로 빌려 쓴다. 재질을 하나만 쓰되 **덩어리마다 부위 id 를
달리** 해서, `inner_lines()` 가 긋는 어두운 줄이 곧 덩어리 사이의 골이 되게 한다
(나무 잎 뭉치·뒷머리 결·상자 판자결과 같은 수법이다).

## 크기 — 36 × 32

「아이템/오브젝트 크기 표준」의 하한이 **짧은 쪽 32px** 이다. 옛 자리표시는 화면
30 × 24px 이라 그 하한을 세로에서 8px 어겼는데, 배율이 1이 되면서 아트 픽셀 수가 곧
화면 크기가 된 지금은 **표의 줄 수가 그대로 그 판정**이다. 가로 36 은 바닥에 놓인
도구(`ground_*.png`)의 칸과 같은 값이라 나란히 놓여도 결이 안 어긋난다.

## 돌리는 법

    .venv/bin/python game/tools/gen_ground_placeholder.py            # 채택한 표를 찍는다
    GEN_OUT=/tmp/ph .venv/bin/python game/tools/gen_ground_placeholder.py --all
        → 후보를 전부 굽고 비교용 PNG 를 그 폴더에 남긴다(저장소를 안 더럽힌다)
"""

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_character as gen  # noqa: E402


# 자리표시가 놓이는 칸. 가로는 바닥 도구 그림(`gen.GROUND_N`)과 같고, 세로는
# 「크기 표준」의 하한(32)이다 — 더미는 도끼보다 납작한 물건이라 세로만 줄인다.
CELL_W = gen.GROUND_N
CELL_H = 32

# 굽는 것은 정사각 캔버스뿐이라(`gen.canvas()`) 36 × 36 에 그리고 아래를 잘라낸다.
# 그림은 y 1~30 안에 들어가야 한다(0 줄과 31 줄은 외곽선 자리다).
CANVAS = CELL_W

# 램프 단계 수 — `ground_item_node.gd` 의 램프와 같은 4단계여야 한다.
STEPS = 4

# 자리표시는 재질이 하나다(색이 아이템마다 다르므로 램프도 하나뿐이다). 어느
# 이름을 쓰든 결과에는 안 남지만, `gen.MATS` 에 있는 이름이어야 `downsample()` 이
# 센다 — 나무 자루와 같은 칸을 빌려 쓴다.
MAT = "helve"


# ── 후보 ──────────────────────────────────────────────────────────────────
# 덩어리는 `(cx, cy, rx, ry)` 다. **밑동이 한 줄에 모이게** 놓는다 — 아래가
# 들쭉날쭉하면 땅에 놓인 것이 아니라 공중에 뜬 것으로 보인다.
#
# 덩어리 크기를 서로 다르게 잡는 것이 중요하다: 같은 크기 원을 여러 개 붙이면
# 더미가 아니라 **포도송이**가 된다(`docs/STYLE_GUIDE.md` 6번, 나무 잎 항목).
CANDIDATES = {
    # **채택한 것** — 아래 둘 + 위 하나, 위가 한 뼘 작다. 크기가 아래에서 위로
    # 줄어드는 것이 「쌓인 더미」로 읽히게 하는 전부다(같은 크기 셋을 쌓은 후보는
    # 대포알 세 개였다). 위 덩어리를 반 칸 왼쪽으로 물려 좌우 대칭을 깼다.
    "three": [(10.5, 22.0, 9.5, 9.0), (25.0, 22.5, 10.0, 8.5),
              (17.0, 9.5, 8.5, 8.5)],
    # 아래 셋 + 위 하나. 큰 것이 위에 얹혀 **조약돌 위의 눈덩이**로 보였다.
    "four": [(8.5, 23.0, 7.5, 8.0), (18.5, 24.0, 8.5, 7.0),
             (27.0, 23.0, 7.5, 8.0), (17.0, 11.0, 9.5, 10.0)],
    # 아래 셋 + 위 둘. 낱알이 다 비슷해져서 **포도송이**가 됐다.
    "five": [(8.0, 24.0, 7.0, 7.0), (18.0, 25.0, 7.5, 6.0),
             (28.0, 24.0, 6.5, 7.0), (12.0, 11.0, 8.0, 10.0),
             (24.0, 12.0, 7.5, 9.0)],
    # 켜켜이 쌓은 산 모양. 낱알이 안 세어져서 갈색으로 칠하면 **똥**이다.
    "heap": [(18.0, 24.0, 16.5, 7.0), (15.0, 16.0, 11.0, 7.0),
             (19.0, 9.0, 8.0, 8.0)],
}

DEFAULT = "three"


def bake(chunks, canvas=CANVAS):
    """덩어리 목록 → `(단계 번호, 칠해짐, 잉크)` 세 장. 전부 `canvas` × `canvas`.

    단계 번호는 `quantize()` 와 같은 식으로 낸다 — 램프 색을 모르므로 색 대신
    번호를 남길 뿐이다. 내부선(`inner_lines()`)도 같은 이유로 「가장 어두운 단계로
    바꾼다」는 조작만 그대로 옮긴다.
    """
    with gen.canvas(canvas, 1.0):
        b = gen.Build()
        for cx, cy, rx, ry in chunks:
            b.add(gen.ellipsoid(cx, cy, rx, ry), MAT)
        lum = gen.light(b.hgt, b.mat, key=gen.CFG["key"], amb=gen.CFG["amb"],
                        rim=gen.CFG["rim"])
        mat, lm = gen.downsample(b.mat, lum)
        part = gen.downsample_part(b.part)

    filled = mat >= 0
    idx = np.clip(np.floor(np.clip(1.0 - lm, 0, 1) * (STEPS - 1)), 0, STEPS - 1)
    idx = idx.astype(np.int32)

    # 내부선 — 광원이 왼쪽 위이므로 경계의 오른쪽/아래에 찍는다(`inner_lines()`).
    # 재질이 하나뿐이라 「같은 재질끼리」 조건은 저절로 참이다.
    edge = np.zeros_like(filled)
    edge[:, 1:] |= filled[:, :-1] & filled[:, 1:] & (part[:, :-1] != part[:, 1:])
    edge[1:, :] |= filled[:-1, :] & filled[1:, :] & (part[:-1, :] != part[1:, :])
    idx[edge] = STEPS - 1

    # 외곽선 — 칠해진 자리 바깥 1px.
    pad = np.pad(filled, 1, constant_values=False)
    near = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    ink = near & ~filled
    return idx, filled, ink


def rows(chunks, height=CELL_H, width=CELL_W):
    """`PLACEHOLDER_ART` 에 그대로 넣을 글자 표. 아래에서 `height` 줄을 잘라 쓴다."""
    idx, filled, ink = bake(chunks)
    out = []
    for y in range(height):
        line = []
        for x in range(width):
            if filled[y, x]:
                line.append(str(int(idx[y, x])))
            elif ink[y, x]:
                line.append("k")
            else:
                line.append(".")
        out.append("".join(line))
    # 위아래로 남는 빈 줄은 버린다 — 표가 곧 그림의 크기여야 한다.
    while out and set(out[0]) == {"."}:
        out.pop(0)
    while out and set(out[-1]) == {"."}:
        out.pop()
    return out


def check(art, height=CELL_H, width=CELL_W):
    """표가 칸을 안 넘고 아래로 새지 않았는지. 문제를 글로 돌려준다(없으면 빈 목록)."""
    bad = []
    if len(art) > height:
        bad.append("세로 %d 줄 — 칸(%d)을 넘는다" % (len(art), height))
    if any(len(r) != width for r in art):
        bad.append("가로가 %d 이 아닌 줄이 있다" % width)
    if len(art) < min(height, width):
        bad.append("짧은 쪽이 %d px — 「크기 표준」의 하한 32 를 깬다" % len(art))
    body = {c for r in art for c in r} - {".", "k"}
    if len(body) < 3:
        bad.append("램프 단계를 %d 개만 쓴다 — 단색으로 보인다" % len(body))
    # 「잘림」 — 표의 테두리에 잉크가 아닌 몸 픽셀이 닿으면 외곽선이 잘린 것이다
    # (`qa_sprite_check.py` 가 구워진 시트에 대고 보는 것과 같은 판정이다).
    border = set(art[0]) | set(art[-1]) | {r[0] for r in art} | {r[-1] for r in art}
    if border - {".", "k"}:
        bad.append("테두리에 몸 픽셀이 닿는다 — 외곽선이 잘렸다")
    return bad


# ── 눈으로 볼 것 ──────────────────────────────────────────────────────────

def _ramp(base):
    """`ground_item_node.gd` 와 **같은 식**이어야 한다 — Godot 의 `Color.lightened`
    는 `c + (1-c)*t`, `darkened` 는 `c * (1-t)` 다."""
    c = np.array(base, dtype=np.float32) / 255.0
    steps = [c + (1.0 - c) * 0.28, c, c * (1.0 - 0.28), c * (1.0 - 0.50)]
    return [tuple(int(round(v * 255)) for v in s) for s in steps]


def render(art, base, scale=1, bg=(76, 108, 58)):
    """글자 표를 그 아이템 색으로 칠한 이미지."""
    ramp = _ramp(base)
    w, h = len(art[0]), len(art)
    img = Image.new("RGB", (w, h), bg)
    px = img.load()
    for y, row in enumerate(art):
        for x, cell in enumerate(row):
            if cell == ".":
                continue
            px[x, y] = gen.INK if cell == "k" else ramp[int(cell)]
    return img.resize((w * scale, h * scale), Image.NEAREST)


def main(argv):
    out = os.environ.get("GEN_OUT")
    names = list(CANDIDATES) if "--all" in argv else [DEFAULT]

    # 자리표시가 실제로 붙는 원재료 색 셋(`item_types.gd`) — 하나만 보고 고르면
    # 어두운 색에서 램프가 뭉치는 것을 놓친다.
    colors = [("wood", (138, 92, 51)), ("stone", (125, 128, 122)),
              ("iron_ore", (112, 97, 87))]

    tiles = []
    for name in names:
        art = rows(CANDIDATES[name])
        bad = check(art)
        print("## %s — %d x %d %s"
              % (name, len(art[0]), len(art), "OK" if not bad else "불합격"))
        for line in bad:
            print("   ! " + line)
        if name == DEFAULT and not bad:
            print("const PLACEHOLDER_ART := [")
            for row in art:
                print('\t"%s",' % row)
            print("]")
        if out:
            for label, base in colors:
                tiles.append((("%s/%s" % (name, label)), render(art, base, 1),
                              render(art, base, 6)))

    if out:
        os.makedirs(out, exist_ok=True)
        pad = 8
        big_h = max(t[2].height for t in tiles)
        width = sum(t[2].width + pad for t in tiles) + pad
        sheet = Image.new("RGB", (width, big_h + 48 + pad * 3), (30, 28, 34))
        x = pad
        for _, small, big in tiles:
            sheet.paste(big, (x, pad))
            sheet.paste(small, (x + (big.width - small.width) // 2,
                                pad * 2 + big_h))
            x += big.width + pad
        path = os.path.join(out, "ground_placeholder_candidates.png")
        sheet.save(path)
        print("남겼다: %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
