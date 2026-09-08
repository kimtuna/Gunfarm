#!/usr/bin/env python3
"""4방향 시트 한 장 → **부품으로 나눈 리그**. 모든 모션을 여기서 조립한다.

왜 이렇게 하는가 (2026-09-08 사람 결정):
    도구 7종 × 4방향 × (들고있기/사용/걷기) 면 시트가 90장이 넘는다. 그림을 매번
    주문해서는 **같은 캐릭터로 일관되게 못 뽑는다** — 오늘 실측으로 확인했다
    (ControlNet 으로 걷기 6프레임을 뽑았더니 프레임 사이 차이의 28%가 머리에 있었다:
    셔츠 색과 그림자가 프레임마다 변했다). 부품을 한 번 잘라두고 **관절 각도만 바꿔**
    조립하면 그 문제가 정의상 사라진다 — 같은 픽셀을 옮기는 것뿐이기 때문이다.

**회전이 도트를 안 뭉개는 이유 — 순서가 전부다:**
    1024px 원본에서 자르고, 1024px 에서 돌리고 옮긴 뒤, **맨 마지막에** 96px 로
    줄이면서 색을 줄인다. 도트는 그 마지막 한 번에서만 만들어지므로 회전 각도가
    아무리 어중간해도 결과는 깨끗한 도트다. (96px 도트를 직접 돌리면 뭉갠다.)

부품을 나누는 방법:
    뼈대를 **우리가 만들었으므로 관절 좌표를 이미 안다** — 그림에서 찾을 필요가 없다.
    각 픽셀을 가장 가까운 뼈에 준다(선분까지의 거리). T자는 팔이 몸통에서 멀리
    떨어져 있어 이 단순한 규칙이 잘 듣는다.
"""
from PIL import Image
import numpy as np
import math, os, sys

## 리그 원본과 그 그림을 그릴 때 쓴 뼈대의 팔 각도.
##
## **T자가 아니라 「팔 내린」 그림을 쓴다** (2026-09-08). T자로 해봤더니 idle 을 만들려고
## 팔을 90도 돌리는 순간 어깨가 망가졌다 — 소매는 **가로로 뻗은 팔에 맞게** 그려진
## 곡선이라, 세로로 세우면 그 곡선이 어깨에 홈을 낸다(사람이 "어깨가 몸에 말려
## 들어간 것 같다"고 한 것). 팔을 내린 그림을 쓰면 **가장 많이 보이는 자세(idle·정면
## 걷기)의 회전이 0도**가 되고, 옆모습 걷기도 ±14도뿐이다. 도구 자세처럼 팔을 크게
## 드는 것만 큰 회전을 쓴다.
SOURCE = "~/ComfyUI/output/ip4_00001_.png"
SOURCE_ARM_DEG = 10.0

## **4방향을 한 장에 받은 시트**(`game/tools/comfy.py` 가 주문한다)를 쓴다.
## 방향마다 따로 뽑으면 같은 씨앗을 써도 캐릭터가 달라진다 — 머리색·옷 모양·몸 비율이
## 전부 어긋났다(2026-09-08 실측, `docs/CHARACTER.md` 「4방향을 한 장에 받는다」).
## 배치는 `comfy.SHEET_CELLS` 와 **반드시 같아야 한다** — 어긋나면 엉뚱한 자리를 자른다.
##
## **저장소 안에 둔다.** `~/ComfyUI/output/` 만 가리키면 그 폴더를 비우는 순간 캐릭터를
## 다시 못 굽는다 — 리그의 원본은 자산이지 임시 파일이 아니다.
## 지금 것: 2026-09-08 INBOX #56 에서 `comfy.py` 의 기본 프롬프트로 씨앗 여섯 개를
## 뽑아 고른 장(seed 5555). 고른 이유는 `docs/STATUS.md` 와 `docs/CHARACTER.md` 3-b 에 있다.
SHEET = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "docs", "design_reference", "farmer_sheet4.png")

## 방향마다 원본이 다르다 — 옆·뒷모습은 그 방향으로 그려진 그림이어야 한다.
## **`right` 는 `left` 를 좌우반전해 쓴다** — 게임의 정석이고, 두 장을 따로 뽑으면
## 캐릭터가 미묘하게 달라진다(같은 씨앗을 써도 뼈대가 바뀌면 달라진다 — 실측).
## 없는 방향은 `down` 으로 대신한다.
##
## **옷을 프롬프트에 못 박아야 한다.** 안 그러면 정면만 반바지고 옆·뒤는 긴바지로
## 나온다(사람 지적, 2026-09-08). 색이 갈리는 것은 `quantize_all(ref_cells=...)` 로
## 정면 팔레트를 씌워 맞출 수 있지만, **옷의 모양이 갈리는 것은 다시 뽑는 수밖에 없다.**
## **옛 길이다 — 지금은 안 쓴다** (2026-09-08, INBOX #56). `build_sheets()` 는 위
## `SHEET` 한 장을 쓴다. 아래는 방향마다 그림을 따로 뽑던 때의 잔재이고, 그 방식이
## 왜 실패했는지는 `docs/CHARACTER.md` 3-b 에 있다 — **되살리지 말 것.**
## (`load()` 는 한 인물짜리 그림을 시험해 볼 때 여전히 쓸 수 있어서 남겨둔다.)
SOURCES = {
    "down": SOURCE,
    "up":   "~/ComfyUI/output/pt5_00001_.png",
    "left": "~/ComfyUI/output/pt1_00001_.png",
}


# ── 뼈대 ────────────────────────────────────────────────────────────────────
# `pose.py` 가 ControlNet 에 넘긴 것과 **같은 값이어야 한다** — 그림이 이 뼈대를
# 보고 그려졌으므로, 여기가 어긋나면 엉뚱한 자리에서 자른다.
def joints(cx=512, top=180, h=680, heads=3.6, arm_deg=90.0):
    H = h/heads
    nose = top + H*0.50; neck = top + H*1.00
    hip = top + h*0.62; knee = top + h*0.81; foot = top + h*1.00
    sw = h*0.105; hw = h*0.070; up, fo = h*0.155, h*0.135
    t = math.radians(arm_deg); dx, dy = math.sin(t), math.cos(t)
    J = {}
    J['head']  = (cx, nose - H*0.35)
    J['nose']  = (cx, nose)
    J['neck']  = (cx, neck)
    J['shoulderR'] = (cx+sw, neck);  J['shoulderL'] = (cx-sw, neck)
    J['elbowR'] = (cx+sw+up*dx, neck+up*dy)
    J['handR']  = (J['elbowR'][0]+fo*dx, J['elbowR'][1]+fo*dy)
    J['elbowL'] = (cx-sw-up*dx, neck+up*dy)
    J['handL']  = (J['elbowL'][0]-fo*dx, J['elbowL'][1]+fo*dy)
    J['hipC']   = (cx, hip - h*0.02)
    J['hipR'] = (cx+hw, hip); J['hipL'] = (cx-hw, hip)
    J['kneeR'] = (cx+hw, knee); J['footR'] = (cx+hw, foot)
    J['kneeL'] = (cx-hw, knee); J['footL'] = (cx-hw, foot)
    return J

## 부품 = (이름, 뼈의 두 끝, 부모 부품, 도는 축, **뼈에서 뻗을 수 있는 반경**).
##
## **반경이 핵심이다.** 그냥 "가장 가까운 뼈"로 나누면 위팔이 가슴을 절반 먹는다
## (어깨 관절이 가슴 바로 옆이라 그렇다) — 그 상태로 팔을 내리면 몸통에 구멍이 난다.
## 팔다리는 제 굵기만큼만 가져가게 막고, 남는 픽셀은 몸통·머리가 받는다
## (그 둘은 반경이 없다 = 제한 없음).
##
## **값은 원본의 자세에 달렸다.** T자에서는 뼈가 팔의 위아래 한가운데를 지나므로
## 반경이 팔 두께의 절반이면 되지만, 팔을 내린 자세에서는 뼈가 팔의 좌우 한가운데를
## 지난다 — 지금 값(34/30)은 후자 기준이다. 너무 크게 잡으면 팔이 가슴을 물고 가서
## 옆모습 걷기에서 셔츠가 팔을 따라 흔들린다.
##
## **반경은 픽셀이 아니라 「키에 대한 비율」이다** (2026-09-08, INBOX #56). 처음엔
## 34/30/78 px 로 적혀 있었는데 그 값은 **키 680px 짜리 그림 한 장 기준**이었다.
## 4방향을 한 장에 받으면서 한 인물의 키가 420px 이 됐고(`comfy.FIG_H`), 같은 픽셀
## 값을 그대로 쓰면 반경이 몸에 비해 1.6배가 되어 위팔이 가슴을 문다. 비율로 적어두면
## 캔버스나 인물 크기가 바뀌어도 따라온다 — `split()` 이 키를 곱한다.
RIG_H = 680.0                     # 아래 비율을 잰 기준 키
PARTS = [
    ("armL_upper", ("shoulderL", "elbowL"), None,          "shoulderL", 34/RIG_H),
    ("armL_lower", ("elbowL", "handL"),     "armL_upper",  "elbowL",    30/RIG_H),
    ("armR_upper", ("shoulderR", "elbowR"), None,          "shoulderR", 34/RIG_H),
    ("armR_lower", ("elbowR", "handR"),     "armR_upper",  "elbowR",    30/RIG_H),
    ("legL_upper", ("hipL", "kneeL"),       None,          "hipL",      78/RIG_H),
    ("legL_lower", ("kneeL", "footL"),      "legL_upper",  "kneeL",     78/RIG_H),
    ("legR_upper", ("hipR", "kneeR"),       None,          "hipR",      78/RIG_H),
    ("legR_lower", ("kneeR", "footR"),      "legR_upper",  "kneeR",     78/RIG_H),
    ("torso",      ("neck", "hipC"),        None,          "hipC",      None),
    ("head",       ("head", "neck"),        None,          "neck",      None),
]
## 그리는 순서 — 몸통보다 앞에 오는 것이 뒤에 온다(팔이 몸을 가린다).
Z_ORDER = ["legL_upper", "legL_lower", "legR_upper", "legR_lower",
           "torso", "armL_upper", "armL_lower", "armR_upper", "armR_lower", "head"]

## 도구는 **부품 하나다 — 아래팔의 자식** (2026-09-08, INBOX #66 (2)).
## 손 좌표에 얹고 끝내면 팔이 도는 동안 도끼가 제자리에 뜬 채로 남는다. 사슬에
## 매달아두면 `compose()` 가 팔 변환을 그대로 물려주므로 **자루가 팔과 따로 놀 수가
## 없다** — 새로 쓴 코드가 아니라 이미 있는 규칙(자식은 부모를 물려받는다)이다.
TOOL_PART = ("tool", None, "armR_lower", "handR", None)

## **뒷모습에서는 도구가 몸 뒤로 간다** (INBOX #66 (3)). 뒤에서 본 사람이 앞으로 든
## 도구는 몸에 가려야 자연스럽다. 그렇다고 통째로 숨기지는 않는다 — 손이 몸 밖에
## 있어서 자루와 머리는 어깨 옆·위로 그대로 보인다(`DESIGN.md` 「새 도구를 추가하는
## 절차」 5: *"뒷모습에서 도구가 몸에 완전히 가려지면 무엇을 들었는지 알 수 없다"*).
TOOL_BEHIND = ("up",)


def _seg_dist(px, py, a, b):
    """점에서 선분까지의 거리."""
    ax, ay = a; bx, by = b
    vx, vy = bx-ax, by-ay
    L = vx*vx + vy*vy
    t = 0.0 if L == 0 else np.clip(((px-ax)*vx + (py-ay)*vy) / L, 0.0, 1.0)
    return np.hypot(px - (ax+t*vx), py - (ay+t*vy))


def strip_outline(a, width=6):
    """실루엣 가장자리 `width` 줄을 벗긴다.

    **자르기 전에 반드시 해야 한다.** 안 하면 소매 위아래를 따라가던 외곽선이 위팔
    부품에 딸려가고, 팔을 90도 돌리는 순간 그 선이 세로로 서서 **어깨 한복판에 박힌다**
    (사람이 "어깨가 몸에 말려 들어간 것 같다"고 지적한 것이 이것이다).
    테두리는 부품을 합친 뒤 `add_ink()` 가 새 실루엣에 다시 두른다.
    """
    from scipy import ndimage
    op = a[..., 3] > 0
    inner = ndimage.binary_erosion(op, iterations=width)
    out = a.copy()
    out[~inner] = 0
    return out


def split(img_rgba, J, h=RIG_H):
    """그림을 부품별 레이어로 나눈다. 픽셀마다 **가장 가까운 뼈**에 준다.

    `h` 는 **그 그림 속 인물의 키**다 — 반경이 비율로 적혀 있어서 여기서 픽셀이 된다.
    """
    a = np.asarray(img_rgba)
    H, W = a.shape[:2]
    ys, xs = np.mgrid[0:H, 0:W]
    best = np.full((H, W), np.inf); who = np.full((H, W), -1, np.int8)
    for i, (name, (p, q), _, _, r) in enumerate(PARTS):
        d = _seg_dist(xs, ys, J[p], J[q])
        if r is not None:
            d = np.where(d > r*h, np.inf, d)   # 제 굵기 밖으로는 안 뻗는다
        m = d < best
        best = np.where(m, d, best); who[m] = i
    layers = {}
    for i, (name, _, _, _, _) in enumerate(PARTS):
        lay = np.zeros_like(a)
        m = (who == i) & (a[..., 3] > 0)
        lay[m] = a[m]
        layers[name] = Image.fromarray(lay, 'RGBA')
    return layers


# ── 조립 ────────────────────────────────────────────────────────────────────
def _mat(pivot, rot=0.0, scale=1.0, dy=0.0, dx=0.0):
    """축을 중심으로 크기 → 회전 → 이동. 3×3 동차 행렬."""
    cx, cy = pivot
    t = math.radians(rot)
    c, s = math.cos(t), math.sin(t)
    A = np.array([[ c*scale, s*scale, 0.0],
                  [-s*scale, c*scale, 0.0],
                  [0.0, 0.0, 1.0]])
    T1 = np.array([[1.0, 0, -cx], [0, 1.0, -cy], [0, 0, 1.0]])
    T2 = np.array([[1.0, 0, cx+dx], [0, 1.0, cy+dy], [0, 0, 1.0]])
    return T2 @ A @ T1


def _apply(img, M):
    """행렬로 레이어를 옮긴다. **NEAREST** 로 알파를 0/255 로 유지한다 —
    부드럽게 만드는 것은 마지막 축소가 알아서 한다."""
    if np.allclose(M, np.eye(3)):
        return img
    Mi = np.linalg.inv(M)                  # PIL 은 「출력→입력」 사상을 받는다
    return img.transform(img.size, Image.AFFINE,
                         tuple(Mi[0]) + tuple(Mi[1]), resample=Image.NEAREST)


def _chain(layers, behind=False):
    """이번 장에 그릴 부품들의 (부모·축) 표와 그리는 순서.

    `layers` 에 `tool` 이 있으면 **아래팔의 자식**으로 사슬에 끼운다(`TOOL_PART`).
    `behind` 면 맨 뒤에 그린다 — 뒷모습에서 도구가 몸에 가리는 자리다.
    """
    parts = list(PARTS)
    order = list(Z_ORDER)
    if "tool" in layers:
        parts.append(TOOL_PART)
        order = ["tool"] + order if behind else order + ["tool"]
    return {n: (par, piv) for n, _, par, piv, _ in parts}, order


def compose(layers, J, xf, behind=False):
    """부품 변환 → 한 장.

    `xf` 는 `{부품이름: {"rot":도, "scale":배, "dy":px, "dx":px}}`.
    **자식은 부모 변환을 그대로 물려받는다** — 위팔을 내리면 아래팔과 손이 따라간다.
    변환을 전부 **원본 좌표계에서** 정의하고 뿌리부터 곱하므로, 축이 옮겨진 자리를
    따로 계산할 필요가 없다.

    **회전은 옆모습용이고, 정면·뒷모습은 `scale`·`dy` 를 쓴다.** 정면으로 걸어오는
    것은 팔다리가 좌우가 아니라 **깊이 축**으로 흔들리는 것이라, 화면에서는 회전이
    아니라 「앞으로 나온 것은 조금 아래·조금 크게」로 그려야 한다. 회전으로 그리면
    팔벌려뛰기가 된다(사람 지적, 2026-09-08).
    """
    size = next(iter(layers.values())).size
    out = Image.new('RGBA', size, (0, 0, 0, 0))
    meta, order = _chain(layers, behind)
    for name in order:
        chain = []
        n = name
        while n is not None:
            par, piv = meta[n]
            chain.append((n, piv))
            n = par
        M = np.eye(3)
        for nm, piv in chain:                 # 자신 → 부모 → 뿌리 순으로 왼쪽에 곱한다
            t = xf.get(nm) or {}
            M = _mat(J[piv], t.get("rot", 0.0), t.get("scale", 1.0),
                     t.get("dy", 0.0), t.get("dx", 0.0)) @ M
        out.alpha_composite(_apply(layers[name], M))
    return out


def render(layers, J, xf, cell=96):
    """부품 변환 → 게임용 칸 하나. **줄이는 것은 여기 한 번뿐이다.**"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_player import to_cell
    big = compose(layers, J, xf)
    a = np.asarray(big)
    return to_cell(Image.fromarray(a[..., :3]), a[..., 3] > 0, cell=cell)


def load(path=None, arm_deg=None):
    """캐릭터 그림 → (부품 레이어, 관절). `arm_deg` 는 **그 그림을 그릴 때 쓴 뼈대**의 값이다."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_player import cutout
    src, keep = cutout(os.path.expanduser(path or SOURCE))
    rgba = np.dstack([np.asarray(src), (keep*255).astype(np.uint8)])
    J = joints(arm_deg=SOURCE_ARM_DEG if arm_deg is None else arm_deg)
    return split(Image.fromarray(strip_outline(rgba), 'RGBA'), J), J


# ── 모션 ────────────────────────────────────────────────────────────────────
# 원본이 이미 「팔 내린」 자세이므로 idle 은 **회전 0도**다 — 어깨가 망가질 일이 없다.
ARM_DOWN_L, ARM_DOWN_R = 0.0, 0.0


def idle():
    return [{}]        # 원본 그대로가 곧 idle 이다


## 걸음 한 바퀴 6프레임 — 왼다리가 앞으로 나간 정도(-1~+1).
## **여섯 값이 모두 달라야 한다.** 사인으로 만들면 sin(60°)=sin(120°) 이라 두 쌍이
## 같은 그림이 되고, 앞뒤 0 을 두 번 넣어도 그 두 장이 같아진다 — 오늘 이 실수를
## 세 번 했다(`qa_sprite_check.py` 의 「이어짐」이 "죽은 프레임"으로 잡는 자리다).
STRIDE = [1.0, 0.55, -0.15, -1.0, -0.55, 0.15]


def walk_front(thigh=15.0, knee=36.0, knee_bend=0.13, grow=0.02,
               shoulder=6.0, elbow=20.0, elbow_bend=0.10, arm_grow=0.03):
    """정면(또는 뒷모습) 걷기 — **회전이 아니라 원근 축약**이다.

    좌우로 벌리면 걷는 게 아니라 팔벌려뛰기로 보인다(사람 지적, 2026-09-08).
    정면으로 걸어오는 것은 팔다리가 **깊이 축**으로 흔들리는 것이라, 화면에서는
    「흔드는 발이 뜬다 · 앞으로 나온 쪽이 조금 크다」로 그린다.

    **큰 동작은 무릎과 팔꿈치가 한다** (사람 지적). 어깨와 허벅지만 움직이면 몸이
    통나무처럼 보인다 — 실제로 걷을 때 화면에서 제일 많이 움직이는 것은 정강이와
    아래팔이다. 그래서 `thigh` < `knee`, `shoulder` < `elbow` 로 둔다. 굽힌 정강이는
    카메라 쪽으로 접히므로 **짧아 보인다**(`knee_bend` 만큼 줄인다).

    **딛는 발은 절대 안 움직인다.** 처음엔 앞다리를 아래로 내렸는데, 그러면 실루엣의
    아랫줄이 프레임마다 바뀌고 발을 맞추느라 **몸 전체가 밀려서 머리가 흔들렸다**
    (실측: 프레임 간 변화의 36%가 머리에 있었다). 한쪽만 들면 아랫줄이 그대로다.
    """
    out = []
    for s in STRIDE:
        l, r = max(0.0, s), max(0.0, -s)          # 뜨는 쪽만 든다
        out.append({
            # 팔은 같은 쪽 다리와 **반대**로 나간다 (걷기의 기본)
            "armL_upper": {"dy": -shoulder*s, "scale": 1 - arm_grow*s},
            "armL_lower": {"dy": -elbow*s,    "scale": 1 - elbow_bend*s},
            "armR_upper": {"dy":  shoulder*s, "scale": 1 + arm_grow*s},
            "armR_lower": {"dy":  elbow*s,    "scale": 1 + elbow_bend*s},
            "legL_upper": {"dy": -thigh*l, "scale": 1 + grow*l},
            "legL_lower": {"dy": -knee*l,  "scale": 1 - knee_bend*l},
            "legR_upper": {"dy": -thigh*r, "scale": 1 + grow*r},
            "legR_lower": {"dy": -knee*r,  "scale": 1 - knee_bend*r},
        })
    return out


def walk_side(hip=10.0, knee=30.0, shoulder=9.0, elbow=26.0):
    """옆모습 걷기 — 이쪽은 **회전이 맞다**. 깊이 축이 곧 화면의 좌우이기 때문이다.

    정면과 같은 두 원칙을 지킨다:
      - **큰 동작은 무릎과 팔꿈치가 한다** (`hip` < `knee`, `shoulder` < `elbow`).
      - **딛는 발은 안 움직인다.** 처음엔 두 다리를 다 돌렸는데, 그러면 두 발이 다
        떠서 실루엣 아랫줄이 바뀌고, 발을 맞추느라 몸 전체가 밀려 **머리가 흔들렸다**
        (실측 10%). 정면에서 겪은 것과 같은 실수다.
    무릎과 팔꿈치는 **한쪽으로만 접힌다**(사람 관절이 그렇다).
    """
    out = []
    for s in STRIDE:
        l, r = max(0.0, s), max(0.0, -s)          # 흔드는 쪽만 돈다
        out.append({
            # 두 팔은 서로 **반대**로 흔든다 (옆에서 보면 앞팔과 뒷팔이 갈린다)
            "armL_upper": {"rot": -shoulder*s},
            "armL_lower": {"rot": max(0.0, -elbow*s)},
            "armR_upper": {"rot":  shoulder*s},
            "armR_lower": {"rot": max(0.0,  elbow*s)},
            "legL_upper": {"rot": -hip*l},
            "legL_lower": {"rot":  knee*l},
            "legR_upper": {"rot": -hip*r},
            "legR_lower": {"rot":  knee*r},
        })
    return out


## 도구 목록 — `game/scripts/player_frames.gd` 의 `TOOLS` 와 같아야 한다.
## **도구가 늘면 여기 한 줄만 늘린다.** 자세는 도구마다 다르지 않다(지금은) —
## 「든다 / 휘두른다」 두 동작이고, 도구 그림은 손 위치에 얹는다.
TOOLS = ["axe", "pickaxe", "sickle", "gun", "hoe", "watering_can", "fishing_rod"]

## 사용 모션이 없는 도구 (`DESIGN.md` 「생활 스킬」 — 낚싯대의 피드백은 자세가 아니라
## 찌가 날아가는 것이다). `player_frames.gd` 의 `NO_USE_TOOLS` 와 같아야 한다.
NO_USE = ["fishing_rod"]

## 휘두르기 한 바퀴 — 들어올렸다(-1) 내려친다(+1). **여섯 값이 모두 달라야 한다.**
SWING = [-1.0, -0.5, 0.3, 1.0, 0.55, -0.25]


## 도구를 든 팔 (정면·뒷모습). **여기만 정면에서도 회전을 쓴다.**
## 정면 걷기가 회전을 금지하는 것은 「깊이 축의 흔들림을 회전으로 그리면
## 팔벌려뛰기가 된다」는 이유인데, 도구를 든 자세는 깊이가 아니라 **화면 안에서
## 실제로 어깨를 벌리고 팔꿈치를 접는 것**이다. 그리고 접지 않으면 안 된다
## (2026-09-08, INBOX #66 실측): 팔을 곧게 내린 채로는 자루가 팔뚝과 **같은 선 위에
## 서서** 팔을 통째로 덮는다 — 손이 어디인지 안 보이니 「쥐고 있다」가 아니라
## 「팔에 판자를 붙였다」로 읽힌다. 팔꿈치를 접으면 팔과 자루가 손에서 갈라지는
## **V 자**가 되고, 그 갈라짐이 곧 손이다. (옛 17px 생성기가 `reach` 로 손만
## 한 칸 밀면 됐던 것은 거기서 손이 1px 짜리 점이었기 때문이다 —
## `docs/STYLE_GUIDE.md` 「도구를 든 손은 몸에서 한 칸 바깥으로 내보낸다」.)
HOLD_OUT, HOLD_ELBOW, HOLD_RAISE, HOLD_GROW = 10.0, 34.0, 18.0, 0.05


def hold_front():
    """도구를 든 자세 (정면·뒷모습). **오른팔만 든다** — 도구는 오른손에 쥔다."""
    return {"armR_upper": {"rot": HOLD_OUT, "dy": -HOLD_RAISE, "scale": 1 + HOLD_GROW},
            "armR_lower": {"rot": HOLD_ELBOW, "scale": 1 + HOLD_GROW}}


def hold_side(shoulder=-32.0, elbow=-24.0):
    """도구를 든 자세 (옆모습). 이쪽은 회전이다 — 팔을 앞으로 든다."""
    return {"armR_upper": {"rot": shoulder}, "armR_lower": {"rot": elbow},
            "armL_upper": {"rot": shoulder*0.35}}


## 휘두르기는 **`hold` 자세에서 출발한다** (2026-09-08, INBOX #66). 전에는 두 자세가
## 서로 모르는 값이라 `hold` → `use` 로 넘어가는 순간 팔이 튀었다 — `DESIGN.md`
## 「캐릭터 애니메이션」의 *"idle 에서 사용 모션으로 바뀔 때 자세가 갑자기 다른
## 캐릭터처럼 변하면 안 된다"* 가 도구 쪽에서 같은 말을 한다. `s = 0` 이 곧 `hold` 다.
## **「쓴다」는 도구마다 다르다** — `DESIGN.md` 「캐릭터 애니메이션」이 도구를 붙일
## 때마다 적어둔 것이고, 자세(`hold`)가 도구를 안 가리는 것과는 다른 자리다.
## 값은 **(자루가 도는 양 ÷ 기본, 손이 뒤로 밀리는 px)** 이고, 없으면 (1.0, 0) = 내리찍기다.
##   · 총 — **되튐이지 휘두르기가 아니다**(INBOX #28): *"`hold` 자세에서 뒤로 밀렸다
##     돌아올 뿐"* 이고 **돌지 않는다.** 돌리면 총구가 땅을 보고(탑다운에 「위로 튀는」
##     반동은 없다), 앞으로도 나가게 두면 노를 젓는 것처럼 보인다.
##   · 물뿌리개 — **붓기**(INBOX #30). 통을 기울이는 것뿐이라 각이 작다.
USE_STYLE = {"gun": (0.0, 26.0), "watering_can": (0.62, 0.0)}


def _strike(s, wind=0.15):
    """휘두르기의 진행도 — **`hold` 에서 시작해 한쪽으로만 간다** (0 → 1).

    도끼·괭이는 「든 자세」가 곧 들어올린 자세다. `hold` 를 가운데 두고 위아래로
    왕복하면 **위로 더 들 자리가 없어서**(칸 위 테두리) 진폭을 못 키우고, `hold` →
    `use` 로 넘어가는 순간 자세가 튄다. 총의 되튐(`swing_bias`)과 같은 모양이다.
    `wind` 만큼만 반대로 먼저 간다 — 그게 없으면 내려치기에 반동이 없어 보인다.
    """
    t = (s + 1.0) * 0.5
    return (1.0 + wind) * t - wind


def use_front(name=None, swing=34.0, elbow=26.0, grow=0.09, tool=66.0):
    """휘두르기 (정면·뒷모습). 들어올렸다 내려친다 — 화면에서는 위아래 + 크기다.

    **도구만은 여기서도 돈다**(`tool`). 팔을 회전으로 흔들면 팔벌려뛰기가 되지만
    (위 `compose`), 도끼가 위아래로 평행이동만 하면 **패는 게 아니라 승강기**다 —
    손목은 실제로 돌고, 도구는 그 손목에 매달린 막대라 각도가 곧 동작이다.
    팔 회전과 달리 이건 어깨선을 건드리지 않는다.
    """
    turn, back = USE_STYLE.get(name, (1.0, 0.0))
    out = []
    for s in SWING:
        k = _strike(s)
        out.append({"armR_upper": {"rot": HOLD_OUT, "dy": -HOLD_RAISE + swing*turn*k,
                                   "scale": 1 + HOLD_GROW - grow*turn*k},
                    "armR_lower": {"rot": HOLD_ELBOW - elbow*turn*k,
                                   "dx": -back*k,
                                   "scale": 1 + HOLD_GROW - grow*turn*k},
                    "armL_upper": {"dy": swing*turn*k*0.3},
                    "tool": {"rot": -tool*turn*k}})
    return out


def use_side(name=None, shoulder=26.0, elbow=14.0, tool=104.0):
    """휘두르기 (옆모습). **크게 도는 것은 어깨가 아니라 도구다.**

    옆에서 본 도끼질에서 화면을 가로지르는 것은 **날이 그리는 호**이지 어깨가 아니다 —
    사람의 어깨는 그렇게 못 돈다(뒤로 들어올리려면 회전이 120도를 넘어야 하고, 그
    각도에서는 소매가 어깨에서 떨어져 나간다). 어깨는 조금 돌리고 손목 = 도구를 크게
    돌리면 날이 **머리 뒤에서 발 앞까지** 큰 호를 그린다. 정면(`use_front`)이 도구를
    따로 돌리는 것과 같은 자리다.

    **도는 쪽이 정면과 반대다**(`+tool*s`). 옆모습은 그림이 좌우로 뒤집혀 있어서
    날이 화면 왼쪽 위를 보는데, 회전은 뒤집히지 않은 캔버스에서 돌기 때문이다.
    """
    h = hold_side()
    turn, back = USE_STYLE.get(name, (1.0, 0.0))
    out = []
    for s in SWING:
        k = _strike(s)
        out.append({"armR_upper": {"rot": h["armR_upper"]["rot"] + shoulder*turn*k},
                    "armR_lower": {"rot": h["armR_lower"]["rot"] + elbow*turn*k,
                                   "dx": back*k},
                    "armL_upper": {"rot": h["armL_upper"]["rot"] + shoulder*turn*k*0.3},
                    "tool": {"rot": tool*turn*k}})
    return out


def _merge(a, b):
    """두 자세를 겹친다 — 같은 부품이면 b 가 이긴다(도구 쪽 팔이 걷기를 덮는다)."""
    out = {k: dict(v) for k, v in a.items()}
    for k, v in b.items():
        out[k] = dict(out.get(k, {}), **v)
    return out


def hold(front=True):
    return [hold_front() if front else hold_side()]


def use(front=True, name=None):
    """`name` 은 도구 이름 — 「쓴다」가 도구마다 다르다(`USE_STYLE`)."""
    return use_front(name) if front else use_side(name)


def walk_tool(front=True):
    """도구를 든 채 걷기 — 걷기에 「든 팔」을 덮는다.

    **덮는 것이지 겹치는 것이 아니다.** 걷기가 그 팔에 준 값을 통째로 버리고 `hold`
    자세를 놓는다 — 키마다 덮으면 `hold` 에 없는 키(`dy`)만 살아남아 **도구가 걸음마다
    위아래로 흔들린다.** 도구는 머리 옆·위까지 올라오는 물건이라 그 흔들림이 그대로
    「머리가 움직인다」가 된다(2026-09-08, INBOX #66 — 실측 낫 18.8%, 상한 8%).
    """
    base = walk_front() if front else walk_side()
    h = hold_front() if front else hold_side()
    return [_merge({k: v for k, v in f.items() if not k.startswith("armR")}, h)
            for f in base]


# ── 도구 그림 ───────────────────────────────────────────────────────────────
## **도구 7종을 새로 그리지 않는다 — `gen_character.py` 것을 더 큰 격자에 찍는다**
## (2026-09-08, INBOX #66 (1)). 원시 도형·램프·광원·자루 각도가 전부 거기 있고,
## **손 · 인벤토리 칸 · 바닥의 도끼가 같은 도끼여야 한다**(`docs/STYLE_GUIDE.md`
## 「같은 도구가 사는 자리는 이제 셋이다」). 형태를 여기서 다시 정의하면 그 셋이
## 갈린다 — 바꾸는 것은 **칸 크기 하나뿐**이고, 그건 `canvas(n, unit)` 이 이미 하는
## 일이다(*"같은 그림을 더 촘촘한 격자에 찍는다"*).
##
## **줄이는 것은 맨 마지막 한 번뿐이다.** 도구를 96px 도트로 먼저 구워서 손에 붙이면
## 팔 각도만큼 돌리는 순간 뭉갠다(`docs/CHARACTER.md` 「자르고 → 돌리고 → 맨 마지막에
## 줄인다」). 그래서 여기서 굽는 것은 **리그 공간(1024px) 해상도**이고, 도트는
## `bake_rows` 의 축소 한 번에서만 생긴다.
TOOL_UNIT = 4.4     # 도구 설계 단위 하나가 **캐릭터 칸(96px)에서 몇 px** 인가.
## 17px 캐릭터가 쥐던 도끼는 설계 단위 하나가 1px 이었다(칸의 1/17). 96px 칸에서
## 같은 비를 지키면 5.65 인데, 그 값이면 총(가로 8.15단위)이 칸 폭을 넘고 도끼머리가
## 머리 위로 올라간다 — **칸 밖으로 나가면 외곽선이 잘린다**(`qa_character_sheets.py`
## 의 「잘림」이 잡는다). 4.4 면 도끼가 21 × 28 · 총이 42 × 12 라 일곱 도구가 전부
## **몸 중심에서 좌우 47px · 위아래 94px** 안에 들어간다.
TOOL_BOX = 15.0     # 도구를 그릴 설계 공간 한 변 (일곱 도구가 다 들어가는 크기)
TOOL_SS = 6         # 슈퍼샘플 — **칸이 크면 낮춘다**(`gen_objects.py` 와 같은 이유).
## 재는 것은 캔버스 크기가 아니라 출력 픽셀당 샘플 수다: 36 샘플로 구운 리그 px 가
## 마지막 축소에서 다시 25:1 로 평균나므로, 도트 하나는 900 샘플에서 나온다.

_TOOL_CACHE = {}


def gen_tools():
    """도구 7종의 설정(`gen_character.TOOLS`). 이름 목록인 `rig.TOOLS` 와 다르다."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gen_character as gen
    return gen.TOOLS


def tool_sprite(name, angle, sx=1.0, per_cell=5.0):
    """도구 한 자루 → (RGBA, 그림 안의 손 자리). **리그 공간 해상도**로 굽는다.

    `angle` 은 자루가 가리키는 각도(도), `sx` -1 이면 좌우가 뒤집힌다 —
    `gen_character.draw_tool()` 의 규약 그대로다. `per_cell` 은 **리그 px ÷ 칸 px**
    (약 5)로, 이 값이 곧 "도구를 얼마나 촘촘히 찍을 것인가"다.

    **외곽선(`outline`)을 두르지 않는다.** 잉크는 `bake_rows` 뒤의 `add_ink()` 가
    합쳐진 실루엣에 한 번 두른다 — 여기서 미리 두르면 도구와 몸이 겹치는 자리에
    잉크가 끼어 도구가 몸에 붙인 스티커로 보인다(옛 생성기도 도구를 몸과 **같은
    Build 에** 그려서 외곽선을 마지막에 한 번만 둘렀다).
    """
    key = (name, round(angle, 3), sx, round(per_cell, 4))
    if key in _TOOL_CACHE:
        return _TOOL_CACHE[key]
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gen_character as gen
    unit = TOOL_UNIT * per_cell               # 설계 단위 하나 = 리그 px
    n = int(round(TOOL_BOX * unit))
    grip = (TOOL_BOX * 0.5, TOOL_BOX * 0.5)
    keep_ss = gen.SS
    gen.SS = TOOL_SS
    try:
        with gen.canvas(n, unit):
            b = gen.Build()
            gen.draw_tool(b, grip[0], grip[1], angle, sx, gen.TOOLS[name], lift=0.0)
            lum = gen.light(b.hgt, b.mat, key=gen.CFG["key"], amb=gen.CFG["amb"],
                            rim=gen.CFG["rim"])
            m, l = gen.downsample(b.mat, lum)
            pm = gen.downsample_part(b.part)
            rgba = gen.inner_lines(gen.quantize(m, l, gen.palette(), 0.0), m, pm,
                                   gen.palette())
    finally:
        gen.SS = keep_ss
    out = (rgba, (grip[0] * unit, grip[1] * unit))
    _TOOL_CACHE[key] = out
    return out


def tool_layer(name, angle, J, size, sx=1.0, per_cell=5.0, side="R"):
    """도구 그림을 **손 관절 위에** 얹은 리그 크기 레이어.

    자세는 안 준다 — 팔이 도는 것은 `compose()` 가 사슬로 물려준다. 여기서 하는
    일은 "쉬는 자세의 손에 쥐여주는 것"뿐이다.
    """
    art, grip = tool_sprite(name, angle, sx, per_cell)
    lay = np.zeros((size[1], size[0], 4), np.uint8)
    hx, hy = J["hand%s" % side]
    x0 = int(round(hx - grip[0]))
    y0 = int(round(hy - grip[1]))
    h, w = art.shape[:2]
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(size[0], x0 + w), min(size[1], y0 + h)
    if sx1 > sx0 and sy1 > sy0:
        lay[sy0:sy1, sx0:sx1] = art[sy0-y0:sy1-y0, sx0-x0:sx1-x0]
    return Image.fromarray(lay, 'RGBA')


## 자루가 화면에서 **실제로** 몇 도로 서 있을 것인가. 도구 설정의 `hold` 가 그 값이고
## (`gen_character.py` 의 도구마다 있다 — 도끼 80도 · 총 4도 · 물뿌리개 -86도),
## 여기 표는 방향마다 거기서 얼마나 더 눕힐 것인가다.
##
## **옆모습만 더 눕힌다.** 옆모습은 팔을 앞으로 들어 손이 얼굴 앞에 오는데, 거기서
## 자루를 세우면 **자루가 얼굴을 가로지른다**(낚싯대가 실제로 그랬다 — 옛 생성기가
## `swing_fwd` 로 겪은 *"자루가 눈을 덮는다"* 와 같은 자리다).
TOOL_LEAN = {"down": 0.0, "up": 0.0, "left": -16.0}


def tool_draw_angle(kit, direction, pose, sx=1.0):
    """`tool_sprite` 에 넘길 자루 각도 — **팔이 이미 돌아 있는 만큼을 빼둔다.**

    도구는 아래팔의 자식이라 `hold` 자세의 어깨·팔꿈치 회전을 그대로 물려받는다.
    그림을 그 각도 그대로 그리면 자루가 그만큼 더 누워버리므로, 물려받을 양을
    미리 빼고 그린다 — 그러면 **어떤 방향에서도 자루가 `hold` 각도로 선다.**

    **좌우를 뒤집으면 회전의 방향도 뒤집힌다**(`sx`). `draw_tool` 의 `sx=-1` 은 그림을
    거울에 비추는 것이라 화면 각도가 `180 - a` 가 되는데, 팔 회전은 거울과 무관하게
    캔버스 좌표에서 돈다 — 그래서 뺄 것이 더할 것이 된다. 부호를 안 뒤집으면 옆모습에서
    자루가 **가슴을 가로지르는 가로 막대**가 된다(실제로 그렇게 나왔다).
    """
    arm = sum((pose.get(p) or {}).get("rot", 0.0)
              for p in ("armR_upper", "armR_lower"))
    return kit["hold"] + TOOL_LEAN[direction] - sx*arm
def hand_point(J, xf, side="R"):
    """변환을 다 거친 뒤의 손 좌표(1024px 원본 기준).

    **도구를 얹는 데는 이제 안 쓴다** — 도구는 `TOOL_PART` 로 사슬에 매달려
    `compose()` 가 같은 변환을 물려주므로, 좌표를 밖에서 다시 계산할 필요가 없다
    (2026-09-08, INBOX #66). 손이 어디로 가는지 **재보는** 자리로 남긴다.
    """
    meta, _ = _chain({})
    name = "arm%s_lower" % side
    chain = []
    n = name
    while n is not None:
        par, piv = meta[n]
        chain.append((n, piv)); n = par
    M = np.eye(3)
    for nm, piv in chain:                     # `compose()` 와 **같은 순서**여야 한다
        t = xf.get(nm) or {}
        M = _mat(J[piv], t.get("rot", 0.0), t.get("scale", 1.0),
                 t.get("dy", 0.0), t.get("dx", 0.0)) @ M
    p = np.array([J["hand%s" % side][0], J["hand%s" % side][1], 1.0])
    q = M @ p
    return (float(q[0]), float(q[1]))


# ── 재질 나누기 — 커스터마이징이 갈아끼울 단위 ──────────────────────────────
## **AI 그림에는 램프가 없다.** 색이 그림에 구워져 있어서 「이 픽셀이 피부인가 옷인가」를
## 색만 보고는 모른다 — 그래서 2026-09-08 아침까지 커스터마이징이 죽어 있었다
## (`docs/CHARACTER.md` 8절). 리그는 그 답을 이미 갖고 있다: **부품을 우리가 나눴으므로
## 어느 픽셀이 머리·몸통·팔·다리인지 안다.** 거기서 「이 부품의 색들」을 뽑아 재질을
## 가르고, 마지막 축소 때 그 재질의 **기준색 램프**로 갈아 끼운다(2026-09-08, INBOX #68).
##
## 그래서 구워지는 PNG 는 문서가 줄곧 말해온 그대로 **기준색 1벌**이 된다
## (`docs/DESIGN.md` 「캐릭터 커스터마이징 항목」: *"시트는 기준색 1벌로만 굽고 나머지
## 색은 그 PNG 의 색을 바꿔치기해서 만든다"*). 게임 쪽(`character_sprite.gd`)은 한 줄도
## 안 고친다 — 없던 램프가 생긴 것뿐이다.
MATS = ["skin", "hair", "shirt", "pants", "boot", "eye", "helve", "blade"]
BODY_MATS = ["skin", "hair", "shirt", "pants", "boot"]     # 커스터마이징이 바꾸는 것
PART_NAMES = tuple(n for n, _, _, _, _ in PARTS)

## **재질마다 나올 수 있는 부품이 정해져 있다.** 색만으로 가르면 어두운 빨강 머리와
## 어두운 갈색 신발이 섞인다 — 부품이 그 둘을 애초에 갈라놓는다.
## 「머리」가 몸통·위팔까지 도는 것은 긴 머리가 어깨에 내려오기 때문이고,
## 「신발」이 몸통에 있는 것은 **멜빵의 가죽끈**이 신발과 같은 가죽이기 때문이다.
MAT_PARTS = {
    "skin": PART_NAMES,
    "hair": ("head", "torso", "armL_upper", "armR_upper"),
    # **셔츠가 머리 부품에도 난다** — 머리 뼈가 목에서 끝나므로 **깃**이 머리 부품에
    # 들어온다. 안 열어두면 깃이 「피부도 머리도 아닌 것」이 되어 눈으로 칠해진다
    # (실제로 턱 밑에 검은 띠가 생겼다).
    "shirt": ("head", "torso", "armL_upper", "armR_upper", "armL_lower", "armR_lower"),
    "pants": ("torso", "legL_upper", "legR_upper", "legL_lower", "legR_lower"),
    "boot": ("torso", "legL_lower", "legR_lower"),
}

## 씨앗 = (부품, 세로 범위, 가로 범위) — **그 부품 테두리 상자에 대한 비율**이다.
## 확실히 그 재질뿐인 자리만 고른다. 나머지는 아래 `material_protos()` 가 씨앗에서
## 뽑은 색으로 전체를 분류하고, 분류 결과로 색을 다시 뽑기를 몇 바퀴 돌려 넓힌다.
SEEDS = {
    "hair": [("head", 0.00, 0.28)],
    "skin": [("head", 0.55, 0.85, 0.32, 0.68),
             ("armL_lower", 0.15, 1.00), ("armR_lower", 0.15, 1.00)],
    "shirt": [("torso", 0.03, 0.20, 0.30, 0.70)],
    "pants": [("torso", 0.60, 0.95)],
    "boot": [("legL_lower", 0.72, 1.00), ("legR_lower", 0.72, 1.00)],
}

## 눈은 **겨루지 않고 덮어쓴다** — 「얼굴 띠 안에서 피부도 머리도 아닌 것」이다.
## 대표색으로 겨루게 두면 흰 반짝임이 흰 셔츠와, 청록 눈동자가 멜빵과 붙는다.
## **눈을 안 갈라두면 눈이 머리색을 따라간다** — 금발을 고르면 눈이 사라진다.
## 뒷모습에는 얼굴이 없지만 따로 끌 필요가 없다: 거기는 띠 안이 전부 머리라
## 「머리에서 멀다」가 성립하지 않아 저절로 아무것도 안 잡힌다(실측).
EYE_BAND = (-0.058, 0.012)   # 코 관절에서 위아래로 (인물 키에 대한 비율)
EYE_HALF = 0.075             # 머리 한가운데에서 좌우로
EYE_FAR = 45.0               # 피부·머리색에서 **둘 다** 이만큼 멀면 눈

MAT_PROTOS = 10              # 재질 하나에서 뽑는 대표색 수
MAT_ROUNDS = 4               # 씨앗 → 전체 분류 → 대표색 다시 뽑기, 몇 바퀴


def _part_band(layer, r0, r1, c0=0.0, c1=1.0):
    """부품 테두리 상자 안의 띠 하나."""
    a = np.asarray(layer)
    m = a[..., 3] > 0
    if not m.any():
        return m
    ys, xs = np.where(m)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    h, w = y1 - y0 + 1, x1 - x0 + 1
    out = np.zeros_like(m)
    out[int(y0 + r0*h):int(y0 + r1*h) + 1, int(x0 + c0*w):int(x0 + c1*w) + 1] = True
    return out & m


def _protos(cols, k=MAT_PROTOS):
    """색 무더기 → 대표색 몇 개 (중앙절단)."""
    cols = np.asarray(cols, np.uint8).reshape(-1, 3)
    if len(cols) <= k:
        return np.unique(cols, axis=0).astype(float)
    q = Image.fromarray(cols.reshape(-1, 1, 3)).quantize(
        colors=k, method=Image.MEDIANCUT, dither=Image.NONE)
    pal = np.array(q.getpalette()[:k*3]).reshape(k, 3)
    return pal[np.unique(np.asarray(q))].astype(float)


def _flatten(layers):
    """부품 레이어들 → (한 장의 RGBA, 픽셀마다 부품 번호)."""
    shape = np.asarray(next(iter(layers.values()))).shape[:2]
    full = np.zeros(shape + (4,), np.uint8)
    part = np.full(shape, -1, np.int8)
    for i, name in enumerate(PART_NAMES):
        if name not in layers:
            continue
        a = np.asarray(layers[name])
        m = a[..., 3] > 0
        full[m] = a[m]; part[m] = i
    return full, part


def _nearest(cols, protos):
    """색마다 대표색까지의 **가장 가까운 거리**."""
    if len(protos) == 0:
        return np.full(len(cols), np.inf)
    return np.sqrt(((cols[:, None, :] - protos[None, :, :])**2).sum(2)).min(1)


def material_protos(rigs, ref="down"):
    """**정면 한 장에서** 재질마다 「이 재질의 색들」을 뽑는다.

    옆·뒷모습에서 씨앗을 따로 뽑으면 안 된다 — 옆모습은 어깨를 덮은 머리가 소매
    자리에 있고, 뒷모습에는 얼굴이 없다(실측: 씨앗이 통째로 빨강이 됐다). 인물이
    한 명이고 `build_sheets()` 가 이미 **정면의 팔레트를 네 방향에 씌우므로**,
    정면에서 뽑은 대표색이 세 방향에 그대로 맞는다.
    """
    layers, J = rigs[ref]
    full, part = _flatten(layers)
    pure = {}
    for mat, seeds in SEEDS.items():
        mask = np.zeros(full.shape[:2], bool)
        for s in seeds:
            name, r0, r1 = s[0], s[1], s[2]
            c0, c1 = (s[3], s[4]) if len(s) > 3 else (0.0, 1.0)
            if name in layers:
                mask |= _part_band(layers[name], r0, r1, c0, c1)
        pure[mat] = _protos(full[mask][:, :3])
    # 씨앗은 작다 — 전체를 한 번 나눠보고 그 결과에서 대표색을 다시 뽑기를 되풀이하면
    # 재질마다 실제로 쓰인 색이 다 들어온다(그늘·밝은면까지).
    # **씨앗 쪽(`pure`)은 안 넓힌다** — 눈을 가르는 「피부도 머리도 아니다」는 그늘이
    # 섞이지 않은 순수한 색이라야 성립한다.
    protos = dict(pure)
    for _ in range(MAT_ROUNDS):
        lab = classify(layers, protos, J, pure)
        for i, mat in enumerate(MATS):
            if mat not in protos:
                continue
            m = lab == i + 1
            if m.sum() >= MAT_PROTOS:
                protos[mat] = _protos(full[m][:, :3])
    return protos, pure


def _eye_mask(layers, J, full, pure):
    """얼굴 띠 안에서 **피부도 머리도 아닌 것** = 눈(눈동자·속눈썹·반짝임)."""
    m = np.zeros(full.shape[:2], bool)
    if "head" not in layers or not pure:
        return m
    h = float(comfy_fig_h())
    nx, ny = J["nose"]
    band = np.zeros_like(m)
    band[int(ny + EYE_BAND[0]*h):int(ny + EYE_BAND[1]*h) + 1,
         int(nx - EYE_HALF*h):int(nx + EYE_HALF*h) + 1] = True
    face = band & (np.asarray(layers["head"])[..., 3] > 0)
    if not face.any():
        return m
    cols = full[face][:, :3].astype(float)
    m[face] = ((_nearest(cols, pure["skin"]) > EYE_FAR)
               & (_nearest(cols, pure["hair"]) > EYE_FAR))
    return m


def comfy_fig_h():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import comfy
    return comfy.FIG_H


def classify(layers, protos, J=None, pure=None):
    """부품 레이어들 → 픽셀마다 **재질 번호**(0 = 없음, 1.. = `MATS` 순서).

    가장 가까운 대표색이 이기되, **그 부품에 날 수 있는 재질끼리만** 겨룬다
    (`MAT_PARTS`). 그래서 어두운 빨강 머리가 신발이 되는 일이 없다.
    눈만은 겨루지 않고 마지막에 덮어쓴다 (`_eye_mask`).
    """
    full, part = _flatten(layers)
    op = full[..., 3] > 0
    out = np.zeros(full.shape[:2], np.uint8)
    if not op.any():
        return out
    cols = full[op][:, :3].astype(float)
    pid = part[op]
    best = np.full(len(cols), np.inf)
    who = np.zeros(len(cols), np.uint8)
    for i, mat in enumerate(MATS):
        if mat not in protos or len(protos[mat]) == 0 or mat not in MAT_PARTS:
            continue
        ok = np.isin(pid, [PART_NAMES.index(p) for p in MAT_PARTS[mat]])
        d = np.where(ok, _nearest(cols, protos[mat]), np.inf)
        take = d < best
        best[take] = d[take]; who[take] = i + 1
    out[op] = who
    if J is not None:
        out[_eye_mask(layers, J, full, pure or {})] = MATS.index("eye") + 1
    return out


def classify_tool(art):
    """도구 픽셀 → 자루(`helve`) 냐 날(`blade`) 이냐.

    도구는 **커스터마이징을 따라가지 않는다**(`docs/DESIGN.md` 「캐릭터 애니메이션」) —
    그래서 몸 재질과 겨루게 두지 않고, 고정색 램프 둘 중 가까운 쪽으로만 가른다.
    """
    a = np.asarray(art)
    op = a[..., 3] > 0
    out = np.zeros(a.shape[:2], np.uint8)
    if not op.any():
        return out
    cols = a[op][:, :3].astype(float)
    ramps = base_ramps()
    dh = _nearest(cols, np.array(ramps["helve"], float))
    db = _nearest(cols, np.array(ramps["blade"], float))
    out[op] = np.where(dh <= db, MATS.index("helve") + 1, MATS.index("blade") + 1)
    return out


def label_images(layers, body_lab):
    """부품마다 「재질 번호를 R 채널에 적은」 레이어.

    **라벨이 픽셀을 따라다녀야 한다** — `compose()` 가 색과 똑같은 변환으로 옮겨주므로,
    팔이 어디로 돌든 그 픽셀이 무슨 재질이었는지가 축소 뒤에도 남는다. (색을 먼저
    갈아끼우고 옮기는 길은 막혀 있다: 마지막 축소가 이웃을 평균 내므로 램프에 없는
    중간색이 생긴다.)
    """
    out = {}
    for name, img in layers.items():
        a = np.asarray(img)
        m = a[..., 3] > 0
        lay = np.zeros(a.shape[:2] + (4,), np.uint8)
        if name == "tool":
            lay[..., 0] = np.where(m, classify_tool(a), 0)
        else:
            lay[..., 0] = np.where(m, body_lab, 0)
        lay[..., 3] = a[..., 3]
        out[name] = Image.fromarray(lay, 'RGBA')
    return out


_RAMPS = {}


def base_ramps():
    """재질별 **기준색 램프** — `game/scripts/character_palettes.gd` 의 BASE 와 같은 원본.

    값을 여기에 적지 않고 `gen_character.palette()` 를 그대로 부른다. 그 함수가
    `export_palettes()` 로 GDScript 상수를 내려보내는 바로 그 함수라, **시트에 구운 색과
    게임이 「출발점」으로 아는 색이 어긋날 자리가 없다.**
    """
    if _RAMPS:
        return _RAMPS
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gen_character as gen
    pal = gen.palette()
    for m in ("skin", "hair", "shirt", "pants", "boot", "helve", "blade"):
        _RAMPS[m] = [tuple(int(round(v)) for v in c) for c in pal[m]]
    # 눈은 **잉크 + 반짝임 한 점**이다(옛 생성기가 눈을 그리던 방식 그대로).
    # 램프가 아니라 고정색이라 커스터마이징이 건드리지 않는다.
    _RAMPS["eye"] = [tuple(gen.GLINT), tuple(gen.INK), tuple(gen.INK), tuple(gen.INK)]
    return _RAMPS


def recolor_cells(cells, labels):
    """축소된 칸들 → **재질마다 딱 4단계**로 줄인 칸들 + 테두리.

    `gen_player.quantize_all()`(그림 전체를 32색으로 줄이던 것)을 대신한다. 색을
    통째로 줄이면 셔츠 밝은면과 피부 그늘이 **한 색으로 합쳐질 수** 있는데, 그러면
    옷색을 바꿀 때 얼굴이 같이 변한다. 재질별로 줄이면 그 일이 정의상 안 생기고,
    덤으로 **22장이 전부 같은 색을 쓴다**(램프가 상수라서) — 방향마다 옷 색이
    달라지던 것도 여기서 함께 닫힌다.
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_player import add_ink
    ramps = base_ramps()
    out = [c.copy() for c in cells]
    for i, mat in enumerate(MATS):
        ramp = np.array(ramps[mat], float)
        masks = [(l == i + 1) & (c[..., 3] > 0) for c, l in zip(cells, labels)]
        total = sum(int(m.sum()) for m in masks)
        if total == 0:
            continue
        cols = np.concatenate([c[m][:, :3] for c, m in zip(cells, masks) if m.any()])
        levels = _levels(cols, len(ramp))
        order = np.argsort(-(levels @ np.array([0.299, 0.587, 0.114])))  # 밝은 것부터
        table = ramp[np.argsort(order)]        # 무리 번호 → 램프 단계
        for c, m in zip(out, masks):
            if not m.any():
                continue
            v = c[m][:, :3].astype(float)
            k = ((v[:, None, :] - levels[None, :, :])**2).sum(2).argmin(1)
            c[m, :3] = table[k]
    return [add_ink(c) for c in out]


def _levels(cols, k):
    """색 무더기 → 단계 `k` 개. 램프의 단 수만큼만 남긴다."""
    lv = _protos(cols, k)
    while len(lv) < k:                          # 색이 모자라면 마지막 것을 늘린다
        lv = np.vstack([lv, lv[-1:]])
    return lv[:k]


def bake_rows(rows, layers, J, cell=96, behind=False, labels=None):
    """방향별 자세 목록 → 방향별 칸 목록.

    **시트 한 장의 모든 칸이 같은 테두리와 같은 팔레트를 쓴다.**
      - 같은 테두리: 프레임마다 제 몸에 맞춰 자르면 축소 배율이 달라져 캐릭터가
        들썩이고, 방향마다 크기가 달라진다.
      - 같은 팔레트: 프레임마다 색을 따로 줄이면 팔레트가 미세하게 달라져 **모든
        픽셀이 조금씩 변한다** — 그건 걷기가 아니라 깜빡임이다(실측 56%).

    **테두리의 세로는 도구를 빼고 잰다** (2026-09-08, INBOX #66). 도구를 넣고 재면
    도끼를 들었다는 이유로 테두리가 높아져 **캐릭터가 그만큼 작아진다** — 시트마다
    사람 크기가 달라지는 것은 `DESIGN.md` 「캐릭터 애니메이션」이 못 박아 금지한
    것이다(*"서로 다른 생성 호출로 만든 프레임끼리 캐릭터가 차지하는 크기가 달라지면
    안 된다"*). 가로는 **선 축을 두고 좌우 같은 만큼** 넓혀서 도구를 담는다 —
    한쪽만 넓히면 칸 안에서 캐릭터가 옆으로 밀려 발밑이 노드 원점에서 벗어난다.
    **그 축은 테두리의 한가운데가 아니라 쉼 자세의 한가운데다** (2026-09-08, INBOX #71
    — 테두리에는 뻗은 팔이 들어가서, 도구를 들면 캐릭터가 6px 옆으로 미끄러졌다).
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_player import downscale
    flat = [x for r in rows for x in r]
    bigs = [compose(layers, J, a, behind) for a in flat]
    body = {k: v for k, v in layers.items() if k != "tool"}
    bodies = bigs if len(body) == len(layers) \
        else [compose(body, J, a) for a in flat]
    # **발을 땅에 맞춘다 — 밀지 말고 넘친 것을 자른다.**
    # 프레임을 통째로 밀면 96px 로 줄일 때 그 밀린 양(1024px 에서 몇 px)이 위쪽 한 줄의
    # 커버리지를 뒤집어서 **머리가 1px 흔들린다**(실측: 옆모습 걷기에서 아랫줄 편차가
    # 5px 이었고, 그 탓에 변화의 14%가 머리에 있었다). 제일 높은 아랫줄에 맞춰 그
    # 아래를 잘라내면 머리는 한 픽셀도 안 움직인다 — 잘려나가는 것은 흔드는 발의
    # 신발 끝 몇 px 뿐이라 96px 에서는 보이지 않는다.
    # **발은 몸으로 맞춘다** — 매달린 도구(물뿌리개)가 바닥을 정하면 안 된다.
    bots = [int(np.flatnonzero((np.asarray(b)[..., 3] > 0).sum(1) > 0).max()) for b in bodies]
    floor = min(bots)
    clipped = []
    for b in bigs:
        a = np.asarray(b).copy()
        a[floor + 1:] = 0
        clipped.append(Image.fromarray(a, 'RGBA'))
    bigs = clipped
    keeps = [np.asarray(b)[..., 3] > 0 for b in bigs]
    union = keeps[0].copy()
    for k in keeps[1:]:
        union |= k
    body_union = union
    if bodies is not bigs:
        body_union = np.zeros_like(union)
        for b in bodies:
            a = np.asarray(b)[..., 3] > 0
            a[floor + 1:] = False
            body_union |= a
    bys = np.flatnonzero(body_union.sum(1) > 0)
    xs = np.flatnonzero(union.sum(0) > 0)
    W = union.shape[1]
    # **가로의 축은 「선 축」이지 테두리의 한가운데가 아니다** (2026-09-08, INBOX #71).
    # 테두리로 재면 **뻗은 팔이 거기 들어간다** — 도구를 든 자세는 오른팔이 옆으로
    # 나가므로 축이 그만큼 오른쪽으로 밀리고, 상자가 따라 밀려 **몸통·다리가 칸 안에서
    # 왼쪽으로 밀린다.** 그러면 빈손 ↔ 도구를 오갈 때 캐릭터가 옆으로 순간이동한다
    # (실측: 정면 -5.5 ~ -7.5px, 뒷모습 -5.0 ~ -7.0px).
    # 쉼 자세(변환 없음, 도구 없음)의 한가운데가 그 축이다 — **모션과 무관하게 방향마다
    # 한 값**이라 22장이 저절로 같은 자리에 선다. 관절(`J['hipC']`)을 안 쓰는 이유는
    # 그림이 뼈대에 정확히 얹혀 있지 않기 때문이고, 쉼 자세로 재면 지금 맞아 있는
    # idle 이 한 픽셀도 안 움직인다(idle 이 곧 쉼 자세다).
    rest = np.asarray(compose(body, J, {}))[..., 3] > 0
    rxs = np.flatnonzero(rest.sum(0) > 0)
    cx = (int(rxs.min()) + int(rxs.max()) + 1) * 0.5
    r = min(max(cx - int(xs.min()), int(xs.max()) + 1 - cx), cx, W - cx)
    box = (int(bys.min()), int(bys.max())+1, int(round(cx - r)), int(round(cx + r)))
    cells = [downscale(Image.fromarray(np.asarray(b)[..., :3]), k, cell=cell, box=box)
             for b, k in zip(bigs, keeps)]      # **색은 아직 안 줄인다** — 부르는 쪽이 한 번에 한다
    labs = None
    if labels is not None:
        # **라벨은 색과 같은 변환·같은 격자를 지난다** — 그래야 축소 뒤에도 이 도트가
        # 무슨 재질이었는지 알 수 있다(`recolor_cells()` 가 그걸로 램프를 고른다).
        from gen_player import downscale_labels
        lbig = [np.asarray(compose(labels, J, a, behind))[..., 0] for a in flat]
        labs = [downscale_labels(np.where(k, l, 0), k, cell=cell, box=box, top=len(MATS))
                for l, k in zip(lbig, keeps)]
    out = []; lout = []; at = 0
    for r in rows:
        out.append(cells[at:at+len(r)])
        if labs is not None:
            lout.append(labs[at:at+len(r)])
        at += len(r)
    return out if labels is None else (out, lout)


def _only_figure(rgba, J):
    """칸 안에서 **인물 한 덩어리만** 남긴다 — 나머지 덩어리는 지운다.

    프롬프트에 "reference sheet" 류의 말을 넣으면 SDXL 이 인물 옆에 **소품(화분·항아리·
    아이콘)을 같이 그린다.** 그 픽셀은 머리·몸통(반경 없음)이 통째로 가져가 버려서,
    걷기에서 항아리가 머리를 따라 흔들린다. 골반에 닿은 덩어리 하나만 남긴다.
    """
    from skimage import measure
    op = rgba[..., 3] > 0
    lab = measure.label(op, connectivity=1)
    hx, hy = int(J["hipC"][0]), int(J["hipC"][1])
    want = lab[hy, hx]
    if want == 0:                       # 골반이 빈 칸이면 가장 큰 덩어리를 쓴다
        cnt = np.bincount(lab.ravel()); cnt[0] = 0
        want = int(cnt.argmax()) if cnt.size > 1 else 0
    out = rgba.copy()
    out[lab != want] = 0
    return out


def load_sheet(path=None):
    """4방향이 한 장에 든 시트 → `{방향: (부품, 관절)}`.

    자르지 않고 **한 캔버스 위에서 사분면만 남긴다** — 리그의 조립은 원본 좌표계에서
    돌아가므로, 관절 좌표를 옮겨 계산할 필요가 없다.
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_player import cutout
    import comfy
    src, keep = cutout(os.path.expanduser(path or SHEET))
    a = np.dstack([np.asarray(src), (keep*255).astype(np.uint8)])
    H, W = a.shape[:2]
    if (H, W) != (comfy.SHEET_SIZE, comfy.SHEET_SIZE):
        raise SystemExit("시트가 %dx%d 다 — comfy.SHEET_SIZE(%d) 와 달라서 자를 자리를 모른다"
                         % (W, H, comfy.SHEET_SIZE))
    out = {}
    for cx, top, face in comfy.SHEET_CELLS:
        if face == "right":
            continue                       # right 는 left 를 반전해 쓴다
        half = comfy.SHEET_SIZE // 2
        x0, x1 = cx - half//2, cx + half//2
        y0, y1 = top - 40, top + comfy.FIG_H + 60
        m = np.zeros((H, W), bool)
        m[max(0, y0):min(H, y1), max(0, x0):min(W, x1)] = True
        q = a.copy(); q[~m] = 0
        J = joints(cx=cx, top=top, h=comfy.FIG_H,
                   heads=comfy.FIG_HEADS, arm_deg=comfy.ARM_DEG)
        q = _only_figure(q, J)
        name = {"front": "down", "left": "left", "back": "up"}[face]
        out[name] = (split(Image.fromarray(strip_outline(q), 'RGBA'), J,
                           comfy.FIG_H), J)
    return out


def load_dirs(sources=None):
    """방향마다 (부품, 관절). 없는 방향은 `down` 으로 대신한다."""
    src = dict(SOURCES if sources is None else sources)
    out = {}
    for d in ("down", "left", "up"):
        p = src.get(d)
        out[d] = load(p) if p else out["down"]
    return out


def mirror_cells(cells):
    """왼쪽 걷기 칸들을 좌우반전해 오른쪽으로 쓴다."""
    return [np.ascontiguousarray(c[:, ::-1]) for c in cells]


def build_sheets(src=None, style="farmer", cell=96):
    """리그 → 게임 시트(`player_<모션>_<스타일>.png`).

    **행 = 방향(down/left/right/up), 열 = 프레임** — `game/scripts/player_frames.gd`
    가 쥔 규칙이다. 걷기는 **방향마다 흔드는 축이 다르다**: 정면·뒷모습(down/up)은
    원근 축약, 옆모습(left/right)은 회전이다.

    **색은 22장을 다 구운 뒤 한 번에 줄인다** (2026-09-08, INBOX #68). 시트마다 따로
    줄이면 시트마다 팔레트가 미세하게 달라지는데, 색 바꿔치기는 **색이 정확히 같아야**
    걸리므로 그러면 걷기 시트만 옷을 안 갈아입는다. 재질별 램프는 상수라 22장이
    저절로 같은 색을 쓴다 — `recolor_cells()` 참고.
    """
    rigs = load_sheet(src) if (src or SHEET) else load_dirs()
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "assets", "sprites")
    # **리그 px ÷ 칸 px** — 도구를 얼마나 촘촘히 찍을지 여기서 정한다. 방향마다
    # 다르다(옆모습이 조금 작다): 몸 하나가 칸의 세로를 다 채우게 굽기 때문이다.
    per_cell = {}
    for d, (layers, J) in rigs.items():
        op = np.asarray(compose(layers, J, {}))[..., 3] > 0
        ys = np.flatnonzero(op.sum(1) > 0)
        per_cell[d] = (int(ys.max()) - int(ys.min()) + 1) / float(cell - 2)
    plans = {
        "idle": {"down": idle(), "left": idle(), "up": idle()},
        "walk": {"down": walk_front(), "left": walk_side(), "up": walk_front()},
    }
    # 도구별 모션 3종 (`DESIGN.md` 「새 도구를 추가하는 절차」 1).
    # **도구가 늘면 `TOOLS` 한 줄만 늘리면 여기가 따라온다.**
    for t in TOOLS:
        plans["hold_%s" % t] = {"down": hold(True), "left": hold(False), "up": hold(True)}
        plans["walk_%s" % t] = {"down": walk_tool(True), "left": walk_tool(False),
                                "up": walk_tool(True)}
        if t not in NO_USE:
            plans["use_%s" % t] = {"down": use(True, t), "left": use(False, t),
                                   "up": use(True, t)}
    # **재질은 정면 한 장에서 한 번만 나눈다** — 세 방향이 같은 사람이다.
    protos, pure = material_protos(rigs)
    body_lab = {d: classify(layers, protos, J, pure) for d, (layers, J) in rigs.items()}

    order = ["down", "left", "up"]
    baked = {}                       # 모션 → 방향 → 칸들 (색을 아직 안 줄인 것)
    labeled = {}                     # 같은 자리의 재질 번호
    for motion, per_dir in plans.items():
        # **방향마다 원본이 다르므로 따로 굽는다.** 그래도 크기는 맞아야 하니
        # 칸 안에서 발밑이 아랫줄에 오게 굽는 규칙(`bake_rows`)이 그대로 맞춰준다.
        tool = motion.split("_", 1)[1] if "_" in motion else None
        baked[motion] = {}; labeled[motion] = {}
        for d, frames in per_dir.items():
            layers, J = rigs[d]
            if tool:
                # **자루 각도는 방향마다 다르다** — 팔이 이미 돌아 있는 만큼을 뺀다.
                sx = -1.0 if d == "left" else 1.0
                angle = tool_draw_angle(gen_tools()[tool], d,
                                        hold_side() if d == "left" else hold_front(), sx)
                layers = dict(layers)
                layers["tool"] = tool_layer(
                    tool, angle, J, next(iter(layers.values())).size,
                    sx=sx, per_cell=per_cell[d])
            cells, labs = bake_rows([frames], layers, J, cell,
                                    behind=(tool is not None and d in TOOL_BEHIND),
                                    labels=label_images(layers, body_lab[d]))
            baked[motion][d] = cells[0]; labeled[motion][d] = labs[0]

    # **22장을 한 번에 줄인다.** 여기서 비로소 도트의 색이 정해지고, 그 색이 곧
    # `character_palettes.gd` 의 기준색 램프다 — 게임이 그걸 갈아끼운다.
    flat_cells = [c for m in plans for d in order for c in baked[m][d]]
    flat_labs = [l for m in plans for d in order for l in labeled[m][d]]
    done = recolor_cells(flat_cells, flat_labs)
    at = 0
    for m in plans:
        for d in order:
            n = len(baked[m][d]); baked[m][d] = done[at:at+n]; at += n

    for motion in plans:
        rows_out = [baked[motion]["down"], baked[motion]["left"],
                    mirror_cells(baked[motion]["left"]), baked[motion]["up"]]
        cols = max(len(r) for r in rows_out)
        sheet = np.zeros((cell*4, cell*cols, 4), np.uint8)
        for r, cells in enumerate(rows_out):
            for i, c in enumerate(cells):
                sheet[r*cell:(r+1)*cell, i*cell:(i+1)*cell] = c
        path = os.path.join(out_dir, "player_%s_%s.png" % (motion, style))
        Image.fromarray(sheet, 'RGBA').save(path)
        print("%s: %dx%d (4방향 × %d프레임, 칸 %dpx)"
              % (os.path.basename(path), cell*cols, cell*4, cols, cell))


## 부품 나눔을 눈으로 볼 때 쓰는 색 (부품 순서 그대로).
PART_COLORS = [(255,80,80),(255,160,80),(80,160,255),(80,220,255),
               (120,255,120),(200,255,120),(255,120,255),(255,200,255),
               (200,200,200),(255,255,120)]


def preview_parts(path=None, out="~/Desktop/rig_parts.png"):
    """**시트 한 장의 세 방향**을 부품 색으로 칠해 한 장에 보여준다.

    `CHARACTER.md` 7절의 4번이 보는 그림이다 — **팔이 가슴을 물었으면 `PARTS` 의
    반경을 줄인다.** 방향마다 따로 보지 않고 한 장에 그리는 이유는, 어긋나는 것이
    보통 한 방향뿐이기 때문이다(옆모습에서 팔이 몸통에 겹친다).
    """
    for d, (layers, J) in load_sheet(path).items():
        size = next(iter(layers.values())).size
        break
    prev = np.full((size[1], size[0], 3), 24, np.uint8)
    for d, (layers, J) in load_sheet(path).items():
        for i, (name, _, _, _, _) in enumerate(PARTS):
            prev[np.asarray(layers[name])[..., 3] > 0] = PART_COLORS[i]
    out = os.path.expanduser(out)
    Image.fromarray(prev).save(out)
    return out


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    out = preview_parts(sys.argv[1] if len(sys.argv) > 1 else None)
    print("부품:", ", ".join(n for n,_,_,_,_ in PARTS))
    print("→", out)
