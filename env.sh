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

# --- 멈춤 조건 ---
STUCK_REPEAT_LIMIT="${STUCK_REPEAT_LIMIT:-3}"  # 같은 INBOX 번호가 연속 N회 미완료면 멈춘다
GOTCHAS_MAX_LINES="${GOTCHAS_MAX_LINES:-150}"  # docs/GOTCHAS.md 가 이 줄 수를 넘으면 경고(정리 필요)

# --- 경로 ---
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT/.venv/bin/python}"   # Pillow가 들어있는 venv
PUSH_REMOTE="${PUSH_REMOTE:-origin}"
PUSH_BRANCH="${PUSH_BRANCH:-main}"
