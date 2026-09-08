"""데스드롭 상자 스프라이트 (docs/DESIGN.md 「데스드롭 상자」, INBOX #40).

`gen_character.py` 옆에 둔 **상자용 생성기**다. 그림을 만드는 방법 자체는
`gen_character.py` 그대로 빌려 쓴다 — 같은 원시 도형(`rbox`/`capsule`), 같은 램프
(`palette()` 의 `helve`/`blade`), 같은 광원(왼쪽 위), 같은 축소·양자화·내부선·외곽선.
그래야 상자가 도구·캐릭터와 **같은 손에서 나온 그림**으로 보인다
(`docs/DESIGN.md` 「그래픽 파이프라인」 1) 어울림).

## 왜 재질이 나무(`helve`)와 쇠(`blade`) 둘뿐인가

이 두 램프는 **커스터마이징을 따라가지 않는 고정색**이다(「캐릭터 애니메이션」의
"도구 색은 커스터마이징을 따라가지 않는다"). 상자도 마찬가지여야 하므로 —
옷색을 바꿨다고 남의 데스드롭 상자 색이 달라지면 안 된다 — 새 재질을 늘리는 대신
자루(나무)와 날(쇠)의 램프를 그대로 쓴다. 덤으로 도구 아이콘과 **정확히 같은
나무색·쇠색**이 되어 바닥에 나란히 놓여도 어긋나지 않는다.

## 칸이 정사각형이 아니다 (48 × 42)

상자 크기는 `death_boxes.gd` 의 `BOX_SIZE`(48 × 42)가 이미 정해뒀다 — **배율 1**이라
아트도 48 × 42px 이다. `gen_character.canvas()` 는 정사각 캔버스만 만들 수 있으므로
**48 × 48 에 굽고 아래 여섯 줄을 잘라낸다.** 그래서 그림은 설계 공간 y 1~12 안에
들어가야 한다(0 줄과 13 줄은 외곽선 자리다) — 잘라낸 줄에 무언가 남으면
`qa_sprite_check.py` 의 「잘림」이 잡는다.

## 설계 공간은 16칸 그대로다 (2026-09-08, INBOX #67)

그전에는 아트 16 × 14px 을 화면에서 3배로 그렸다 — 배율은 정수였지만 **아트 픽셀
하나가 화면 3px** 이라 도트가 1px 인 캐릭터·지형·바닥 아이템 옆에서 상자만 뭉툭했다.
지금은 같은 16칸짜리 설계를 `UNIT`(3) 배로 촘촘한 격자에 찍는다 — **아래 형태 값은
한 줄도 안 바뀌었고** 화면 크기(48 × 42)도 그대로다. 「쇠 띠는 두 칸」·「자물쇠는
띠 아래로 두 칸」 같은 실측은 전부 이 16칸 설계 단위의 값이라 그대로 산다.
"""

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_character as gen                                     # noqa: E402

## 설계 공간 한 변(칸). 형태 값이 전부 이 단위로 적혀 있다 — 위 설명 참고.
DESIGN = 16
## 설계 단위 하나를 몇 px 로 찍는가. 캐릭터(96px 칸)·지형(48px 칸)과 같이 **배율 1**
## 이므로 이 값이 곧 도트 하나의 화면 크기가 아니라 **설계 한 칸의 화면 크기**다.
UNIT = 3

## 아트 픽셀 칸. **`death_boxes.gd` 의 `BOX_SIZE` 와 같은 값이다**(배율 1).
BOX_W, BOX_H = 16 * UNIT, 14 * UNIT      # 48 × 42
## 굽는 캔버스 — 정사각이라 세로가 여섯 줄 남고, 그 줄들은 잘라낸다.
CANVAS = DESIGN * UNIT

## 시트의 열 순서. `death_box_node.gd` 의 `FRAME_CLOSED`/`FRAME_OPEN` 과 같아야 한다.
FRAMES = ("closed", "open")

# ── 형태 ──────────────────────────────────────────────────────────────────
# 몸통. 좌우로 부푼 원기둥(`axis="x"`)이라 왼쪽 위가 밝고 오른쪽이 그늘진다.
BODY = (1.5, 5.0, 14.5, 13.0)
BODY_R, BODY_DOME = 1.2, 1.5

# 판자 결. **부위 id 만 다른 조각을 겹쳐 얹어** 그 경계에 `inner_lines()` 가 가장
# 어두운 단계를 긋게 한다 — 뒷머리 결을 내는 것과 같은 수법이다
# (`docs/STYLE_GUIDE.md` 6번). 높이장을 따로 만들지 않으므로 그 자리가 납작해지지
# 않는다. 셋을 고르게 벌려야 궤짝이 통나무가 아니라 **판자를 이어 붙인 것**으로 읽힌다.
PLANKS = (5.35, 8.5, 11.65)

## 뚜껑 — 가로로 누운 캡슐이라 **위가 둥글다**. 몸통보다 조금 넓어서 옆선이 한 칸
## 꺾인다(실루엣에 곧은 구간을 남기지 않는다, `docs/STYLE_GUIDE.md` 「자연스러움」).
LID_CLOSED = dict(x0=3.4, x1=12.6, y=3.3, r=2.35, dome=1.7, lift=0.15)
## 열린 뚜껑 — **뒤로 젖혀져 위에 납작하게 눕는다.** 캔버스 맨 윗줄(0)은 외곽선
## 자리라 `y - r` 이 0.7 보다 작아지면 「잘림」이다.
LID_OPEN = dict(x0=3.4, x1=12.6, y=2.0, r=1.40, dome=0.90, lift=0.15)

## 뚜껑과 몸통을 가르는 쇠 띠. **이 한 줄이 궤짝을 궤짝으로 만든다** — 없으면
## 나무 덩어리 위에 나무 덩어리가 얹힌 것으로만 보인다.
##
## **두 칸 두께여야 한다.** 한 칸(`BAND_R` 0.55)으로 뽑았더니 축소하면서 띠의 밝은
## 윗면이 이웃 나무와 평균나서 쇠 평균 명도가 150 으로 떨어졌다 — 아이콘 하한과
## 같은 값이라 「재질명도」가 잡았다. 얇은 쇠붙이가 어두워지는 것은
## `docs/STYLE_GUIDE.md` 「손에 쥔 도구」에 이미 적힌 사실이고, **검사를 늦출
## 자리가 아니라 그림을 고칠 자리다**(낚싯대 「명암폭」과 같다). 실측:
## 0.55 → 150 / 0.70 → 151 / **0.85 → 158** / 1.00 → 164(띠가 상자를 반으로 가른다).
BAND_R, BAND_DOME, BAND_LIFT = 0.85, 0.30, 0.20
BAND_X = (2.0, 14.0)
BAND_Y_CLOSED, BAND_Y_OPEN = 5.30, 3.35

## 자물쇠 — 띠 가운데에 걸린 쇳조각. **띠 아래로 두 칸 내려와야** 걸쇠로 읽힌다
## (띠 안에만 있으면 띠가 한 칸 굵어진 것으로 보인다). 열린 프레임에서는 그 두 칸이
## **어두운 구멍 위에 걸린다** — 뚜껑에 매달려 있다는 것이 거기서 보인다.
LATCH_W, LATCH_DOME, LATCH_LIFT = 1.2, 0.55, 0.55
LATCH_Y_CLOSED = (4.60, 7.60)
LATCH_Y_OPEN = (2.90, 6.20)

## 열렸을 때 보이는 **상자 안쪽**. 두 켜다:
##   `HOLE`  — 뚜껑 밑의 빈 구멍. **공통 잉크색으로 채운다.**
##   `WALL`  — 그 아래로 보이는 안쪽 앞벽. **나무 램프의 가장 어두운 단계**다.
##
## **구멍을 조명으로 만들 수는 없다.** `light()` 의 환경광(`CFG["amb"]` 0.17) 때문에
## 명도가 0 까지 안 내려가서, 아무리 가파른 면을 세워도 램프 4단계 중 3단계(그늘)가
## 하한이다 — 실제로 그렇게 구운 후보는 "뚜껑이 하나 더 얹힌 상자"로 보였다.
## **구멍은 재질이 아니라 재질이 없는 자리**라 잉크가 맞다(외곽선이 잉크인 것과 같은
## 이유다). 대신 **잉크만으로 채우면 검은 스티커**가 되므로, 그 아래에 한 켜 밝은
## 안쪽 벽을 두어 깊이를 만든다 — 이 두 켜가 있어야 "열렸다"가 한눈에 읽힌다.
HOLE = (3.2, 4.30, 12.8, 6.90)
WALL = (3.2, 6.90, 12.8, 7.90)
INSIDE_H = (2.6, 0.0)


## 안쪽 앞벽 색. **베껴 적지 않고 램프에서 꺼낸다** — 나무 램프가 바뀌면 같이 따라간다.
PAL_DARK_WOOD = gen.palette()["helve"][-1]


def slope(x0, y0, x1, y1, h0, h1):
    """위에서 아래로 높이가 기우는 판. 반환은 다른 원시 도형과 같은 (마스크, 높이).

    `rbox` 는 가운데가 솟은 돔이라 아래쪽만 그늘지는데, 상자 안쪽은 **면 전체가**
    광원을 등져야 한다 — 기울기가 일정한 판이 그 형태다.
    """
    m = (gen.GX >= x0) & (gen.GX <= x1) & (gen.GY >= y0) & (gen.GY <= y1)
    t = np.clip((gen.GY - y0) / max(y1 - y0, 1e-6), 0.0, 1.0)
    return m, (h0 + (h1 - h0) * t) * m


def _body(b):
    b.add(gen.rbox(*BODY, r=BODY_R, dome=BODY_DOME, axis="x"), "helve")
    for px in PLANKS:
        b.add(gen.rbox(px, BODY[1], BODY[2], BODY[3], r=BODY_R, dome=BODY_DOME,
                       axis="x"), "helve")


def _lid(b, spec):
    b.add(gen.capsule(spec["x0"], spec["y"], spec["x1"], spec["y"], spec["r"],
                      dome=spec["dome"]), "helve", lift=spec["lift"])


def _band(b, y):
    b.add(gen.capsule(BAND_X[0], y, BAND_X[1], y, BAND_R, dome=BAND_DOME),
          "blade", lift=BAND_LIFT)


def _latch(b, y):
    b.add(gen.rbox(8.0 - LATCH_W, y[0], 8.0 + LATCH_W, y[1], r=0.4,
                   dome=LATCH_DOME, axis="x"), "blade", lift=LATCH_LIFT)


def build_closed(b):
    _body(b)
    _lid(b, LID_CLOSED)
    _band(b, BAND_Y_CLOSED)
    _latch(b, LATCH_Y_CLOSED)


def build_open(b):
    _body(b)
    # 두 켜의 부위 id 를 돌려준다 — 색은 조명이 아니라 아래 `frame()` 이 찍는다.
    hole = b.add(slope(*HOLE, *INSIDE_H), "helve")
    wall = b.add(slope(*WALL, *INSIDE_H), "helve")
    _lid(b, LID_OPEN)
    _band(b, BAND_Y_OPEN)
    _latch(b, LATCH_Y_OPEN)
    return {hole: gen.INK, wall: PAL_DARK_WOOD}


BUILDS = {"closed": build_closed, "open": build_open}


def frame(name="closed", pal=None):
    """상자 한 프레임(`BOX_W` × `BOX_H`). `tool_icon()` 과 같은 파이프라인이다.

    `BUILDS[name]` 이 **부위 id → 색** 을 돌려주면 그 부위를 그 색으로 덮는다
    (열린 상자의 구멍·안쪽 벽). `inner_lines()` **다음에** 덮는다 — 구멍 테두리에
    한 단계 어두운 줄을 또 그으면 구멍이 한 칸 커진다.
    """
    pal = pal or gen.palette()
    with gen.canvas(CANVAS, UNIT):
        b = gen.Build()
        paint = BUILDS[name](b) or {}
        lum = gen.light(b.hgt, b.mat, key=gen.CFG["key"], amb=gen.CFG["amb"],
                        rim=gen.CFG["rim"])
        m, l = gen.downsample(b.mat, lum)
        pm = gen.downsample_part(b.part)
        rgb = gen.inner_lines(gen.quantize(m, l, pal, 0.0), m, pm, pal)
        for part, color in paint.items():
            rgb[pm == part] = np.concatenate([np.array(color, np.uint8), [255]])
        rgb = gen.outline(rgb, m)
    return rgb[:BOX_H]


def sheet(pal=None):
    """열 = 프레임(닫힘 · 열림) 한 장. 시트 규칙은 캐릭터 시트와 같다."""
    pal = pal or gen.palette()
    out = np.zeros((BOX_H, BOX_W * len(FRAMES), 4), dtype=np.uint8)
    for i, name in enumerate(FRAMES):
        out[:, i * BOX_W:(i + 1) * BOX_W] = frame(name, pal)
    return out


def sheet_path():
    """`death_box_node.gd` 의 `SHEET` 와 같은 경로여야 한다."""
    return f"{gen.SPRITES}/death_box.png"


if __name__ == "__main__":
    gen.to_img(sheet()).save(sheet_path())
    print("saved", sheet_path())
    if os.environ.get("GEN_OUT"):       # 후보 비교용 — 저장소를 더럽히지 않는다
        out = gen.OUT
        for scale in (12, 6, 3):
            gen.strip([gen.to_img(frame(n), scale) for n in FRAMES]) \
                .save(f"{out}/death_box_x{scale}.png")
