# 이 저장소의 실행 환경

> 게임 설계는 `docs/DESIGN.md`, 매 바퀴의 작업 지시는 `PROMPT.md` 에 있다.
> 이 파일은 **이 기계에서 무엇을 어떤 명령으로 돌리는가**만 적는다.

## Godot

PATH 에 `godot` 이 없다. 항상 전체 경로로 부른다:

```
/Applications/Godot.app/Contents/MacOS/Godot
```

- 프로젝트는 `game/` 이다 — `--path game` (또는 `game/` 안에서 `--path .`).
- 엔진 버전 4.7.2, `project.godot` 의 `config/features` 도 4.7 이다.
- **새 PNG 를 저장했으면 확인 전에 반드시 재임포트한다** (안 하면 옛 이미지가 로드된다):
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import`
- 로직만 검증: `--headless --path game --quit-after <프레임수>`
- **화면 캡처는 `--headless` 로 안 된다** — 캡처가 필요하면 `--headless` 를 빼고
  실제 렌더러로 띄운다. 자세한 함정은 `docs/GOTCHAS.md` 참고.

## Python — 그림 생성 / 절차적 생성

시스템 `python3` 은 3.9 이고 **Pillow 가 없다.** 그림·노이즈는 저장소 안의 venv 를 쓴다:

```
.venv/bin/python        # Python 3.13
```

들어있는 것:

| 패키지 | 쓰임 |
|---|---|
| `PIL` (Pillow) 12.3 | 도트 직접 찍기 — `[DESIGN]` 항목의 기본 도구 |
| `numpy` 2.5 | 배열로 픽셀 다루기. 팔레트 교체/색상 변형(옷색만 바꾸기)에 쓴다 |
| `opensimplex` 0.4.5 | 심리스 노이즈 — **절차적 맵 생성** |
| `hitherdither` | Floyd-Steinberg / Bayer 디더링 — 제한 팔레트에서 그라데이션 |
| `pyxelate` | **이미지 → 픽셀아트 변환** — 참고 그림을 도트로 바꿀 때 이걸 쓴다. 그냥 축소하면 픽셀마다 색이 달라져 도트가 아니라 「축소한 사진」이 된다(2026-09-08 실측: 축소는 평평한 면 1%, pyxelate 는 75%). **주의: PyPI 의 `pyxelate` 0.0.1 은 아무 기능이 없는 빈 껍데기다** — `pip install git+https://github.com/sedthh/pyxelate.git` 로 받아야 한다 |
| `skimage` 0.26 | 외곽선 추출, 형태 연산 |

venv 는 `.gitignore` 되어 있다(커밋하지 않는다). 없어졌으면 다시 만든다:

```
/opt/homebrew/bin/python3.13 -m venv .venv \
  && .venv/bin/pip install Pillow numpy opensimplex hitherdither scikit-image \
  && .venv/bin/pip install "git+https://github.com/sedthh/pyxelate.git"
```

대시보드 렌더러(`scripts/render_dashboard.py`)만은 이것들이 필요 없어서 시스템
`/usr/bin/python3` 로 돈다.

### 그림 방식 (사람이 정한 것)

**절차 생성이 기본이다. AI 생성물을 「자산」으로 쓰지 않는다** — `DESIGN.md` 「그래픽
파이프라인」 그대로다. **다만 「참고 자료」로는 쓴다**(2026-09-08 결정).

로컬에 **ComfyUI** 가 `~/ComfyUI` 에 설치돼 있다(SDXL Base 1.0 + 픽셀아트 LoRA, MPS).
띄우는 법:

```
cd ~/ComfyUI && ./venv/bin/python main.py --listen 127.0.0.1 --port 8188
```

- 뜨는 데 1분쯤 걸린다. `curl -s http://127.0.0.1:8188/system_stats` 가 응답하면 준비된 것이다.
- 그림은 `~/ComfyUI/output/` 에 쌓이고, **API 로 주문한다**(`POST /prompt`, 워크플로 JSON).
- **여기서 나온 그림은 `docs/design_reference/` 에 참고 자료로만 넣는다.** 게임 자산
  (`game/assets/`)으로 옮기지 않는다 — 이유는 `DESIGN.md` 「그래픽 파이프라인」에 있다
  (팔레트 교체가 안 되고, 92장을 일관되게 못 뽑는다).
- `Draw Things 2.app` 도 깔려 있지만 **API 를 GUI 에서 켜야 해서 세션이 못 쓴다.**
  ComfyUI 를 쓴다.

근거: 도구 4종 × 4방향 × (들고있기/사용/걷기) 세트가 서로 어긋나면 안 된다는
「캐릭터 애니메이션 — 절대 되돌리지 말 것」 규칙은, 같은 함수에 각도만 바꿔
호출하는 절차 생성이라야 공짜로 지켜진다.

## git

`origin` = https://github.com/kimtuna/Gunfarm.git, 기본 브랜치 `main`.
인증은 `gh` (keyring)로 이미 설정돼 있다 — `git push origin HEAD:main` 이 바로 된다.

### `*.gd.uid` 는 커밋한다 (2026-09-06 결정, INBOX #6)

Godot 은 `.gd` 마다 `res://` 경로를 해시한 uid 를 `<스크립트>.gd.uid` 에 적어둔다.
**새 스크립트를 만든 바퀴는 그 `.gd.uid` 도 같은 커밋에 같이 넣는다.** 스크립트를
지우면 짝이 되는 `.uid` 도 같이 지운다(고아 uid 를 남기지 않는다).

- 커밋하는 쪽을 고른 이유: 엔진이 권장하는 방식이고, **파일을 옮기거나 이름을 바꿔도
  uid 가 그대로 따라가서** 씬의 `uid://` 참조가 안 깨진다. 무시하면 그 순간
  경로 해시로 새로 만들어져 옛 참조와 어긋난다.
- diff 가 지저분해지지 않는다: uid 는 경로에서 결정되는 한 줄짜리 값이라 **한 번
  생기면 다시 바뀌지 않는다** — 새 스크립트당 한 줄 늘어날 뿐이다.
- 커밋 전에 `--import` 를 한 번 돌려야 새 스크립트의 `.uid` 가 생긴다.
- 검증: `--headless --path game --script qa/qa_uid_files.gd` (짝 맞음 + 고아 없음 +
  전부 git 추적 중인지 확인, 종료 코드로 판정).

### `*.import` 도 커밋한다 (2026-09-06 결정, INBOX #7)

PNG·SVG·오디오처럼 **임포트되는 자산마다** 생기는 `<자산>.import` 도 `.gd.uid` 와
똑같이 다룬다 — **자산을 만든 바퀴가 같은 커밋에 `.import` 도 같이 넣고**, 자산을
지우면 짝이 되는 `.import` 도 같이 지운다. (`.godot/` 는 계속 무시한다 — 거기 들어가는
`.ctex` 등 실제 임포트 결과물은 언제든 다시 만들어진다.)

- **`.import` 는 uid 와 달리 경로에서 되살릴 수 없는 정보를 갖고 있다.** `[remap]` 의
  `uid`/`path` 는 `res://` 경로에서 결정되지만(그래서 diff 가 지저분해지지 않는다),
  `[params]` 절의 임포트 설정(압축 모드, 밉맵, 알파 테두리 보정 등)은 **파일을 지우면
  기본값으로 되돌아간다.** 도트 그래픽은 이 설정이 그림 품질을 직접 바꾸므로,
  무시하면 새 클론마다 조용히 다른 설정으로 임포트된다.
- `.gd.uid` 때와 같은 실험으로 확인했다: 임시 프로젝트에서 `.import` 와 `.godot/` 를
  지우고 재임포트해도 같은 경로면 `uid`/`path` 가 **똑같이** 나오고(그림 내용을 바꿔도
  같다), 경로가 달라야 값이 달라진다. 반면 손으로 바꾼 `[params]` 값은 재임포트해도
  유지되다가 파일을 지우는 순간 기본값으로 돌아갔다.
- 검증은 `.gd.uid` 와 같은 스크립트(`qa/qa_uid_files.gd`)가 함께 본다 — 자산에 짝
  `.import` 가 있는지, 고아 `.import` 가 없는지, 전부 git 에 추적되는지.

## 하네스

**루프가 둘이고 따로 돈다.**

| | 명령 | 큐 | 프롬프트 | 페이지 |
|---|---|---|---|---|
| 기능 | `./ctl.sh start\|stop\|status\|logs` | `docs/feedback/INBOX.md` | `PROMPT.md` | [대시보드](https://kimtuna.github.io/Gunfarm/) |
| **그림·모션** | `./ctl.sh design start\|stop\|status\|logs` | `docs/feedback/DESIGN_QUEUE.md` | `PROMPT_DESIGN.md` + `PROMPT_CRITIC.md` | [갤러리](https://kimtuna.github.io/Gunfarm/design.html) |

설정은 둘 다 `env.sh`. 런타임 상태(로그/PID/바퀴별 JSON)는 `.harness/` 에 쌓이고
커밋하지 않는다.

**그림 루프는 한 바퀴에 세션을 두 번 부른다** — 만드는 쪽(`PROMPT_DESIGN.md`)과
보는 쪽(`PROMPT_CRITIC.md`). 보는 쪽은 감상이 아니라 **「무엇을 어떻게 재라」**만
내놓는다. 규칙과 근거는 `docs/DESIGN_LOOP.md` 에 있다.
