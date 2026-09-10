#!/usr/bin/env python3
"""ComfyUI 로 뽑은 캐릭터 그림 → 게임용 48px idle 시트.

**AI 그림을 자산으로 쓰는 첫 도구다** (2026-09-08 사람 결정). 그전 규칙은 "AI 는
참고 자료로만"이었는데, 손으로 찍은 48px 을 사람이 보고 "이거는 아니야" 라고
물렸다. 대신 지켜야 하는 것이 생겼다 — **그림을 주문할 때 그림자를 반드시 금지한다**
(`no shadow` / NEG 에 `drop shadow, cast shadow, ground shadow`). AI 가 발밑에 그려
넣는 바닥 그림자는 48px 에서 회색 옷과 색으로 구별되지 않아 **프로그램으로 뗄 수 없다**
(실제로 떼려다 회색 멜빵바지와 흰 셔츠가 같이 날아갔다).

**자세는 그림을 주문할 때 정한다 — 나중에 픽셀로 고치지 않는다.** 팔을 내린 자세로
그냥 주문하면 AI 가 손을 안 그리고 소매를 뭉갠다. 손을 얻으려고 팔을 벌려 뽑은 뒤
도트에서 팔을 내려봤는데, 위팔이 몸통에 묻혀 있어서 아래팔만 밀리고 어깨에 판자가
붙은 꼴이 됐다. 답은 프롬프트였다 — `arms straight down along the body` 와
`both hands visible, clear hands hanging at the sides` 를 **함께** 넣으면 팔을 내린
채로 손이 그려진다.

줄이는 순서가 중요하다 — **배경을 먼저 떼고, 캐릭터 픽셀만 평균 내어 줄인다.**
배경째 축소기(pyxelate 등)에 넣으면 테두리에서 배경색이 섞여 회색 후광이 낀다.

배치 규칙은 `game/scripts/player_frames.gd` 가 쥐고 있다 — 행 = 방향
(down/left/right/up), 열 = 프레임.
"""
from PIL import Image
import numpy as np
from collections import deque
import sys, os

CELL = 96          # 아트 한 칸. 씬 배율 1 → 화면 96px = 타일 두 칸
# **48 이 아니라 96 인 이유** (2026-09-08 사람 결정): 48px 로 줄이면 머리가 캐릭터의
# 1/4 이라 얼굴이 7px, 눈이 1px 이 되어 얼굴이 죽는다(실측). 1px 짜리 눈이 성립하려면
# **손으로 그 1px 을 찍어야** 하지, 큰 그림을 평균 내어 얻을 수 있는 것이 아니다.
# 칸을 96 으로 올리면 배율이 1 이 되므로 지형 아트도 48px(배율 1)로 같이 올렸다 —
# 도트 하나의 화면 크기가 서로 같아야 한다(STYLE_GUIDE 1번).
PAD = 1            # 외곽선이 들어갈 여백 (칸 테두리에 그림이 닿으면 선이 잘린다)
FIG = 72           # **칸 안에서 인물이 차지하는 키(px).** 칸(96)과 따로 있는 값이다.
# 2026-09-10 (`DESIGN_QUEUE #d1`) 에 96 → 72 로 내렸다. 칸은 96 그대로다 —
# 인물이 72 가 되면 **24px 이 남고, 그 여유가 가로로 넓은 도구를 받는다**(총·낚싯대).
# 전에는 인물이 칸을 세로로 꽉 채워서(94 + 외곽선 2 = 96) 가로가 세로보다 넓어지는
# 순간 `_grid()` 가 세로를 깎았고, 그래서 **낫만 87px 로 작아졌다**(INBOX #72).
# 화면에서는 1080p 세로의 8.9% → **6.7%** 가 된다(`DESIGN.md` 「카메라 / 해상도」).
COLORS = 32        # 팔레트 크기 — 이보다 많으면 도트가 아니라 「축소한 그림」이 된다.
                   # 96px 칸은 48px 때(16색)보다 넓고, 게다가 **시트 한 장의 프레임
                   # 전부가 이 한 팔레트를 나눠 쓰므로**(`quantize_all`) 더 준다.
INK = (26, 15, 24)
DIRS = ["down", "left", "right", "up"]


def _flood(mask):
    """칸 테두리에서 `mask` 를 타고 흘려 채운 자리."""
    H, W = mask.shape
    seen = np.zeros((H, W), bool)
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    for y in range(H):
        for x in (0, W - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for b, c in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
            if 0 <= b < H and 0 <= c < W and mask[b, c] and not seen[b, c]:
                seen[b, c] = True; q.append((b, c))
    return seen


def cutout(path):
    """배경을 뗀다 — **배경색과의 거리**로 잡는다.

    채도로 잡으면 안 된다: 회색 멜빵바지와 흰 셔츠가 같이 날아간다(실측).
    배경색은 네 귀퉁이에서 읽고, 테두리 한 줄이 다 지워질 때까지 허용 오차를 넓힌다.
    """
    src = Image.open(path).convert('RGB')
    a = np.asarray(src).astype(int)
    k = 12
    corners = np.concatenate([a[:k, :k].reshape(-1, 3), a[:k, -k:].reshape(-1, 3),
                              a[-k:, :k].reshape(-1, 3), a[-k:, -k:].reshape(-1, 3)])
    bg = np.median(corners, axis=0)
    seen = None
    for tol in (34, 48, 64, 84):
        near = np.abs(a - bg).max(2) < tol
        seen = _flood(near)
        if seen[0].mean() + seen[-1].mean() + seen[:, 0].mean() + seen[:, -1].mean() > 3.9:
            break
    return src, ~(seen | _trapped_bg(near, seen))


def _trapped_bg(near, seen):
    """테두리에서 못 흘러간 배경 — **큰 덩어리만** 배경으로 친다.

    두 신발이 맞닿으면 그 위의 다리 사이 틈이 막혀 안 지워지고, 96px 로 줄면서
    **가랑이에 회색 기둥**이 선다(2026-09-08, INBOX #56).

    **그렇다고 「배경색이면 다 배경」으로 하면 안 된다.** 그늘진 흰 셔츠와 피부가
    배경 회색에서 34 안에 들어와서, 옷과 얼굴에 구멍이 숭숭 뚫리고 `add_ink()` 가
    그 구멍마다 테두리를 둘러 **검은 반점**이 됐다(실측). 크기로 가른다 — 갇힌
    덩어리를 재보면 가랑이는 746·990px 인데 그 다음이 93px 이라 사이가 넓다.
    """
    from skimage import measure
    holes = near & ~seen
    lab = measure.label(holes, connectivity=1)
    if lab.max() == 0:
        return np.zeros_like(holes)
    big = np.bincount(lab.ravel()) >= max(60, round(0.0002 * near.size))
    big[0] = False
    return big[lab]


def add_ink(body, ink=INK):
    """새 실루엣 둘레에 1px 테두리를 두른다."""
    op = body[..., 3] > 0
    H, W = op.shape
    out = body.copy()
    for y in range(H):
        for x in range(W):
            if op[y, x]:
                continue
            if any(0 <= b < H and 0 <= c < W and op[b, c]
                   for b, c in ((y-1, x), (y+1, x), (y, x-1), (y, x+1))):
                out[y, x, :3] = ink; out[y, x, 3] = 255
    return out


def _grid(keep, cell, pad, box, fig=None):
    """축소 격자 — (자를 상자, 세로칸, 가로칸, 칸 안 왼쪽 여백, 칸 안 위 여백).

    **색과 라벨이 같은 격자를 써야 한다** — 한 칸이라도 어긋나면 「이 픽셀이 무슨
    재질인가」가 옆 픽셀 것이 되어 색 바꿔치기가 엉뚱한 자리를 칠한다.

    `fig` 는 **칸 안에서 인물이 차지할 키**다(기본 `FIG`). 세로는 여기에 맞추고,
    가로는 비율대로 따라가되 **칸을 넘지 않는다** — 그래서 `fig < cell` 인 만큼이
    가로로 넓은 도구가 들어갈 여유가 된다. `fig=cell` 이면 옛 동작(칸을 꽉 채움)이다.

    **발밑은 `fig` 와 무관하게 늘 칸의 아랫줄이다** (`cell - pad`). 위 여백만
    늘어난다 — `player_frames.feet_y()` 가 아랫줄을 발밑으로 믿기 때문이다.
    """
    if box is None:
        ys, xs = np.where(keep)
        box = (int(ys.min()), int(ys.max()) + 1, int(xs.min()), int(xs.max()) + 1)
    y0, y1, x0, x1 = box
    ch, cw = y1 - y0, x1 - x0
    th = (cell if fig is None else fig) - 2*pad
    tw = max(1, round(cw * th / ch))
    if tw > cell - 2*pad:
        tw = cell - 2*pad; th = max(1, round(ch * tw / cw))
    return box, th, tw, (cell - tw)//2, (cell - pad) - th


def downscale(rgb, keep, cell=CELL, pad=PAD, box=None, fig=FIG):
    """큰 그림 → 칸 크기의 RGBA. **색은 아직 줄이지 않는다.**

    색 줄이기(양자화)를 프레임마다 따로 하면 팔레트가 조금씩 달라져서 **모든 픽셀이
    미세하게 변한다** — 한 시트 안에서 그건 걷기가 아니라 깜빡임이다(실측: 프레임
    사이 차이가 56%까지 나왔다). 그래서 축소와 양자화를 나눠두고, 양자화는
    `quantize_all()` 이 **시트 한 장을 한 팔레트로** 한 번에 한다.
    """
    a = np.asarray(rgb).astype(float)
    # **여러 프레임을 구울 때는 같은 `box` 를 넘긴다** — 프레임마다 제 몸에 맞춰 자르면
    # 다리를 들 때 축소 배율이 달라져 캐릭터가 프레임마다 들썩인다.
    box, th, tw, ox, oy = _grid(keep, cell, pad, box, fig)
    y0, y1, x0, x1 = box
    a = a[y0:y1, x0:x1]
    k = keep[y0:y1, x0:x1].astype(float)
    ch, cw = k.shape
    small = np.zeros((th, tw, 4), np.uint8)
    for y in range(th):
        for x in range(tw):
            ya, yb = int(y*ch/th), max(int(y*ch/th)+1, int((y+1)*ch/th))
            xa, xb = int(x*cw/tw), max(int(x*cw/tw)+1, int((x+1)*cw/tw))
            w = k[ya:yb, xa:xb]
            if w.sum() < 0.5 * w.size:       # 절반 넘게 배경이면 빈 칸
                continue
            # **알파 가중 평균** — 배경색이 섞이지 않는 것이 요점이다
            small[y, x, :3] = ((a[ya:yb, xa:xb] * w[..., None]).sum((0, 1)) / w.sum()).round()
            small[y, x, 3] = 255
    out = np.zeros((cell, cell, 4), np.uint8)
    out[oy:oy+th, ox:ox+tw] = small
    return out


def downscale_labels(labels, keep, cell=CELL, pad=PAD, box=None, top=255, fig=FIG):
    """재질 라벨(정수) → 칸 크기. **`downscale()` 과 같은 격자에서 최빈값**을 고른다.

    색은 평균이 맞지만 라벨은 평균이 뜻이 없다 — 피부 3px 과 옷 1px 의 「평균」은
    아무 재질도 아니다. 블록에서 **가장 넓은 재질**이 그 도트의 재질이다.
    """
    box, th, tw, ox, oy = _grid(keep, cell, pad, box, fig)
    y0, y1, x0, x1 = box
    lab = np.asarray(labels)[y0:y1, x0:x1]
    k = keep[y0:y1, x0:x1]
    ch, cw = k.shape
    small = np.zeros((th, tw), np.uint8)
    for y in range(th):
        for x in range(tw):
            ya, yb = int(y*ch/th), max(int(y*ch/th)+1, int((y+1)*ch/th))
            xa, xb = int(x*cw/tw), max(int(x*cw/tw)+1, int((x+1)*cw/tw))
            w = k[ya:yb, xa:xb]
            if w.sum() < 0.5 * w.size:
                continue
            v = lab[ya:yb, xa:xb][w]
            v = v[v > 0]
            if v.size:
                small[y, x] = np.bincount(v, minlength=top + 1).argmax()
    out = np.zeros((cell, cell), np.uint8)
    out[oy:oy+th, ox:ox+tw] = small
    return out


def quantize_all(cells, colors=COLORS, ref_cells=None):
    """칸 여러 장을 **한 팔레트로** 함께 색을 줄이고 테두리를 두른다.

    `ref_cells` 를 주면 **그 칸들에서만 팔레트를 뽑아** 전체에 씌운다. 방향마다 그림을
    따로 뽑으면 옷 색이 조금씩 다르게 나오는데(뒷모습이 청바지가 되는 식 — 실측),
    정면의 팔레트를 강제하면 없는 색이 가장 가까운 색으로 끌려와 방향끼리 색이 맞는다.
    """
    if not cells:
        return []
    h, w = cells[0].shape[:2]
    base = ref_cells if ref_cells else cells
    pal = Image.fromarray(np.concatenate([c[..., :3] for c in base], axis=1)) \
        .quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE)
    strip = np.concatenate([c[..., :3] for c in cells], axis=1)
    flat = np.asarray(Image.fromarray(strip).quantize(palette=pal, dither=Image.NONE)
                      .convert('RGB'))
    out = []
    for i, c in enumerate(cells):
        q = c.copy()
        q[..., :3] = flat[:, i*w:(i+1)*w]
        q[c[..., 3] == 0] = 0
        out.append(add_ink(q))
    return out


def to_cell(rgb, keep, cell=CELL, pad=PAD, colors=COLORS, box=None, fig=FIG):
    """큰 그림 한 장 → 칸 하나 (축소 + 색 줄이기 + 테두리)."""
    return quantize_all([downscale(rgb, keep, cell, pad, box, fig)], colors)[0]


def shrink(path, cell=CELL, pad=PAD, colors=COLORS):
    """그림 파일 한 장 → 칸 하나."""
    src, keep = cutout(path)
    return to_cell(src, keep, cell, pad, colors)


def build(sources, out_path, cell=CELL):
    """방향별 그림 → idle 시트 한 장 (48 × 192).

    `sources` 는 `{방향: 그림경로}`. **없는 방향은 down 을 그대로 쓴다** — 방향별
    그림이 다 갖춰지기 전에도 게임이 돌아가야 하기 때문이다.
    """
    cells = {}
    for d, p in sources.items():
        cells[d] = shrink(p, cell)
        print(f"  {d}: {os.path.basename(p)} → {cell}px")
    sheet = np.zeros((cell*len(DIRS), cell, 4), np.uint8)
    for r, d in enumerate(DIRS):
        sheet[r*cell:(r+1)*cell] = cells.get(d, cells["down"])
    Image.fromarray(sheet, 'RGBA').save(out_path)
    print(f"{os.path.basename(out_path)}: {cell}x{cell*len(DIRS)}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("쓰기: gen_player.py <down.png> [left.png] [up.png]")
    src = {"down": sys.argv[1]}
    if len(sys.argv) > 2: src["left"] = sys.argv[2]
    if len(sys.argv) > 3: src["up"] = sys.argv[3]
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build(src, os.path.join(here, "assets", "sprites", "player_idle_farmer.png"))
