#!/usr/bin/env python3
"""스프라이트 자동 검사 — **눈으로 보기 전에 기계가 먼저 거른다.**

    .venv/bin/python game/qa/qa_sprite_check.py [PNG ...]

인자가 없으면 아래 `SPECS` 에 등록된 시트를 전부 본다. 불합격이 하나라도 있으면
종료 코드 1 을 낸다. 리포트는 **짧게** 찍는다 — 이 스크립트의 목적이 [DESIGN] 바퀴의
토큰(=이미지를 눈으로 보는 횟수)을 줄이는 것이기 때문이다. 자세한 숫자는 실패한
검사 줄에만 붙는다.

시트는 두 갈래다 — **캐릭터 시트**(칸 = 방향×프레임, 배경 투명)와 **지형 타일
시트**(칸 = 지형 배치, 배경 없음). 스펙의 `kind` 가 어느 검사를 돌릴지 정한다.

무엇을 보는가 — 캐릭터 시트 (전부 기계가 판정할 수 있는 것만):
  규격      캔버스 칸 크기 / 행(방향) 수 / 방향 4개의 바운딩박스가 어긋나지 않는지
  알파      반투명 픽셀이 없는지 (도트는 알파 0 아니면 255)
  팔레트    램프에 없는 색이 섞이지 않았는지, 재질끼리 색이 겹치지 않는지
  외곽선    실루엣 가장자리가 잉크색인지, 순검정이 쓰이지 않았는지
  실루엣    떨어져 나온 조각이 없는지 (4-연결 요소 개수)
  대비      맞닿은 재질끼리 **경계에서** 명도가 갈리는지 (셔츠/바지가 한 덩어리로
            뭉치는 것을 여기서 잡는다 — INBOX #9)
  명도분포  전체가 너무 어둡거나 너무 납작하지 않은지

**「자연스러움」 갈래**(INBOX #13) — 위가 "틀렸는가"라면 이쪽은 "어색한가"다.
`docs/STYLE_GUIDE.md` 「자연스러움」의 항목들을 숫자로 옮긴 것이다:
  단색      재질마다 램프 4단계 중 몇 개를 실제로 썼는가 / 한 단계가 그 재질 영역의
            70% 를 넘는가 — 넘으면 색종이를 오려 붙인 것처럼 보인다
  색상차    상의와 하의의 **hue** 가 충분히 다른가 (명도만 다르면 몸이 한 덩어리다)
  각짐      실루엣 옆선/윗선에 5px 넘게 곧은 구간이 있는가 (있으면 각져 보인다)
  비율      머리/몸통/다리/신발 높이가 STYLE_GUIDE 표 범위인가, **머리 폭이 어깨+팔
            폭보다 넓은가**(치비 비율의 핵심 — 아니면 그냥 작은 사람이다)
  눈        흰 하이라이트가 있는가, 눈 덩어리가 3×3 이상인가

**「이어짐」 갈래**(INBOX #15) — 프레임이 여러 장인 시트(걷기 등)에만 돈다.
`DESIGN.md` 「캐릭터 애니메이션」의 "프레임 사이의 움직임이 자연스럽게 이어져야
한다"를 숫자로 옮긴 것이다. 한 장씩 보면 다 멀쩡한데 **넘겨보면 뚝뚝 끊기는** 경우를
잡는다:
  프레임수  4~6 장인가 (DESIGN.md 「캐릭터 애니메이션」)
  이어짐    연속한 두 프레임 사이에 **몸 픽셀이 얼마나 바뀌는가**. 너무 크면 한
            프레임에서 순간이동하고, 너무 작으면 그 프레임이 죽어 있다(앞 프레임과
            사실상 같은 그림이라 프레임 수만 늘린 셈이다). 마지막→첫 프레임도 본다
            (걷기는 도는 애니메이션이다)
  고르게    가장 큰 변화 ÷ 가장 작은 변화. 몇 장이 서로 붙어 있고 남은 자리에서
            한꺼번에 건너뛰면 여기서 걸린다
  자리      실루엣 바운딩박스가 한 프레임에 움직이는 거리 — 캐릭터가 칸 안에서
            미끄러지면 안 된다
  이음      **idle 시트의 첫 프레임 → 이 시트의 첫 프레임**. 걷기 안에서의 가장 큰
            변화보다 크게 벌어지면 걷기 시작하는 순간 다른 캐릭터가 된다

지형 타일 시트는 보는 게 다르다:
  규격      칸 크기 / 시트가 칸 수에 맞는지
  팔레트    재질 램프 밖의 색이 없는지 (여기가 곧 "PNG 가 지금 생성기와 같은가")
  이음매    **같은 지형이 이어붙었을 때 타일 경계가 안 보이는지** — 경계를 사이에
            둔 픽셀쌍의 명도차를 타일 안쪽의 명도차와 견준다. 격자가 비치면 여기서
            숫자로 잡힌다 (INBOX #12 의 "인접한 같은 지형끼리 이어져 보여야 한다")
  변주      무늬 변주들이 실제로 서로 다른지 (같으면 벽지가 된다)
  캐릭터대비 풀 위에 선 캐릭터가 배경에 묻히지 않는지 — 풀과 셔츠의 명도차

**팔레트의 원본은 그림을 만든 생성기다** — 스펙이 `gen_character.palette()` 를 그대로
불러온다. 그래서 "램프 밖의 색" 검사는 곧 "PNG 가 지금 생성기와 같은 상태인가"까지
겸한다(생성기만 고치고 재생성을 잊으면 여기서 걸린다).
"""
import os
import sys

import numpy as np
from PIL import Image
from skimage import measure

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TOOLS = os.path.join(ROOT, "tools")
SPRITES = os.path.join(ROOT, "assets", "sprites")


def luma(rgb):
    """지각 명도(Rec.601). 재질이 구분되는지는 색상이 아니라 이 값이 정한다."""
    a = np.asarray(rgb, dtype=np.float32)
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


# ── 스펙 ──────────────────────────────────────────────────────────────────
def _player_palette():
    """생성기에서 램프를 그대로 가져온다 — 손으로 베껴두면 반드시 어긋난다."""
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    import gen_character as gen
    return gen.palette(), gen.INK, gen.GLINT


def _cloth_accents():
    """생성기가 지금 켜 둔 옷 포인트 이름들 (허리띠/옷깃/소맷부리)."""
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    import gen_character as gen
    return gen.cloth_accents()


def _terrain_palette():
    """지형 생성기에서 램프를 그대로 가져온다."""
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    import gen_terrain as gen
    return gen


def _player_spec(**over):
    return dict(dict(
        kind="character",
        # 2026-09-07 (INBOX #19) 에 34 에서 절반이 됐다. **아래 숫자는 전부 이 칸
        # 크기에 매인다** — 각짐/비율/눈은 그냥 반으로 나눈 값이 아니라 17px 로
        # 실제로 그려본 결과에서 다시 잡았다.
        cell=17,
        rows=["down", "left", "right", "up"],
        palette=_player_palette,
        # 실제로 맞닿는 재질쌍과 **경계에서 요구하는 최소 명도차**.
        # 두 면이 "다른 재질"로 읽히려면 경험적으로 20 안팎이 필요하다.
        # 바지↔신발만 낮은 건 둘이 같은 옷색 계열이고 신발 입구 하이라이트가
        # 경계를 대신 그어주기 때문이다.
        contrast=[
            ("shirt", "pants", 20.0),
            ("pants", "boot", 10.0),
            ("skin", "shirt", 30.0),
            ("skin", "hair", 40.0),
        ],
        # 잉크·눈·투명을 뺀 몸 전체의 평균 명도가 들어가야 할 범위.
        # 아래를 벗어나면 "전체가 어둡다", 위를 벗어나면 "떠 보인다".
        luma_mean=(100.0, 170.0),
        # p95 - p5. 좁으면 음영이 없는 평평한 그림이다.
        luma_spread=100.0,
        # 명도 45 미만(= 잉크 근처) 픽셀이 몸에서 차지하는 비율 상한.
        # 이게 크면 캐릭터가 검은 덩어리로 보인다.
        dark_frac=0.22,
        # 채도(max-min 채널)의 평균 하한. 코어키퍼풍은 탁하지 않다 —
        # 명도만 올리고 채도를 안 올리면 회색 캐릭터가 된다.
        # **이 값은 등록된 시트의 색(기준색 1벌 = 풀색 옷)에 맞춰 잡은 것이다.**
        # 17px idle 실측은 37~44 다.
        # 일부러 무채색인 색(옷색 「잿빛」 등)으로 팔레트를 갈아끼운 시트를 새로
        # 등록할 때는 그 시트의 스펙에서 이 값을 따로 낮춰 잡을 것.
        chroma_mean=34.0,

        # ── 아래는 「자연스러움」 갈래 (INBOX #13) ──────────────────────────
        # 램프 4단계를 실제로 몇 개나 쓰는지 볼 재질. 넓은 면만 본다 —
        # 신발처럼 몇 px 짜리 재질에 4단계를 요구하면 얼룩이 된다.
        # **재질마다 요구 단계가 다르다**(2026-09-07, INBOX #19). 넓은 면(상의·바지·
        # 머리)은 여전히 3단계를 요구한다. **얼굴만 2단계**인데, 17px 에서 보이는
        # 피부는 이마가 앞머리에 덮인 뒤 남는 세 줄 × 다섯 칸뿐이라 거기에 4단계를
        # 요구하면 얼굴이 얼룩진다(34px 때는 같은 자리가 8줄이었다).
        flat=dict(shirt=3, pants=3, hair=3, skin=2),
        flat_share=0.70,        # 한 단계가 그 재질의 이 비율을 넘으면 단색이다
        # 상의/하의는 **색상(hue)**이 달라야 한다. 명도 계단은 위 「대비」가 따로 본다.
        hue_pairs=(("shirt", "pants", 25.0),),
        # 실루엣 옆선/윗선의 곧은 구간 상한(px). **숫자는 34px 때와 같은 5 지만
        # 기준은 달라졌다** — 34px 에서는 캐릭터 높이 32 의 16% 였고 17px 에서는
        # 16 의 31% 다. 같은 비율(3px)로 옮겨봤더니 **다리 두 줄 + 신발 두 줄만으로
        # 이미 4px** 이라 어떤 그림도 통과할 수 없었다. 5 는 실측으로 정한
        # 값이다: 짧은머리·긴머리·묶은머리는 4 에서 끝나고, **단발만 5** 다 —
        # 단발은 관자놀이에서 턱을 지나 어깨까지 이어지는 옆선이 곧은 것이
        # 그 머리모양의 생김새 자체다. 6 은 실제로 각져 보였다(흘러내린 머리단을
        # 머리 옆선에서 한 칸 안으로 넣었을 때 그렇게 나왔다).
        straight_max=5,
        # 비율 (STYLE_GUIDE 3번 표 — 2026-09-07 에 17px 로 다시 잡았다).
        # 머리는 전체 높이(14px)에 대한 비, 나머지는 px.
        # 실측: 머리 6 / 몸통 3 / 다리 3 / 신발 2.
        head_frac=(0.38, 0.48),
        # 하한이 실측보다 한 칸 낮은 건 **머리카락이 어깨를 덮으면 보이는 상의가
        # 한 줄 줄어들기 때문**이다 — 단발·긴머리 뒷모습이 그렇다.
        bands=dict(torso=(2, 4), legs=(2, 4), shoes=(2, 3)),
        # 옷 포인트(허리띠/옷깃/소맷부리) 개수 상한. **17px 에서는 하나까지다**
        # (STYLE_GUIDE 「자연스러움」 — 상의가 세 줄뿐이라 둘을 넣으면 가운데
        # 한 줄만 남는다). 그림에서 세지 않고 **생성기의 설정에서** 센다 —
        # 팔레트를 생성기에서 그대로 불러오는 것과 같은 이유다.
        accents_max=1,
        # 눈을 확인할 방향. 뒷모습(up)은 얼굴이 없으니 뺀다.
        eye_dirs=("down", "left", "right"),
        # **눈 크기에 상한이 생겼다**(2026-09-07, INBOX #19 — 사람이 "눈이 너무
        # 커서 줄여주고"). 옛 검사는 하한(3×3)만 봐서 큰 눈을 통과시켰다.
        # 17px 의 얼굴은 폭 7 × 높이 3 이라, 지금 쓰는 눈은 **가로 2 × 세로 1**
        # 이다. 세로 2 를 허용하면 눈이 얼굴 높이의 2/3 가 된다.
        eye_size=dict(w=(1, 2), h=(1, 1)),
        # 하이라이트(흰자)는 **2×2 일 때만** 넣는다 — 2×1 에 넣으면 두 칸 중 한
        # 칸이 흰색이 되어 눈이 아니라 점 두 개로 읽힌다. 지금은 없어야 한다.
        eye_glint=False,
        # 프레임이 한 장뿐인 시트(idle)는 「이어짐」을 돌 게 없다 — `motion` 을 준
        # 시트만 본다.
        motion=None,
    ), **over)


def _walk_spec(style):
    """걷기 시트 — **idle 과 같은 17px 스펙에서 두 가지만** 다르다
    (2026-09-07, INBOX #20 — 걷기도 17px 로 다시 구웠다. 전에는 이 함수가 옛 34px
    숫자를 통째로 들고 있었다).

    1) `bands["legs"]`/`bands["shoes"]`: 비율 검사는 "신발 맨 윗줄"을 다리와 신발의
       경계로 삼는데, 걷기는 **한 발이 떠 있어서** 그 줄이 든 높이만큼 올라간다 —
       신발이 그만큼 길어 보이고 다리는 그만큼 짧아 보인다. 든 높이(1px)만큼
       양쪽으로 한 칸씩 넓힌다.
    나머지는 idle 과 **한 칸도 다르지 않다** — 34px 때는 「각짐」을 6px 로 늦췄었는데,
    17px 에서는 다리가 세 줄뿐이라 딛고 선 다리가 기둥이 되어도 5px 를 안 넘는다.
    """
    return _player_spec(
        bands=dict(torso=(2, 4), legs=(2, 4), shoes=(2, 4)),
        motion=dict(
            # DESIGN.md 「캐릭터 애니메이션」: walk 는 4~6 프레임.
            frames=(4, 6),
            # 연속한 두 프레임 사이에 바뀌는 몸 픽셀 비율. 위는 순간이동, 아래는
            # **죽은 프레임**(앞 프레임과 사실상 같은 그림)을 잡는다.
            # **17px 에서 상한을 0.40 → 0.30 으로 조였다**(2026-09-07, INBOX #20).
            # 몸 픽셀이 1/4 로 줄어서 같은 "한 칸"이 네 배로 잡힌다 — 34px 때의
            # 상한을 그대로 두면 팔다리가 두 칸씩 튀어도 통과한다.
            change=(0.05, 0.30),
            # 가장 큰 변화 ÷ 가장 작은 변화. 실제로 이걸로 잡았다: 위상을 반 칸
            # 밀어 뽑았더니 6장 중 2장이 서로 거의 같은 그림이 되고 나머지 자리에서
            # 한꺼번에 건너뛰었다 — 비 4.9.
            even=3.0,
            # 실루엣 바운딩박스가 한 프레임에 움직일 수 있는 px.
            shift=2,
            # idle 시트의 첫 프레임과 이 시트의 첫 프레임이 벌어져도 되는 정도
            # (걷기 안에서의 가장 큰 변화의 몇 배까지). 칸 크기가 같아진
            # 2026-09-07(INBOX #20)부터 다시 견준다.
            idle="player_idle_%s.png" % style,
            from_idle=1.5,
        ),
    )


# 머리모양 4종은 **형태만 다르고 팔레트·비율·광원이 같다** — 그래서 스펙도 하나를
# 돌려 쓴다. 34px 시트는 **머리카락이 길수록 실제로 더 어둡고 덜 쨍해서**(기준색의
# 머리는 검정 = 무채색이다) 그 셋(평균명도/어두운비율/채도)만 시트마다 늦춰야 했다.
# **17px 에서는 그 완화가 통째로 필요 없어졌다**(2026-09-07 — idle 은 INBOX #19,
# 걷기는 INBOX #20) — 캔버스가 줄면서 머리카락이 차지하는 넓이가 작아져 여덟 시트가
# 평균명도 102~110 / 어두운비율 4~8% / 채도 36~42 로 모였다. 그래서 머리모양별로
# 늦추는 표는 없앴다 — **네 머리모양이 같은 스펙을 그대로 통과한다.**

# 지형 타일 시트. 캐릭터와 견주는 기준(`shirt_gap`)은 **기준색 1벌의 셔츠**다 —
# 캐릭터가 풀밭에 서 있을 때 묻히지 않아야 한다(DESIGN.md 「그래픽 파이프라인」 1).
TERRAIN_SPEC = dict(
    kind="tile",
    cell=16,
    palette=_terrain_palette,
    # 같은 지형끼리 이어붙였을 때, 타일 경계의 명도차가 안쪽보다 이만큼 넘게
    # 크면 격자가 비치는 것이다.
    seam_ratio=1.35,
    luma_mean={"grass": (90.0, 115.0), "sea": (45.0, 70.0)},
    chroma_mean={"grass": 28.0, "sea": 30.0},
    shirt_gap=35.0,
)

SPECS = {"terrain_tiles.png": TERRAIN_SPEC}
for _style in ("short", "bob", "long", "ponytail"):     # gen_character.HAIR_STYLES
    SPECS["player_idle_%s.png" % _style] = _player_spec()
    SPECS["player_walk_%s.png" % _style] = _walk_spec(_style)


# ── 검사 ──────────────────────────────────────────────────────────────────
class Report:
    def __init__(self, title):
        self.title = title
        self.lines = []
        self.failed = False

    def add(self, ok, name, detail="", always=""):
        """통과하면 한 줄로 짧게, 실패하면 숫자를 붙여서."""
        if not ok:
            self.failed = True
        self.lines.append("  %-4s %-9s %s" % ("ok" if ok else "FAIL", name,
                                              always if ok else detail))

    def dump(self):
        print(("FAIL " if self.failed else "ok   ") + self.title)
        for ln in self.lines:
            print(ln)


def _neighbors(mask):
    """4-이웃 중 하나라도 mask 인 자리."""
    out = np.zeros_like(mask)
    out[1:, :] |= mask[:-1, :]
    out[:-1, :] |= mask[1:, :]
    out[:, 1:] |= mask[:, :-1]
    out[:, :-1] |= mask[:, 1:]
    return out


def _hue(rgb):
    """색상환 각도(0~360). 무채색이면 None — 비교할 색상이 없다는 뜻이다."""
    r, g, b = (float(v) for v in rgb)
    mx, mn = max(r, g, b), min(r, g, b)
    if mx - mn < 8.0:
        return None
    if mx == r:
        h = 60.0 * (((g - b) / (mx - mn)) % 6.0)
    elif mx == g:
        h = 60.0 * ((b - r) / (mx - mn) + 2.0)
    else:
        h = 60.0 * ((r - g) / (mx - mn) + 4.0)
    return h % 360.0


def _hue_gap(a, b):
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


def _longest_run(profile):
    """같은 값이 연속으로 몇 칸 이어지는가. `None`(빈 줄)에서 끊긴다."""
    best = cur = 0
    prev = None
    for v in profile:
        if v is None:
            cur, prev = 0, None
            continue
        cur = cur + 1 if v == prev else 1
        prev = v
        best = max(best, cur)
    return best


def _straight_run(mask):
    """실루엣 옆선/윗선에서 가장 긴 **곧은** 구간(px).

    줄마다 바깥쪽 끝 좌표를 뽑아 같은 값이 몇 줄 이어지는지 센다 — 6줄 내리
    같은 자리면 그 옆선은 자로 그은 직선이다(STYLE_GUIDE 「자연스러움」).

    **아랫변(발바닥)만 빼고 본다** — 캐릭터는 땅을 딛고 서 있어서 신발 밑창이
    평평한 게 맞다. 여기를 같이 재면 발이 클수록 불합격이 되는데, 그건 각진
    실루엣과 아무 상관이 없다.
    """
    best = 0
    for m, both in ((mask, True), (mask.T, False)):
        lo, hi = [], []
        for line in m:
            xs = np.nonzero(line)[0]
            lo.append(None if xs.size == 0 else int(xs[0]))
            hi.append(None if xs.size == 0 else int(xs[-1]))
        best = max(best, _longest_run(lo))
        if both:
            best = max(best, _longest_run(hi))
    return best


def _width(mask, y0, y1):
    """행 y0..y1 안에서 실루엣이 가장 넓은 줄의 폭."""
    if y1 < y0:
        return 0
    sub = mask[y0:y1 + 1]
    if not sub.any():
        return 0
    return int(max(int(np.nonzero(r)[0][-1] - np.nonzero(r)[0][0] + 1)
                   for r in sub if r.any()))


def check_sheet(path, spec):
    name = os.path.basename(path)
    rep = Report(name)
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    rgb, alpha = a[..., :3].astype(np.int32), a[..., 3]

    cell = spec["cell"]
    rows = spec["rows"]
    h, w = alpha.shape
    ok_size = h % cell == 0 and w % cell == 0 and h // cell == len(rows) and w >= cell
    rep.add(ok_size, "규격",
            "%dx%d 은 %dpx 칸 × %d행 이 아니다" % (w, h, cell, len(rows)),
            "%dpx × %d방향 × %d프레임" % (cell, len(rows), max(w // cell, 1)))
    if not ok_size:
        rep.dump()
        return rep
    cols = w // cell

    semi = int(((alpha > 0) & (alpha < 255)).sum())
    rep.add(semi == 0, "알파", "반투명 %d px" % semi)

    body = alpha == 255
    pal, ink, glint = spec["palette"]()

    # 색 → 재질. 두 재질이 같은 RGB 를 쓰면 그림에서도 구분이 안 된다.
    color2mat, dup = {}, []
    for mat, ramp in pal.items():
        if mat in ("eye", "glint"):
            continue
        for c in ramp:
            c = tuple(int(v) for v in c)
            if c in color2mat and color2mat[c] != mat:
                dup.append((mat, color2mat[c], "%02x%02x%02x" % c))
            color2mat.setdefault(c, mat)
    rep.add(not dup, "색충돌",
            ", ".join("%s=%s(#%s)" % d for d in dup[:3]))

    # **램프 맨 아래가 외곽선보다 어두우면 그 재질은 색이 아니라 구멍으로 읽힌다.**
    # (#8 의 바지·신발이 정확히 이 상태였다 — 잉크 명도 33 아래로 11 까지 내려갔다.)
    ink_l = float(luma(np.array(ink)))
    sunk = ["%s %.0f" % (mat, min(float(luma(np.array(c))) for c in ramp))
            for mat, ramp in pal.items() if mat not in ("eye", "glint")
            and min(float(luma(np.array(c))) for c in ramp) < ink_l]
    rep.add(not sunk, "잉크아래", "잉크(%.0f)보다 어두운 램프: %s" % (ink_l, ", ".join(sunk)))

    allowed = set(color2mat) | {tuple(int(v) for v in ink), tuple(int(v) for v in glint)}
    flat = rgb[body].reshape(-1, 3)
    used = {tuple(int(v) for v in c) for c in np.unique(flat, axis=0)}
    stray = sorted(used - allowed)
    rep.add(not stray, "팔레트",
            "램프 밖 %d색 %s" % (len(stray),
                                 " ".join("#%02x%02x%02x" % c for c in stray[:4])),
            "%d색" % len(used))

    black = int((body & (rgb.sum(-1) == 0)).sum())
    rep.add(black == 0, "순검정", "%d px" % black)

    # 외곽선 — 투명에 맞닿은 몸 픽셀은 잉크여야 한다
    inkm = body & np.all(rgb == np.array(ink), axis=-1)
    edge = body & _neighbors(~body)
    edge_n = int(edge.sum())
    edge_ink = float((edge & inkm).sum()) / max(edge_n, 1)
    rep.add(edge_n > 0 and edge_ink >= 0.90, "외곽선",
            "가장자리의 %.0f%% 만 잉크색" % (edge_ink * 100))

    # 실루엣 — 프레임마다 4-연결 덩어리가 하나여야 한다
    bad = []
    for r in range(len(rows)):
        for c in range(cols):
            sub = body[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
            lab = measure.label(sub, connectivity=1)
            n = int(lab.max())
            if n != 1:
                sizes = sorted(np.bincount(lab.ravel())[1:], reverse=True)
                bad.append("%s#%d:%d조각%s" % (rows[r], c, n, sizes[1:4]))
    rep.add(not bad, "실루엣", " ".join(bad[:4]))

    # 바운딩박스 — 방향이 달라도 캐릭터가 차지하는 크기는 같아야 한다
    box = {}
    for r, d in enumerate(rows):
        for c in range(cols):
            sub = body[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
            ys, xs = np.nonzero(sub)
            box[(d, c)] = (int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max()))
    msgs = []
    for c in range(cols):
        hs = [box[(d, c)][1] - box[(d, c)][0] + 1 for d in rows]
        ws = [box[(d, c)][3] - box[(d, c)][2] + 1 for d in rows]
        bots = [box[(d, c)][1] for d in rows]
        if max(hs) - min(hs) > 1:
            msgs.append("프레임%d 높이 %s" % (c, hs))
        if max(bots) - min(bots) > 1:
            msgs.append("프레임%d 발밑y %s" % (c, bots))
        if max(ws) - min(ws) > 6:
            msgs.append("프레임%d 너비 %s" % (c, ws))
    rep.add(not msgs, "바운딩",
            " / ".join(msgs[:3]),
            "높이 %d, 너비 %d~%d" % (box[(rows[0], 0)][1] - box[(rows[0], 0)][0] + 1,
                                     min(box[(d, 0)][3] - box[(d, 0)][2] + 1 for d in rows),
                                     max(box[(d, 0)][3] - box[(d, 0)][2] + 1 for d in rows)))

    # 재질 지도 (정확 일치 — quantize 가 램프 색을 그대로 찍으므로)
    matmap = np.full(alpha.shape, "", dtype=object)
    for c, m in color2mat.items():
        matmap[body & np.all(rgb == np.array(c), axis=-1)] = m
    L = luma(rgb)

    # 재질 — 검사 대상 재질이 그림에 실제로 있는지 먼저 본다. 아래 「대비」가
    # "안 맞닿으면 건너뛴다"이므로, 이게 없으면 **재질이 통째로 사라진 그림**이
    # 대비 검사를 조용히 통과해버린다.
    want = sorted({m for pair in spec["contrast"] for m in pair[:2]})
    missing = [m for m in want if int((matmap == m).sum()) < 4]
    rep.add(not missing, "재질", "안 보이는 재질: %s" % ", ".join(missing))

    # 대비 — **경계에서** 갈리는지 본다. 재질 전체 평균으로 보면 넓은 면의 밝은
    # 부분이 평균을 끌어올려서 "맞닿은 자리는 붙어 보이는데 통과"가 된다.
    # **안 맞닿는 쌍은 건너뛴다**(리포트에 `-` 로 남는다) — 예를 들어 긴 머리는
    # 목을 덮어서 피부와 셔츠가 어디서도 닿지 않는다. 그건 불합격이 아니다.
    gaps = []
    for m1, m2, need in spec["contrast"]:
        a1, a2 = matmap == m1, matmap == m2
        t1, t2 = a1 & _neighbors(a2), a2 & _neighbors(a1)
        n = min(int(t1.sum()), int(t2.sum()))
        gaps.append((None if n < 4 else abs(float(L[t1].mean()) - float(L[t2].mean())),
                     m1, m2, need, n))
    bad = ["%s|%s %.0f<%.0f" % (m1, m2, g, need)
           for g, m1, m2, need, n in gaps if g is not None and g < need]
    rep.add(not bad, "대비", " ".join(bad),
            " ".join("%s|%s %s" % (m1, m2, "-" if g is None else "%.0f" % g)
                     for g, m1, m2, _, _ in gaps))

    # 명도 분포 — 잉크(외곽선·눈)를 빼고 본다
    vals = L[body & (matmap != "")]
    mean = float(vals.mean())
    spread = float(np.percentile(vals, 95) - np.percentile(vals, 5))
    dark = float((vals < 45).mean())
    lo, hi = spec["luma_mean"]
    rep.add(lo <= mean <= hi, "평균명도", "%.0f (%.0f~%.0f 밖)" % (mean, lo, hi),
            "%.0f" % mean)
    rep.add(spread >= spec["luma_spread"], "명암폭",
            "%.0f < %.0f — 평평하다" % (spread, spec["luma_spread"]), "%.0f" % spread)
    rep.add(dark <= spec["dark_frac"], "어두운비율",
            "%.0f%% > %.0f%%" % (dark * 100, spec["dark_frac"] * 100), "%.0f%%" % (dark * 100))

    sel = body & (matmap != "")
    ch = float((rgb[sel].max(-1) - rgb[sel].min(-1)).mean())
    rep.add(ch >= spec["chroma_mean"], "채도",
            "%.0f < %.0f — 탁하다" % (ch, spec["chroma_mean"]), "%.0f" % ch)

    _check_natural(rep, spec, pal, body, rgb, matmap, cell, rows, cols, ink, glint)
    if spec.get("motion"):
        _check_motion(rep, spec["motion"], os.path.dirname(path), rgb, body, cell, rows, cols)

    rep.dump()
    return rep


# ── 「이어짐」 (INBOX #15) ────────────────────────────────────────────────
# 프레임이 여러 장인 시트만 본다. 앞의 검사들은 **한 장씩** 보므로, 여섯 장이
# 저마다 멀쩡한데 넘겨보면 뚝뚝 끊기는 걸 못 잡는다.
def _frame(rgb, body, cell, r, c):
    sl = (slice(r * cell, (r + 1) * cell), slice(c * cell, (c + 1) * cell))
    return rgb[sl], body[sl]


def _box(mask):
    ys, xs = np.nonzero(mask)
    return np.array([ys.min(), ys.max(), xs.min(), xs.max()])


def _shifted(a, dy, dx):
    out = np.zeros_like(a)
    ys, yd = slice(max(dy, 0), a.shape[0] + min(dy, 0)), slice(max(-dy, 0), a.shape[0] + min(-dy, 0))
    xs, xd = slice(max(dx, 0), a.shape[1] + min(dx, 0)), slice(max(-dx, 0), a.shape[1] + min(-dx, 0))
    out[ys, xs] = a[yd, xd]
    return out


def _changed(a, ba, b, bb):
    ch = (ba != bb) | (ba & bb & np.any(a != b, axis=-1))
    return float(ch.sum()) / max(int(ba.sum()), int(bb.sum()), 1)


def _delta(a, ba, b, bb):
    """두 프레임 사이 (바뀐 몸 픽셀 비율, 실루엣 바운딩박스가 움직인 px).

    **바뀐 비율**은 색까지 본다 — 실루엣만 보면 팔이 몸 앞에서 움직이는 것처럼
    테두리가 안 바뀌는 움직임을 통째로 놓친다.

    다만 **몸 전체가 1px 통짜로 움직인 몫은 빼고 본다**(뒤 프레임을 ±1px 씩
    밀어보고 가장 적게 바뀌는 값을 쓴다). 걷기는 착지마다 몸이 한 칸 가라앉는데,
    그 한 칸만으로 몸 픽셀의 절반 넘게 값이 바뀐다 — 그걸 그대로 재면 **정상적인
    바운스가 "순간이동"으로 잡히고**, 정작 보려던 팔다리의 움직임은 그 잡음에
    묻힌다. 바운딩박스가 움직인 거리는 따로 재므로 통짜 이동을 놓치지 않는다.
    """
    ratio = min(_changed(a, ba, _shifted(b, dy, dx), _shifted(bb, dy, dx))
                for dy in (-1, 0, 1) for dx in (-1, 0, 1))
    return ratio, int(np.abs(_box(ba) - _box(bb)).max())


def _check_motion(rep, mo, folder, rgb, body, cell, rows, cols):
    lo, hi = mo["frames"]
    rep.add(lo <= cols <= hi, "프레임수", "%d장 (%d~%d장이어야 한다)" % (cols, lo, hi),
            "%d장" % cols)

    clo, chi = mo["change"]
    jumpy, dead, slid, ratios = [], [], [], []
    for r, d in enumerate(rows):
        deltas = []
        for c in range(cols):
            a, ba = _frame(rgb, body, cell, r, c)
            b, bb = _frame(rgb, body, cell, r, (c + 1) % cols)   # 도는 애니메이션이다
            ch, shift = _delta(a, ba, b, bb)
            deltas.append(ch)
            tag = "%s#%d→%d" % (d, c, (c + 1) % cols)
            if ch > chi:
                jumpy.append("%s %.2f" % (tag, ch))
            if ch < clo:
                dead.append("%s %.2f" % (tag, ch))
            if shift > mo["shift"]:
                slid.append("%s %dpx" % (tag, shift))
        ratios.append(max(deltas) / max(min(deltas), 1e-6))
    rep.add(not jumpy and not dead, "이어짐",
            ("%s 가 한 프레임에 너무 크게 바뀐다(상한 %.2f)" % (" ".join(jumpy[:3]), chi)
             if jumpy else "")
            + ("%s 가 앞 프레임과 같은 그림이다(하한 %.2f)" % (" ".join(dead[:3]), clo)
               if dead else ""),
            "%.2f~%.2f" % (clo, chi))
    rep.add(max(ratios) <= mo["even"], "고르게",
            "변화량 최대/최소 %.1f배 > %.1f배 — 몇 장이 붙어 있고 남은 자리에서 건너뛴다"
            % (max(ratios), mo["even"]), "%.1f배" % max(ratios))
    rep.add(not slid, "자리", "%s — 캐릭터가 칸 안에서 미끄러진다(상한 %dpx)"
            % (" ".join(slid[:3]), mo["shift"]))

    if not mo.get("idle"):
        return
    path = os.path.join(folder, mo["idle"])
    prev = np.array(Image.open(path).convert("RGBA"))
    pr, pa = prev[..., :3].astype(np.int32), prev[..., 3] == 255
    worst = max(max(_delta(*_frame(rgb, body, cell, r, c),
                           *_frame(rgb, body, cell, r, (c + 1) % cols))[0]
                    for c in range(cols)) for r in range(len(rows)))
    bad, show = [], 0.0
    for r, d in enumerate(rows):
        b, bb = _frame(rgb, body, cell, r, 0)
        ch, shift = _delta(*_frame(pr, pa, cell, r, 0), b, bb)
        show = max(show, ch)
        if ch > worst * mo["from_idle"] or shift > mo["shift"]:
            bad.append("%s %.2f/%dpx" % (d, ch, shift))
    rep.add(not bad, "이음",
            "%s ← idle 에서 넘어오는 순간이 걷기 안의 가장 큰 변화(%.2f)의 %.1f배를 넘는다"
            % (" ".join(bad[:3]), worst, mo["from_idle"]),
            "%.2f (걷기 최대 %.2f)" % (show, worst))


# ── 「자연스러움」 (INBOX #13) ────────────────────────────────────────────
# 위의 검사들이 "틀렸는가"(팔레트 밖의 색, 순검정, 조각난 실루엣)를 본다면 여기는
# **"어색한가"** 를 본다. 눈으로만 잡히던 지적 — "상하의가 단색이다", "각져 보인다",
# "짜리몽땅하지 않다" — 을 숫자로 옮긴 것이라, 여기서 걸리면 눈으로 볼 단계가 아니다.
def _check_natural(rep, spec, pal, body, rgb, matmap, cell, rows, cols, ink, glint):
    # 단색 — 램프 4단계 중 실제로 몇 개를 썼고, 한 단계가 얼마나 차지하는가.
    step_of = {}
    for mat, ramp in pal.items():
        if mat in ("eye", "glint"):
            continue
        for i, c in enumerate(ramp):
            step_of.setdefault(tuple(int(v) for v in c), i)
    stepmap = np.full(matmap.shape, -1, np.int16)
    for c, i in step_of.items():
        stepmap[body & np.all(rgb == np.array(c), axis=-1)] = i
    bad, show = [], []
    for mat, need in spec["flat"].items():
        sel = (matmap == mat) & (stepmap >= 0)
        n = int(sel.sum())
        if n < 8:
            bad.append("%s 가 거의 없다" % mat)
            continue
        cnt = np.bincount(stepmap[sel], minlength=len(pal[mat]))
        used, share = int((cnt > 0).sum()), float(cnt.max()) / n
        show.append("%s %d단%.0f%%" % (mat, used, share * 100))
        if used < need:
            bad.append("%s 가 %d단계뿐(%d 이상)" % (mat, used, need))
        if share > spec["flat_share"]:
            bad.append("%s 의 한 단계가 %.0f%%" % (mat, share * 100))
    rep.add(not bad, "단색",
            "%s — 색종이를 오려 붙인 것처럼 보인다 (한 단계 %.0f%% 이하)"
            % (", ".join(bad), spec["flat_share"] * 100),
            " ".join(show))

    # 색상차 — 상하의가 명도만 다르면 몸이 한 덩어리로 뭉친다.
    bad, show = [], []
    for m1, m2, need in spec["hue_pairs"]:
        h1, h2 = _hue(pal[m1][1]), _hue(pal[m2][1])
        if h1 is None or h2 is None:
            show.append("%s|%s 무채색" % (m1, m2))
            continue
        gap = _hue_gap(h1, h2)
        show.append("%s|%s %.0f°" % (m1, m2, gap))
        if gap < need:
            bad.append("%s|%s %.0f° < %.0f°" % (m1, m2, gap, need))
    rep.add(not bad, "색상차", " ".join(bad) + " — 명도만 다르면 한 덩어리로 뭉친다",
            " ".join(show))

    # 아래 셋은 프레임마다 본다.
    angular, prop, eyes, worst = [], [], [], 0
    head_show = ""
    for r, d in enumerate(rows):
        for c in range(cols):
            sub = body[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
            mm = matmap[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
            px = rgb[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
            tag = "%s#%d" % (d, c)

            run = _straight_run(sub)
            worst = max(worst, run)
            if run > spec["straight_max"]:
                angular.append("%s %dpx" % (tag, run))

            # 비율은 **외곽선을 뺀 알맹이**로 잰다 — STYLE_GUIDE 3번 표가 그
            # 기준이다(외곽선은 위아래로 1px 씩 더 붙는다).
            fill = mm != ""
            ys = np.nonzero(fill.any(1))[0]
            top, bot = int(ys[0]), int(ys[-1])

            def first(mat):
                got = np.nonzero((mm == mat).any(1))[0]
                return None if got.size == 0 else int(got[0])

            shirt, pants, boot = first("shirt"), first("pants"), first("boot")
            if None in (shirt, pants, boot):
                prop.append("%s 재질 없음" % tag)
                continue
            total = bot - top + 1
            band = dict(torso=pants - shirt, legs=boot - pants, shoes=bot - boot + 1)
            frac = (shirt - top) / float(total)
            lo, hi = spec["head_frac"]
            if not lo <= frac <= hi:
                prop.append("%s 머리 %.0f%%" % (tag, frac * 100))
            for k, (blo, bhi) in spec["bands"].items():
                if not blo <= band[k] <= bhi:
                    prop.append("%s %s %dpx" % (tag, k, band[k]))
            # **머리가 어깨+팔보다 넓어야 치비다** (STYLE_GUIDE 3번).
            hw, sw = _width(fill, top, shirt - 1), _width(fill, shirt, pants - 1)
            if hw <= sw:
                prop.append("%s 머리폭 %d ≤ 어깨폭 %d" % (tag, hw, sw))
            if not head_show:
                head_show = "머리 %.0f%% %dpx / 어깨 %dpx / 몸통%d 다리%d 신발%d" % (
                    frac * 100, hw, sw, band["torso"], band["legs"], band["shoes"])

            if d not in spec["eye_dirs"]:
                continue
            # 눈 = **피부에 둘러싸인** 잉크/하이라이트 덩어리. 그냥 "안쪽 잉크"로
            # 잡으면 머리와 어깨 사이, 두 다리 사이에 낀 외곽선까지 눈으로 센다.
            glintm = np.all(px == np.array(glint), axis=-1)
            inky = sub & (np.all(px == np.array(ink), axis=-1) | glintm)
            lab = measure.label(inky, connectivity=2)
            skinish = (mm == "skin") | (mm == "blush")
            blobs = []
            for i in range(int(lab.max())):
                blob = lab == i + 1
                around = _neighbors(blob) & sub & ~blob
                # 둘러싸인 비율의 하한을 0.7 → 0.6 으로 내렸다(2026-09-07, INBOX #19).
                # 17px 의 얼굴은 세 줄뿐이라 **눈 바로 위가 늘 앞머리**다 —
                # 0.7 을 요구하면 멀쩡한 눈이 눈이 아닌 것으로 빠진다.
                if around.any() and float((around & skinish).sum()) / int(around.sum()) >= 0.6:
                    blobs.append(np.nonzero(blob))
            if not blobs:
                eyes.append("%s 눈 없음" % tag)
                continue
            has_glint = bool((inky & glintm).any())
            if has_glint != spec["eye_glint"]:
                eyes.append("%s 하이라이트가 %s" % (tag, "있다" if has_glint else "없다"))
            wlo, whi = spec["eye_size"]["w"]
            hlo, hhi = spec["eye_size"]["h"]
            for ys2, xs2 in blobs:
                bh, bw = ys2.max() - ys2.min() + 1, xs2.max() - xs2.min() + 1
                if not (wlo <= bw <= whi and hlo <= bh <= hhi):
                    eyes.append("%s 눈 %dx%d" % (tag, bw, bh))
                    break
    rep.add(not angular, "각짐",
            "%s 곧은 구간 (상한 %dpx) — 어깨·머리 모서리를 굴릴 것"
            % (" ".join(angular[:4]), spec["straight_max"]), "최대 %dpx" % worst)
    rep.add(not prop, "비율", " ".join(prop[:4]), head_show)
    rep.add(not eyes, "눈", " ".join(eyes[:4]) + " (가로 %d~%d × 세로 %d~%d, 하이라이트 %s)"
            % (spec["eye_size"]["w"] + spec["eye_size"]["h"]
               + ("있음" if spec["eye_glint"] else "없음",)),
            "%d~%dx%d~%d" % (spec["eye_size"]["w"] + spec["eye_size"]["h"]))

    # 옷 포인트 — 허리띠/옷깃/소맷부리를 몇 개나 넣었는가. 그림에서 세지 않고
    # **생성기의 설정에서** 센다(팔레트를 생성기에서 불러오는 것과 같은 이유 —
    # 손으로 베껴두면 반드시 어긋난다). 17px 에서는 상의가 세 줄뿐이라 하나까지다.
    if spec.get("accents_max") is not None:
        got = _cloth_accents()
        rep.add(len(got) <= spec["accents_max"], "옷포인트",
                "%d개(%s) > %d개 — 상의가 포인트로 꽉 찬다"
                % (len(got), "/".join(got), spec["accents_max"]),
                "%d개(%s)" % (len(got), "/".join(got) or "없음"))


# ── 지형 타일 검사 ────────────────────────────────────────────────────────
def _luma_steps(image):
    """가로/세로로 이웃한 픽셀쌍의 명도차를, 타일 경계와 안쪽으로 나눠서."""
    lum = luma(image.astype(np.float32))
    cell = 16
    dx = np.abs(np.diff(lum, axis=1))
    dy = np.abs(np.diff(lum, axis=0))
    bx = np.zeros(dx.shape[1], bool)
    bx[cell - 1::cell] = True          # 열 k*cell-1 과 k*cell 사이가 타일 경계
    by = np.zeros(dy.shape[0], bool)
    by[cell - 1::cell] = True
    border = np.concatenate([dx[:, bx].ravel(), dy[by, :].ravel()])
    inside = np.concatenate([dx[:, ~bx].ravel(), dy[~by, :].ravel()])
    return float(border.mean()), float(inside.mean())


def check_tiles(path, spec):
    name = os.path.basename(path)
    rep = Report(name)
    gen = spec["palette"]()
    a = np.array(Image.open(path).convert("RGB"), dtype=np.int32)
    cell = spec["cell"]
    h, w = a.shape[:2]

    want = gen.TILE_ART if hasattr(gen, "TILE_ART") else gen.TILE
    ok_size = (cell == want and h % cell == 0 and w % cell == 0
               and (h // cell) * (w // cell) == gen.TILE_COUNT)
    rep.add(ok_size, "규격", "%dx%d 는 %dpx 칸 %d개가 아니다" % (w, h, cell, gen.TILE_COUNT),
            "%dpx × %d칸" % (cell, gen.TILE_COUNT))
    if not ok_size:
        rep.dump()
        return rep

    allowed = {tuple(int(v) for v in c) for ramp in gen.PAL.values() for c in ramp}
    used = {tuple(int(v) for v in c) for c in np.unique(a.reshape(-1, 3), axis=0)}
    stray = sorted(used - allowed)
    rep.add(not stray, "팔레트",
            "램프 밖 %d색 %s" % (len(stray), " ".join("#%02x%02x%02x" % c for c in stray[:4])),
            "%d색" % len(used))

    black = int((a.sum(-1) == 0).sum())
    rep.add(black == 0, "순검정", "%d px" % black)

    # 이음매 — 같은 지형을 넓게 깔았을 때 타일 경계가 보이면 안 된다.
    lines = []
    ok_seam = True
    for what, kind in (("땅", 1), ("바다", 0)):
        field = gen.compose([[kind] * 9 for _ in range(9)])
        border, inside = _luma_steps(field)
        ratio = border / max(inside, 1e-3)
        ok_seam &= ratio <= spec["seam_ratio"]
        lines.append("%s %.2f" % (what, ratio))
    rep.add(ok_seam, "이음매",
            "타일 경계의 명도차가 안쪽의 %s배 (상한 %.2f) — 48px 격자가 비친다"
            % ("/".join(lines), spec["seam_ratio"]), " ".join(lines))

    # 변주 — 지형 한가운데 칸들이 서로 다른 그림이어야 한다.
    for what, land, mask in (("땅", True, 255), ("바다", False, 0)):
        seen = set()
        for v in range(gen.VARIANTS):
            r, c = divmod(gen.tile_index(v, land, mask), gen.SHEET_COLS)
            seen.add(a[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell].tobytes())
        rep.add(len(seen) == gen.VARIANTS, "변주",
                "%s 변주 %d종이 실제로는 %d종 — 벽지가 된다"
                % (what, gen.VARIANTS, len(seen)), "%d종" % len(seen))

    # 명도/채도 — 지형 한가운데 칸만 본다(해안이 섞이면 값이 흐려진다).
    stats = {}
    for what, land, mask in (("grass", True, 255), ("sea", False, 0)):
        cells = []
        for v in range(gen.VARIANTS):
            r, c = divmod(gen.tile_index(v, land, mask), gen.SHEET_COLS)
            cells.append(a[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell])
        flat = np.concatenate([c.reshape(-1, 3) for c in cells])
        stats[what] = (float(luma(flat).mean()),
                       float((flat.max(-1) - flat.min(-1)).mean()))
        lo, hi = spec["luma_mean"][what]
        rep.add(lo <= stats[what][0] <= hi, "평균명도",
                "%s %.0f (%.0f~%.0f 밖)" % (what, stats[what][0], lo, hi),
                "%s %.0f" % (what, stats[what][0]))
        rep.add(stats[what][1] >= spec["chroma_mean"][what], "채도",
                "%s %.0f < %.0f — 탁하다" % (what, stats[what][1], spec["chroma_mean"][what]),
                "%s %.0f" % (what, stats[what][1]))

    # 캐릭터가 풀밭에 묻히지 않는가 — 기준색 셔츠와 풀의 명도차.
    pal, _ink, _glint = _player_palette()
    shirt = float(luma(np.array(pal["shirt"][1], dtype=np.float32)))
    gap = abs(shirt - stats["grass"][0])
    rep.add(gap >= spec["shirt_gap"], "캐릭터대비",
            "셔츠 %.0f vs 풀 %.0f — 차이 %.0f < %.0f 면 캐릭터가 배경에 묻힌다"
            % (shirt, stats["grass"][0], gap, spec["shirt_gap"]), "%.0f" % gap)

    rep.dump()
    return rep


def main(argv):
    paths = argv[1:] or [os.path.join(SPRITES, n) for n in SPECS]
    failed = False
    for p in paths:
        spec = SPECS.get(os.path.basename(p))
        if spec is None:
            print("FAIL %s — 등록된 스펙이 없다 (qa_sprite_check.py 의 SPECS 에 추가할 것)"
                  % os.path.basename(p))
            failed = True
            continue
        check = check_tiles if spec.get("kind") == "tile" else check_sheet
        failed |= check(p, spec).failed
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
