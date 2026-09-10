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
INBOX="$ROOT/docs/INBOX.md"
PROMPT="$ROOT/docs/PROMPT.md"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

# 사람이 개입해야 할 때만 알린다(큐가 빔 / 멈춤). **한도 대기는 알리지 않는다** —
# 저절로 풀려서 이어 돌기 때문에 사람이 할 일이 없다. 알림이 흔해지면 안 보게 된다.
# osascript 가 없거나 실패해도 루프는 그대로 간다 — 알림은 부가 기능이다.
notify() {
  [[ "${NOTIFY:-1}" == "1" ]] || return 0
  command -v osascript >/dev/null 2>&1 || return 0
  local title="Gunfarm" sub="$1" body="$2"
  osascript -e "display notification \"${body//\"/}\" with title \"$title\" subtitle \"${sub//\"/}\" sound name \"${NOTIFY_SOUND:-Glass}\"" \
    >/dev/null 2>&1 || true
}

# ── git 자물쇠 ──────────────────────────────────────────────────────────
# **두 루프가 같은 저장소에 커밋한다.** 동시에 `git add`/`commit` 하면 `index.lock`
# 이 겹쳐서 커밋이 깨진다. `mkdir` 은 원자적이라 자물쇠로 쓴다(macOS 에 flock 이 없다).
GIT_LOCK="$ROOT/.harness/git.lock"
git_lock() {
  local i
  for i in $(seq 1 600); do            # 최대 10분 기다린다
    if mkdir "$GIT_LOCK" 2>/dev/null; then
      echo $$ > "$GIT_LOCK/pid"
      return 0
    fi
    # 자물쇠를 쥔 프로세스가 죽었으면 뺏는다 (안 그러면 영영 막힌다)
    local owner; owner="$(cat "$GIT_LOCK/pid" 2>/dev/null)"
    if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$GIT_LOCK"
      continue
    fi
    sleep 1
  done
  return 1
}
git_unlock() { rm -rf "$GIT_LOCK"; }

render_and_push_dashboard() {
  /usr/bin/python3 "$ROOT/scripts/render_dashboard.py" >>"$LOG" 2>&1 || return 0
  git_lock || { log "경고: git 자물쇠를 못 얻었다 — 이번 갱신은 건너뛴다"; return 0; }
  git -C "$ROOT" add docs/index.html >/dev/null 2>&1
  if ! git -C "$ROOT" diff --cached --quiet -- docs/index.html 2>/dev/null; then
    git -C "$ROOT" commit -q -m "chore(dashboard): 진행 상황 갱신" >>"$LOG" 2>&1
    git -C "$ROOT" pull -q --rebase "$PUSH_REMOTE" "$PUSH_BRANCH" >>"$LOG" 2>&1
    git -C "$ROOT" push -q "$PUSH_REMOTE" "HEAD:$PUSH_BRANCH" >>"$LOG" 2>&1 \
      || log "경고: 대시보드 push 실패 (다음 바퀴에 다시 시도)"
  fi
  git_unlock
}

# 루프를 멈추고 그 이유를 대시보드 배너로 남긴다.
halt() {
  printf '%s\n\n(%s)\n' "$1" "$(date '+%Y-%m-%d %H:%M:%S')" > "$WARNING_FILE"
  log "== 멈춤: $1"
  render_and_push_dashboard
  # 알림에는 첫 줄만 넣는다 — 멈춤 사유에 INBOX 항목 본문이 통째로 들어 있을 수 있고,
  # 그대로 밀어넣으면 알림 창이 넘쳐서 정작 무슨 일인지가 안 보인다.
  notify "루프가 멈췄습니다 — 확인이 필요합니다" "$(printf '%s' "$1" | head -1)"
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
[[ -f "$INBOX"  ]] || { echo "docs/INBOX.md 없음"; exit 1; }
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
    notify "할 일이 다 떨어졌습니다" \
      "완료 $(grep -cE '^- \[[xX]\]' "$INBOX" 2>/dev/null || echo 0)개. docs/INBOX.md 에 새 항목을 넣고 ./ctl.sh start"
    exit 0
  fi
  NUM="${ITEM%%$'\t'*}"
  TEXT="${ITEM#*$'\t'}"

  # `[ASK]` — 사람이 답을 줘야 하는 물음이다. **세션을 아예 열지 않는다.**
  # 2026-09-07: 세션이 판단이 필요한 것을 발견하면 INBOX 에 항목으로 남기는데, 그게
  # 보통 항목([BUILD])으로 들어가면 루프가 그냥 작업으로 알고 재시도한다. 실제로 #39
  # ("총알이 물에 막히는 게 맞는지 사람이 정해줄 것")가 세 바퀴를 돌며 매번 같은
  # 결론에 도달하고 $19 를 태웠다 — 답을 아는 주체가 세션이 아니라 사람이라, 몇 번을
  # 열어도 결과가 같다. 연속 실패 카운트를 건드리기 전에 먼저 걸러낸다.
  if [[ "$TEXT" == \[ASK\]* ]]; then
    halt "INBOX #$NUM 은 사람이 정해줘야 합니다 — 세션을 열지 않았습니다.
  항목: $TEXT
  정한 뒤 그 항목의 [ASK] 를 [BUILD]/[DESIGN] 으로 바꾸고 ./ctl.sh start 하세요." 0
  fi

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
  # 한도 감지를 **이번 바퀴가 쓴 줄에만** 걸기 위해 지금 로그 길이를 기억한다.
  # 2026-09-07: 한도에 걸릴 때 받은 문구를 로그에 남기게 했더니, 그 줄이 다음 바퀴의
  # `tail -50` 에 그대로 잡혀서 **성공한 바퀴 뒤에 한도로 오인해 멈췄다**(실제로 #31 이
  # 통과했는데 멈췄다). 옛 줄을 다시 읽지 않게 이번 바퀴 이후만 본다.
  LOG_MARK="$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')"
  LOG_MARK="${LOG_MARK:-0}"
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
  if grep -qiE "$CREDIT_RE" "$OUT_JSON" 2>/dev/null \
     || tail -n "+$((LOG_MARK + 1))" "$LOG" 2>/dev/null | grep -qiE "$CREDIT_RE"; then
    # 감지된 문구에는 대개 "resets 9:50am" 처럼 **언제 풀리는지**가 들어 있다.
    HIT="$(grep -oiE "[^\"]*($CREDIT_RE)[^\"]*" "$OUT_JSON" 2>/dev/null | head -1)"
    RESET_AT="$(/usr/bin/python3 "$ROOT/scripts/parse_reset.py" "$HIT" 2>/dev/null)"

    # 한도로 못 돈 바퀴는 **연속 실패로 세지 않는다.** 이걸 안 되돌리면 한도 한 번에
    # STUCK_REPEAT_LIMIT 이 다 타버린다(2026-09-07 에 실제로 그렇게 멈췄다).
    echo "$((COUNT - 1))" > "$REPEAT_FILE"

    # 언제 걸렸고 얼마나 굴린 뒤였는지 남긴다 — 대시보드가 이걸 읽어 한도 상태를 보여준다.
    # 한도 잔량 자체는 조회할 방법이 없어서, **창마다 얼마에서 걸렸는지**를 실측으로 쌓는 게
    # 지금 얻을 수 있는 유일한 눈금이다.
    printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "${RESET_AT:-0}" "$(cat "$HARNESS/total_cost" 2>/dev/null || echo 0)" "$HIT" \
      >> "$HARNESS/limit_log"

    if [[ -n "$RESET_AT" ]]; then
      # 60초 여유를 둔다 — 리셋 시각 정각에 깨면 아직 안 풀려 있을 수 있다.
      WAKE=$((RESET_AT + 60))
      log "== 한도에 걸림 — $(date -r "$RESET_AT" '+%H:%M') 리셋. 그때까지 자고 INBOX #$NUM 을 이어서 돈다"
      log "   받은 문구: $HIT"
      printf '%s\n\n(%s 까지 기다리는 중 — 자동으로 이어서 돕니다)\n' \
        "한도에 걸려 대기 중입니다. 사람이 할 일은 없습니다." "$(date -r "$RESET_AT" '+%H:%M')" > "$WARNING_FILE"
      render_and_push_dashboard

      # **벽시계로 잰다.** 한 번에 길게 자면 맥이 잠든 동안 타이머까지 멈춰서 영영 안 깬다
      # (바퀴 타임아웃에서 이미 겪은 문제다). 30초씩 깨어나 실제 시각을 비교한다.
      while (( $(date +%s) < WAKE )); do
        if [[ -f "$STOP_FILE" ]]; then
          rm -f "$STOP_FILE" "$WARNING_FILE"
          log "== 한도 대기 중 STOP 파일 감지 — 정상 종료"
          render_and_push_dashboard
          exit 0
        fi
        sleep 30
      done

      rm -f "$WARNING_FILE"
      log "== 한도 리셋됨 — 다시 시작"
      render_and_push_dashboard
      continue
    fi

    # 언제 풀리는지 못 읽었으면 짐작해서 자지 않는다 — 예전처럼 멈춰서 사람에게 넘긴다.
    halt "크레딧/사용량 한도에 걸린 것으로 보입니다. 한도가 풀린 뒤 ./ctl.sh start 로 다시 시작하세요.
  (리셋 시각을 문구에서 읽지 못해 자동 대기를 못 했습니다.)${HIT:+

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
