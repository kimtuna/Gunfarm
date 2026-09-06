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
  돌려주던 문제) 를 검증해서 그대로 살렸다 — 별도 커밋.

## 다음에 할 것

INBOX #2 (캐릭터 슬롯 화면).

## 막힌 것 / 보류

없음.
