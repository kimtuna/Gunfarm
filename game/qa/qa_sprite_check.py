#!/usr/bin/env python3
"""스프라이트 자동 검사 — **눈으로 보기 전에 기계가 먼저 거른다.**

    .venv/bin/python game/qa/qa_sprite_check.py [PNG ...]

인자가 없으면 아래 `SPECS` 에 등록된 시트를 전부 본다. 불합격이 하나라도 있으면
종료 코드 1 을 낸다. 리포트는 **짧게** 찍는다 — 이 스크립트의 목적이 [DESIGN] 바퀴의
토큰(=이미지를 눈으로 보는 횟수)을 줄이는 것이기 때문이다. 자세한 숫자는 실패한
검사 줄에만 붙는다.

시트는 두 갈래다 — **캐릭터 시트**(칸 = 방향×프레임, 배경 투명)와 **지형 타일
시트**(칸 = 지형 배치, 배경 없음). 스펙의 `kind` 가 어느 검사를 돌릴지 정한다.

**지금 이 스크립트가 실제로 보는 것은 지형 · 아이템 아이콘 · 바닥 그림 · 상자다**
(2026-09-08, INBOX #58). **캐릭터 시트는 `qa_character_sheets.py` 로 넘어갔다** —
이 파일의 캐릭터 스펙은 절차 생성기(`gen_character.py`)의 램프를 원본으로 삼는데
캐릭터가 ComfyUI 그림 + 리그로 바뀌면서 그 원본이 사라졌기 때문이다. 자세한 것은
아래 `SPECS` 옆과 `docs/CHARACTER.md` 6절. 아래 「캐릭터 시트」 설명은 그 스펙을
되살릴 때를 위해 남겨둔 것이다.

무엇을 보는가 — 캐릭터 시트 (전부 기계가 판정할 수 있는 것만):
  규격      캔버스 칸 크기 / 행(방향) 수 / 방향 4개의 바운딩박스가 어긋나지 않는지
  알파      반투명 픽셀이 없는지 (도트는 알파 0 아니면 255)
  팔레트    램프에 없는 색이 섞이지 않았는지, 재질끼리 색이 겹치지 않는지
  외곽선    실루엣 가장자리가 잉크색인지, 순검정이 쓰이지 않았는지
  실루엣    떨어져 나온 조각이 없는지 (4-연결 요소 개수)
  대비      맞닿은 재질끼리 **경계에서** 갈리는지 — 재는 축(명도/채도/색차)은 쌍마다
            정한다 (셔츠/바지가 한 덩어리로
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
            둔 픽셀쌍의 명도차를 **그 무늬에서 아무 두 픽셀을 골랐을 때**와 견준다.
            격자가 비치면 여기서 숫자로 잡힌다 (INBOX #12 의 "인접한 같은 지형끼리
            이어져 보여야 한다"). 견주는 대상이 「타일 안쪽」에서 바뀐 이유는
            `_luma_steps` 에 있다 (2026-09-08, INBOX #60)
  변주      무늬 변주들이 실제로 서로 다른지 (같으면 벽지가 된다)
  무늬      **칸 안에 무늬가 실제로 보이는지** — 가장 넓은 한 색이 칸을 덮고 있지
            않은지 + 명도가 실제로 갈리는지. 「변주」·「채도」·「평균명도」는 셋 다
            단색을 통과시킨다 (2026-09-08, INBOX #60)
  캐릭터대비 풀 위에 선 캐릭터가 배경에 묻히지 않는지 — **실제 캐릭터 시트**의 몸
            픽셀 중 풀과 명도로 갈리는 넓이가 얼마나 되는지 (2026-09-08, INBOX #59)

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
    """지각 명도(Rec.601). 재질이 구분되는지는 **대개** 색상이 아니라 이 값이 정한다
    — 다만 나무와 쇠처럼 램프가 명도로 겹치는 쌍은 채도가 정한다(「대비」의 `색차`)."""
    a = np.asarray(rgb, dtype=np.float32)
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


# ── 스펙 ──────────────────────────────────────────────────────────────────
def _player_palette():
    """생성기에서 램프를 그대로 가져온다 — 손으로 베껴두면 반드시 어긋난다."""
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    import gen_character as gen
    return gen.palette(), gen.INK, gen.GLINT


def _gen():
    """캐릭터 생성기 모듈. **도구가 무슨 모션을 만드는가는 생성기가 원본이다** —
    이쪽에 목록을 다시 박아두면 한쪽만 고쳤을 때 조용히 어긋난다."""
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    import gen_character as gen
    return gen


def _gen_box():
    """상자 생성기(`game/tools/gen_box.py`). 칸 크기를 **베껴 적지 않고** 불러온다."""
    _gen()                     # `game/tools` 를 sys.path 에 올린다
    import gen_box
    return gen_box


def _gen_objects():
    """월드 오브젝트 생성기(`game/tools/gen_objects.py`) — 칸 크기와 램프를 불러온다."""
    _gen()
    import gen_objects
    return gen_objects


def _object_palette():
    """오브젝트가 쓰는 램프(잎 · 돌 · 나무 자루)를 생성기에서 그대로 가져온다."""
    return _gen_objects().palette(), _gen().INK, _gen().GLINT


def _cloth_accents(over=None):
    """생성기가 그 시트에 켜 둔 옷 포인트 이름들 (허리띠/옷깃/소맷부리).

    **모션마다 설정이 다를 수 있다**(2026-09-08, INBOX #47). 전에는 전역 `CFG` 만
    읽어서, 32px idle 이 옷깃을 켰는데도 검사는 `1개(belt)` 라고 셌다 — 시트마다
    그 시트를 구운 설정(`MOTION_OVER`)을 얹어서 센다.
    """
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    import gen_character as gen
    return gen.cloth_accents(dict(gen.CFG, **(over or {})))


def _character_sheets():
    """지금 게임에 실려 있는 캐릭터 시트의 경로 (`qa_character_sheets.py` 가 원본).

    **패턴을 여기에 베껴 적지 않는다** (2026-09-08, INBOX #58) — 아래
    `_handed_over()` 옆 설명 그대로다. 폴더를 훑을 때 건너뛸 목록도, 아래
    「캐릭터대비」가 실제로 열어볼 그림도 전부 이 한 함수에서 나온다.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    import qa_character_sheets
    return qa_character_sheets.sheet_paths()


def _character_fill():
    """캐릭터 시트의 **외곽선을 뺀 몸 픽셀**의 명도와 그 잉크색.

    (2026-09-08, INBOX #59) 「캐릭터대비」가 견줄 값을 **그림에서 잰다.** 전에는
    절차 생성기의 셔츠 램프(`gen_character.palette()["shirt"][1]`)를 썼는데, 캐릭터가
    ComfyUI 그림 + 리그로 바뀌면서 그 생성기는 더 이상 캐릭터를 굽지 않는다
    (`docs/CHARACTER.md`) — **없는 캐릭터를 상대로 여유를 보고하고 있었다.**

    무엇을 「캐릭터의 색」으로 볼 것인가:

    - **몸 픽셀 전체의 평균은 쓸 수 없다.** 잉크(명도 19)와 하이라이트(251)를 같이
      평균 내는 값이라 실제로 눈에 보이는 색이 아니다 — 지금 그림에서 94.5 가 나오는데
      풀(101)과 6.5 밖에 안 떨어져 있어서, 그대로 기준을 삼으면 **멀쩡한 그림이
      불합격**한다(INBOX #59 의 실측).
    - **중앙값도 아니다.** 그러면 캐릭터의 *전부* 가 풀과 갈리라는 요구가 되는데,
      옛 검사가 물었던 것은 셔츠 **한 벌**이었다. 신발이 풀과 비슷한 명도인 것은
      결함이 아니다.
    - **그래서 넓이로 잰다** — 몸 픽셀 하나하나가 풀과 명도로 갈리는지 세어서,
      **갈리는 넓이가 몸의 몇 %인가**를 본다. 옛 검사(셔츠 한 색 대 풀)를 색 하나가
      아니라 명도 히스토그램으로 넓힌 것이고, 잉크·하이라이트가 값을 끌고 다니지
      않는다.

    **외곽선(잉크)은 뺀다.** 몸의 15%를 차지하면서 어떤 배경과도 항상 갈리는 색이라,
    넣어두면 어떤 그림이든 15% 를 공짜로 얻는다. 잉크색은 **상수로 적지 않고**
    실루엣 테두리에서 가장 많이 쓰인 색으로 찾는다(`docs/CHARACTER.md` 8절 — 팔레트가
    ComfyUI 그림에서 나오므로 적어두면 그림을 바꾼 바퀴가 반드시 잊는다. 지금 시트
    22장의 테두리는 `#1a0f18` **한 색이다**).
    """
    body, edge = [], []
    paths = _character_sheets()
    for p in paths:
        a = np.asarray(Image.open(p).convert("RGBA"))
        on = a[..., 3] > 0
        pad = np.pad(on, 1)
        inner = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
        body.append(a[..., :3][on])
        edge.append(a[..., :3][on & ~inner])
    if not body:
        return None, None, 0
    body, edge = np.concatenate(body), np.concatenate(edge)
    colors, counts = np.unique(edge.reshape(-1, 3), axis=0, return_counts=True)
    ink = colors[int(np.argmax(counts))]
    fill = body[(body != ink).any(1)].astype(np.float32)
    return luma(fill), tuple(int(v) for v in ink), len(paths)


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
        # **손에 쥔 도구는 「비율」에서 뺀다**(2026-09-07, INBOX #24) — 「비율」은
        # 몸의 비율을 보는 검사라 머리 옆에 든 도끼날이 "머리"로 세어지면 안 된다.
        # (「각짐」은 반대로 도구까지 넣어서 잰다 — 아래 `_check_natural` 참고.)
        # 도구가 없는 시트에서는 이 검사가 한 픽셀도 달라지지 않는다.
        tool_mats=("helve", "blade"),
        # 프레임이 한 장뿐인 시트(idle)는 「이어짐」을 돌 게 없다 — `motion` 을 준
        # 시트만 본다. `link` 는 그 반대로 **1프레임짜리 시트**가 다른 시트와 얼마나
        # 벌어졌는지만 본다(도구를 들었다고 다른 캐릭터가 되면 안 된다).
        motion=None,
        link=None,
        # 칸 안에서 캐릭터의 세로 : 가로 비. **17px 시트는 아직 안 잰다**(`None`) —
        # 걷기·도구 시트가 32px 로 이사할 때 이 자리에 같은 밴드가 들어간다.
        aspect=None,
        # 「머리 폭 > 어깨 폭」을 요구할 것인가 (위 `_check_natural` 참고).
        head_wider=True,
        # 「옷포인트」를 셀 때 전역 `CFG` 위에 얹을 그 시트의 설정.
        accents_over=None,
    ), **over)


# ── 아래 셋(`_idle_spec` / `_walk_spec` / `_tool_spec`)은 지금 **아무 시트에도
# 등록돼 있지 않다** (2026-09-08, INBOX #58 — 아래 `SPECS` 옆 설명). 캐릭터가
# ComfyUI 그림 + 리그로 바뀌면서 이 값들이 전제하던 것(절차 생성기의 램프, 17px/32px
# 칸)이 없어졌다. **지우지 않고 두는 이유**는 여기 적힌 숫자가 전부 실측이라
# 그렇다 — 다만 **되살릴 때 그대로 쓰지 말 것.** 지금 캐릭터를 보는 검사는
# `qa_character_sheets.py` 이고, 기준은 `docs/CHARACTER.md` 「합격 기준」이다.
def _idle_spec(**over):
    """**32px idle 시트** — 2026-09-08, INBOX #49 에 **참고 자료가 바뀌면서** 다시 잡았다.

    사람이 ComfyUI 로 뽑은 농부 시안(`docs/design_reference/ref_farmer_ai.png`)을
    고르고 *"엄청 잘 나왔는데? 내가 원했던 거긴 해"*, **1:2 제약도 풀었다.**
    `#47` 이 **1 : 2** 를 목표로 잡았던 값 중 **두 개가 뒤집혔다.**

    | | #47 (1 : 2 목표) | #49 (지금 참고 자료) |
    |---|---|---|
    | 세로비 | 1 : 2 (16 × 32) | **1 : 1.78 (18 × 32)** — 참고 자료가 15 × 28 = 1:1.87 |
    | 머리(목 포함) | 40% | **53%** — 참고 자료의 머리 14줄 = 50% + 목 한 줄 |
    | 머리 폭 > 어깨 폭 | 놓았다 | **다시 요구한다** — 참고 자료는 15 vs 11 이다 |
    | 몸통 / 다리 / 신발 | 6 / 8 / 4 | **5 / 6 / 3** (머리가 커진 만큼 몸이 짧다) |
    | 옷 포인트 | 2개(허리띠 + 옷깃) | **3개(+ 멜빵)** |

    17px 시트(걷기·도구 18장)는 `_player_spec()` 그대로다 — 이 항목은 idle 만이다.
    """
    _gen()
    import gen_character as gen
    return _player_spec(
        cell=gen.IDLE_N,
        # **캔버스가 두 배가 되면 곧은 구간도 두 배로 잡힌다.** 다리 한 짝이
        # 여러 줄이라 17px 의 5px 로는 어떤 그림도 통과할 수 없다. 실측: 9.
        straight_max=9,
        # 머리 14줄(50%) + 목 한 줄. **아래는 "머리를 안 키운 것", 위는 "몸이
        # 사라진 것"이 벽이다** — 참고 자료 실측이 53% 다.
        head_frac=(0.50, 0.57),
        bands=dict(torso=(4, 6), legs=(5, 8), shoes=(3, 4)),
        # 참고 자료가 **15 × 28 = 1 : 1.87** 이라 1 : 2 를 놓았다(사람 결정).
        # 실측은 앞/뒷모습 18 × 32 = 1 : 1.78, 옆모습 17 × 32 = 1 : 1.88 이고
        # **묶은머리 옆모습만 1 : 1.68** 이다(꼬리가 뒤로 나와 한 칸 넓다) —
        # 아래 벽은 그 한 칸을 받아주는 자리에 둔다. #47 이 잡았던 1 : 1.56 은
        # 여전히 걸린다.
        aspect=(1.65, 2.00),
        # **되살렸다** — 참고 자료는 머리 폭 15, 어깨 폭 11 이다(2026-09-08, INBOX #49).
        # `#47` 이 1 : 2 를 목표로 하면서 놓았던 것을 사람이 다시 뒤집었다.
        head_wider=True,
        # 눈 2×2. 바깥 칸이 흰자라 하이라이트(흰색)가 **있어야** 한다.
        eye_size=dict(w=(2, 2), h=(2, 2)),
        eye_glint=True,
        # 허리띠 + 옷깃 + **멜빵**. 멜빵은 참고 자료에서 옷이 "색칠한 사각형"이
        # 아닌 이유라, 셋째 포인트를 여는 값을 한다.
        accents_max=3,
        accents_over=gen.IDLE_OVER,
        **over)


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


def _tool_spec(motion, tool, style):
    """도구를 든 세 모션(`hold`/`use`/`walk`) 시트 — idle/걷기 스펙에서 갈라진다
    (2026-09-07, INBOX #24. 도구 6종이 더 붙을 때 이 함수만 다시 부르면 된다).

    더해지는 것:
      **대비 helve|blade** — 자루와 날이 색으로 갈리는지. 17px 에서 도끼가 도끼로
      읽히는 것은 형태가 아니라 이 두 재질의 명도차다. 겸해서 「재질」 검사가
      **도구가 시트에서 통째로 사라지지 않았는지**(각 재질 4px 이상)를 본다.
      **이음** — `hold` 는 맨손 idle 과, `use`/`walk` 는 `hold` 와 견준다.
      DESIGN.md 「캐릭터 애니메이션」의 "idle 에서 사용 모션으로 바뀔 때 자세가
      갑자기 다른 캐릭터처럼 변하면 안 된다" 가 여기서 숫자가 된다.
    """
    base = _walk_spec(style) if motion == "walk" else _player_spec()
    spec = dict(base, contrast=base["contrast"] + [("helve", "blade", 18.0)])
    held = "player_hold_%s_%s.png" % (tool, style)
    if motion == "hold":
        # 1프레임짜리라 「이어짐」이 돌 게 없다 — 맨손 idle 과의 차이만 본다.
        # 상한 0.42: 도구를 쥐면 손이 몸 밖으로 나가고 도끼가 통째로 더해지므로
        # 걷기 한 프레임(0.30)보다는 커야 하고, 그보다 크면 자세가 딴판이 된 것이다.
        return dict(spec, motion=None,
                    link=dict(to="player_idle_%s.png" % style, max=0.42))
    # `use` 만 「이어짐」 상한을 0.30 → 0.35 로 늦춘다 — 한 프레임에 도끼가 칸의
    # 1/4 을 돈다. **그게 이 모션의 내용이다**(도끼가 안 움직이면 패는 게 아니다).
    # **「자리」는 걷기와 같은 2px 그대로다.** 처음엔 3px 로 늦춰뒀는데, 그건
    # 도구가 몸을 가려서가 아니라 **견주는 두 시트를 서로 다르게 재던 탓**이었다
    # (한쪽만 도구를 뺐다 — `_load_ref`). 재는 법을 맞추자 2px 로 통과한다.
    swing = motion == "use"
    return dict(spec, link=None, motion=dict(
        base["motion"] or {},
        frames=(4, 6),
        change=(0.05, 0.35 if swing else 0.30),
        even=3.0,
        shift=2,
        idle=held,
        from_idle=1.5,
    ))


def _icon_spec(**over):
    """도구 아이템 아이콘 한 장(`item_<도구>.png`, `gen_character.ICON_N` px 한 칸).

    **칸 크기를 여기 적지 않는다** (2026-09-08, INBOX #67 — 지형 스펙이 같은 이유로
    `gen_terrain.TILE` 을 읽게 된 것과 같은 자리다). 아트가 17 → 51px 이 되는 동안
    검사에만 옛 숫자가 남아 있으면 **그림은 멀쩡한데** 시트가 「규격」에서 통째로
    불합격한다.

    캐릭터 시트와 **같은 램프·같은 잉크·같은 광원**을 쓰므로 앞쪽 검사(팔레트 /
    색충돌 / 잉크아래 / 순검정 / 외곽선 / 잘림 / 실루엣 / 재질 / 대비)가 그대로
    돈다 — 아이콘만 다른 손에서 나온 것처럼 보이는 것을 여기서 막는다.
    「자연스러움」 갈래(각짐·비율·눈·옷 포인트·단색)만 건너뛴다 — 아이콘에는 사람이
    없다. 대신 **평평한 아이콘은 「명암폭」이 잡는다**(음영이 없으면 55 를 못 넘는다).

    **「잘림」이 여기서 특히 중요하다** — 칸 가득 그리다 보면 날이 테두리에 닿아
    외곽선이 잘리기 쉽다(실제로 자리를 잡는 동안 여러 번 그랬다).
    """
    return dict(_player_spec(
        kind="icon",
        cell=_gen().ICON_N,
        rows=["icon"],
        # **명도가 아니라 「색차」로 잰다** — 근거는 `check_sheet()` 의 「대비」 옆에 있다.
        contrast=[("helve", "blade", 18.0, "색차")],
        # 도구는 쇠(무채색)와 나무 둘뿐이라 사람 기준을 그대로 쓸 수 없다.
        # 실측(도끼): 평균 156 / 명암폭 73 / 어두운비율 0% / 채도 44.
        luma_mean=(120.0, 190.0),
        luma_spread=55.0,
        dark_frac=0.22,
        chroma_mean=25.0,
        # 도구가 그림의 전부다 — 「비율」에서 뺄 것이 없다.
        tool_mats=(),
        # **쇠와 나무의 밝기는 도구가 늘어도 같아야 한다** — 아이콘은 인벤토리
        # 칸에 나란히 놓이므로 하나만 탁하면 바로 보인다(STYLE_GUIDE 10번의
        # `item_axe_x6.png` 가 기준선이다). 실측: 도끼 날 173 / 자루 133,
        # 곡괭이 날 166 / 자루 131.
        mat_luma=dict(blade=(150.0, 195.0), helve=(112.0, 155.0)),
    ), **over)


# 머리모양 4종은 **형태만 다르고 팔레트·비율·광원이 같다** — 그래서 스펙도 하나를
# 돌려 쓴다. 34px 시트는 **머리카락이 길수록 실제로 더 어둡고 덜 쨍해서**(기준색의
# 머리는 검정 = 무채색이다) 그 셋(평균명도/어두운비율/채도)만 시트마다 늦춰야 했다.
# **17px 에서는 그 완화가 통째로 필요 없어졌다**(2026-09-07 — idle 은 INBOX #19,
# 걷기는 INBOX #20) — 캔버스가 줄면서 머리카락이 차지하는 넓이가 작아져 여덟 시트가
# 평균명도 102~110 / 어두운비율 4~8% / 채도 36~42 로 모였다. 그래서 머리모양별로
# 늦추는 표는 없앴다 — **네 머리모양이 같은 스펙을 그대로 통과한다.**

# 지형 타일 시트. 캐릭터와 견주는 값은 **지금 게임에 실려 있는 캐릭터 시트**에서
# 잰다(2026-09-08, INBOX #59 — 그전에는 절차 생성기의 셔츠 램프였는데 캐릭터가
# 거기서 안 나온다). 캐릭터가 풀밭에 서 있을 때 묻히지 않아야 한다
# (DESIGN.md 「그래픽 파이프라인」 1 / 「월드 생성」의 "캐릭터와의 명도차").
TERRAIN_SPEC = dict(
    kind="tile",
    # **칸 크기를 여기 적지 않는다** (2026-09-08, INBOX #58). 한때 `cell=16` 이라고
    # 박아뒀는데 지형 아트가 48px 이 되면서(`gen_terrain.TILE`) 그 한 줄 때문에
    # 시트가 「규격」에서 통째로 불합격이었다 — **그림은 멀쩡했고 검사만 안 따라온
    # 것이다.** 지금은 `check_tiles()` 가 생성기에서 읽는다.
    palette=_terrain_palette,
    # 같은 지형끼리 이어붙였을 때, 타일 경계의 명도차가 **그 무늬에서 아무 두
    # 픽셀을 골랐을 때**보다 이만큼 넘게 크면 격자가 비치는 것이다. 견주는 대상이
    # 「타일 안쪽」에서 바뀐 이유와 실측표는 `_luma_steps` 에 있다
    # (2026-09-08, INBOX #60).
    #
    # **상한을 지형마다 따로 잡는다** (2026-09-08, INBOX #62). 전에는 둘 다 1.10
    # 이었는데, 무늬를 다시 그리면서 실측이 땅 0.94 / **바다 0.61** 로 갈렸다 —
    # 바다는 물결이 가로로 길어서 세로 이웃끼리 오히려 **덜** 달라진다. 한 숫자로
    # 두면 바다 쪽에 0.5 나 되는 헐렁함이 생겨서, **일부러 타일 끝줄을 8% 어둡게
    # 해도 1.05 라 안 잡혔다**(실제로 넣어 보고 확인했다). 지형마다 실측 바로 위에
    # 붙여야 검사가 계속 잡는다:
    #
    # | 끝줄을 어둡게 | 0% | 2% | 4% | 8% |
    # |---|---|---|---|---|
    # | 땅 (상한 1.10) | 0.94 | **1.12** | 1.25 | 1.50 |
    # | 바다 (상한 0.80) | 0.61 | 0.76 | **0.84** | 1.05 |
    #
    # **무늬를 다시 그린 바퀴는 이 표를 다시 재고 상한을 옮긴다** — 값을 늦추는
    # 것이 아니라 새 실측에 다시 붙이는 것이다.
    seam_ratio={"땅": 1.10, "바다": 0.80},
    luma_mean={"grass": (90.0, 115.0), "sea": (45.0, 70.0)},
    chroma_mean={"grass": 28.0, "sea": 30.0},
    # 한 픽셀이 "풀과 갈렸다"고 칠 명도차. **옛 `shirt_gap` 과 같은 35 다** — 바뀐
    # 것은 무엇을 견주는가이지 얼마나 갈려야 하는가가 아니다.
    char_gap=35.0,
    # 그 명도차를 넘는 몸 픽셀이 **최소 이만큼**은 돼야 한다(외곽선 제외).
    # 실측한 두 극단의 가운데다 — 지금 그림 59.7% / 멜빵과 머리를 둘 다 풀색으로
    # 칠해본 것 16.5%(아래 `_character_fill` 옆 설명).
    char_share=0.40,
    # ── 무늬가 실제로 보이는가 (2026-09-08, INBOX #60) ────────────────────
    # **「변주」와 「채도」·「평균명도」는 단색을 통과시킨다** — 8종의 바이트열이
    # 다르기만 하면 8종이고(점 두 개를 다른 자리에 찍어도 그렇다), 명도·채도는
    # 오히려 단색일 때 가장 안정적으로 통과한다. 실제로 그 셋이 전부 초록불인
    # 채로 땅 한가운데 칸 픽셀의 **98.9% 가 한 색**이었다.
    # 지형 한가운데 칸에서 **가장 넓은 한 색**이 차지하는 비율의 상한.
    # 실측: 무늬를 넣기 전 98.9% → 넣은 뒤 땅 76% / 바다 82%.
    pattern_share=0.85,
    # 그리고 칸 안 명도의 표준편차 하한 — 넓이만 갈라놓고 **명도가 안 갈리면**
    # 무늬가 있어도 안 보인다. 재질마다 램프 폭이 달라 따로 잡는다
    # (실측: 전 땅 2.3 / 바다 1.5 → 후 땅 9.9 / 바다 6.1).
    pattern_std={"grass": 6.0, "sea": 4.0},
    # ── 변주마다 풀 양이 벌어지는가 (2026-09-10, #d2) ──────────────────────
    # 「변주」·「무늬」가 둘 다 초록불인 채로 화면이 벽지였다. 재는 자리는
    # `check_tiles()` 의 「변주폭」 — 왜 이걸 재는지는 거기 주석에 있다.
    #
    # | | 덤불을 칸마다 하나씩(옛 그림) | 덤불 수 0~3(#d2) |
    # |---|---|---|
    # | 덮인 넓이 | 18.4 ~ 24.9% | **0.0 ~ 50.0%** |
    # | 폭 | 6.5% | **50.0%** |
    #
    # 하한 30% 는 두 실측의 사이가 아니라 **옛 그림의 폭(6.5%)의 네 배 넘는
    # 자리**에 뒀다 — 6.5 와 50 의 한가운데(28%)에 두면 덤불 수를 0/1 두 종으로만
    # 갈라놓은 그림이 통과하는데, 그건 화면에서 「반은 민무늬」라 또 다른 무늬가 된다.
    tuft_spread=0.30,
    # 그리고 **맨땅이 드러난 칸이 실제로 있어야 한다.** 폭만 보면 전부 우거진 채로
    # 제일 우거진 칸만 더 우거진 그림이 통과한다 — 그때는 성긴 데가 없어서
    # 「드문드문」이 안 읽힌다.
    tuft_bare=0.05,
)

# 도구가 늘면 이 줄만 늘린다 (`gen_character.TOOLS` 와 같아야 한다) —
# 손에 쥔 세 모션 시트 12장과 아이템 아이콘 한 장이 함께 등록된다.
TOOL_NAMES = ("axe", "pickaxe", "sickle", "gun", "hoe", "watering_can",
              "fishing_rod")

# 그 도구가 실제로 만드는 모션. **낚싯대만 사용 모션이 없다**(2026-09-07 사람 결정,
# INBOX #31) — 없는 시트를 검사에 등록하면 그 파일이 없어서 통째로 불합격이 된다.
# 목록은 생성기(`gen_character.has_use()`)가 원본이다 — 여기에 도구 이름을 다시
# 박아두면 한쪽만 고쳤을 때 조용히 어긋난다.
def _tool_motions(tool):
    return ("hold", "use", "walk") if _gen().has_use(tool) else ("hold", "walk")

def _ground_spec(**over):
    """바닥에 놓인 도구 한 장(`ground_<도구>.png`, `gen_character.GROUND_N` px 한 칸).

    아이콘과 **같은 도형을 작은 칸에 그대로 축소한 것**이라(`gen_character.shrink()`)
    검사도 아이콘 것을 그대로 쓴다 — **칸 크기 한 줄만 다르다.** 숫자를 늦추지
    않은 것은 그럴 필요가 없어서다(실측 평균명도 132~165 / 명암폭 69~76 /
    채도 34~57 로 아이콘과 같은 자리에 모였다).

    **「명암폭」이 실제로 한 번 잡았다** — 낚싯대는 대가 1px 굵기라 축소하면서
    밝은 윗면과 그늘이 한 톤으로 평균나서 34 까지 떨어졌다. 그건 검사를 늦출
    자리가 아니라 그림을 고칠 자리였다(`gen_character.GROUNDS`).
    """
    return _icon_spec(cell=_gen().GROUND_N, **over)


def _box_spec(**over):
    """데스드롭 상자 시트(`death_box.png`, **48 × 42px** 칸 × 2프레임 — INBOX #40).

    상자도 도구 아이콘과 **같은 램프(나무 `helve` / 쇠 `blade`) · 같은 광원 · 같은
    잉크**로 굽는다(`gen_box.py`) — 그래서 스펙도 아이콘 것을 그대로 쓰고 **칸 크기
    두 줄만** 다르다. 바닥에 놓인 도구 옆에 나란히 놓이는 물건이라, 여기서 갈리면
    「어울림」이 그대로 깨진다.

    **칸이 정사각형이 아닌 첫 시트다** — 크기는 그림 사정이 아니라 `death_boxes.gd`
    의 `BOX_SIZE`(48 × 42)가 정한 것이라 그림 쪽에서 고를 값이 아니다. 2026-09-08
    (INBOX #67) 에 배율이 3에서 1로 내려오면서 **아트가 그 값과 같아졌다.**

    **숫자는 한 줄도 늦추지 않았다** — 실측이 아이콘과 같은 자리에 모였다
    (평균명도 126 / 명암폭 78 / 채도 69 / 쇠 161 · 나무 121). 바닥 그림
    (`_ground_spec()`)이 아이콘 스펙을 그대로 쓴 것과 같다.
    """
    return _icon_spec(cell=_gen_box().BOX_W, cell_h=_gen_box().BOX_H,
                      rows=["box"], **over)


def _object_spec(kind, **over):
    """월드 오브젝트 한 장(`object_<종류>.png`, 열 = 변주 — INBOX #63).

    **도구 아이콘 스펙에서 갈래를 그대로 물려받는다**(규격 / 알파 / 색충돌 / 잉크아래 /
    팔레트 / 순검정 / 외곽선 / 잘림 / 실루엣 / 바운딩 / 대비 / 재질명도 / 명암폭).
    상자(`_box_spec()`)가 그랬던 것과 같은 자리다 — 같은 원시 도형·같은 광원·같은
    잉크로 굽기 때문이다(`gen_objects.py`).

    **숫자는 세 갈래만 다시 잡았다.** 실측(변주 3벌씩):

    | | 평균명도 | 명암폭 | 채도 | 재질 |
    |---|---|---|---|---|
    | 나무 | 106 | 66 | 55~56 | 자루 121 · 잎 104 |
    | 바위 | 130~131 | 82 | 19 | 돌 130~131 |
    | 덤불 | 94~95 | 80 | 51 | 잎 94~95 |

    - **평균명도**: 아이콘 밴드(120~190)는 쇠붙이 도구를 전제한 값이다. 잎은 목표
      명도가 88 이라(풀 101 보다 확실히 어두워야 나무가 풀밭 위에서 덩어리로 읽힌다)
      그 밴드에 들어갈 수가 없다 — **그림을 밝게 고치면 지형과 안 갈린다.**
    - **채도**: 바위만 19 다. 돌은 **원래 무채색에 가까운 재질**이고(쇠 램프와 같은
      자리다), 밝은면까지 색을 넣은 후보는 바위가 아니라 모래·빵덩어리가 됐다
      (실측 6 / 13 / **19** / 17 — `gen_objects.palette()` 옆 표).
    - **어두운비율**은 셋 다 0% 라 아이콘 값(0.22)을 그대로 둔다.
    """
    objects = _gen_objects()
    cell = objects.SIZES[kind]
    return _icon_spec(cell=cell[0], cell_h=cell[1], rows=[kind],
                      palette=_object_palette, **over)


OBJECT_SPECS = {
    "tree": _object_spec("tree", luma_mean=(95.0, 120.0), chroma_mean=45.0,
                         # 줄기와 잎이 색으로 갈려야 나무로 읽힌다. 실측 17.
                         contrast=[("helve", "leaf", 12.0)],
                         mat_luma=dict(helve=(110.0, 135.0), leaf=(95.0, 115.0))),
    "rock": _object_spec("rock", luma_mean=(118.0, 145.0), chroma_mean=15.0,
                         contrast=[], mat_luma=dict(stone=(118.0, 145.0))),
    "bush": _object_spec("bush", luma_mean=(85.0, 108.0), chroma_mean=42.0,
                         contrast=[], mat_luma=dict(leaf=(85.0, 108.0))),
}

SPECS = {"terrain_tiles.png": TERRAIN_SPEC, "death_box.png": _box_spec()}
for _kind, _spec in OBJECT_SPECS.items():
    SPECS["object_%s.png" % _kind] = _spec
for _tool in TOOL_NAMES:
    SPECS["item_%s.png" % _tool] = _icon_spec()
    SPECS["ground_%s.png" % _tool] = _ground_spec()

# **캐릭터 시트(`player_*.png`)는 여기 없다** (2026-09-08, INBOX #58).
# 이 파일의 캐릭터 스펙은 절차 생성기(`gen_character.py`)가 굽던 17px/32px 시트를
# 전제로 했고 **팔레트도 그 생성기의 램프를 원본으로 삼았다.** 2026-09-08 에
# 캐릭터가 ComfyUI 그림 + 리그(`game/tools/rig.py`)로 바뀌면서 시트는 96px 이 됐고
# 색은 그림에서 나온다 — 되살릴 원본이 없다. `docs/CHARACTER.md` 6절이
# *"`qa_sprite_check.py` 는 캐릭터 시트를 못 본다"* 고 이미 정해뒀다.
#
# **지금 캐릭터 시트를 보는 것은 `qa_character_sheets.py` 다** — 그쪽은 "무슨
# 색인가"를 묻지 않고 프레임이 애니메이션으로 성립하는지만 본다(규격/알파/발밑/
# 머리/이어짐/고르게/색맞음). 아래 `main()` 이 그 스크립트가 실제로 맡는 파일만
# 훑기에서 뺀다 — **패턴을 여기 다시 적지 않는다**(양쪽에서 동시에 빠지는 PNG 가
# 생긴다).
#
# 아이템 아이콘(`item_*.png`)·바닥 그림(`ground_*.png`)·상자(`death_box.png`)는
# **여전히 옛 생성기가 굽는다** — 그래서 그것들은 그대로 여기 남아 있다
# (`docs/CHARACTER.md` 8절: "아이템 아이콘과 바닥 그림은 아직 옛 17px/12px 이다").


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


def _chroma(rgb):
    """채도(가장 밝은 채널 - 가장 어두운 채널). 파일 전체가 쓰는 정의다
    (`chroma_mean` 과 같다) — 「대비」의 `색차` 축도 이 값으로 잰다."""
    f = np.asarray(rgb, dtype=np.float32)[..., :3]      # 알파는 빼고 본다
    return f.max(axis=-1) - f.min(axis=-1)


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


def _load_ref(folder, name, spec, color2mat, ref_cell=None, ref_rows=1):
    """견줄 시트 한 장 → (rgb, 몸 마스크, **도구를 뺀 몸 마스크**).

    「이음」은 이 시트와 지금 시트의 바운딩박스를 견주는데, **양쪽을 같은 방식으로
    재야** 한다 — 한쪽만 도구를 빼면 그 차이가 통째로 "미끄러졌다"로 잡힌다
    (도끼를 든 시트끼리 견주는 `use`/`walk` 가 실제로 그랬다).
    """
    img = np.array(Image.open(os.path.join(folder, name)).convert("RGBA"))
    rgb, body = img[..., :3].astype(np.int32), img[..., 3] == 255
    if ref_cell is not None and img.shape[0] // ref_rows != ref_cell:
        # **칸이 다른 시트끼리는 견줄 수 없다**(2026-09-08, INBOX #47). 지금은
        # idle 만 32px 이고 걷기·도구는 17px 이라(INBOX #46 의 의도된 어긋남),
        # 두 시트를 같은 칸으로 잘라 겹치면 "몸이 통째로 바뀌었다"만 나온다 —
        # 그림이 잘못된 게 아니라 잴 수가 없는 것이다. 이사가 끝나면 저절로 다시 돈다.
        return None
    mm = np.full(body.shape, "", dtype=object)
    for c, m in color2mat.items():
        mm[body & np.all(rgb == np.array(c), axis=-1)] = m
    return rgb, body, body & ~_tool_mask(spec, mm, body)


def _tool_mask(spec, matmap, body):
    """손에 쥔 도구가 차지한 픽셀 — **도구 재질 + 거기 붙은 외곽선**.

    잉크는 어느 재질에도 안 잡히므로 재질(`tool_mats`)만 지우면 도구 모양의
    **잉크 테두리가 몸으로 남는다.** 「각짐」(어느 줄을 판정하지 않을지)과
    「자리」·「이음」(몸이 칸 안에서 미끄러졌는지)이 둘 다 이 마스크를 쓴다.
    """
    tool = np.zeros(body.shape, bool)
    for mat in spec.get("tool_mats", ()):
        tool |= matmap == mat
    if not tool.any():
        return tool
    return tool | (_neighbors(tool) & body & (matmap == ""))


def _straight_run(mask, skip=None):
    """실루엣 옆선/윗선에서 가장 긴 **곧은** 구간(px).

    줄마다 바깥쪽 끝 좌표를 뽑아 같은 값이 몇 줄 이어지는지 센다 — 6줄 내리
    같은 자리면 그 옆선은 자로 그은 직선이다(STYLE_GUIDE 「자연스러움」).

    **아랫변(발바닥)만 빼고 본다** — 캐릭터는 땅을 딛고 서 있어서 신발 밑창이
    평평한 게 맞다. 여기를 같이 재면 발이 클수록 불합격이 되는데, 그건 각진
    실루엣과 아무 상관이 없다.

    `skip`(손에 쥔 도구)이 그 줄의 바깥쪽 끝을 차지하고 있으면 **그 줄은
    "모름"으로 끊는다**(2026-09-07, INBOX #24). 도구를 빼고 재면 도구가 가린
    자리에 **없던 직선**이 생기고(도끼가 팔 바깥을 덮으면 몸의 오른쪽 끝이
    도끼 왼쪽 경계에서 잘려 8줄 곧은 선이 된다), 도구를 넣고 재면 이번엔
    **자루·날의 곧은 변**이 잡힌다 — 막대의 옆선이 곧은 건 각진 게 아니라
    자루의 생김새다. 어느 쪽도 아닌 "그 줄은 판정하지 않는다"가 맞다.
    """
    best = 0
    for m, sk, both in ((mask, skip, True),
                        (mask.T, None if skip is None else skip.T, False)):
        lo, hi = [], []
        for i, line in enumerate(m):
            xs = np.nonzero(line)[0]
            if xs.size == 0:
                lo.append(None)
                hi.append(None)
                continue
            lo.append(None if (sk is not None and sk[i][xs[0]]) else int(xs[0]))
            hi.append(None if (sk is not None and sk[i][xs[-1]]) else int(xs[-1]))
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
    # **칸이 정사각형이 아닐 수 있다**(2026-09-07, INBOX #40 — 데스드롭 상자는
    # 16 × 14px 이다. 크기를 `death_boxes.gd` 의 `BOX_SIZE` 가 이미 정해뒀다).
    # 안 준 시트는 지금까지처럼 세로도 `cell` 이다.
    cell_h = spec.get("cell_h", cell)
    rows = spec["rows"]
    h, w = alpha.shape
    ok_size = (h % cell_h == 0 and w % cell == 0 and h // cell_h == len(rows)
               and w >= cell)
    rep.add(ok_size, "규격",
            "%dx%d 은 %dx%dpx 칸 × %d행 이 아니다" % (w, h, cell, cell_h, len(rows)),
            "%dx%dpx × %d방향 × %d프레임" % (cell, cell_h, len(rows), max(w // cell, 1)))
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

    # 잘림 — **칸 테두리에 잉크가 아닌 픽셀이 닿으면 외곽선이 잘린 것이다**
    # (2026-09-07, INBOX #24). 도구를 크게 휘두르면 날이 칸 밖으로 나가는데, 잘린
    # 자리는 외곽선이 없어서 그림이 칼로 도려낸 것처럼 보인다. 맨 몸은 머리
    # 외곽선이 맨 윗줄에 닿아 있어서(잉크는 닿아도 된다) 이 검사를 그대로 통과한다.
    cut = []
    for r, d in enumerate(rows):
        for c in range(cols):
            sub_m = (body & ~inkm)[r * cell_h:(r + 1) * cell_h, c * cell:(c + 1) * cell]
            n = int(sub_m[0].sum() + sub_m[-1].sum() + sub_m[:, 0].sum() + sub_m[:, -1].sum())
            if n:
                cut.append("%s#%d:%dpx" % (d, c, n))
    rep.add(not cut, "잘림", "%s 가 칸 테두리에 닿았다 — 외곽선이 잘린다" % " ".join(cut[:4]))

    # 실루엣 — 프레임마다 4-연결 덩어리가 하나여야 한다
    bad = []
    for r in range(len(rows)):
        for c in range(cols):
            sub = body[r * cell_h:(r + 1) * cell_h, c * cell:(c + 1) * cell]
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
            sub = body[r * cell_h:(r + 1) * cell_h, c * cell:(c + 1) * cell]
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

    # 세로비 — **칸 안에서 캐릭터가 얼마나 세로로 긴가**(2026-09-08, INBOX #47).
    # 여기가 비어 있어서 **가로 18 × 세로 28 = 1 : 1.56** 이 그냥 통과했다:
    # 「규격」은 칸 크기만 보고 「바운딩」은 방향끼리 어긋나는지만 봐서, 캔버스를
    # 키웠는데 그림이 정사각에 가깝게 퍼진 것을 아무도 안 봤다. 세로비는
    # **"사람으로 보이는가"를 가르는 첫 번째 값**이다 — 정사각에 가까우면 사람이 아니다.
    if spec.get("aspect"):
        lo, hi = spec["aspect"]
        bad, got = [], []
        for d in rows:
            top, bot, x0, x1 = box[(d, 0)]
            a = (bot - top + 1) / float(x1 - x0 + 1)
            got.append("%s 1:%.2f" % (d, a))
            if not lo <= a <= hi:
                bad.append("%s 1:%.2f (%dx%d)" % (d, a, x1 - x0 + 1, bot - top + 1))
        rep.add(not bad, "세로비",
                "%s — 세로비가 1:%.2f~1:%.2f 밖이다. 캔버스가 정사각이라고 캐릭터까지"
                " 정사각으로 그리면 사람으로 안 보인다" % (" ".join(bad[:4]), lo, hi),
                " ".join(got))

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
    #
    # **재는 축은 쌍마다 정한다** (2026-09-08, INBOX #67). 기본은 명도인데,
    # **자루(나무)와 날(쇠)은 명도로 안 갈린다** — 두 램프가 148/118/95/74 와
    # 192/152/121/96 이라 가운데 두 단계가 사실상 겹쳐 있다. 그래서 맞닿은 자리의
    # 명도차는 조명이 어느 쪽을 비추느냐에 따라 2에서 72까지 흔들린다(실측: 도끼
    # 26.7 · 곡괭이 11.9 · 괭이 4.1 · 총 42.6). **그 둘을 실제로 가르는 것은 채도**다
    # (나무 78 / 쇠 13 — 맞닿은 자리에서 53~70 으로 일곱 도구가 다 모인다).
    # 명도만 요구하면 「괭이 목의 그늘진 아랫면을 억지로 밝게 칠하라」가 되는데,
    # 그건 그림을 고치는 게 아니라 **음영에 거짓말을 시키는 것**이다.
    # `inner_lines()` 가 *"재질이 다르면 램프가 이미 갈라놓았다"* 며 재질 경계에
    # 선을 안 긋는 것도 같은 전제인데, 이 쌍에서는 그 「갈라놓음」이 채도 쪽에 있다.
    # **숫자(18)는 늦추지 않았다 — 어느 축에서 재는가만 바로잡았다.**
    axes = {"명도": L, "채도": _chroma(rgb)}
    gaps = []
    for pair in spec["contrast"]:
        m1, m2, need = pair[:3]
        axis = pair[3] if len(pair) > 3 else "명도"
        a1, a2 = matmap == m1, matmap == m2
        t1, t2 = a1 & _neighbors(a2), a2 & _neighbors(a1)
        n = min(int(t1.sum()), int(t2.sum()))
        # `색차` 는 **둘 중 갈리는 축 하나면 된다** — 사람 눈도 그렇게 본다.
        names = ("명도", "채도") if axis == "색차" else (axis,)
        got = None if n < 4 else max(
            abs(float(axes[k][t1].mean()) - float(axes[k][t2].mean())) for k in names)
        gaps.append((got, m1, m2, need, n))
    bad = ["%s|%s %.0f<%.0f" % (m1, m2, g, need)
           for g, m1, m2, need, n in gaps if g is not None and g < need]
    rep.add(not bad, "대비", " ".join(bad),
            " ".join("%s|%s %s" % (m1, m2, "-" if g is None else "%.0f" % g)
                     for g, m1, m2, _, _ in gaps))

    # 재질별 평균 명도 — **도구끼리 쇠와 나무의 밝기가 같은가**
    # (2026-09-07, INBOX #26). 전체 평균(아래 「평균명도」)만 보면 자루가 길어진
    # 만큼 상쇄돼서 **날만 통째로 어두워진 그림이 통과한다** — 실제로 곡괭이머리를
    # 토막 낸 `capsule` 마다 부위 id 가 붙어 `inner_lines()` 가 토막 경계를 전부
    # 최암부로 그었을 때, 머리 34px 중 21px 이 가장 어두운 단계인데도 전체 평균은
    # 합격선 안이었다. 그 상태를 도끼 옆에 놓으면 곡괭이만 탁해 보인다(「어울림」).
    for mat, (lo, hi) in sorted(spec.get("mat_luma", {}).items()):
        sel = matmap == mat
        if int(sel.sum()) < 4:
            rep.add(True, "재질명도", "", "%s -" % mat)
            continue
        v = float(L[sel].mean())
        rep.add(lo <= v <= hi, "재질명도",
                "%s %.0f (%.0f~%.0f 밖)" % (mat, v, lo, hi), "%s %.0f" % (mat, v))

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

    # 「자연스러움」은 **사람 그림에만** 도는 갈래다(머리 비율·눈·옷 포인트) —
    # 도구 아이콘에는 머리도 옷도 없다.
    if spec["kind"] == "character":
        _check_natural(rep, spec, pal, body, rgb, matmap, cell, rows, cols, ink, glint)
    # 도구를 뺀 몸 실루엣 — 「자리」(칸 안에서 미끄러지는가)를 이걸로 잰다.
    # **도구에 붙은 외곽선까지 같이 뺀다**: 잉크는 어느 재질에도 안 잡혀서
    # 재질만 지우면 도끼 모양의 잉크 테두리가 몸으로 남고, 바운딩박스가 도구를
    # 뺀 자리까지 그대로 벌어진다(실제로 날을 키웠더니 「이음」이 3px 로 튀었다).
    # 「각짐」의 `skip` 과 같은 계산이다 — 한 곳에 모아 둔다.
    bodym = body & ~_tool_mask(spec, matmap, body)
    if spec.get("motion"):
        _check_motion(rep, spec["motion"], os.path.dirname(path), rgb, body, cell, rows, cols,
                      bodym, spec, color2mat)
    if spec.get("link"):
        _check_link(rep, spec["link"], os.path.dirname(path), rgb, body, cell, rows, bodym,
                    spec, color2mat)

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


def _delta(a, ba, b, bb, boxa=None, boxb=None):
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
    # **바운딩박스는 도구를 뺀 몸으로 잰다**(`boxa`/`boxb`, 2026-09-07 INBOX #24).
    # "칸 안에서 미끄러지는가"는 캐릭터가 제자리에 서 있는지를 보는 것인데,
    # 도끼를 휘두르면 도구가 칸의 절반을 가로질러서 몸이 가만히 있어도 3px 이 나온다.
    return ratio, int(np.abs(_box(ba if boxa is None else boxa)
                             - _box(bb if boxb is None else boxb)).max())


def _check_motion(rep, mo, folder, rgb, body, cell, rows, cols, bodym, spec, color2mat):
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
            ch, shift = _delta(a, ba, b, bb,
                               _frame(rgb, bodym, cell, r, c)[1],
                               _frame(rgb, bodym, cell, r, (c + 1) % cols)[1])
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
    ref = _load_ref(folder, mo["idle"], spec, color2mat, cell, len(rows))
    if ref is None:
        rep.add(True, "이음", "", "칸이 달라 못 견줌(%s 는 %dpx 가 아니다)" % (mo["idle"], cell))
        return
    pr, pa, pm = ref
    worst = max(max(_delta(*_frame(rgb, body, cell, r, c),
                           *_frame(rgb, body, cell, r, (c + 1) % cols))[0]
                    for c in range(cols)) for r in range(len(rows)))
    bad, show = [], 0.0
    for r, d in enumerate(rows):
        b, bb = _frame(rgb, body, cell, r, 0)
        ch, shift = _delta(*_frame(pr, pa, cell, r, 0), b, bb,
                           _frame(pr, pm, cell, r, 0)[1], _frame(rgb, bodym, cell, r, 0)[1])
        show = max(show, ch)
        if ch > worst * mo["from_idle"] or shift > mo["shift"]:
            bad.append("%s %.2f/%dpx" % (d, ch, shift))
    rep.add(not bad, "이음",
            "%s ← idle 에서 넘어오는 순간이 걷기 안의 가장 큰 변화(%.2f)의 %.1f배를 넘는다"
            % (" ".join(bad[:3]), worst, mo["from_idle"]),
            "%.2f (걷기 최대 %.2f)" % (show, worst))


def _check_link(rep, link, folder, rgb, body, cell, rows, bodym, spec, color2mat):
    """**1프레임짜리 시트가 다른 시트와 얼마나 벌어졌는가**(2026-09-07, INBOX #24).

    「이어짐」의 `이음` 은 프레임이 여럿인 시트에만 도는데, 도구를 들고 서 있는
    시트(`hold_<도구>`)는 한 장뿐이라 아무도 안 본다 — 그런데 **거기가 바로
    "도구를 들었더니 다른 캐릭터가 됐다"가 나타나는 자리**다. 맨손 idle 과 나란히
    놓고 바뀐 몸 픽셀 비율을 잰다.
    """
    ref = _load_ref(folder, link["to"], spec, color2mat, cell, len(rows))
    if ref is None:
        rep.add(True, "이음", "", "칸이 달라 못 견줌(%s 는 %dpx 가 아니다)" % (link["to"], cell))
        return
    pr, pa, pm = ref
    bad, show = [], 0.0
    for r, d in enumerate(rows):
        # 바뀐 비율은 **도구까지 넣어서**(도구가 더해진 몫이 곧 이 검사의 내용이다),
        # 미끄러짐은 **도구를 빼고**(몸이 제자리에 서 있는지) 잰다.
        ch, shift = _delta(*_frame(pr, pa, cell, r, 0), *_frame(rgb, body, cell, r, 0),
                           _frame(pr, pm, cell, r, 0)[1], _frame(rgb, bodym, cell, r, 0)[1])
        show = max(show, ch)
        if ch > link["max"] or shift > link.get("shift", 2):
            bad.append("%s %.2f/%dpx" % (d, ch, shift))
    rep.add(not bad, "이음", "%s ← %s 와 너무 많이 다르다(상한 %.2f)"
            % (" ".join(bad), link["to"], link["max"]), "%.2f" % show)


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

            # 「각짐」 — **도구가 바깥 끝을 차지한 줄은 판정하지 않는다**
            # (`_straight_run` 의 `skip`, 2026-09-07 INBOX #24). 도구 픽셀과
            # 거기 붙은 잉크(도구의 외곽선)를 함께 넘긴다.
            skip = _tool_mask(spec, mm, sub)
            run = _straight_run(sub, skip if skip.any() else None)
            worst = max(worst, run)
            if run > spec["straight_max"]:
                angular.append("%s %dpx" % (tag, run))

            # 비율은 **외곽선을 뺀 알맹이**로 잰다 — STYLE_GUIDE 3번 표가 그
            # 기준이다(외곽선은 위아래로 1px 씩 더 붙는다). **손에 쥔 도구는
            # 몸이 아니라 뺀다**(2026-09-07, INBOX #24) — 머리 옆에 든 도끼날이
            # 머리로, 자루가 어깨폭으로 세어지면 비율이 통째로 뒤틀린다.
            tool_mats = tuple(spec.get("tool_mats", ()))
            fill = mm != ""
            for mat in tool_mats:
                fill &= mm != mat
            ys = np.nonzero(fill.any(1))[0]
            top, bot = int(ys[0]), int(ys[-1])

            def first(mat):
                got = np.nonzero((mm == mat).any(1))[0]
                return None if got.size == 0 else int(got[0])

            def band_start(mat):
                """그 재질이 **그 줄에서 가장 넓은 재질이 되는 첫 줄**.

                전에는 그냥 `first(mat)`(그 재질이 처음 보이는 줄)이었는데,
                2026-09-08(INBOX #49)에 32px idle 에 **멜빵**이 붙으면서 그게
                깨졌다 — 멜빵은 상의 위에 얹힌 **바지 재질**이라 첫 바지 줄이
                허리가 아니라 어깨를 가리킨다. 「가장 넓은 재질」로 바꾸면
                한 짝에 한 칸뿐인 멜빵은 안 잡히고 몸통을 가로지르는 허리띠만
                잡힌다. **도구 재질은 빼고 센다** — 도구가 다리를 가리는 사용
                프레임에서 바지가 두세 칸까지 줄어들기 때문이다.
                """
                names = [x for x in set(mm.ravel()) if x and x not in tool_mats]
                if mat not in names:
                    return None
                cnts = {x: (mm == x).sum(1) for x in names}
                best = np.max(np.stack([cnts[x] for x in names]), axis=0)
                got = np.nonzero((cnts[mat] > 0) & (cnts[mat] >= best))[0]
                return None if got.size == 0 else int(got[0])

            # **허리선만 「가장 넓은 재질」로 찾는다** — 어깨선(상의)과 신발은
            # 예전대로 첫 줄이다. 상의는 도구를 든 프레임에서 어깨 맨 윗줄이
            # 한두 칸뿐이라 「가장 넓은 재질」로 재면 한 줄 밀린다(곡괭이 시트가
            # 실제로 그랬다) — 거기는 애초에 재질이 겹칠 일이 없다.
            shirt, pants, boot = first("shirt"), band_start("pants"), first("boot")
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
            # **2026-09-08 (INBOX #47) 부터 시트마다 켜고 끈다** — 사람이 목표를
            # 더 사실적인 비율(1 : 2)로 옮기면서 이 규칙을 놓았다(그 비율에서는
            # 머리가 어깨보다 넓지 않다). 17px 시트는 여전히 켜 둔다: 거기서는 얼굴을 담을 칸이
            # 없어 머리를 키운 것이 치비 비율의 근거였다.
            hw, sw = _width(fill, top, shirt - 1), _width(fill, shirt, pants - 1)
            if spec.get("head_wider", True) and hw <= sw:
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
        got = _cloth_accents(spec.get("accents_over"))
        rep.add(len(got) <= spec["accents_max"], "옷포인트",
                "%d개(%s) > %d개 — 상의가 포인트로 꽉 찬다"
                % (len(got), "/".join(got), spec["accents_max"]),
                "%d개(%s)" % (len(got), "/".join(got) or "없음"))


# ── 지형 타일 검사 ────────────────────────────────────────────────────────
def _uncorrelated_step(lum):
    """그 그림에서 **아무 두 픽셀**을 골랐을 때의 평균 명도차 E|X-Y|.

    무늬가 있는 바닥에서 「이음매」의 기준선이 되는 값이다 — 아래 `_luma_steps`
    참고. 표본을 뽑지 않고 정렬 한 번으로 정확히 구한다(같은 그림이면 언제나
    같은 값이라야 검사가 흔들리지 않는다).
    """
    x = np.sort(lum.ravel().astype(np.float64))
    n = x.size
    i = np.arange(n, dtype=np.float64)
    return float((2.0 / n ** 2) * np.dot(2.0 * i - n + 1.0, x))


def _luma_steps(image, cell):
    """타일 경계를 사이에 둔 픽셀쌍의 명도차를 **셋**으로 나눠 돌려준다.

    (경계, 타일 안쪽, **아무 두 픽셀**) — 판정에 쓰는 것은 경계 ÷ 아무 두 픽셀이다.

    **칸 크기를 인자로 받는다** (2026-09-08, INBOX #60). 한때 `cell = 16` 이 여기
    박혀 있었는데, 지형 아트가 48px 이 된 뒤로는 16px 마다 그은 선이 타일 경계가
    아니라 **타일 안쪽**이라 「이음매」가 격자를 아예 안 보고 있었다 —
    `check_tiles()` 가 생성기에서 읽어온 칸 크기를 그대로 넘긴다.

    **견주는 대상도 같은 바퀴에 바꿨다.** 전에는 「타일 안쪽」과 견줬는데, 그건
    **무늬가 있는 바닥에서 성립하지 않는 기준**이다: 풀잎은 세로로 이어진 획이라
    타일 **안쪽**의 세로 명도차가 원래 낮고, 타일 경계에서는 서로 다른 변주가
    만나 그 상관이 끊긴다 — 격자가 하나도 안 보이는 그림도 비가 1.5 까지 오른다
    (실측: 무늬를 넣기 전 1.04 → 넣은 뒤 1.51, 눈으로는 3배로 확대해도 격자가 없다).
    올바른 대조군은 **「그 무늬에서 아무 두 픽셀을 골랐을 때」** 다 — 이음매가
    없다면 경계의 픽셀쌍이 딱 그만큼 무관해야 한다. 실측으로 갈린다:

    | | 무늬 없음(옛 그림) | 무늬 있음 | 타일 끝줄을 4% 어둡게 |
    |---|---|---|---|
    | 경계 ÷ 안쪽 | 1.04 | **1.51 (거짓 실패)** | 1.95 |
    | 경계 ÷ 아무 두 픽셀 | 0.47 | **0.95** | **1.22** |

    **무늬가 짙을수록 이음매가 실제로 덜 보이는 것도 이 기준이 맞다** — 같은 격자를
    넣어도 옛 그림은 3.16, 무늬가 있으면 1.22 다(무늬가 이음매를 가린다).
    """
    lum = luma(image.astype(np.float32))
    dx = np.abs(np.diff(lum, axis=1))
    dy = np.abs(np.diff(lum, axis=0))
    bx = np.zeros(dx.shape[1], bool)
    bx[cell - 1::cell] = True          # 열 k*cell-1 과 k*cell 사이가 타일 경계
    by = np.zeros(dy.shape[0], bool)
    by[cell - 1::cell] = True
    border = np.concatenate([dx[:, bx].ravel(), dy[by, :].ravel()])
    inside = np.concatenate([dx[:, ~bx].ravel(), dy[~by, :].ravel()])
    return float(border.mean()), float(inside.mean()), _uncorrelated_step(lum)


def check_tiles(path, spec):
    name = os.path.basename(path)
    rep = Report(name)
    gen = spec["palette"]()
    a = np.array(Image.open(path).convert("RGB"), dtype=np.int32)
    # **칸 크기는 생성기가 원본이다** (2026-09-08, INBOX #58). 스펙에 손으로 적어두면
    # 그림을 다시 구운 바퀴가 반드시 잊는다 — 실제로 16 에서 48 로 바뀌는 동안
    # 여기만 안 따라와서 지형 검사가 첫 줄에서 멈춰 있었다.
    cell = gen.TILE
    h, w = a.shape[:2]

    ok_size = (h % cell == 0 and w % cell == 0
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
    fields = {}
    for what, kind in (("땅", 1), ("바다", 0)):
        # **검사할 PNG 를 넘긴다.** 안 넘기면 `compose()` 가 생성기로 시트를 다시
        # 구워서, 「이음매」만 파일이 아니라 **지금 코드**를 재게 된다 — 굽기를
        # 잊은 채 생성기만 고친 바퀴를 이 검사가 놓친다(2026-09-08, INBOX #60).
        fields[what] = field = gen.compose([[kind] * 9 for _ in range(9)],
                                           a.astype(np.uint8))
        border, inside, uncorr = _luma_steps(field, cell)
        ratio = border / max(uncorr, 1e-3)
        cap = spec["seam_ratio"][what]
        ok_seam &= ratio <= cap
        # 옛 기준(경계÷안쪽)도 같이 적어둔다 — 무늬를 손대는 바퀴가 두 값이
        # 어떻게 갈리는지 보고 판단할 수 있게.
        lines.append("%s %.2f/상한%.2f(안쪽대비 %.2f)"
                     % (what, ratio, cap, border / max(inside, 1e-3)))
    rep.add(ok_seam, "이음매",
            "타일 경계의 명도차가 **아무 두 픽셀**의 %s배 — %dpx 격자가 비친다"
            % ("/".join(lines), cell), " ".join(lines))

    # 변주 — 지형 한가운데 칸들이 서로 다른 그림이어야 한다.
    for what, land, mask in (("땅", True, 255), ("바다", False, 0)):
        seen = set()
        for v in range(gen.VARIANTS):
            r, c = divmod(gen.tile_index(v, land, mask), gen.SHEET_COLS)
            seen.add(a[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell].tobytes())
        rep.add(len(seen) == gen.VARIANTS, "변주",
                "%s 변주 %d종이 실제로는 %d종 — 벽지가 된다"
                % (what, gen.VARIANTS, len(seen)), "%d종" % len(seen))

    # ── 변주폭 — **변주마다 무늬의 「양」이 벌어지는가** (2026-09-10, #d2) ──────
    # 「변주」는 8종의 바이트열이 다르기만 하면 통과한다. 그래서 **덤불을 칸마다
    # 똑같이 하나씩 놓고 자리만 옮긴** 그림이 초록불이었다 — 실측하면 여덟 칸의
    # 덮인 넓이가 18.4~24.9% 로 전부 한 덩어리라, 화면에서는 같은 그림이 자리만
    # 옮겨 다니는 **벽지**로 보였다(사람 지적: *"드문드문 풀이 있어야지"*).
    #
    # 재는 것은 **바탕색이 아닌 픽셀의 넓이**다. 「무늬」가 8종을 한 덩어리로 뭉쳐
    # 평균만 보는 데 반해, 이건 **변주끼리의 폭**을 본다 — 둘 다 있어야 한다:
    # 평균만 보면 고른 그림이 통과하고, 폭만 보면 전부 성기거나 전부 우거진 그림이
    # 통과한다.
    #
    # **땅만 잰다.** 바다는 일부러 고르게 뿌린다 — 물결을 한자리로 몰거나 칸마다
    # 양을 벌리면 맨물이 타일 모서리에 걸려 「이음매」가 깨진다(`gen_terrain.py`
    # 의 `CLUMP_SPREAD` 위 주석. 실측 0.61 → 1.31).
    covers = []
    base = np.array(gen.PAL["grass"][1], np.int32)
    for v in range(gen.VARIANTS):
        r, c = divmod(gen.tile_index(v, True, 255), gen.SHEET_COLS)
        cellpix = a[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
        covers.append(float((np.abs(cellpix - base).sum(-1) > 0).mean()))
    spread = max(covers) - min(covers)
    rep.add(spread >= spec["tuft_spread"] and min(covers) <= spec["tuft_bare"],
            "변주폭",
            "땅 변주별 덮인 넓이 %.0f~%.0f%% (폭 %.0f%% < 하한 %.0f%% 또는 "
            "가장 성긴 칸 %.0f%% > 상한 %.0f%%) — 칸마다 풀 양이 같아서 벽지가 된다"
            % (min(covers) * 100, max(covers) * 100, spread * 100,
               spec["tuft_spread"] * 100, min(covers) * 100, spec["tuft_bare"] * 100),
            "폭 %.0f%% (%.0f~%.0f%%)" % (spread * 100, min(covers) * 100,
                                         max(covers) * 100))

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

        # 무늬 — 넓이(가장 넓은 한 색)와 명도(표준편차)를 함께 본다. 둘 중
        # 하나만 보면 빠져나갈 길이 있다: 넓이만 보면 명도가 거의 같은 두 색으로
        # 갈라놓은 그림이 통과하고, 명도만 보면 한 색이 칸을 덮은 채 점 몇 개만
        # 튀는 그림이 통과한다.
        counts = np.unique(flat, axis=0, return_counts=True)[1]
        share = float(counts.max()) / len(flat)
        std = float(luma(flat).std())
        rep.add(share <= spec["pattern_share"] and std >= spec["pattern_std"][what],
                "무늬",
                "%s 가장 넓은 한 색 %.0f%%(상한 %.0f%%) · 명도 표준편차 %.1f"
                "(하한 %.1f) — 무늬가 있어도 안 보인다"
                % (what, share * 100, spec["pattern_share"] * 100,
                   std, spec["pattern_std"][what]),
                "%s %.0f%%/±%.1f" % (what, share * 100, std))

        lo, hi = spec["luma_mean"][what]
        rep.add(lo <= stats[what][0] <= hi, "평균명도",
                "%s %.0f (%.0f~%.0f 밖)" % (what, stats[what][0], lo, hi),
                "%s %.0f" % (what, stats[what][0]))
        rep.add(stats[what][1] >= spec["chroma_mean"][what], "채도",
                "%s %.0f < %.0f — 탁하다" % (what, stats[what][1], spec["chroma_mean"][what]),
                "%s %.0f" % (what, stats[what][1]))

    # 캐릭터가 풀밭에 묻히지 않는가 — **실제 시트**의 몸 픽셀 중 풀과 명도로 갈리는
    # 넓이 (2026-09-08, INBOX #59. 무엇을 재고 왜 그것을 재는지는 `_character_fill`).
    fill, ink, sheets = _character_fill()
    if fill is None or not fill.size:
        # **조용히 넘어가지 않는다.** 캐릭터가 없으면 "묻히는가"는 답이 없는 물음이고,
        # 답이 없는 물음에 초록불을 주면 공짜로 통과한 검사가 굳는다.
        rep.add(False, "캐릭터대비",
                "캐릭터 시트가 없어 잴 수가 없다 — qa_character_sheets.sheet_paths()")
    else:
        split = float((np.abs(fill - stats["grass"][0]) >= spec["char_gap"]).mean())
        rep.add(split >= spec["char_share"], "캐릭터대비",
                "몸의 %.0f%% 만 풀(%.0f)과 명도 %.0f 이상 갈린다 (하한 %.0f%%) — "
                "캐릭터가 배경에 묻힌다. **합격선을 늦출 자리가 아니라** 지형 색이나 "
                "옷 색을 사람이 정할 자리다(INBOX #59)"
                % (split * 100, stats["grass"][0], spec["char_gap"],
                   spec["char_share"] * 100),
                "%.0f%% (시트 %d장, 잉크 #%02x%02x%02x)" % ((split * 100, sheets) + ink))

    rep.dump()
    return rep


def _handed_over():
    """`qa_character_sheets.py` 가 맡는 파일 이름들 (2026-09-08, INBOX #58).

    **패턴을 베껴 적지 않고 그 스크립트에서 불러온다.** 여기에 `player_*` 같은
    글로브를 다시 적으면, 저쪽 패턴에는 안 걸리는데 이쪽 패턴에는 걸리는 시트가
    생겼을 때(예: 머리모양이 늘어 `player_idle_ponytail.png`) **양쪽에서 동시에
    빠져 아무도 안 보는 PNG** 가 된다. 저쪽이 실제로 여는 파일만 넘긴다.
    """
    return {os.path.basename(p) for p in _character_sheets()}


def main(argv):
    # **인자가 없으면 폴더를 훑는다** — SPECS 만 돌면 등록을 잊은 새 PNG 가
    # 조용히 검사에서 빠진다(STYLE_GUIDE 7번 "등록되지 않은 PNG 는 불합격").
    paths = argv[1:] or sorted(os.path.join(SPRITES, n) for n in os.listdir(SPRITES)
                               if n.endswith(".png"))
    # 캐릭터 시트는 `qa_character_sheets.py` 로 넘어갔다 (위 SPECS 옆 설명).
    # **건너뛴다는 것을 찍는다** — 조용히 넘어가면 "공짜로 통과한 검사"가 된다.
    handed = _handed_over()
    skipped = [p for p in paths if os.path.basename(p) in handed]
    if skipped:
        print("skip 캐릭터 시트 %d장 — qa_character_sheets.py 가 본다"
              " (docs/CHARACTER.md 6절)" % len(skipped))
    failed = False
    for p in paths:
        if os.path.basename(p) in handed:
            continue
        name = os.path.basename(p)
        spec = SPECS.get(name)
        if spec is None:
            # 캐릭터 시트인데 여기까지 왔다는 것은 **저쪽 패턴에 안 걸렸다**는
            # 뜻이다 — 이 파일에 스펙을 다시 만들 자리가 아니라, 그쪽이 맡는
            # 범위를 넓힐 자리다.
            where = ("qa_character_sheets.py 의 sheet_paths() 가 이 이름을 못 잡는다"
                     if name.startswith("player_")
                     else "qa_sprite_check.py 의 SPECS 에 추가할 것")
            print("FAIL %s — 등록된 스펙이 없다 (%s)" % (name, where))
            failed = True
            continue
        check = check_tiles if spec.get("kind") == "tile" else check_sheet
        failed |= check(p, spec).failed
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
