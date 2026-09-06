# STATUS — 이번 바퀴 작업 메모

> 매 바퀴 완전히 덮어쓴다. 영구 기록이 아니다 — 지난 이력은 `git log`를 본다.

## 마지막 갱신

2026-09-06 — INBOX #14 ([BUILD] 월드 안의 플레이어에게 슬롯에 저장된 외형 입히기) 완료.

## 만든 것

- **`player.gd` 에 `appearance` 속성.** 값을 넣으면 그 자리에서 시트를 다시 칠해
  `SpriteFrames` 를 갈아끼운다(`_apply_appearance()`). **빈 Dictionary 면 기본 외형**이라,
  슬롯을 안 거치고 월드 씬을 직접 띄워도(자체 QA 가 그 경로다) 캐릭터가 멀쩡히 뜬다.
- **`world.gd` 가 슬롯의 `appearance` 를 읽어 플레이어에게 넘긴다.** 슬롯이 없거나
  (`selected_slot < 0`) 옛 세이브라 `appearance` 가 없으면 빈 값 = 기본 외형이다.
- **`character_sprite.gd` 에 `idle_frames()`** — 칠한 텍스처를 `SpriteFrames` 로 잘라
  준다. 미리보기(`appearance_preview.gd`)와 월드의 캐릭터가 **같은 함수의 결과**라
  서로 어긋날 수가 없다.
- **`player_frames.gd` 의 `_slice()` 를 `slice_sheet()` 로 공개**했다(시트 배치 규칙은
  여전히 이 파일 한 곳에만 있다). 칠한 텍스처도 그대로 넘길 수 있다 — 팔레트 교체는
  알파를 안 건드려서 칸 배치가 그대로다.
- **`game/qa/qa_player_appearance.gd`**(새 검증):
  1) 월드 스프라이트가 커스터마이징 화면의 그림과 **네 방향 모두 픽셀 단위로 같은가**,
  2) 기준색이 한 픽셀도 안 남았는가, 3) **머리모양 시트가 실제로 바뀌었는가**(실루엣),
  4) 슬롯 없이 월드 씬만 띄워도 기본 외형으로 뜨는가. 캐릭터만 확대해 자른 캡처도 남긴다.
- `docs/DESIGN.md` 「캐릭터 커스터마이징 항목」에 이 경로를 한 항목으로 적었다.

## 스스로 판단해서 고친 부분

- **머리모양 검사를 "한 방향"이 아니라 "네 방향 전부 + 기본과 최소 한 방향 다름"으로
  잡았다.** 처음엔 뒷모습(up) 하나만 봤는데 **묶은머리 뒷모습은 짧은머리와 실루엣이
  완전히 같고 색만 다르다** — 그래서 올바른 구현인데도 검사가 실패했다. 방향 하나로
  머리모양을 판정할 수 없다.
- **외형을 `setup()` 의 인자가 아니라 속성으로 만들었다.** 나중에 다른 플레이어를
  그릴 때(멀티플레이) 이미 서 있는 캐릭터의 외형만 바꿔 끼울 일이 생기고, 속성이면
  대입 한 줄로 끝난다. `setup()` 은 지금대로 "월드에 세우는 일"만 한다.
- **칠하기에 실패해도 기준색 시트로는 서 있게 했다**(`_apply_appearance()` 의 폴백).
  스프라이트가 통째로 비면 그 자리에 아무것도 안 보여서 원인을 찾기 더 어렵다.
- 슬롯에서 읽은 `appearance` 가 Dictionary 가 아니면 무시한다(깨진 세이브 대비) —
  `slot_store.gd` 가 다른 필드에 하는 것과 같은 태도다.

## 어려움 / 에러와 해결

- `character_sprite.gd` 가 이미 `player_frames.gd` 를 preload 하고 있어서, 반대로
  `player_frames.gd` 에서 칠하는 코드를 부르면 순환 참조가 된다. **칠하는 쪽
  (`character_sprite.gd`)에 `idle_frames()` 를 두고 자르는 함수만 공개**해서 방향을
  한쪽으로 유지했다.
- 부모(`world.gd`)의 `_ready()` 는 자식(`player.gd`)의 `_ready()` **뒤에** 돈다 —
  그래서 기본 외형으로 한 번 굽고 슬롯 외형으로 한 번 더 굽는다. `_ready()` 에서
  `sprite_frames == null` 일 때만 굽게 해서 순서가 반대인 경우(외형을 먼저 넣은 경우)에는
  두 번 굽지 않는다. 34×34 열여섯 칸이라 실제 비용은 무시할 만하다.

## 자체 QA

- **새 검증 `qa_player_appearance` PASS** — 슬롯 외형(짙은 피부 / 은발 / 자주색 옷 /
  묶은머리) 네 방향 픽셀 일치, 기준색 21색 전부 사라짐, 실루엣이 묶은머리 시트와
  일치하고 짧은머리와는 3방향에서 다름, 슬롯 없이 띄운 월드도 기본 외형으로 뜸.
- **캡처를 눈으로 봤다**: `71_world_appearance_zoom`(고른 외형 그대로 — 짙은 피부에
  은발, 자주색 상의), `73_world_default_zoom`(슬롯 없이 띄운 월드 — 기본 외형).
- 기존 Godot QA 전부 재실행 PASS: `qa_uid_files` / `qa_world_gen` / `qa_player_world` /
  `qa_slot_store` / `qa_main_menu` / `qa_character_slots` / `qa_world_entry` /
  `qa_settings` / `qa_player_sprite` / `qa_character_sprite` / `qa_character_customize` /
  `qa_terrain_view`.

## 다음 바퀴가 알아야 할 것

- **#15(걷기 시트)가 생기면 `player.gd` 는 안 고쳐도 된다** — `_update_animation()` 이
  `walk_<방향>` 이 있으면 자동으로 쓴다. 대신 **칠하는 쪽에 모션이 하나 더 생긴다**:
  `character_sprite.gd` 의 `idle_frames()` 는 idle 시트 한 장만 자르므로, walk 시트도
  같이 칠해서 한 `SpriteFrames` 에 합치도록 넓혀야 한다(자르는 함수
  `PlayerFrames.slice_sheet()` 는 모션 이름을 이미 인자로 받는다).
- `qa_player_appearance.gd` 도 그때 walk 를 같이 보게 넓힐 것 — 지금은 idle 만 본다.

## 막힌 것 / 보류

없음.
