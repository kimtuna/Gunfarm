# STATUS — 이번 바퀴 작업 메모

> 매 바퀴 완전히 덮어쓴다. 영구 기록이 아니다 — 지난 이력은 `git log`를 본다.

## 마지막 갱신

2026-09-06 — INBOX #4 (캐릭터 커스터마이징 화면) 완료.

- `game/scripts/character_appearance.gd`: 고정 팔레트(피부 5 / 머리색 6 / 옷색 6 /
  머리모양 4)와 기본값·되감기·정규화·이름 다듬기. slot_store.gd 와 같은 이유로 노드를
  상속하지 않는 순수 클래스다. **저장에는 색이 아니라 id 문자열**을 넣는다 — 스프라이트를
  팔레트 교체로 만들 때 그 id 가 그대로 팔레트 키가 된다. 정한 값은 `docs/DESIGN.md`
  "캐릭터 커스터마이징 항목"에 표로 적어뒀다.
- `game/scenes/character_customize.tscn` + `scripts/character_customize.gd`: 이름 입력 +
  네 항목을 `<` / `>` 로 고르고 확정. 이름이 비면 확정 버튼이 잠긴다. 확정하면 슬롯에
  저장되고 곧바로 월드로 들어간다(DESIGN.md "클라이언트 화면 흐름" 그대로).
  자리만 잡아뒀던 `scripts/character_customize_stub.gd` 는 지웠다.
- `game/scripts/appearance_preview.gd`: 캐릭터 그림이 아직 없어서 **색 사각형을 쌓은
  사람 형태**로 미리보기를 그린다(`_draw()` 만 쓴다 — 스프라이트 없음). 머리모양 4종이
  실제로 달라 보이는지가 이 스크립트의 유일한 존재 이유다. 그림이 생기면 통째로
  스프라이트로 갈아끼운다.
- `slot_store.make_character()` 가 외형을 받아 저장하도록 인자를 하나 늘렸다.
- 자체 QA `game/qa/qa_character_customize.gd` 통과(스크린샷 10장을 직접 눈으로 확인 —
  머리모양 4종을 한 장씩 남겨서 서로 구별되는지 봤다). 확정 흐름이 "슬롯 화면 복귀"에서
  "월드 입장"으로 바뀌었으므로 `qa_character_slots.gd` 의 해당 단계도 같이 고쳤다.
  기존 `qa_slot_store.gd` / `qa_main_menu.gd` / `qa_settings.gd` 도 다시 돌려서 전부 PASS.

## 다음에 할 것

INBOX #5 (월드 생성 1단계 + 입장).

**#5 를 하는 세션에게**: `scripts/world_stub.gd` 가 지금 "어느 슬롯/캐릭터로 들어왔는지"만
보여주는 임시 화면이다. 슬롯에는 `world_seed` 자리가 이미 있고 지금은 항상 0 이다 —
시드를 언제 정해서 거기 넣을지(캐릭터 생성 시점 / 첫 입장 시점)를 #5 에서 정하면 된다.

**카메라를 건드리는 바퀴에게**: `game/qa/qa_settings.gd` 를 다시 돌려라. 해상도 4종 +
"창을 손으로 늘린 16:9 아닌 창"에서 카메라가 덮는 월드 사각형이 전부 같은지 자동으로
확인하고, `game/qa/world_range_probe.tscn`(시야 경계 안쪽 초록 / 바깥 빨강 표식)으로
눈으로도 볼 수 있게 캡처를 남긴다 — **빨간 표식이 찍히면 시야가 넓어진 것이다.**

**캐릭터 그림([DESIGN])을 만드는 바퀴에게**: 커스터마이징이 저장하는 id 들
(`character_appearance.gd` 의 `SKIN` / `HAIR_COLOR` / `CLOTHES_COLOR` / `HAIRSTYLE`)이
그대로 팔레트 키가 되도록 만들 것. 머리모양 4종 × 4방향 × 모든 모션이라는 비용은
DESIGN.md 에 적힌 대로 항목을 쪼개서 감당한다.

## 막힌 것 / 보류

없음.
