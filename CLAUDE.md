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
| `pyxelate` | 이미지 → 픽셀아트 변환(다운샘플 + 팔레트 양자화) |
| `skimage` 0.26 | 외곽선 추출, 형태 연산 |

venv 는 `.gitignore` 되어 있다(커밋하지 않는다). 없어졌으면 다시 만든다:

```
/opt/homebrew/bin/python3.13 -m venv .venv \
  && .venv/bin/pip install Pillow numpy opensimplex hitherdither pyxelate scikit-image
```

대시보드 렌더러(`scripts/render_dashboard.py`)만은 이것들이 필요 없어서 시스템
`/usr/bin/python3` 로 돈다.

### 그림 방식 (사람이 정한 것)

**절차 생성이 기본이다.** AI 생성물을 자산으로 쓰지 않는다 — `DESIGN.md` 「그래픽
파이프라인」 그대로다. 로컬에 `Draw Things.app` 이 깔려 있지만 그건 사람이
**참고 이미지**(`docs/design_reference/`)를 만들 때 쓰는 것이지, 세션이 자산을
생성하는 경로가 아니다.

근거: 도구 4종 × 4방향 × (들고있기/사용/걷기) 세트가 서로 어긋나면 안 된다는
「캐릭터 애니메이션 — 절대 되돌리지 말 것」 규칙은, 같은 함수에 각도만 바꿔
호출하는 절차 생성이라야 공짜로 지켜진다.

## git

`origin` = https://github.com/kimtuna/Gunfarm.git, 기본 브랜치 `main`.
인증은 `gh` (keyring)로 이미 설정돼 있다 — `git push origin HEAD:main` 이 바로 된다.

## 하네스

`./ctl.sh status|start|stop|graceful-stop|logs`, 설정은 `env.sh`.
런타임 상태(로그/PID/바퀴별 JSON)는 `.harness/` 에 쌓이고 커밋하지 않는다.
대시보드: https://kimtuna.github.io/Gunfarm/ (`docs/index.html`, GitHub Pages `main` `/docs`)
