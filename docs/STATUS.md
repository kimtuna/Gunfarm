# STATUS — 이번 바퀴 작업 메모

> 매 바퀴 완전히 덮어쓴다. 영구 기록이 아니다 — 지난 이력은 `git log`를 본다.

## 마지막 갱신

2026-09-06 — INBOX #2 (캐릭터 슬롯 화면) 완료.

- `game/scripts/slot_store.gd`: 슬롯 3개의 저장/불러오기. `user://characters.json`
  (`{"version": 1, "slots": [...]}`), 빈 슬롯은 빈 Dictionary. 노드를 상속하지 않는
  순수 클래스라 화면 없이 단독으로 돈다. **오토로드로 만들지 않았다** — 오토로드는
  `--script` 자체 QA에서 컴파일 에러를 내기 때문(GOTCHAS). 고른 슬롯 번호는 `static var`
  하나로 다음 화면에 넘긴다.
- 캐릭터 한 명의 저장 형식에 `appearance`(#4 가 채움)와 `world_seed`(#5 가 채움) 자리를
  미리 비워뒀다. 나중에 저장 형식을 갈아엎지 않으려는 것이고, 값은 아직 아무도 안 쓴다.
- `game/scenes/character_slots.tscn` + `scripts/character_slots.gd`: 슬롯 3줄(선택 버튼 +
  삭제 버튼), 뒤로 버튼, Esc. 삭제는 되돌릴 수 없어서 화면 안 확인창을 한 번 거친다
  (별도 창이 아니라 씬 안의 Control 이라 스크린샷에 그대로 찍힌다).
- `scenes/character_customize.tscn`(#4 자리), `scenes/world.tscn`(#5 자리)을 새로 만들었다.
  둘 다 뒤로/Esc 로 슬롯 화면으로 돌아온다.
- 자체 QA 셋 다 통과(스크린샷 13장을 직접 눈으로 확인):
  - `game/qa/qa_slot_store.gd` — **`--headless` 로 도는 저장소 단독 테스트.** 저장/불러오기
    왕복, 삭제, 깨진 파일, 모르는 버전. #4/#5 가 저장 형식을 넓힐 때 회귀 잡는 데 그대로 쓴다.
    (깨진 파일 테스트는 일부러 파일을 망가뜨려서 로그에 ERROR/WARNING 이 찍힌다 — 정상이다.)
  - `game/qa/qa_character_slots.gd` — 화면 전체 흐름. `--headless` 없이 돌려야 한다.
  - `game/qa/qa_main_menu.gd` — #1 것. 슬롯 화면 제목이 "캐릭터 슬롯"→"캐릭터 선택"으로
    바뀌어서 기대 문구만 고쳤다(기능 회귀 아님).

## 다음에 할 것

INBOX #3 (설정 화면 해상도 옵션).

**#4 를 하는 세션에게**: `scripts/character_customize_stub.gd` 의 "기본값으로 만들기" 버튼은
#4 가 오기 전까지 슬롯 저장/삭제를 실제로 눌러볼 수 있게 둔 임시 장치다. #4 는 이 스크립트를
통째로 갈아끼우고, `qa_character_slots.gd` 에서 그 버튼을 누르는 단계도 같이 고치면 된다.

## 막힌 것 / 보류

없음.
