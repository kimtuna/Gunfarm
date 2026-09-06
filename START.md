# START.md — 프로젝트 시작 체크리스트

> 이 파일은 **한 번만 쓰는 부팅 문서**다. 프로젝트를 처음 세팅할 때만 보고, 루프가
> 실제로 돌기 시작하면 다시 읽을 일이 없다(`PROMPT.md`의 매 바퀴 읽기 목록에도
> 없음).

## 1. 문서 읽는 순서

1. **`README.md`** — 이 하네스가 왜 이렇게 설계됐는지(4단계 루프, STATUS.md/
   GOTCHAS.md 처리 방식 등).
2. **`DESIGN.md`** — 무엇을 만드는지, 전체를 읽는다.
3. **`PROMPT.md`** — 매 바퀴 세션에게 실제로 전달될 지시서. 지금 한 번 이해해두면
   루프 스크립트를 짤 때(4번) 뭘 구현해야 하는지 명확해진다.

`STYLE_GUIDE.md`/`VISION.md`/`GOTCHAS.md`는 지금 다 읽을 필요 없다 — 각 파일 맨
위에 언제 읽는지 적혀있다(`[DESIGN]` 태그일 때만 / 지금 범위 아님 / 문제 생겼을 때만).

## 2. 프로젝트 뼈대 만들기

- [ ] Godot 4 프로젝트를 `game/` 폴더에 새로 만든다.
- [ ] `game/qa/` 빈 폴더를 만든다(재사용 QA 스크립트를 쌓아둘 곳, `.gitkeep`로 커밋).
- [ ] `docs/` 폴더를 만들고 이 폴더(`new-hanes/`)의 문서들을 그대로 복사한다:
  - `docs/DESIGN.md`, `docs/STYLE_GUIDE.md`, `docs/VISION.md`, `docs/GOTCHAS.md`
  - (`GOTCHAS.md`는 지금 있는 내용 그대로 가져간다 — Godot 4 엔진 자체의 함정이라
    이 새 프로젝트에도 그대로 유효하다.)
- [ ] `docs/design_reference/`를 만들고 `style_ref_dragon.png`/
  `style_ref_fisherman.png`를 넣는다(`STYLE_GUIDE.md`가 가리키는 참고 이미지).
- [ ] `docs/feedback/INBOX.md`를 빈 템플릿으로 만든다 — 형식 설명 한 줄과
  `## 처리 대기` 헤더만 있으면 된다(예시: `- [ ] #1 여기에 내용을 적으세요`).
- [ ] `docs/STATUS.md`를 빈 템플릿으로 만든다 — `## 마지막 갱신` / `## 다음에 할 것`
  정도의 뼈대만(내용은 첫 바퀴가 채운다).
- [ ] `docs/index.html`을 최소한의 정적 HTML로 하나 만들어 커밋해둔다(3번의 GitHub
  Pages가 서빙할 대상 — 나중에 `loop.sh`가 매 바퀴 다시 그린다).

## 3. GitHub Pages로 진행 상황 대시보드 켜기

`docs/index.html`을 공개 URL로 자동 서빙하는 무료 정적 호스팅이다. 별도 서버 없음 —
push할 때마다 몇 분 안에 반영된다.

- [ ] GitHub에 저장소를 만들고 `origin`으로 연결, 첫 커밋을 push한다.
- [ ] 저장소 **Settings → Pages**에서 Source를 "Deploy from a branch"로,
  Branch를 `main` / `/docs`로 지정한다(또는 `gh repo edit <owner>/<repo>
  --enable-pages`).
- [ ] 몇 분 뒤 `https://<계정>.github.io/<저장소이름>/`에서 `docs/index.html`이
  보이는지 확인한다.

## 4. 하네스 스크립트 작성

`loop.sh`/`ctl.sh`/`env.sh`는 아직 없다 — `README.md`(설계와 이유)와 `PROMPT.md`
(매 바퀴 지시 내용)를 바탕으로 새로 짠다. 핵심만 요약하면:

- **`loop.sh`**: INBOX에서 번호가 가장 작은 미완료 항목을 찾아 `claude -p`에
  `PROMPT.md` 내용을 그대로 넘겨 헤드리스 세션을 연다(`--no-session-persistence`).
  큐가 비면 세션을 열지 않고 종료. 클로드 자체의 크레딧/사용량 한도 문구를 감지하면
  즉시 멈춘다. 같은 항목이 `STUCK_REPEAT_LIMIT`(예: 3)회 연속 미완료면 멈추고 알린다.
  매 바퀴 후 `docs/index.html`을 다시 그려서 커밋+push한다(작업 커밋의 push는
  세션이 이미 직접 했으므로, 여기선 대시보드만).
- **`ctl.sh`**: `start`(launchd 등록+즉시 시작, kickstart 성공 여부를 몇 초 안에
  확인하고 안 되면 직접 백그라운드 실행으로 폴백) / `stop` / `status` /
  `graceful-stop`(STOP 파일 생성).
- **`env.sh`**: `MODEL`, `MAX_BUDGET_USD_PER_LAP`, `LAP_TIMEOUT_SECONDS`,
  `WAIT_BETWEEN_LAPS`, `STUCK_REPEAT_LIMIT`, `PERMISSION_MODE=bypassPermissions`.

외부 API를 안 쓰므로(Pillow만 사용) API 키를 관리할 `secrets.env` 같은 파일은
필요 없다.

## 5. 첫 작업 큐잉 + 시작

- [ ] `docs/feedback/INBOX.md`에 `- [ ] #1 [BUILD] ...` 형식으로 첫 작업을 추가한다
  (보통 프로젝트 뼈대: 메인 메뉴, 캐릭터 슬롯 화면 등 — `DESIGN.md` "클라이언트
  화면 흐름" 참고).
- [ ] `./ctl.sh start`로 루프를 시작한다.

이후로는 사람이 `docs/feedback/INBOX.md`에 새 항목을 추가하고 `./ctl.sh start`로
깨우는 것 외에는 개입할 일이 없다.
