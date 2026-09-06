# STATUS — 이번 바퀴 작업 메모

> 매 바퀴 완전히 덮어쓴다. 영구 기록이 아니다 — 지난 이력은 `git log`를 본다.

## 마지막 갱신

2026-09-06 — INBOX #1 (메인 메뉴 화면) 완료.

- `game/scenes/main_menu.tscn` + `scripts/main_menu.gd`: 플레이 / 설정 / 나가기.
  진입 씬(`run/main_scene`)을 이 씬으로 바꾸고 뼈대였던 `scenes/main.tscn`은 지웠다.
- `scenes/character_slots.tscn`(#2), `scenes/settings.tscn`(#3)은 제목만 있는 빈 화면.
  둘 다 `scripts/menu_placeholder.gd` 하나를 공유한다 — #2/#3이 내용을 채울 때
  이 스크립트를 각 화면 전용 스크립트로 갈아끼우면 된다.
- 메뉴 공용 버튼 모양은 `game/ui/menu_theme.tres`(도트 스타일이라 모서리 둥글리기 없음).
  라벨 크기/색은 씬 쪽 `theme_override`.
- 자체 QA: `game/qa/qa_main_menu.gd` — 세 버튼을 실제로 눌러 화면 전환과 종료를
  확인하고 스크린샷을 `user://qa_shots/`에 남긴다. 스크린샷 4장을 직접 눈으로 확인했다.
  `--headless` 없이 돌려야 한다: `godot --path game --script qa/qa_main_menu.gd`.
- 세션 시작 시 미커밋 상태였던 `ctl.sh`(로그 없을 때 `started_count`가 빈 문자열을
  돌려주던 문제) 를 검증해서 커밋하려 했는데, **같은 저장소의 다른 세션이 그 사이에
  같은 수정을 `28acd60`으로 먼저 커밋**했다. 그래서 내 커밋 `0c34928`에는 ctl.sh 변경이
  남아 있지 않고, 먼저 스테이징돼 있던 뼈대 씬 삭제(`scenes/main.tscn` 등)만 들어갔다 —
  **메시지와 내용이 어긋난 커밋이 하나 남았다.** 이미 push 된 뒤라 다른 세션과 겹칠
  위험을 감수하고 히스토리를 고치지는 않았다. 파일 내용 자체는 전부 정상이다
  (ctl.sh 수정 O, 뼈대 씬 삭제 O). 사람이 판단할 몫으로 남긴다.

## 다음에 할 것

INBOX #2 (캐릭터 슬롯 화면).

## 막힌 것 / 보류

없음.
