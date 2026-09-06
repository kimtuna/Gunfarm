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

## Python / Pillow

시스템 `python3` 은 3.9 이고 **Pillow 가 없다.** 그림 생성은 저장소 안의 venv 를 쓴다:

```
.venv/bin/python        # Python 3.13 + Pillow 12.3
```

venv 는 `.gitignore` 되어 있다(커밋하지 않는다). 없어졌으면 다시 만든다:

```
/opt/homebrew/bin/python3.13 -m venv .venv && .venv/bin/pip install Pillow
```

대시보드 렌더러(`scripts/render_dashboard.py`)만은 Pillow 가 필요 없어서 시스템
`/usr/bin/python3` 로 돈다.

## git

`origin` = https://github.com/kimtuna/Gunfarm.git, 기본 브랜치 `main`.
인증은 `gh` (keyring)로 이미 설정돼 있다 — `git push origin HEAD:main` 이 바로 된다.

## 하네스

`./ctl.sh status|start|stop|graceful-stop|logs`, 설정은 `env.sh`.
런타임 상태(로그/PID/바퀴별 JSON)는 `.harness/` 에 쌓이고 커밋하지 않는다.
대시보드: https://kimtuna.github.io/Gunfarm/ (`docs/index.html`, GitHub Pages `main` `/docs`)
