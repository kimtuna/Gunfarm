"""월드 오브젝트 스프라이트 — 나무 · 바위 · 덤불 (docs/DESIGN.md 「월드 오브젝트」, INBOX #63).

    .venv/bin/python game/tools/gen_objects.py                  # 게임 자산을 다시 굽는다
    GEN_OUT=/tmp/o .venv/bin/python game/tools/gen_objects.py    # 후보 비교용 그림도 남긴다

만드는 것: `game/assets/sprites/object_<종류>.png` 세 장(행 하나 · 열 = 변주).
어느 변주가 어디에 나는지는 `world_gen.gd` 가 좌표 해시로 정한다(지형 무늬 변주와
같은 방식이다).

## 왜 `gen_box.py` 옆에 또 하나인가

`gen_terrain.py` 는 **넓게 깔리는 바닥**이라 "깨끗한 바탕 + 획 몇 개"로 그리고
이음매가 전부인데, 나무·바위는 **부피가 있는 물건 하나**다 — 데스드롭 상자와 같은
갈래다(`docs/STYLE_GUIDE.md` 「도구가 아닌 월드 오브젝트」). 그래서 그리는 방법은
`gen_character.py` 것을 그대로 빌린다: 같은 원시 도형, 같은 광원(왼쪽 위), 같은
축소·양자화·내부선·외곽선. 그래야 캐릭터·도구·상자와 **같은 손에서 나온 그림**으로
보인다.

## 값을 치르고 알아낸 것 (고칠 때 되돌리지 말 것)

  * **배율이 1이라 아트 px 이 곧 화면 px 이다.** 캔버스가 캐릭터(96)·타일(48)과
    같은 자에 놓여 있으므로, 여기 적은 크기가 그대로 「몇 칸짜리 물건인가」다
    (`docs/DESIGN.md` 「아이템/오브젝트 크기 표준」).
  * **슈퍼샘플은 8이다** (캐릭터는 24). 캔버스가 17px 이던 시절의 24 를 144px 에
    그대로 쓰면 한 변이 3456px 이라 배열 한 장이 47MB 다. 8이면 출력 픽셀 하나당
    64 샘플이라 형태가 뭉개지지 않으면서 1초 안에 굽는다.
  * **줄기는 재질을 새로 늘리지 않고 도구 자루(`helve`)를 쓴다.** 상자가 그랬던
    것과 같은 이유다 — 바닥에 떨어진 도끼와 정확히 같은 나무색이 되어 「어울림」이
    공짜로 지켜진다.
  * **잎은 램프를 넓게 잡아야 한다.** 깊은 바다와 같은 자리다(`gen_terrain.py`):
    좁은 램프로는 덩어리를 아무리 나눠도 화면이 초록 한 판이라 「명암폭」에 걸린다.
  * **잎 덩어리는 부위 id 만 갈라서 낸다** — 높이장을 따로 만들지 않으므로 그
    자리가 납작해지지 않는다(뒷머리 결·상자 판자결과 같은 수법이다). 덩어리가
    많을수록 내부선이 늘어 「어두운비율」이 오른다 — 나무는 다섯 덩어리가 상한이었다.
  * **바위는 타원 세 개다 — 각지게 만들면 오히려 상자가 된다.** `rbox` 로 면을
    세운 후보(각진 몸통 / 타원 몸통 + 각진 윗면)는 둘 다 48px 에서 **케이크**로
    읽혔다. 이끼를 얹은 후보는 초록 스티커였다. 면이 다섯이면 내부선이 그물이
    되어 **깨진 유리**다. **옆에 굴러 나온 조각도 뺐다** — 실제 크기에서 그건
    조각이 아니라 바위에 붙은 **흰 얼룩**으로 보인다.
  * **끝이 반원인 원시 도형은 반지름만큼 더 나간다.** 줄기 밑동을 칸의 아랫줄에
    맞춰 뒀더니 밑동이 통째로 칸 밖으로 나가 잘렸다(「잘림」) — 캡슐의 끝점은
    그림의 끝이 아니라 **중심**이다.
"""

import contextlib
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_character as gen                                     # noqa: E402

OUT = os.environ.get("GEN_OUT")

## 슈퍼샘플 배율 — 위 설명 참고. `gen.SS`(24)를 이 값으로 잠깐 갈아끼운다.
SS = 8

## 종류마다 (칸 가로, 칸 세로). **화면 크기와 같은 값이다**(배율 1).
## 타일 한 칸이 48px 이므로 나무는 세로 세 칸, 바위·덤불은 한 칸이다.
SIZES = {"tree": (96, 144), "rock": (48, 48), "bush": (48, 48)}

## 종류마다 변주 몇 벌. `world_gen.gd` 의 `OBJECT_VARIANTS` 와 같아야 한다.
VARIANTS = 3

KINDS = ("tree", "rock", "bush")


# ── 팔레트 ────────────────────────────────────────────────────────────────
# 재질 셋: 줄기는 도구 자루(`helve`, 고정색)를 그대로 쓰고, **잎과 돌만 새로
# 만든다.** 목표 명도는 지형·캐릭터와 겹치지 않게 잡았다:
#   풀 101 (`gen_terrain.GRASS_LUMA`) / 캐릭터 몸 평균 95 안팎 / 자루 118
# 잎을 88 로 두면 풀보다 확실히 어두워 나무가 풀밭 위에서 덩어리로 읽히고,
# 돌을 128 로 두면 반대로 풀보다 밝아 바위가 눈에 띈다.
LEAF = "3d6b33"
LEAF_LUMA = 88.0
STONE = "8f8474"
STONE_LUMA = 128.0

## **잎 램프만 폭이 넓다**(밝은면 ×1.55). 다른 램프는 1.2~1.3배인데, 잎은 기본
## 명도가 88 이라 좁은 램프로는 덩어리를 나눠도 화면이 초록 한 판이 된다 —
## 깊은 바다 램프를 1.80 으로 넓힌 것과 같은 자리다(`gen_terrain.py`).
LEAF_RAMP = (1.55, 1.0, 0.80, 0.64)
STONE_RAMP = (1.30, 1.0, 0.82, 0.66)


def palette():
    """이 파일이 쓰는 재질만 담은 램프 표. `qa_sprite_check.py` 가 그대로 부른다."""
    base = gen.palette()
    return {
        "helve": base["helve"],
        "leaf": gen.make_ramp(gen._hex(LEAF), LEAF_LUMA, hi_mix=0.20,
                              sat=(0.90, 1.0, 1.14, 1.26), ramp=LEAF_RAMP),
        # **돌은 채도를 그늘 쪽에서 번다**(`sat` 이 뒤로 갈수록 크다). 회색 그대로
        # 두면 채도가 6 이라 「탁하다」고 잡히는데(도구 아이콘 하한 25), 밝은면까지
        # 색을 넣으면 이번엔 모래·빵덩어리가 된다 — 실측 6 / 13 / **19** / 17 중
        # 19 를 골랐다.
        "stone": gen.make_ramp(gen._hex(STONE), STONE_LUMA, hi_to=gen.COOL,
                               hi_mix=0.24, sat=(0.82, 1.0, 1.20, 1.36),
                               ramp=STONE_RAMP),
    }


EXTRA_MATS = ("leaf", "stone")


@contextlib.contextmanager
def _scene(n):
    """`gen` 의 캔버스를 `n`px 으로, 슈퍼샘플을 `SS` 로, 재질 목록을 잠깐 넓힌다.

    **재질 목록을 되돌리는 것이 중요하다** — `gen.MATS` 는 모듈 전역 리스트라
    늘려둔 채로 두면 `gen.palette()`(잎·돌이 없다)로 `quantize()` 를 부르는 쪽
    (도구 아이콘)이 KeyError 로 죽는다.
    """
    keep_ss, keep_mats = gen.SS, list(gen.MATS)
    gen.SS = SS
    gen.MATS.extend(m for m in EXTRA_MATS if m not in gen.MATS)
    try:
        with gen.canvas(n):
            yield
    finally:
        gen.SS = keep_ss
        gen.MATS[:] = keep_mats


def _render(build, w, h, pal):
    """`build(b, pal)` 이 쌓은 덩어리를 한 장의 RGBA 로 굽는다(캔버스는 정사각).

    `inner_lines()`/`quantize()` 가 정사각 배열을 전제하므로 **긴 쪽에 굽고
    가운데를 오려낸다** — 상자(`gen_box.py`)가 아래 두 줄을 잘라내는 것과 같다.
    잘라낸 자리에 그림이 남으면 「잘림」이 잡는다.
    """
    n = max(w, h)
    full = dict(gen.palette(), **pal)
    with _scene(n):
        b = gen.Build()
        build(b, pal)
        lum = gen.light(b.hgt, b.mat, key=gen.CFG["key"], amb=gen.CFG["amb"],
                        rim=gen.CFG["rim"])
        m, l = gen.downsample(b.mat, lum)
        pm = gen.downsample_part(b.part)
        rgb = gen.inner_lines(gen.quantize(m, l, full, 0.0), m, pm, full)
        rgb = gen.outline(rgb, m)
    x0, y0 = (n - w) // 2, n - h
    return rgb[y0:y0 + h, x0:x0 + w]


# ── 나무 (96 × 144 = 타일 두 칸 폭 × 세 칸 높이) ──────────────────────────
# 밑동이 칸의 맨 아랫줄에 오고 잎이 위로 뻗는다 — 노드의 원점이 밑동이라
# (`world_object_node.gd`) 그림의 아래 모서리가 곧 그 나무가 선 자리다.
TREE_CX = 72.0                  # 캔버스(144)의 가운데
## 밑동의 **캡슐 중심**이다 — 캡슐은 끝이 반원이라 여기서 반지름만큼 더 내려간다.
## 칸의 맨 아랫줄(143)은 외곽선 자리라 `TREE_FOOT + TRUNK_R[0]` 이 142 를 넘으면
## 「잘림」이다(실제로 141 로 뒀다가 밑동이 잘려나갔다).
TREE_FOOT = 130.0
TRUNK_TOP = 92.0
TRUNK_R = (11.5, 8.0)           # 밑동 → 잎에 묻히는 곳
TRUNK_DOME = 6.0                # 굵기와 따로 잡는다 — 그대로 두면 줄기가 통째로 밝은면이다
## 뿌리 — (x 오프셋, 끝 굵기). **밑동보다 위에서 시작해 옆으로 벌어진다.**
## 바닥까지 내리면 발 두 개가 되어 나무가 서 있는 사람처럼 보인다.
ROOT = ((-8.0, 2.6), (7.0, 2.2))
## 껍질 결 — 줄기 위에 **부위 id 만 다른** 가는 기둥을 하나 얹어 그 경계에
## `inner_lines()` 가 세로줄을 긋게 한다(상자 판자결과 같은 수법이다).
## **하나까지다** — 둘을 얹으면 경계가 넷이 되어 줄기가 나무가 아니라 **셀러리**다.
BARK = (2.6, 2.4)

## 잎 덩어리 — (중심 x 오프셋, 중심 y, 반지름 x, 반지름 y). **첫 덩어리가
## 몸통**이고 나머지가 실루엣을 흔드는 혹이다. 혹을 몸통만 하게 키우면
## 나무가 아니라 **포도송이**로 보인다 — 몸통의 절반 아래로 둔다.
CANOPY = ((0.0, 52.0, 41.0, 44.0),
          (-24.0, 34.0, 16.0, 15.0),
          (23.0, 40.0, 15.0, 14.0),
          (-2.0, 20.0, 18.0, 13.0),
          (-21.0, 78.0, 16.0, 13.0),
          (20.0, 80.0, 15.0, 12.0))
CANOPY_LIFT = 0.9               # 잎을 줄기보다 앞으로 — 같은 높이면 경계가 사라진다
JITTER = 3.0                    # 변주가 덩어리를 흔드는 폭의 **상한**
LEAN = 3.0                      # 줄기가 기우는 폭


def _tree(b, pal, v=0):
    rng = np.random.default_rng(4100 + v)
    # 변주는 **덩어리 자리를 조금 흔드는 것**이다. 크기는 흔들지 않는다 —
    # 「그 카테고리 안에서는 서로 크기가 들쭉날쭉하지 않게」(DESIGN.md 크기 표준).
    # **흔들림에 벽을 둔다.** 정규분포는 꼬리가 길어서 가끔 덩어리가 칸 밖으로
    # 나가고, 그러면 그 변주만 외곽선이 잘린다(「잘림」 — 실제로 3벌 중 2벌이
    # 걸렸다). 위 `CANOPY` 의 자리는 `lean` ± `JITTER` 를 다 더해도 칸 안이다.
    jitter = np.clip(rng.normal(0.0, 2.4, (len(CANOPY), 2)), -JITTER, JITTER)
    lean = float(rng.uniform(-LEAN, LEAN))

    trunk = b.add(gen.capsule(TREE_CX, TREE_FOOT, TREE_CX + lean, TRUNK_TOP,
                              TRUNK_R[0], TRUNK_R[1], dome=TRUNK_DOME), "helve")
    for dx, r in ROOT:
        b.add(gen.capsule(TREE_CX, TREE_FOOT - 11.0, TREE_CX + dx, TREE_FOOT - 1.0,
                          TRUNK_R[0] * 0.45, r, dome=TRUNK_DOME * 0.7), "helve",
              part=trunk)
    b.add(gen.capsule(TREE_CX + BARK[0], TREE_FOOT - 6.0,
                      TREE_CX + lean + BARK[0] * 0.6, TRUNK_TOP + 4.0, BARK[1],
                      dome=TRUNK_DOME * 0.9), "helve")
    for i, (dx, cy, rx, ry) in enumerate(CANOPY):
        jx, jy = (0.0, 0.0) if i == 0 else tuple(jitter[i])
        b.add(gen.ellipsoid(TREE_CX + lean + dx + jx, cy + jy, rx, ry),
              "leaf", lift=CANOPY_LIFT)


# ── 바위 (48 × 48 = 타일 한 칸) ───────────────────────────────────────────
## 면 셋. 첫 덩어리가 몸통이고 나머지 둘이 **부위 id 만 다른 면**이라 그 경계에
## `inner_lines()` 가 한 단계 어두운 줄을 긋는다 — 그게 바위의 각진 면이다.
## 다섯으로 쪼갠 후보는 그 줄이 그물이 되어 깨진 유리로 보였다.
ROCK_BODY = (23.5, 31.0, 19.5, 13.5)
ROCK_FACETS = ((15.0, 25.5, 10.5, 9.0), (32.0, 30.0, 8.5, 7.5))


def _rock(b, pal, v=0):
    rng = np.random.default_rng(7700 + v)
    jitter = rng.normal(0.0, 1.6, (3, 2))
    b.add(gen.ellipsoid(*ROCK_BODY), "stone")
    for i, (cx, cy, rx, ry) in enumerate(ROCK_FACETS):
        jx, jy = tuple(jitter[i])
        b.add(gen.ellipsoid(cx + jx, cy + jy, rx, ry), "stone", lift=0.4 + 0.3 * i)


# ── 덤불 (48 × 48 = 타일 한 칸) ───────────────────────────────────────────
## 나무와 같은 잎 램프를 쓰되 **줄기가 없고 납작하다** — 그래야 "작은 나무"가
## 아니라 덤불로 읽힌다. 세 덩어리가 옆으로 퍼진다.
BUSH = ((24.0, 33.0, 20.0, 12.5),
        (13.5, 25.0, 10.5, 9.5),
        (33.5, 27.0, 9.5, 8.5),
        (24.0, 21.0, 8.5, 7.0))


def _bush(b, pal, v=0):
    rng = np.random.default_rng(3300 + v)
    jitter = rng.normal(0.0, 1.8, (len(BUSH), 2))
    for i, (cx, cy, rx, ry) in enumerate(BUSH):
        jx, jy = (0.0, 0.0) if i == 0 else tuple(jitter[i])
        b.add(gen.ellipsoid(cx + jx, cy + jy, rx, ry), "leaf", lift=0.4 * i)


BUILDS = {"tree": _tree, "rock": _rock, "bush": _bush}


def frame(kind, variant=0, pal=None):
    pal = pal or palette()
    w, h = SIZES[kind]
    return _render(lambda b, p: BUILDS[kind](b, p, variant), w, h, pal)


def sheet(kind, pal=None):
    """열 = 변주 한 장. 행은 하나다(오브젝트는 방향이 없다)."""
    pal = pal or palette()
    w, h = SIZES[kind]
    out = np.zeros((h, w * VARIANTS, 4), dtype=np.uint8)
    for v in range(VARIANTS):
        out[:, v * w:(v + 1) * w] = frame(kind, v, pal)
    return out


def sheet_name(kind):
    """`world_object_node.gd` 의 `SHEETS` 와 같은 이름이어야 한다."""
    return "object_%s.png" % kind


def main():
    pal = palette()
    for kind in KINDS:
        path = os.path.join(gen.SPRITES, sheet_name(kind))
        img = sheet(kind, pal)
        gen.to_img(img).save(path)
        print("wrote %s %dx%d (%d변주)" % (path, img.shape[1], img.shape[0], VARIANTS))
    if OUT:
        os.makedirs(OUT, exist_ok=True)
        for scale in (3, 1):
            gen.strip([gen.to_img(frame(k, v, pal), scale)
                       for k in KINDS for v in range(VARIANTS)]) \
                .save(os.path.join(OUT, "world_objects_x%d.png" % scale))
        print("wrote %s/world_objects_x1.png" % OUT)


if __name__ == "__main__":
    main()
