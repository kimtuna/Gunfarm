# STATUS — 이번 바퀴 작업 메모

> 매 바퀴 완전히 덮어쓴다. 영구 기록이 아니다 — 지난 이력은 `git log`를 본다.

## 마지막 갱신

2026-09-07 — INBOX #16 ([BUILD] 바라보는 방향을 이동 방향이 아니라 마우스 조준으로) 완료.

## 만든 것

- **`game/scripts/player_input.gd`(새 순수 클래스)** — 한 틱의 입력 한 벌
  (`move: Vector2i` + `aim_angle: float`). **이게 나중에 네트워크로 오갈 값이다**
  (DESIGN.md 「서버 권위」의 "입력만 보낸다"). 이동과 조준을 한 구조체에 같이 담는
  이유는 둘이 같은 순간의 입력이라서다 — 따로 보내면 서버에서 어긋난 짝으로
  시뮬레이션된다.
- **`player_motion.gd`**: `tick(move)` → `tick(input)`. 방향을 이동에서 뽑던
  `_facing_for()` 를 지우고 조준 각도를 4방향으로 스냅하는 `_facing_for_aim()` 로
  바꿨다. **원본 각도는 `aim_angle` 에 각도 그대로 남는다**(총알/시야 콘용) —
  꺼내 쓰기 쉽게 `aim_direction()` 도 같이 뒀다.
- **스냅 경계 히스테리시스 10도**(`FACING_HYSTERESIS`). 지금 방향을 45+10도까지
  붙잡는다. 정한 값은 `DESIGN.md` 「조작」에 적었다.
- **`player.gd`**: `aim_origin()`(조준 기준점) + `aim_angle_for(마우스 전역좌표)`
  까지만 노드가 하고, 그 각도를 쓰는 계산은 전부 코어에 있다. `read_input()` 이
  `Vector2i` 대신 `PlayerInput` 을 돌려준다.
- **검사 갱신**(INBOX #16 (3)):
  - `qa_player_world.gd` — 코어 쪽에 「조준이 방향을 정한다」 갈래를 새로 넣었다
    (4방향 스냅 / **게걸음**(왼쪽 이동 + 오른쪽 조준) / 경계 떨림 / 원본 각도 보존).
    화면 쪽은 네 짝 중 **셋을 일부러 어긋나게** 바꿨고, 서 있는 채 마우스만 돌리는
    검사와 **실제 마우스로 45도 경계를 흔드는** 검사를 더했다.
  - `qa_player_walk.gd` — `_press(이동, 조준)` 으로 쪼개고 어긋난 짝
    (왼쪽으로 걸으며 오른쪽 조준 → `walk_right`)을 넣었다.

## 스스로 판단해서 고친 부분

- **조준 기준점을 발밑이 아니라 몸 한가운데로 잡았다**(`aim_origin()`). 노드 원점이
  발밑이라 발에서 각도를 재면, 마우스를 캐릭터 가슴 높이에 두는 것만으로 "위쪽 조준"이
  되어 방향이 뒤집힌다. 그림 칸 절반(=51px) 위에서 잰다.
- **검사에서 각도를 코어에 직접 넣지 않고 `Input.warp_mouse()` 로 실제 마우스를 옮겼다.**
  각도를 직접 넣으면 정작 이번에 만든 "마우스 좌표 → 각도" 변환을 안 지나간다.
- **재현성 검사에서 조준 각도도 같이 흔든다.** 조준이 입력이 된 이상 재현성 검사가
  이동만 보면 반쪽이다.
- **`aim_direction()` 을 미리 뒀다.** 총알/시야 콘이 스냅된 `facing` 을 집어 쓰는 걸
  막으려면 "각도 쓰는 정식 통로"가 눈에 보이는 게 낫다.

## 어려움 / 에러와 해결

- **화면 쪽 「경계 흔들기」 검사가 처음엔 이가 없었다.** 히스테리시스를 0으로 만들어도
  통과했다 — 매 프레임 다른 자리로 `Input.warp_mouse()` 를 부르면 OS 가 커서 이동을
  합쳐버려서 마우스가 사실상 안 움직였다. **한 자리마다 3프레임씩 머물게** 고쳐서
  이가 생겼다(고치기 전/후를 히스테리시스 0으로 둘 다 확인). `docs/GOTCHAS.md` 의
  옛 `warp_mouse` 항목을 이 사실로 갱신했다.
- **경계 흔들기 검사가 직전 방향(위)을 섞어 읽었다.** 재기 시작하기 전에 오른쪽으로
  자리잡을 10프레임을 줘서 해결.
- `--headless` 로는 마우스가 없어 이 두 QA 가 전부 헛돈다 — 문서 주석에 있던 "캡처가
  안 된다"에 더해 **마우스 기반 검사도 안 된다**는 사실을 GOTCHAS 에 적었다.

## 자체 QA

- **검사에 이가 있는지 먼저 확인했다**: (1) `player.gd` 가 마우스를 무시하고 아래쪽
  고정 각도를 넘기게 바꿨더니 두 QA 가 9건 FAIL, (2) `FACING_HYSTERESIS` 를 0으로
  두었더니 코어·화면 양쪽의 경계 검사가 FAIL. 둘 다 원복 후 재통과.
- **캡처를 눈으로 봤다** — `51_move_left_aim_right`(왼쪽으로 걸으며 오른쪽 옆모습),
  `51_move_up_aim_down`(위로 걸으며 앞모습), `53_aim_up_standing`(선 채로 뒷모습),
  `83_walk_left_aim_right`(긴머리로도 같음). 네 장 모두 **이동 방향이 아니라 조준
  방향의 시트**가 나온다.
- Godot QA 전부 재실행 PASS: `qa_uid_files` / `qa_world_gen` / `qa_slot_store` /
  `qa_main_menu` / `qa_character_slots` / `qa_world_entry` / `qa_settings` /
  `qa_player_sprite` / `qa_character_sprite` / `qa_character_customize` /
  `qa_terrain_view` / `qa_player_appearance` / `qa_player_world` / `qa_player_walk`.

## 다음 바퀴가 알아야 할 것

- **#17(Esc 일시정지 메뉴)에서 "입력만 0 으로 넣는다"는 이제 `PlayerInput` 한 벌을
  비우는 것이다.** 다만 **조준까지 0 으로 만들지 말 것** — 각도를 0(오른쪽)으로 넣으면
  메뉴를 열 때마다 캐릭터가 오른쪽으로 홱 돈다. `player.gd` 의 `input_enabled` 가
  이미 "이동만 비우고 조준은 보던 각도 유지"로 동작한다.
- **#18(맵)의 화살표는 `motion.aim_angle`(또는 `aim_direction()`)을 쓴다** — `facing`
  은 45도로 뭉갠 값이라 맵에서 방향을 잃는다.
- **#19(17px 캐릭터)에서 `aim_origin()` 도 같이 따라온다** — `PlayerFrames.CELL *
  SCALE * 0.5` 로 계산하므로 캔버스를 17px 로 줄이면 저절로 맞는다. 다만
  `qa_player_world.gd` / `qa_player_walk.gd` 의 `_aim*()` 도 같은 식을 쓰므로
  그쪽도 같이 확인할 것.
- **`docs/GOTCHAS.md` 는 106줄**이다(한계 150줄).

## 막힌 것 / 보류

없음.
