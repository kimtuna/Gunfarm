#!/usr/bin/env python3
"""ComfyUI 에 캐릭터 그림을 주문한다 — 뼈대(OpenPose) 만들기 + API 주문.

띄우는 법은 저장소 루트 `CLAUDE.md` 에, **무엇을 왜 이렇게 주문하는가**는
`docs/CHARACTER.md` 에 있다. 여기는 그 절차를 코드로 옮긴 것뿐이다.

    .venv/bin/python game/tools/comfy.py            # 뼈대만 만들어 ~/ComfyUI/input/ 에 넣는다
    .venv/bin/python game/tools/comfy.py order      # 뼈대를 넣고 4방향 한 장을 주문한다

**4방향을 한 캔버스에 넣는다.** 방향마다 따로 뽑으면 같은 씨앗을 써도 캐릭터가
달라진다 — 머리색·옷 모양·몸 비율이 전부 어긋났다(2026-09-08 실측, `CHARACTER.md`
「방향 4장을 맞추기」). 한 장에 네 자세를 넣으면 **정의상 같은 캐릭터**다.
"""
import json
import math
import os
import sys
import urllib.error
import urllib.request
import uuid

from PIL import Image, ImageDraw

HOST = "http://127.0.0.1:8188"
INPUT_DIR = os.path.expanduser("~/ComfyUI/input")

# OpenPose(COCO 18점) 표준 색 — **이 색을 지켜야** ControlNet 이 어느 관절인지 알아본다.
JC = [(255,0,0),(255,85,0),(255,170,0),(255,255,0),(170,255,0),(85,255,0),(0,255,0),
      (0,255,85),(0,255,170),(0,255,255),(0,170,255),(0,85,255),(0,0,255),(85,0,255),
      (170,0,255),(255,0,255),(255,0,170),(255,0,85)]
LIMBS = [(1,2),(1,5),(2,3),(3,4),(5,6),(6,7),(1,8),(8,9),(9,10),(1,11),(11,12),(12,13),
         (1,0),(0,14),(14,16),(0,15),(15,17)]
LC = JC[:len(LIMBS)]

## 2×2 배치 — (가로중심, 위, 바라보는 쪽). `rig.SHEET_CELLS` 와 같아야 한다.
SHEET_SIZE = 1024
SHEET_CELLS = [(256, 40, "front"), (768, 40, "left"),
               (256, 552, "back"), (768, 552, "right")]
FIG_H = 420                 # 한 인물의 키(px)
FIG_HEADS = 3.6             # 등신수 — **비율은 프롬프트가 아니라 이 값이 정한다**
ARM_DEG = 10.0              # 팔을 몸에서 벌린 각도. 내린 자세여야 어깨가 안 망가진다


def figure(cx, top, h=FIG_H, heads=FIG_HEADS, arm_deg=ARM_DEG, face="front"):
    """관절 18점. `face` 는 front / left / right / back."""
    H = h / heads
    nose = top + H*0.50; neck = top + H*1.00
    hip = top + h*0.62; knee = top + h*0.81; foot = top + h*1.00
    er = H*0.30; up, fo = h*0.155, h*0.135
    side = face in ("left", "right")
    s = -1 if face == "left" else 1
    # **옆모습은 어깨·골반을 접는다** — 폭이 같으면 프롬프트에 side view 를 넣어도
    # 정면을 그린다(실측).
    sw = H*0.12 if side else h*0.105
    hw = H*0.10 if side else h*0.070
    t = math.radians(arm_deg); dx, dy = math.sin(t), math.cos(t)
    P = [None]*18
    P[0] = (cx + (s*er*0.9 if side else 0), nose); P[1] = (cx, neck)
    P[2] = (cx+sw, neck); P[5] = (cx-sw, neck)
    # 옆모습이면 두 팔이 **같은 쪽**(앞)으로 간다
    fr = s*h*0.035 if side else 0.0
    fl = -s*h*0.015 if side else 0.0
    P[3] = (cx+sw+up*dx+fr, neck+up*dy); P[4] = (P[3][0]+fo*dx, P[3][1]+fo*dy)
    P[6] = (cx-sw-up*dx+fl, neck+up*dy); P[7] = (P[6][0]-fo*dx, P[6][1]+fo*dy)
    P[8] = (cx+hw, hip); P[11] = (cx-hw, hip)
    P[9] = (cx+hw, knee); P[10] = (cx+hw, foot)
    P[12] = (cx-hw, knee); P[13] = (cx-hw, foot)
    if face == "front":
        P[14] = (cx+er*0.55, nose-er*0.35); P[15] = (cx-er*0.55, nose-er*0.35)
        P[16] = (cx+er*1.10, nose-er*0.20); P[17] = (cx-er*1.10, nose-er*0.20)
    elif face == "back":                      # **코도 눈도 없다 — 뒤통수**
        # OpenPose 는 뒤에서 본 사람을 「코 없이 귀 둘」로 적는다. 그 규약을 지킨다.
        # **다만 이것만으로는 뒷모습이 안 나온다** (2026-09-08, INBOX #56 실측:
        # 코를 빼도, 좌우를 바꿔도 여섯 장 전부 얼굴이 그려졌다). 뒷모습을 만드는
        # 것은 뼈대가 아니라 **아래 `GRID` 프롬프트**다.
        P[0] = None
        P[16] = (cx+er*1.00, nose-er*0.20); P[17] = (cx-er*1.00, nose-er*0.20)
    else:                                     # 보이는 쪽 눈 하나 + 반대쪽 귀
        P[14 if s > 0 else 15] = (cx+s*er*1.20, nose-er*0.35)
        P[17 if s > 0 else 16] = (cx-s*er*0.55, nose-er*0.20)
    return P


def sheet_skeleton(path=None):
    """4방향 뼈대 한 장. `~/ComfyUI/input/` 에도 넣는다(거기 있어야 주문할 수 있다)."""
    im = Image.new('RGB', (SHEET_SIZE, SHEET_SIZE), (0, 0, 0))
    d = ImageDraw.Draw(im)
    for cx, top, face in SHEET_CELLS:
        P = figure(cx, top, face=face)
        for i, (a, b) in enumerate(LIMBS):
            if P[a] and P[b]:
                d.line([P[a], P[b]], fill=LC[i], width=6)
        for i, p in enumerate(P):
            if p:
                r = 8 if i in (0, 14, 15, 16, 17) else 5   # 머리 관절은 크게 = 큰 머리 신호
                d.ellipse([p[0]-r, p[1]-r, p[0]+r, p[1]+r], fill=JC[i])
    out = path or os.path.join(INPUT_DIR, "pose_sheet4.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.save(out)
    return out


## 프롬프트 — **여기 규칙은 값을 치르고 알아낸 것이다** (`docs/CHARACTER.md` 2절).
##   · 그림자 금지: 96px 에서 회색 옷과 색으로 구별되지 않아 프로그램으로 못 뗀다.
##   · 손 명시: 팔을 내리라고만 하면 AI 가 손을 안 그리고 소매를 뭉갠다.
##   · 옷을 못 박기: 안 그러면 방향마다 옷이 달라진다(정면만 반바지가 됐다).
##
## **칸마다 무엇을 그릴지 말로 적어야 뒷모습이 나온다** (2026-09-08, INBOX #56).
## `front view, side view, back view, side view` 처럼 나열만 하면 **네 칸이 전부 얼굴**로
## 나온다 — 씨앗 여섯 장, 뼈대 세 가지(코 빼기 / 좌우 바꾸기 / 그대로)를 다 시험해도
## 한 장도 뒤를 안 봤다. `bottom left ...` 처럼 **자리를 집어 말한** 순간 세 장 중 세 장이
## 제대로 나왔다. **뼈대는 자세를 정하지만 「어느 쪽을 보는가」는 글이 정한다.**
GRID = ("character turnaround reference sheet, 2x2 grid of the SAME character, "
        "top left front view facing the viewer, top right side profile view, "
        "bottom left rear view seen from behind showing only the back of the head and hair, "
        "faceless from behind, bottom right side profile view, "
        "consistent design across all four views, ")

## 사람이 주문한 것: **여자, 귀엽게** (INBOX #56). 큰 눈 · 볼 홍조 · 3등신.
BODY = ("cute chibi pixel art sprite of a young female farmer, "
        "3 head tall proportions, big round head, big expressive eyes, rosy cheeks, "
        "friendly smile, long wavy auburn hair worn loose down her back, "
        "white short sleeve shirt, teal overall shorts with shoulder straps, "
        "knee length, bare lower legs, tall brown boots, "
        "arms straight down along the body, both hands visible, clear hands, "
        "full body, standing idle, "
        "16-bit SNES JRPG overworld sprite, clean dark outline, flat cel shading, "
        "limited palette, plain solid grey background, no shadow, no cast shadow")
POS = GRID + BODY
## `reference sheet` 라고 하면 SDXL 이 **인물 옆에 소품을 같이 그린다**(화분·항아리·
## 얼굴 아이콘 — 실측). 여기서 막고, 그래도 남는 것은 `rig._only_figure()` 가 지운다.
NEG = ("drop shadow, cast shadow, ground shadow, floor shadow, shadow under feet, "
       "realistic proportions, tall, adult body, slim, long legs, small head, "
       "beard, mustache, muscular, male, "
       "blurry, antialiased, soft gradient, 3d render, photo, "
       "detailed background, scenery, grass, floor, text, watermark, label, "
       "long pants, trousers, jeans, covered legs, hat, cropped, headshot, "
       "different characters, inconsistent design, extra people, "
       "face on the back of the head, all four facing forward, ponytail, hair tie, "
       "item icons, props, plants, jars, pots, crops, flowers, furniture, tools, "
       "inventory sprite sheet, extra objects")


def workflow(seed, cn_strength=0.9, prefix="sheet4", pose="pose_sheet4.png",
             pos=None, neg=None):
    return {
      "1": {"class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": "sd_xl_base_1.0.safetensors"}},
      "2": {"class_type": "LoraLoader",
            "inputs": {"lora_name": "pixel_art_xl.safetensors",
                       "strength_model": 1.1, "strength_clip": 1.1,
                       "model": ["1", 0], "clip": ["1", 1]}},
      "3": {"class_type": "CLIPTextEncode", "inputs": {"text": pos or POS, "clip": ["2", 1]}},
      "4": {"class_type": "CLIPTextEncode", "inputs": {"text": neg or NEG, "clip": ["2", 1]}},
      "5": {"class_type": "EmptyLatentImage",
            "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
      "9": {"class_type": "LoadImage", "inputs": {"image": pose, "upload": "image"}},
      "10": {"class_type": "ControlNetLoader",
             "inputs": {"control_net_name": "OpenPoseXL2.safetensors"}},
      "11": {"class_type": "ControlNetApplyAdvanced",
             "inputs": {"strength": cn_strength, "start_percent": 0.0, "end_percent": 0.85,
                        "positive": ["3", 0], "negative": ["4", 0],
                        "control_net": ["10", 0], "image": ["9", 0]}},
      "6": {"class_type": "KSampler",
            "inputs": {"seed": seed, "steps": 28, "cfg": 7.5,
                       "sampler_name": "dpmpp_2m", "scheduler": "karras", "denoise": 1.0,
                       "model": ["2", 0], "positive": ["11", 0], "negative": ["11", 1],
                       "latent_image": ["5", 0]}},
      "7": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
      "8": {"class_type": "SaveImage", "inputs": {"filename_prefix": prefix, "images": ["7", 0]}},
    }


def send(wf):
    """주문 하나. 노드 배선이 틀리면 여기서 거절 내용을 그대로 찍고 죽는다."""
    data = json.dumps({"prompt": wf, "client_id": str(uuid.uuid4())}).encode()
    req = urllib.request.Request(HOST + "/prompt", data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=30))["prompt_id"]
    except urllib.error.HTTPError as e:
        print("ComfyUI 가 거절했다:", e.read().decode()[:1500])
        raise


def alive():
    try:
        urllib.request.urlopen(HOST + "/system_stats", timeout=5)
        return True
    except Exception:
        return False


if __name__ == "__main__":
    path = sheet_skeleton()
    print("뼈대:", path)
    if len(sys.argv) > 1 and sys.argv[1] == "order":
        if not alive():
            sys.exit("ComfyUI 가 안 떠 있다 — CLAUDE.md 의 띄우는 법 참고")
        for i, (seed, cn) in enumerate([(1111, 0.9), (2222, 0.9), (3333, 0.9),
                                        (4444, 1.0), (5555, 1.0), (6666, 0.8)]):
            print("g%d (seed %d, cn %.1f)" % (i, seed, cn),
                  send(workflow(seed, cn, "g%d" % i)), flush=True)
