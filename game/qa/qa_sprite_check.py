#!/usr/bin/env python3
"""스프라이트 자동 검사 — **눈으로 보기 전에 기계가 먼저 거른다.**

    .venv/bin/python game/qa/qa_sprite_check.py [PNG ...]

인자가 없으면 아래 `SPECS` 에 등록된 시트를 전부 본다. 불합격이 하나라도 있으면
종료 코드 1 을 낸다. 리포트는 **짧게** 찍는다 — 이 스크립트의 목적이 [DESIGN] 바퀴의
토큰(=이미지를 눈으로 보는 횟수)을 줄이는 것이기 때문이다. 자세한 숫자는 실패한
검사 줄에만 붙는다.

무엇을 보는가 (전부 기계가 판정할 수 있는 것만):
  규격      캔버스 칸 크기 / 행(방향) 수 / 방향 4개의 바운딩박스가 어긋나지 않는지
  알파      반투명 픽셀이 없는지 (도트는 알파 0 아니면 255)
  팔레트    램프에 없는 색이 섞이지 않았는지, 재질끼리 색이 겹치지 않는지
  외곽선    실루엣 가장자리가 잉크색인지, 순검정이 쓰이지 않았는지
  실루엣    떨어져 나온 조각이 없는지 (4-연결 요소 개수)
  대비      맞닿은 재질끼리 **경계에서** 명도가 갈리는지 (셔츠/바지가 한 덩어리로
            뭉치는 것을 여기서 잡는다 — INBOX #9)
  명도분포  전체가 너무 어둡거나 너무 납작하지 않은지

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


def _player_spec(**over):
    return dict(dict(
        cell=34,
        rows=["down", "left", "right", "up"],
        palette=_player_palette,
        # 실제로 맞닿는 재질쌍과 **경계에서 요구하는 최소 명도차**.
        # 34px 에서 두 면이 "다른 재질"로 읽히려면 경험적으로 20 안팎이 필요하다.
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
        # 일부러 무채색인 색(옷색 「잿빛」 등)으로 팔레트를 갈아끼운 시트를 새로
        # 등록할 때는 그 시트의 스펙에서 이 값을 따로 낮춰 잡을 것.
        chroma_mean=34.0,
    ), **over)


# 머리모양 4종은 **형태만 다르고 팔레트·비율·광원이 같다** — 그래서 스펙도 하나를
# 돌려 쓴다. 다만 **머리카락이 길수록 그 시트는 실제로 더 어둡고 덜 쨍하다**
# (기준색의 머리는 검정 = 무채색이다). 그래서 그 셋(평균명도/어두운비율/채도)만
# 시트마다 늦춘다 — 기준을 봐주는 게 아니라 시트가 그리는 대상이 다른 것이다.
# **나머지 검사(대비/명암폭/실루엣/팔레트/바운딩)는 한 칸도 안 늦춘다.**
SPECS = {
    "player_idle_short.png": _player_spec(),
    "player_idle_ponytail.png": _player_spec(luma_mean=(94.0, 170.0)),
    "player_idle_bob.png": _player_spec(luma_mean=(90.0, 170.0), dark_frac=0.26,
                                        chroma_mean=35.0),
    "player_idle_long.png": _player_spec(luma_mean=(85.0, 170.0), dark_frac=0.30,
                                         chroma_mean=31.0),
}


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
        failed |= check_sheet(p, spec).failed
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
