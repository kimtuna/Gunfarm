# STATUS — 이번 바퀴 작업 메모

> 매 바퀴 완전히 덮어쓴다. 영구 기록이 아니다 — 지난 이력은 `git log`를 본다.

## 마지막 갱신

2026-09-06 — INBOX #3 (설정 화면 해상도 옵션) 완료.

- `game/scripts/settings_store.gd`: 해상도 저장/불러오기/적용. `user://settings.json`
  (`{"version": 1, "resolution_width": .., "resolution_height": ..}`). slot_store.gd 와
  같은 이유로 노드를 상속하지 않는 순수 클래스다(오토로드는 `--script` 자체 QA에서
  컴파일 에러 — GOTCHAS). 모니터에 안 들어가는 해상도는 목록에서 걸러낸다.
- `game/scenes/settings.tscn` + `scripts/settings.gd`: `<` / `>` 로 해상도를 고르면
  그 자리에서 창에 적용되고 저장된다. 자리만 잡아뒀던 `scripts/menu_placeholder.gd` 는
  쓰는 곳이 없어져서 지웠다.
- 진입 씬(메인 메뉴)의 `_ready()` 에서 `SettingsStore.apply_saved()` 를 부른다 —
  오토로드를 안 쓰기로 한 이상 저장된 해상도를 창에 반영할 자리는 여기뿐이다.
- **`project.godot` 의 stretch aspect 를 `expand` → `keep` 으로 바꿨다.** 정한 값과
  근거는 `docs/DESIGN.md` "카메라 / 해상도"에 적어뒀다.
- 자체 QA `game/qa/qa_settings.gd` 통과(스크린샷 9장을 직접 눈으로 확인). 기존
  `qa_main_menu.gd` / `qa_character_slots.gd` / `qa_slot_store.gd` 도 다시 돌려서 전부 PASS.

## 다음에 할 것

INBOX #4 (캐릭터 커스터마이징 화면).

**카메라를 건드리는 바퀴에게**: `game/qa/qa_settings.gd` 를 다시 돌려라. 해상도 4종 +
"창을 손으로 늘린 16:9 아닌 창"에서 카메라가 덮는 월드 사각형이 전부 같은지 자동으로
확인하고, `game/qa/world_range_probe.tscn`(시야 경계 안쪽 초록 / 바깥 빨강 표식)으로
눈으로도 볼 수 있게 캡처를 남긴다 — **빨간 표식이 찍히면 시야가 넓어진 것이다.**

**#4 를 하는 세션에게** (지난 바퀴에서 그대로 넘어온 메모):
`scripts/character_customize_stub.gd` 의 "기본값으로 만들기" 버튼은 #4 가 오기 전까지
슬롯 저장/삭제를 실제로 눌러볼 수 있게 둔 임시 장치다. #4 는 이 스크립트를 통째로
갈아끼우고, `qa_character_slots.gd` 에서 그 버튼을 누르는 단계도 같이 고치면 된다.

## 막힌 것 / 보류

없음.
