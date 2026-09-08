#!/usr/bin/env python3
"""리그가 구운 캐릭터 시트 검사 (`docs/CHARACTER.md` 「합격 기준」).

    .venv/bin/python game/qa/qa_character_sheets.py

불합격이 하나라도 있으면 **종료 코드 1** 을 낸다. 리포트는 짧게 찍는다 — 불합격한
줄에만 숫자를 붙인다.

**이 검사는 `qa_sprite_check.py` 와 다르다.** 그쪽은 절차 생성기(`gen_character.py`)의
팔레트·램프를 원본으로 삼는데, 2026-09-08 에 캐릭터를 ComfyUI 그림 + 리그로 바꾸면서
그 원본이 사라졌다. 여기서는 **그림이 무슨 색인지는 묻지 않고**, 프레임들이 애니메이션
으로서 성립하는지만 본다 — 그건 그림이 어디서 왔든 기계가 판정할 수 있다.

무엇을 보는가 (전부 `docs/CHARACTER.md` 「합격 기준」의 항목이다):
  규격      칸이 정사각이고 행이 4개(방향)인가 / 칸 크기가 시트마다 같은가
  알파      반투명 픽셀이 없는가 (도트는 알파 0 아니면 255)
  잘림      칸 테두리에 **잉크가 아닌 픽셀**이 닿지 않았는가 — 닿으면 그림이 칸을
            넘어 외곽선이 끊긴 것이다 (도구가 생기면서 필요해졌다, INBOX #66)
  발밑      한 줄(방향) 안의 모든 프레임에서 실루엣 아랫줄이 같은가
            — 다르면 캐릭터가 걸으며 들썩인다
  머리      프레임 사이 변화 중 **위 30%** 에서 일어난 비율. 걷기에서 머리는 움직이면
            안 된다. 넘으면 몸이 통째로 밀리고 있다는 뜻이다
  이어짐    이웃한 두 프레임 사이에 몸 픽셀이 얼마나 바뀌는가. 너무 작으면 죽은
            프레임(그 장이 앞 장과 사실상 같다), 너무 크면 순간이동이다
  고르게    가장 큰 변화 ÷ 가장 작은 변화
  색맞음    방향끼리 팔레트가 같은가 — 방향마다 그림을 따로 뽑으므로 여기가 갈리면
            걷다가 방향을 바꿀 때 옷 색이 바뀐다
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "assets", "sprites")
DIRS = ["down", "left", "right", "up"]

CELL = 96                 # docs/CHARACTER.md 「크기」
## 「머리」는 **목에서 자른다** — 위에서부터 몇 %로 잡으면 방향마다 비율이 달라서
## (옆모습이 더 말랐다) 어깨가 들어오고, 팔을 흔들기만 해도 "머리가 움직인다"고
## 잡힌다. 목은 실루엣이 가장 좁아지는 줄이라 기계가 찾을 수 있다(`neck_row`).
## 아래 값은 목을 못 찾았을 때만 쓰는 대비책이다.
HEAD_BAND = 0.22
HEAD_MAX = 0.08           # 변화 중 머리가 차지해도 되는 비율

## **머리 검사를 건너뛰는 모션.** 도구를 들거나 휘두르는 자세는 팔이 머리 옆·위로
## 올라가는 것이 그 모션의 내용이다 — 거기서 머리 부근이 변하는 건 결함이 아니다.
HEAD_SKIP = ("use_", "hold_")
CHANGE_MIN, CHANGE_MAX = 0.02, 0.45
EVEN_MAX = 3.5


def cells(path):
    im = Image.open(path).convert("RGBA")
    cell = im.height // len(DIRS)
    cols = im.width // cell
    a = np.asarray(im)
    return cell, cols, [[a[r*cell:(r+1)*cell, i*cell:(i+1)*cell]
                         for i in range(cols)] for r in range(len(DIRS))]


def body(c):
    return c[..., 3] > 0


def neck_row(op):
    """머리와 몸통 사이 — **위에서 내려오다 처음 잘록해지는 줄.** 못 찾으면 None.

    **가장 좁은 줄을 고르면 안 된다** (2026-09-08, INBOX #56). 머리가 긴 캐릭터는
    옆모습에서 머리카락이 어깨보다 넓어서, 구간 안의 최솟값이 목이 아니라 **허리**에
    떨어진다 — 그러면 「머리」 띠가 어깨와 팔을 통째로 삼켜서 팔만 흔들어도
    "머리가 움직인다"로 잡힌다(실측: 목 24줄인 캐릭터를 43줄로 잡아 18.3%).
    목은 그 아래가 어깨로 **다시 넓어지는** 자리다 — 그것으로 가른다.
    """
    ys = np.flatnonzero(op.sum(1) > 0)
    if ys.size < 8:
        return None
    top, bot = int(ys.min()), int(ys.max())
    h = bot - top + 1
    lo, hi = top + int(h*0.18), top + int(h*0.48)
    if hi <= lo:
        return None
    w = op.sum(1).astype(int)
    for y in range(max(lo, top+1), min(hi, bot)):
        # ① 내려오다 멈춘 자리(골짜기 바닥) ② 그 아래가 다시 넓어진다(어깨)
        # ③ **위쪽에서 가장 넓었던 곳보다 뚜렷이 좁다** — 머리카락 안의 잔물결을 뺀다
        if (w[y] <= w[y-1] and w[y] < w[y+1]
                and w[y] <= 0.90 * w[top:y+1].max()):
            return y
    return lo + int(np.argmin(w[lo:hi]))  # 잘록한 데가 없으면 예전대로 최솟값


def clipped(c):
    """칸 테두리에 **잉크가 아닌 픽셀**이 닿은 수 = 그림이 칸을 넘어 잘렸다.

    도구가 생기면서 필요해졌다(2026-09-08, INBOX #66) — 낫처럼 위로 넓은 날이나
    총처럼 가로로 긴 도구는 **손 위치가 조금만 밖으로 나가도 칸을 넘는다.** 넘으면
    그 자리에서 외곽선이 끊겨 도구가 잘린 것으로 보인다.

    **잉크색을 상수로 적지 않는다**(`docs/CHARACTER.md` 8절) — 팔레트가 ComfyUI
    그림에서 나오므로 적어두면 그림을 바꾼 바퀴가 반드시 잊는다. 실루엣 테두리에서
    가장 많이 쓰인 색을 잉크로 삼는다. 테두리 한 줄은 원래 잉크가 차지하는 자리라
    (`gen_player.add_ink`) 잉크는 닿아도 된다.
    """
    op = c[..., 3] > 0
    if not op.any():
        return 0
    pad = np.pad(op, 1)
    rim = op & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    cols, cnt = np.unique(c[rim][:, :3], axis=0, return_counts=True)
    ink = cols[cnt.argmax()].astype(int)
    edge = np.zeros(op.shape, bool)
    edge[0] = edge[-1] = True
    edge[:, 0] = edge[:, -1] = True
    return int((op & edge & (np.abs(c[..., :3].astype(int) - ink).max(2) > 10)).sum())


def change(p, q):
    dp, dq = body(p), body(q)
    diff = (dp != dq) | ((dp & dq) &
                         (np.abs(p[..., :3].astype(int) - q[..., :3].astype(int)).max(2) > 24))
    return diff.sum() / max(1, (dp | dq).sum())


def head_bands(paths):
    """방향마다 「머리」 띠(윗줄 ~ 목) — **맨손 idle 시트에서 잰다.**

    시트마다 제 첫 프레임에서 재면 **도구가 목을 옮긴다**(2026-09-08, INBOX #66).
    낫이나 낚싯대는 날 끝이 머리 위로 나가서 `top` 을 끌어올리고, 자루가 어깨 옆에
    서서 폭 곡선의 골짜기를 지운다 — 그러면 띠가 어깨·팔까지 삼켜서 **팔만 흔들어도
    "머리가 움직인다"로 잡힌다**(낫 17.0%). 머리가 어디까지인지는 **사람의 성질**이지
    무엇을 들었느냐가 아니고, 모든 시트가 같은 테두리로 구워지므로(`rig.bake_rows`)
    맨손 idle 에서 한 번 재면 22장에 그대로 쓸 수 있다.
    """
    idle = [p for p in paths if os.path.basename(p).startswith("player_idle_")]
    if not idle:
        return {}
    _, _, rows = cells(idle[0])
    out = {}
    for r, frames in enumerate(rows):
        op = body(frames[0])
        ys = np.flatnonzero(op.sum(1) > 0)
        top, bot = int(ys.min()), int(ys.max())
        nk = neck_row(op)
        out[DIRS[r]] = slice(top, nk if nk is not None
                             else top + int((bot - top + 1) * HEAD_BAND))
    return out


def check(path, fails, bands=None):
    name = os.path.basename(path)
    cell, cols, rows = cells(path)
    if cell != CELL:
        fails.append("%s [규격] 칸이 %dpx 다 — %dpx 여야 한다" % (name, cell, CELL))
        return
    palettes = []
    for r, frames in enumerate(rows):
        d = DIRS[r]
        alpha = {int(v) for f in frames for v in np.unique(f[..., 3])}
        if alpha - {0, 255}:
            fails.append("%s [%s] 알파 반투명 픽셀이 있다: %s"
                         % (name, d, sorted(alpha - {0, 255})[:4]))
        cut = [(i, clipped(f)) for i, f in enumerate(frames)]
        cut = [(i, n) for i, n in cut if n]
        if cut:
            fails.append("%s [%s] 그림이 칸을 넘었다 — 테두리에 닿은 픽셀 %s"
                         % (name, d, ", ".join("%d번 %dpx" % x for x in cut[:3])))
        bottoms = {int(np.flatnonzero(body(f).sum(1) > 0).max()) for f in frames}
        if len(bottoms) > 1:
            fails.append("%s [%s] 발밑 아랫줄이 프레임마다 다르다: %s"
                         % (name, d, sorted(bottoms)))
        palettes.append({tuple(int(x) for x in p[:3])
                         for f in frames for row in f for p in row if p[3] > 0})
        if cols < 2:
            continue
        ch = [change(frames[i], frames[(i+1) % cols]) for i in range(cols)]
        if min(ch) < CHANGE_MIN:
            fails.append("%s [%s] 죽은 프레임 — 이웃과 %.3f 밖에 안 다르다 (기준 %.2f 이상)"
                         % (name, d, min(ch), CHANGE_MIN))
        if max(ch) > CHANGE_MAX:
            fails.append("%s [%s] 프레임이 튄다 — %.3f (기준 %.2f 이하)"
                         % (name, d, max(ch), CHANGE_MAX))
        even = max(ch) / max(1e-9, min(ch))
        if even > EVEN_MAX:
            fails.append("%s [%s] 변화가 고르지 않다 — 최대÷최소 %.2f (기준 %.1f 이하)"
                         % (name, d, even, EVEN_MAX))
        if any(name.startswith("player_" + k) for k in HEAD_SKIP):
            continue                      # 팔이 머리 위로 가는 것이 이 모션의 내용이다
        head = (bands or {}).get(d)
        if head is None:
            op = body(frames[0])
            ys = np.flatnonzero(op.sum(1) > 0)
            top, bot = int(ys.min()), int(ys.max())
            nk = neck_row(op)
            head = slice(top, nk if nk is not None
                         else top + int((bot - top + 1) * HEAD_BAND))
        hd = tot = 0
        for i in range(1, cols):
            dd = (np.abs(frames[i][..., :3].astype(int) - frames[0][..., :3].astype(int)).max(2) > 24) \
                | (body(frames[i]) != body(frames[0]))
            hd += dd[head].sum(); tot += dd.sum()
        if tot and hd / tot > HEAD_MAX:
            fails.append("%s [%s] 머리가 움직인다 — 변화의 %.1f%% (기준 %.0f%% 이하)"
                         % (name, d, hd/tot*100, HEAD_MAX*100))
    # 방향끼리 색이 같은가 — 합집합이 한 방향 팔레트보다 많이 크면 갈린 것이다
    union = set().union(*palettes)
    biggest = max(len(p) for p in palettes)
    if len(union) > biggest * 1.35:
        fails.append("%s [색맞음] 방향끼리 팔레트가 다르다 — 합쳐 %d색, 한 방향 최대 %d색"
                     % (name, len(union), biggest))


## 이 검사가 맡는 파일. **`qa_sprite_check.py` 가 폴더를 훑을 때 이 목록을 그대로
## 불러다 건너뛴다**(2026-09-08, INBOX #58) — 두 곳에 패턴을 따로 적어두면, 여기
## 패턴에 안 걸리는 캐릭터 시트(예: 머리모양이 늘어 `player_idle_ponytail.png`)가
## 생겼을 때 양쪽에서 동시에 빠져 **아무도 안 보는 PNG** 가 된다.
def sheet_paths():
    return sorted(glob.glob(os.path.join(SPRITES, "player_*_farmer.png")))


def main():
    paths = sheet_paths()
    if not paths:
        print("[qa] FAIL — 검사할 캐릭터 시트가 없다 (%s)" % SPRITES)
        return 1
    fails = []
    bands = head_bands(paths)
    for p in paths:
        check(p, fails, bands)
    for f in fails:
        print("[qa] FAIL — %s" % f)
    print("[qa] 캐릭터 시트 %d장 — %s"
          % (len(paths), "전부 합격" if not fails else "불합격 %d건" % len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
