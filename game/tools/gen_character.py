"""코어키퍼풍 캐릭터 절차 생성 — 슈퍼샘플 + 입체 음영 + 팔레트 디더링.

[출발점 구현이다. 그대로 쓰라는 게 아니라 docs/STYLE_GUIDE.md 의 파이프라인이 실제로
 돌아가는 예시다 — 더 낫게 만들 수 있으면 고쳐 쓴다. 실행: .venv/bin/python]


왜 이렇게 하나:
  도트를 한 픽셀씩 직접 찍으면 "평평"해진다(테두리에만 음영이 걸림). 대신
  1) 캐릭터를 입체 덩어리(구/캡슐/둥근상자)의 합으로 정의하고
  2) 12배 해상도에서 각 덩어리의 높이장(height field)을 만든 뒤 법선을 구해 램버트 조명을 계산하고
  3) 네이티브 34px 로 줄이고
  4) 재질별 팔레트 램프(4단계)에 **순서 디더링**으로 양자화한다.
  이러면 손으로 찍은 것 같은 또렷한 단차를 유지하면서도 형태가 입체로 읽힌다.

쓰는 것: numpy(전 과정), Pillow(입출력). 디더링은 4x4 Bayer 를 직접 쓴다 —
재질마다 램프가 달라서 이미지 전체를 한 팔레트로 떨구는 도구는 여기 안 맞는다.

크기: 네이티브 34px, 게임 화면 102px = 정확히 3배(정수 배율).
"""
import numpy as np
from PIL import Image
import os

N = 34          # 네이티브 캔버스
SS = 12         # 슈퍼샘플 배율
H = N * SS
OUT = os.environ.get("GEN_OUT") or os.path.dirname(os.path.abspath(__file__))
# 기본은 스크립트 옆. 저장소를 더럽히지 않으려면 GEN_OUT 으로 임시 폴더를 준다.

INK = np.array([38, 28, 44], dtype=np.uint8)

# 재질별 램프: 밝은쪽 → 어두운쪽 4단계
RAMPS = {
    "skin":  [(255, 224, 196), (240, 196, 160), (214, 160, 126), (176, 120, 94)],
    "hair":  [(150, 100, 62), (118, 76, 48), (90, 56, 36), (66, 40, 26)],
    "shirt": [(154, 202, 114), (116, 166, 86), (86, 128, 64), (62, 96, 48)],
    "pants": [(104, 118, 158), (78, 90, 126), (58, 68, 98), (42, 50, 74)],
    "boot":  [(112, 86, 64), (86, 64, 48), (64, 46, 34), (48, 32, 24)],
    "eye":   [(38, 28, 44), (38, 28, 44), (38, 28, 44), (38, 28, 44)],
}
MATS = list(RAMPS.keys())

BAYER4 = np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], dtype=np.float32) / 16.0


# ── 좌표 격자 (네이티브 단위, 슈퍼샘플 해상도) ──────────────────────────────
_yy, _xx = np.mgrid[0:H, 0:H].astype(np.float32)
GX = (_xx + 0.5) / SS
GY = (_yy + 0.5) / SS


def ellipsoid(cx, cy, rx, ry, squash=1.0):
    """구/타원체. 반환: (마스크, 높이 0..1)"""
    dx = (GX - cx) / rx
    dy = (GY - cy) / ry
    d2 = dx * dx + dy * dy
    m = d2 <= 1.0
    h = np.sqrt(np.clip(1.0 - d2, 0, 1)) * squash
    return m, h * m


def rbox(x0, y0, x1, y1, r=1.2, dome=0.75):
    """둥근 모서리 상자. 가운데가 살짝 부푼 원기둥 느낌의 높이장."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hw, hh = (x1 - x0) / 2, (y1 - y0) / 2
    qx = np.abs(GX - cx) - (hw - r)
    qy = np.abs(GY - cy) - (hh - r)
    d = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
    m = d <= 0
    # 가로 방향으로만 부풀린다(원기둥) — 세로로 긴 팔다리가 자연스럽다
    t = np.clip(np.abs(GX - cx) / max(hw, 1e-6), 0, 1)
    h = np.sqrt(np.clip(1 - t * t, 0, 1)) * dome
    return m, h * m


class Build:
    """재질 id / 높이장 / 부위 id 를 페인터 순서로 쌓는다.

    부위 id 를 따로 두는 이유: 팔과 몸통은 같은 'shirt' 재질이라 재질만으로는
    경계가 사라진다. 도트에서는 그 경계에 한 단계 어두운 내부선을 넣어야 형태가
    읽힌다 — 그 판정에 부위 id 를 쓴다.
    """

    def __init__(self):
        self.mat = np.full((H, H), -1, dtype=np.int8)
        self.hgt = np.zeros((H, H), dtype=np.float32)
        self.part = np.full((H, H), -1, dtype=np.int16)
        self._n = 0

    def add(self, shape, mat):
        m, h = shape
        self._n += 1
        self.mat[m] = MATS.index(mat)
        self.hgt[m] = h[m]
        self.part[m] = self._n
        return self

    def cut_above(self, shape, mat, ymax):
        """도형의 y<=ymax 부분만 (머리카락 덮개)."""
        m, h = shape
        m = m & (GY <= ymax)
        self._n += 1
        self.mat[m] = MATS.index(mat)
        self.hgt[m] = h[m]
        self.part[m] = self._n
        return self


def light(hgt, mat):
    """높이장의 기울기로 법선을 만들고 램버트 + 림라이트로 명도를 낸다."""
    # 슈퍼샘플 격자에서의 기울기 → 법선
    gy, gx = np.gradient(hgt.astype(np.float32), 1.0 / SS)
    nz = np.ones_like(hgt)
    nl = np.sqrt(gx * gx + gy * gy + nz * nz)
    nx, ny, nz = -gx / nl, -gy / nl, nz / nl

    L = np.array([-0.55, -0.68, 0.49], dtype=np.float32)   # 왼쪽 위 앞
    L /= np.linalg.norm(L)
    lam = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)

    # 위쪽에서 오는 은은한 환경광 + 아래쪽 어둡게
    amb = 0.42 + 0.18 * np.clip(nz, 0, 1)
    lum = np.clip(0.62 * lam + amb, 0, 1)
    lum[mat < 0] = 0
    return lum


def _blocks(a):
    return a.reshape(N, SS, N, SS).transpose(0, 2, 1, 3).reshape(N, N, SS * SS)


def downsample_part(part):
    """부위 id 는 최빈값으로 줄인다(평균이 의미 없는 라벨이므로)."""
    p4 = _blocks(part)
    out = np.full((N, N), -1, dtype=np.int16)
    best = np.zeros((N, N), dtype=np.int32)
    for v in np.unique(part):
        if v < 0:
            continue
        cnt = (p4 == v).sum(axis=2)
        win = cnt > best
        best = np.where(win, cnt, best)
        out = np.where(win, v, out)
    return out


def downsample(mat, lum):
    """네이티브 해상도로 줄인다. 재질은 최빈값, 명도는 평균."""
    m4 = _blocks(mat)
    l4 = _blocks(lum)

    out_m = np.full((N, N), -1, dtype=np.int8)
    out_l = np.zeros((N, N), dtype=np.float32)
    for i in range(len(MATS)):
        cnt = (m4 == i).sum(axis=2)
        if i == 0:
            best, best_i = cnt.copy(), np.where(cnt > 0, 0, -1)
        else:
            win = cnt > best
            best = np.where(win, cnt, best)
            best_i = np.where(win, i, best_i)
    # 절반 이상이 비어있으면 그 칸은 비운다(가장자리가 지저분해지지 않게)
    empty = (m4 < 0).sum(axis=2) > (SS * SS * 0.55)
    out_m = np.where(empty, -1, best_i).astype(np.int8)

    for i in range(len(MATS)):
        sel = m4 == i
        cnt = sel.sum(axis=2)
        s = (l4 * sel).sum(axis=2)
        take = (out_m == i) & (cnt > 0)
        out_l[take] = (s / np.maximum(cnt, 1))[take]
    return out_m, out_l


def quantize(mat, lum):
    """재질별 4단계 램프로 떨어뜨린다. 단계 사이는 Bayer 순서 디더링."""
    rgb = np.zeros((N, N, 4), dtype=np.uint8)
    by = np.tile(BAYER4, (N // 4 + 1, N // 4 + 1))[:N, :N]
    for i, name in enumerate(MATS):
        ramp = np.array(RAMPS[name], dtype=np.uint8)
        sel = mat == i
        if not sel.any():
            continue
        # 명도 0..1 → 램프 인덱스(어두울수록 큰 인덱스)
        t = np.clip(1.0 - lum, 0, 1) * (len(ramp) - 1)
        idx = np.floor(t + (by - 0.5) * 0.9)          # 디더링으로 단계 경계를 흩뿌린다
        idx = np.clip(idx, 0, len(ramp) - 1).astype(np.int32)
        rgb[sel] = np.concatenate([ramp[idx][sel], np.full((sel.sum(), 1), 255, np.uint8)], axis=1)
    return rgb


def inner_lines(rgb, mat, part):
    """다른 부위와 맞닿은 안쪽 픽셀을 한 단계 어둡게 해서 경계를 살린다.

    팔과 몸통은 같은 'shirt' 재질이라 음영만으로는 경계가 사라진다. 바깥
    외곽선처럼 잉크로 긋지 않고 **그 재질 램프의 가장 어두운 색**을 쓰는 게
    핵심이다 — 잉크로 그으면 캐릭터가 조각조각 잘려 보인다.
    """
    filled = mat >= 0
    p = part
    # 오른쪽/아래 이웃이 다른 부위면 그 픽셀을 어둡게 (광원이 왼쪽 위라 그늘 방향과 일치)
    diff = np.zeros((N, N), dtype=bool)
    diff[:, :-1] |= filled[:, :-1] & filled[:, 1:] & (p[:, :-1] != p[:, 1:])
    diff[:-1, :] |= filled[:-1, :] & filled[1:, :] & (p[:-1, :] != p[1:, :])
    for i, name in enumerate(MATS):
        if name == "eye":
            continue
        sel = diff & (mat == i)
        if sel.any():
            rgb[sel] = np.concatenate([np.array(RAMPS[name][-1], np.uint8), [255]])
    return rgb


def outline(rgb, mat):
    """칠해진 영역 바깥에 1px 잉크 테두리."""
    filled = mat >= 0
    pad = np.pad(filled, 1, constant_values=False)
    near = (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:])
    edge = near & ~filled
    rgb[edge] = np.concatenate([INK, [255]])
    return rgb


# ── 캐릭터 정의 ────────────────────────────────────────────────────────────
def character(direction="down", hair="short"):
    b = Build()

    # 비율: 머리 지름 ≈ 몸통 높이(치비지만 몸이 뭉개지지 않는 선).
    #   머리 y 2.5..15  /  몸통 y 15..24  /  다리 24..29  /  신발 29..31.5
    # 다리 / 신발
    b.add(rbox(12.2, 23.6, 16.6, 29.2, r=1.3), "pants")
    b.add(rbox(17.4, 23.6, 21.8, 29.2, r=1.3), "pants")
    b.add(rbox(11.9, 28.8, 16.9, 31.4, r=1.0), "boot")
    b.add(rbox(17.1, 28.8, 22.1, 31.4, r=1.0), "boot")

    # 몸통 (어깨가 머리보다 조금 좁다)
    b.add(rbox(11.8, 15.2, 22.2, 24.4, r=2.2, dome=0.95), "shirt")

    # 팔 — 몸통과 살짝 떨어뜨려 실루엣이 붙지 않게
    if direction in ("down", "up"):
        b.add(rbox(9.0, 15.8, 11.6, 22.4, r=1.2), "shirt")
        b.add(rbox(22.4, 15.8, 25.0, 22.4, r=1.2), "shirt")
        b.add(ellipsoid(10.3, 23.3, 1.7, 1.6), "skin")
        b.add(ellipsoid(23.7, 23.3, 1.7, 1.6), "skin")
    else:
        sx = 1 if direction == "right" else -1
        b.add(rbox(16.7 + sx * 3.4, 15.8, 19.3 + sx * 3.4, 22.4, r=1.2), "shirt")
        b.add(ellipsoid(18.0 + sx * 3.4, 23.3, 1.8, 1.7), "skin")

    # 머리 (치비 비율)
    hx = 17.0 + (1.3 if direction == "right" else -1.3 if direction == "left" else 0)
    b.add(ellipsoid(hx, 9.0, 7.2, 6.6, squash=1.0), "skin")

    # 머리카락
    head = ellipsoid(hx, 9.0, 7.4, 6.8, squash=1.05)
    if direction == "up":
        b.add(head, "hair")                       # 뒷모습 — 머리 전체가 머리카락
    elif hair == "short":
        b.cut_above(head, "hair", ymax=6.4)
        b.add(rbox(hx - 7.5, 5.8, hx - 5.9, 10.2, r=0.8), "hair")
        b.add(rbox(hx + 5.9, 5.8, hx + 7.5, 10.2, r=0.8), "hair")
    elif hair == "long":
        b.cut_above(head, "hair", ymax=5.6)
        b.add(rbox(hx - 8.0, 4.8, hx - 5.7, 17.5, r=1.1), "hair")
        b.add(rbox(hx + 5.7, 4.8, hx + 8.0, 17.5, r=1.1), "hair")
    elif hair == "bun":
        b.cut_above(head, "hair", ymax=6.0)
        b.add(ellipsoid(hx, 1.9, 2.9, 2.4), "hair")
        b.add(rbox(hx - 7.5, 5.8, hx - 5.9, 9.6, r=0.8), "hair")
        b.add(rbox(hx + 5.9, 5.8, hx + 7.5, 9.6, r=0.8), "hair")
    elif hair == "_unused":
        b.add(ellipsoid(hx, 2.6, 3.2, 2.6), "hair")
        b.add(rbox(hx - 8.3, 7.0, hx - 6.6, 10.6, r=0.8), "hair")
        b.add(rbox(hx + 6.6, 7.0, hx + 8.3, 10.6, r=0.8), "hair")

    mat, lum = b.mat, light(b.hgt, b.mat)
    m, l = downsample(mat, lum)
    pm = downsample_part(b.part)

    # 눈은 축소 뒤에 네이티브 격자에 직접 찍는다 — 줄이면서 뭉개지면 안 되므로
    def eye(x, y):
        for dx in (0, 1):
            for dy in (0, 1):
                if 0 <= y + dy < N and 0 <= x + dx < N and m[y + dy, x + dx] >= 0:
                    m[y + dy, x + dx] = MATS.index("eye")
                    l[y + dy, x + dx] = 0.0
    ox = int(round(hx - 17.0))
    if direction == "down":
        eye(13 + ox, 11); eye(20 + ox, 11)
    elif direction == "left":
        eye(12 + ox, 11)
    elif direction == "right":
        eye(21 + ox, 11)

    return outline(inner_lines(quantize(m, l), m, pm), m)


def to_img(rgb, scale=1):
    im = Image.fromarray(rgb, "RGBA")
    return im.resize((N * scale, N * scale), Image.NEAREST) if scale != 1 else im


def strip(imgs, pad=8, bg=(30, 28, 34, 255)):
    w = sum(i.width for i in imgs) + pad * (len(imgs) + 1)
    h = max(i.height for i in imgs) + pad * 2
    s = Image.new("RGBA", (w, h), bg)
    x = pad
    for im in imgs:
        s.alpha_composite(im, (x, pad)); x += im.width + pad
    return s


if __name__ == "__main__":
    dirs = ["down", "left", "right", "up"]
    strip([to_img(character(d), 6) for d in dirs]).save(f"{OUT}/v3_dirs.png")
    strip([to_img(character("down", h), 6) for h in ("short", "long", "bun")]).save(f"{OUT}/v3_hair.png")
    strip([to_img(character(d), 3) for d in dirs]).save(f"{OUT}/v3_actual.png")
    print("saved v3")
