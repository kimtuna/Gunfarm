#!/usr/bin/env python3
"""T자 그림 한 장 → **부품으로 나눈 리그**. 모든 모션을 여기서 조립한다.

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
## 전부 어긋났다(2026-09-08 실측, `docs/CHARACTER.md` 「방향 4장을 맞추기」).
## 배치는 `comfy.SHEET_CELLS` 와 **반드시 같아야 한다** — 어긋나면 엉뚱한 자리를 자른다.
SHEET = "~/ComfyUI/output/g0_00001_.png"

## 방향마다 원본이 다르다 — 옆·뒷모습은 그 방향으로 그려진 그림이어야 한다.
## **`right` 는 `left` 를 좌우반전해 쓴다** — 게임의 정석이고, 두 장을 따로 뽑으면
## 캐릭터가 미묘하게 달라진다(같은 씨앗을 써도 뼈대가 바뀌면 달라진다 — 실측).
## 없는 방향은 `down` 으로 대신한다.
##
## **옷을 프롬프트에 못 박아야 한다.** 안 그러면 정면만 반바지고 옆·뒤는 긴바지로
## 나온다(사람 지적, 2026-09-08). 색이 갈리는 것은 `quantize_all(ref_cells=...)` 로
## 정면 팔레트를 씌워 맞출 수 있지만, **옷의 모양이 갈리는 것은 다시 뽑는 수밖에 없다.**
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
PARTS = [
    ("armL_upper", ("shoulderL", "elbowL"), None,          "shoulderL", 34),
    ("armL_lower", ("elbowL", "handL"),     "armL_upper",  "elbowL",    30),
    ("armR_upper", ("shoulderR", "elbowR"), None,          "shoulderR", 34),
    ("armR_lower", ("elbowR", "handR"),     "armR_upper",  "elbowR",    30),
    ("legL_upper", ("hipL", "kneeL"),       None,          "hipL",      78),
    ("legL_lower", ("kneeL", "footL"),      "legL_upper",  "kneeL",     78),
    ("legR_upper", ("hipR", "kneeR"),       None,          "hipR",      78),
    ("legR_lower", ("kneeR", "footR"),      "legR_upper",  "kneeR",     78),
    ("torso",      ("neck", "hipC"),        None,          "hipC",      None),
    ("head",       ("head", "neck"),        None,          "neck",      None),
]
## 그리는 순서 — 몸통보다 앞에 오는 것이 뒤에 온다(팔이 몸을 가린다).
Z_ORDER = ["legL_upper", "legL_lower", "legR_upper", "legR_lower",
           "torso", "armL_upper", "armL_lower", "armR_upper", "armR_lower", "head"]


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


def split(img_rgba, J):
    """그림을 부품별 레이어로 나눈다. 픽셀마다 **가장 가까운 뼈**에 준다."""
    a = np.asarray(img_rgba)
    H, W = a.shape[:2]
    ys, xs = np.mgrid[0:H, 0:W]
    best = np.full((H, W), np.inf); who = np.full((H, W), -1, np.int8)
    for i, (name, (p, q), _, _, r) in enumerate(PARTS):
        d = _seg_dist(xs, ys, J[p], J[q])
        if r is not None:
            d = np.where(d > r, np.inf, d)     # 제 굵기 밖으로는 안 뻗는다
        m = d < best
        best = np.where(m, d, best); who[m] = i
    layers = {}
    for i, (name, _, _, _, _) in enumerate(PARTS):
        lay = np.zeros_like(a)
        m = (who == i) & (a[..., 3] > 0)
        lay[m] = a[m]
        layers[name] = Image.fromarray(lay, 'RGBA')
    return layers


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_player import cutout
    src, keep = cutout(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else SOURCE))
    rgba = np.dstack([np.asarray(src), (keep*255).astype(np.uint8)])
    J = joints(arm_deg=SOURCE_ARM_DEG)
    layers = split(Image.fromarray(strip_outline(rgba), 'RGBA'), J)
    # 부품을 색으로 칠해 확인
    COLORS = [(255,80,80),(255,160,80),(80,160,255),(80,220,255),
              (120,255,120),(200,255,120),(255,120,255),(255,200,255),
              (200,200,200),(255,255,120)]
    prev = Image.new('RGB', src.size, (24,24,28))
    for i,(name,_,_,_,_) in enumerate(PARTS):
        m = np.asarray(layers[name])[...,3] > 0
        p = np.asarray(prev).copy(); p[m] = COLORS[i]; prev = Image.fromarray(p)
    prev.save(os.path.expanduser("~/Desktop/rig_parts.png"))
    print("부품:", ", ".join(n for n,_,_,_,_ in PARTS))
    print("→ ~/Desktop/rig_parts.png")


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


def compose(layers, J, xf):
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
    meta = {n: (par, piv) for n, _, par, piv, _ in PARTS}
    for name in Z_ORDER:
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


def hold_front(raise_=26.0, elbow=30.0, grow=0.06):
    """도구를 든 자세 (정면·뒷모습). **오른팔만 든다** — 도구는 오른손에 쥔다.
    정면에서 「앞으로 든다」는 화면에서 **위로 조금 · 크게**다(원근 축약)."""
    return {"armR_upper": {"dy": -raise_, "scale": 1 + grow},
            "armR_lower": {"dy": -elbow,  "scale": 1 + grow}}


def hold_side(shoulder=-32.0, elbow=-24.0):
    """도구를 든 자세 (옆모습). 이쪽은 회전이다 — 팔을 앞으로 든다."""
    return {"armR_upper": {"rot": shoulder}, "armR_lower": {"rot": elbow},
            "armL_upper": {"rot": shoulder*0.35}}


def use_front(swing=34.0, elbow=40.0, grow=0.10):
    """휘두르기 (정면·뒷모습). 들어올렸다 내려친다 — 화면에서는 위아래 + 크기다."""
    return [{"armR_upper": {"dy": swing*s,  "scale": 1 + grow*(-s)},
             "armR_lower": {"dy": elbow*s,  "scale": 1 + grow*(-s)},
             "armL_upper": {"dy": swing*s*0.3}} for s in SWING]


def use_side(shoulder=62.0, elbow=38.0):
    """휘두르기 (옆모습). 어깨를 크게 돌린다 — 도끼질이 안 보이면 패는 게 아니다."""
    return [{"armR_upper": {"rot": shoulder*s}, "armR_lower": {"rot": max(0.0, elbow*s)},
             "armL_upper": {"rot": shoulder*s*0.3}} for s in SWING]


def _merge(a, b):
    """두 자세를 겹친다 — 같은 부품이면 b 가 이긴다(도구 쪽 팔이 걷기를 덮는다)."""
    out = {k: dict(v) for k, v in a.items()}
    for k, v in b.items():
        out[k] = dict(out.get(k, {}), **v)
    return out


def hold(front=True):
    return [hold_front() if front else hold_side()]


def use(front=True):
    return use_front() if front else use_side()


def walk_tool(front=True):
    """도구를 든 채 걷기 — 걷기에 「든 팔」을 덮는다."""
    base = walk_front() if front else walk_side()
    h = hold_front() if front else hold_side()
    return [_merge(f, h) for f in base]


def hand_point(J, xf, side="R"):
    """도구 그림을 얹을 자리 — 변환을 다 거친 뒤의 손 좌표(1024px 원본 기준).

    아직 쓰이지 않는다(도구 그림이 96px 판으로 없다). **도구 그림이 생기면**
    여기서 받은 좌표에 얹고 나서 `bake_rows` 로 넘기면 손에 쥔 것이 된다.
    """
    meta = {n: (par, piv) for n, _, par, piv, _ in PARTS}
    name = "arm%s_lower" % side
    chain = []
    n = name
    while n is not None:
        par, piv = meta[n]
        chain.append((n, piv)); n = par
    chain.reverse()
    M = np.eye(3)
    for nm, piv in chain:
        t = xf.get(nm) or {}
        M = _mat(J[piv], t.get("rot", 0.0), t.get("scale", 1.0),
                 t.get("dy", 0.0), t.get("dx", 0.0)) @ M
    p = np.array([J["hand%s" % side][0], J["hand%s" % side][1], 1.0])
    q = M @ p
    return (float(q[0]), float(q[1]))


def bake_rows(rows, layers, J, cell=96):
    """방향별 자세 목록 → 방향별 칸 목록.

    **시트 한 장의 모든 칸이 같은 테두리와 같은 팔레트를 쓴다.**
      - 같은 테두리: 프레임마다 제 몸에 맞춰 자르면 축소 배율이 달라져 캐릭터가
        들썩이고, 방향마다 크기가 달라진다.
      - 같은 팔레트: 프레임마다 색을 따로 줄이면 팔레트가 미세하게 달라져 **모든
        픽셀이 조금씩 변한다** — 그건 걷기가 아니라 깜빡임이다(실측 56%).
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_player import downscale
    flat = [x for r in rows for x in r]
    bigs = [compose(layers, J, a) for a in flat]
    # **발을 땅에 맞춘다 — 밀지 말고 넘친 것을 자른다.**
    # 프레임을 통째로 밀면 96px 로 줄일 때 그 밀린 양(1024px 에서 몇 px)이 위쪽 한 줄의
    # 커버리지를 뒤집어서 **머리가 1px 흔들린다**(실측: 옆모습 걷기에서 아랫줄 편차가
    # 5px 이었고, 그 탓에 변화의 14%가 머리에 있었다). 제일 높은 아랫줄에 맞춰 그
    # 아래를 잘라내면 머리는 한 픽셀도 안 움직인다 — 잘려나가는 것은 흔드는 발의
    # 신발 끝 몇 px 뿐이라 96px 에서는 보이지 않는다.
    bots = [int(np.flatnonzero((np.asarray(b)[..., 3] > 0).sum(1) > 0).max()) for b in bigs]
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
    ys, xs = np.where(union)
    box = (int(ys.min()), int(ys.max())+1, int(xs.min()), int(xs.max())+1)
    cells = [downscale(Image.fromarray(np.asarray(b)[..., :3]), k, cell=cell, box=box)
             for b, k in zip(bigs, keeps)]      # **색은 아직 안 줄인다** — 부르는 쪽이 한 번에 한다
    out = []; at = 0
    for r in rows:
        out.append(cells[at:at+len(r)]); at += len(r)
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
        name = {"front": "down", "left": "left", "back": "up"}[face]
        out[name] = (split(Image.fromarray(strip_outline(q), 'RGBA'), J), J)
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
    """
    rigs = load_sheet(src) if (src or SHEET) else load_dirs()
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "assets", "sprites")
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
            plans["use_%s" % t] = {"down": use(True), "left": use(False), "up": use(True)}
    for motion, per_dir in plans.items():
        # **방향마다 원본이 다르므로 따로 굽는다.** 그래도 크기는 맞아야 하니
        # 칸 안에서 발밑이 아랫줄에 오게 굽는 규칙(`bake_rows`)이 그대로 맞춰준다.
        baked = {}
        for d, frames in per_dir.items():
            layers, J = rigs[d]
            baked[d] = bake_rows([frames], layers, J, cell)[0]
        # **정면의 팔레트를 네 방향에 씌운다** — 방향마다 그림을 따로 뽑아서 옷 색이
        # 조금씩 다른데(뒷모습이 청바지가 되는 식), 이렇게 하면 색이 맞는다.
        from gen_player import quantize_all
        order = ["down", "left", "up"]
        flat = [c for d in order for c in baked[d]]
        q = quantize_all(flat, ref_cells=baked["down"])
        at = 0
        for d in order:
            n = len(baked[d]); baked[d] = q[at:at+n]; at += n
        rows_out = [baked["down"], baked["left"], mirror_cells(baked["left"]), baked["up"]]
        cols = max(len(r) for r in rows_out)
        sheet = np.zeros((cell*4, cell*cols, 4), np.uint8)
        for r, cells in enumerate(rows_out):
            for i, c in enumerate(cells):
                sheet[r*cell:(r+1)*cell, i*cell:(i+1)*cell] = c
        path = os.path.join(out_dir, "player_%s_%s.png" % (motion, style))
        Image.fromarray(sheet, 'RGBA').save(path)
        print("%s: %dx%d (4방향 × %d프레임, 칸 %dpx)"
              % (os.path.basename(path), cell*cols, cell*4, cols, cell))
