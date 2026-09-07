#!/usr/bin/env bash
# loop.sh — 자율 개발 루프. 한 바퀴에 INBOX 항목 하나를 처리한다.
#
# 한 바퀴:
#   1. INBOX에서 번호가 가장 작은 미완료 항목을 찾는다 (없으면 종료)
#   2. PROMPT.md 를 그대로 넘겨 `claude -p` 헤드리스 세션을 연다
#   3. 세션이 스스로 개발/QA/커밋/push 까지 한다 (README.md 설계)
#   4. 대시보드(docs/index.html)만 여기서 다시 그려서 커밋+push 한다
#
# 멈춤 조건: 큐 비었음 / STOP 파일 / 크레딧·사용량 한도 / 예산 초과 /
#            같은 항목 STUCK_REPEAT_LIMIT 회 연속 미완료
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=env.sh
source "$ROOT/env.sh"

HARNESS="$ROOT/.harness"
mkdir -p "$HARNESS"
LOG="$HARNESS/loop.log"
STOP_FILE="$HARNESS/STOP"
WARNING_FILE="$HARNESS/WARNING"
LAST_ITEM_FILE="$HARNESS/last_item"
REPEAT_FILE="$HARNESS/repeat_count"
INBOX="$ROOT/docs/feedback/INBOX.md"
PROMPT="$ROOT/PROMPT.md"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

render_and_push_dashboard() {
  /usr/bin/python3 "$ROOT/scripts/render_dashboard.py" >>"$LOG" 2>&1 || return 0
  git -C "$ROOT" add docs/index.html >/dev/null 2>&1
  if ! git -C "$ROOT" diff --cached --quiet -- docs/index.html 2>/dev/null; then
    git -C "$ROOT" commit -q -m "chore(dashboard): 진행 상황 갱신" >>"$LOG" 2>&1
    git -C "$ROOT" push -q "$PUSH_REMOTE" "HEAD:$PUSH_BRANCH" >>"$LOG" 2>&1 \
      || log "경고: 대시보드 push 실패 (다음 바퀴에 다시 시도)"
  fi
}

# 루프를 멈추고 그 이유를 대시보드 배너로 남긴다.
halt() {
  printf '%s\n\n(%s)\n' "$1" "$(date '+%Y-%m-%d %H:%M:%S')" > "$WARNING_FILE"
  log "== 멈춤: $1"
  render_and_push_dashboard
  exit "${2:-1}"
}

# 번호가 가장 작은 미완료 항목. 출력: "<번호><TAB><본문>" / 없으면 빈 문자열
next_item() {
  grep -E '^- \[ \] *#[0-9]+' "$INBOX" 2>/dev/null \
    | sed -E 's/^- \[ \] *#([0-9]+) *(.*)$/\1'$'\t''\2/' \
    | sort -n -k1,1 | head -1
}

# 크레딧/사용량 한도 문구 감지 (claude 자체의 한도 — 예산과는 별개)
# 2026-09-07: `session limit` 이 빠져 있어서 실제 한도 응답
# ("You've hit your session limit · resets 9:50am")을 못 잡았다. 그 결과 한도 사건 하나가
# 평범한 실패 3회로 세어져서, 남은 재시도를 9초 만에 태우고 엉뚱한 사유로 멈췄다.
# 문구는 바뀔 수 있으므로 `hit your ... limit` 같은 느슨한 형태도 같이 본다.
CREDIT_RE='usage limit|session limit|rate limit|limit reached|hit your [a-z ]*limit|Credit balance is too low|insufficient credit|quota exceeded|Please run /login'

# --- 시작 전 확인 ---
[[ -f "$PROMPT" ]] || { echo "PROMPT.md 없음"; exit 1; }
[[ -f "$INBOX"  ]] || { echo "docs/feedback/INBOX.md 없음"; exit 1; }
command -v claude >/dev/null || { echo "claude CLI 없음"; exit 1; }
rm -f "$WARNING_FILE"
log "== 루프 시작 (model=$MODEL, budget=\$$MAX_BUDGET_USD_PER_LAP/바퀴, timeout=${LAP_TIMEOUT_SECONDS}s)"

while true; do
  if [[ -f "$STOP_FILE" ]]; then
    rm -f "$STOP_FILE"
    log "== STOP 파일 감지 — 정상 종료"
    render_and_push_dashboard
    exit 0
  fi

  ITEM="$(next_item)"
  if [[ -z "$ITEM" ]]; then
    log "== 큐가 비었음 — 세션을 열지 않고 종료"
    render_and_push_dashboard
    exit 0
  fi
  NUM="${ITEM%%$'\t'*}"
  TEXT="${ITEM#*$'\t'}"

  # 같은 항목 연속 실패 카운트
  PREV="$(cat "$LAST_ITEM_FILE" 2>/dev/null || echo '')"
  COUNT="$(cat "$REPEAT_FILE" 2>/dev/null || echo 0)"
  if [[ "$PREV" == "$NUM" ]]; then COUNT=$((COUNT + 1)); else COUNT=1; fi
  echo "$NUM" > "$LAST_ITEM_FILE"; echo "$COUNT" > "$REPEAT_FILE"
  if (( COUNT > STUCK_REPEAT_LIMIT )); then
    halt "INBOX #$NUM 이 ${STUCK_REPEAT_LIMIT}회 연속 미완료입니다 — 사람이 확인해 주세요.
  항목: $TEXT
  docs/STATUS.md 의 '막힌 것 / 보류'를 보세요."
  fi

  log "-- 바퀴 시작: INBOX #$NUM (연속 ${COUNT}/${STUCK_REPEAT_LIMIT}회차) — $TEXT"

  # 바퀴를 **시작할 때도** 대시보드를 그린다. 끝난 뒤에만 그리면, 사람이 INBOX 에
  # 항목을 넣고 루프를 켠 직후부터 첫 바퀴가 끝날 때까지(최대 LAP_TIMEOUT_SECONDS,
  # [DESIGN] 은 실제로 40분) 공개 대시보드가 "남은 0" 인 옛 상태 그대로 남는다 —
  # 루프가 안 도는 것처럼 보인다(2026-09-07 사람이 실제로 그렇게 오해했다).
  render_and_push_dashboard

  OUT_JSON="$HARNESS/lap_${NUM}_$(date +%s).json"
  # PROMPT.md 를 그대로 세션에 넘긴다. 세션이 커밋/push 까지 스스로 한다.
  claude -p "$(cat "$PROMPT")" \
    --model "$MODEL" \
    --permission-mode "$PERMISSION_MODE" \
    --no-session-persistence \
    --output-format json \
    --add-dir "$ROOT" \
    >"$OUT_JSON" 2>>"$LOG" &
  CLAUDE_PID=$!

  # 타임아웃 감시 — **벽시계 기준**이다.
  # `sleep $LAP_TIMEOUT_SECONDS` 한 방으로 재면 맥이 잠든 동안 타이머까지 같이 멈춰서
  # 제한이 영영 안 걸린다(실제로 4시간 넘게 물린 바퀴를 90분 제한이 못 잡았다).
  # 30초씩 깨어나 `date +%s` 로 실제 경과를 비교하면 잠든 시간도 계산에 들어간다.
  # 출력은 버린다 — 안 그러면 감시 서브셸이 파이프를 붙들어 루프 종료 후에도 EOF 가 안 온다.
  LAP_START=$(date +%s)
  (
    while kill -0 "$CLAUDE_PID" 2>/dev/null; do
      sleep 30
      if (( $(date +%s) - LAP_START >= LAP_TIMEOUT_SECONDS )); then
        kill -TERM "$CLAUDE_PID" 2>/dev/null
        sleep 10
        kill -KILL "$CLAUDE_PID" 2>/dev/null
        break
      fi
    done
  ) >/dev/null 2>&1 &
  WATCHDOG=$!
  wait "$CLAUDE_PID"; RC=$?
  pkill -P "$WATCHDOG" >/dev/null 2>&1
  kill "$WATCHDOG" >/dev/null 2>&1
  wait "$WATCHDOG" 2>/dev/null

  if (( RC == 143 || RC == 137 )); then
    log "경고: 바퀴가 ${LAP_TIMEOUT_SECONDS}s 타임아웃으로 종료됨 (미완료 처리)"
  elif (( RC != 0 )); then
    log "경고: claude 종료코드 $RC"
  fi

  # 크레딧/사용량 한도 — LLM 판단이 아니라 스크립트가 기계적으로 감지한다
  if grep -qiE "$CREDIT_RE" "$OUT_JSON" 2>/dev/null || tail -50 "$LOG" | grep -qiE "$CREDIT_RE"; then
    # 감지된 문구를 그대로 보여준다 — 대개 "resets 9:50am" 처럼 **언제 풀리는지**가 들어 있어서,
    # 그게 없으면 사람이 언제 다시 켜야 할지 알 수 없다.
    HIT="$(grep -oiE "[^\"]*($CREDIT_RE)[^\"]*" "$OUT_JSON" 2>/dev/null | head -1)"
    halt "크레딧/사용량 한도에 걸린 것으로 보입니다. 한도가 풀린 뒤 ./ctl.sh start 로 다시 시작하세요.${HIT:+

  받은 문구: $HIT}"
  fi

  # 이번 바퀴 비용
  COST="$(/usr/bin/python3 -c "
import json
try:
    print(json.load(open('$OUT_JSON')).get('total_cost_usd') or 0)
except Exception:
    print(0)
" 2>/dev/null)"
  # 누적 비용은 제한과 무관하게 항상 기록한다 — 멈추진 않아도 얼마 썼는지는 보여야 한다.
  TOTAL="$(/usr/bin/python3 -c "
prev = 0.0
try:
    prev = float(open('$HARNESS/total_cost').read().strip() or 0)
except Exception:
    pass
t = prev + float('$COST' or 0)
open('$HARNESS/total_cost', 'w').write('%.4f' % t)
print('%.2f' % t)
" 2>/dev/null)"
  log "   비용: \$$COST  (누적 \$$TOTAL)"

  # MAX_BUDGET_USD_PER_LAP=0 이면 무제한 — 예산으로 멈추지 않는다 (env.sh 참고).
  if /usr/bin/python3 -c "import sys; sys.exit(0 if float('$MAX_BUDGET_USD_PER_LAP') > 0 else 1)" 2>/dev/null; then
    if /usr/bin/python3 -c "import sys; sys.exit(0 if float('$COST') > float('$MAX_BUDGET_USD_PER_LAP') else 1)" 2>/dev/null; then
      halt "한 바퀴 예산(\$$MAX_BUDGET_USD_PER_LAP)을 넘었습니다 (이번 바퀴 \$$COST). env.sh 의 MAX_BUDGET_USD_PER_LAP 를 확인하세요."
    fi
  fi

  # GOTCHAS.md 줄 수 — LLM 자율 판단에 맡기지 않고 스크립트가 직접 확인 (README.md 참고)
  GL="$(wc -l < "$ROOT/docs/GOTCHAS.md" 2>/dev/null | tr -d ' ')"
  if [[ -n "$GL" ]] && (( GL > GOTCHAS_MAX_LINES )); then
    log "   경고: docs/GOTCHAS.md 가 ${GL}줄 (>${GOTCHAS_MAX_LINES}) — 사람이 정리할 때가 됐습니다"
  fi

  # 항목이 완료됐는지 확인 (세션이 - [x] 로 바꿨는지).
  # 완료 항목은 `- [x] (2026-09-06) #1 ...` 처럼 번호 앞에 날짜가 붙으므로 그걸 삼킨다.
  if grep -qE "^- \[[xX]\][^#]*#${NUM}([^0-9]|$)" "$INBOX"; then
    log "-- 완료: INBOX #$NUM"
    rm -f "$LAST_ITEM_FILE" "$REPEAT_FILE"
  else
    log "-- 미완료로 남음: INBOX #$NUM (다음 바퀴 재시도)"
  fi

  render_and_push_dashboard
  log "-- 바퀴 끝. ${WAIT_BETWEEN_LAPS}s 대기"
  sleep "$WAIT_BETWEEN_LAPS"
done
