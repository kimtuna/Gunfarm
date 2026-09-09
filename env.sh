#!/usr/bin/env bash
# env.sh — 하네스 설정. loop.sh / ctl.sh 가 source 한다.
# 값을 바꾸면 다음 바퀴부터 적용된다(루프 재시작 불필요 — 매 바퀴 다시 읽는다).

# --- 세션 ---
MODEL="${MODEL:-opus}"                       # claude --model 에 넘길 값
PERMISSION_MODE="${PERMISSION_MODE:-bypassPermissions}"

# --- 한 바퀴의 한계 ---
# 한 바퀴가 이 금액을 넘기면 루프를 멈춘다. **0 = 무제한**(멈추지 않음).
# 2026-09-06 사람이 0 으로 정함 — [DESIGN] 바퀴는 "누가 봐도 퀄리티 좋다" 가 나올
# 때까지 후보를 반복 생성하는 게 정상이라 [BUILD] 보다 몇 배 비싸다. 여기서 끊으면
# 퀄리티 기준을 올려둔 의미가 없어진다. 누적 비용은 계속 기록·표시된다.
MAX_BUDGET_USD_PER_LAP="${MAX_BUDGET_USD_PER_LAP:-0}"
LAP_TIMEOUT_SECONDS="${LAP_TIMEOUT_SECONDS:-5400}"        # 90분. 넘기면 세션을 죽이고 미완료 처리
WAIT_BETWEEN_LAPS="${WAIT_BETWEEN_LAPS:-20}"              # 바퀴 사이 대기(초)

# --- 그림 루프 (loop_design.sh) ---
# **끝나는 조건은 돈도 바퀴 수도 아니다 — 「사람이 직접 보고 퀄리티가 안 떨어진다」다**
# (2026-09-10 사람 지적). 위 MAX_BUDGET_USD_PER_LAP 을 0 으로 정한 이유와 같다:
# 후보를 반복 생성하는 것이 정상이고, 돈으로 끊으면 퀄리티 기준을 올려둔 의미가 없다.
#
# 아래 둘은 **완료 조건이 아니라 안전장치**다 — 사람이 없는 동안 폭주하지 않게 하는 것.
# 걸리면 「끝났다」가 아니라 「와서 한 번 봐라」이고, `design start` 하면 누적을
# 이어받아 계속 돈다. **0 = 무제한이 기본이다.**
DESIGN_MAX_TOTAL_USD="${DESIGN_MAX_TOTAL_USD:-0}"     # 누적 비용 상한 (0=무제한)
DESIGN_MAX_LAPS="${DESIGN_MAX_LAPS:-0}"               # 한 번에 도는 바퀴 (0=무제한)

# --- 멈춤 조건 ---
STUCK_REPEAT_LIMIT="${STUCK_REPEAT_LIMIT:-3}"  # 같은 INBOX 번호가 연속 N회 미완료면 멈춘다
GOTCHAS_MAX_LINES="${GOTCHAS_MAX_LINES:-150}"  # docs/GOTCHAS.md 가 이 줄 수를 넘으면 경고(정리 필요)

# --- 알림 (macOS 알림 센터) ---
# 사람이 개입해야 할 때만 울린다: **큐가 빔** / **멈춤**(연속 실패, 리셋 시각을 못 읽은
# 한도). 한도 대기는 저절로 풀려서 이어 돌기 때문에 알리지 않는다 — 알림이 흔해지면
# 안 보게 된다. 0 이면 끈다.
NOTIFY="${NOTIFY:-1}"
NOTIFY_SOUND="${NOTIFY_SOUND:-Glass}"   # /System/Library/Sounds 의 이름 (Basso/Blow/Funk/Ping/Submarine 등)

# --- 경로 ---
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT/.venv/bin/python}"   # Pillow가 들어있는 venv
PUSH_REMOTE="${PUSH_REMOTE:-origin}"
PUSH_BRANCH="${PUSH_BRANCH:-main}"
