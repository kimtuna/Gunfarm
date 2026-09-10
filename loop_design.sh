#!/usr/bin/env bash
# loop_design.sh — 그림·모션 루프. `loop.sh` 와 **따로** 돈다.
#
# 규칙은 docs/DESIGN_LOOP.md, 큐는 docs/DESIGN_QUEUE.md.
#
# 한 바퀴:
#   1. 큐에서 번호가 가장 작은 미완료(`- [ ] #dN`) 항목을 찾는다
#   2. **만드는 세션** — PROMPT_DESIGN.md. 후보를 굽고 note.md 를 쓴다
#   3. **보는 세션**   — PROMPT_CRITIC.md. ②의 그림을 보고 「잴 것」을 critique.md 에 쓴다
#      (감상 금지 — 근거는 docs/DESIGN_LOOP.md 「판정자는 셋」)
#   4. 갤러리(docs/design.html)를 다시 그려 커밋+push
#
# **끝나는 조건은 돈도 바퀴 수도 아니다 — 「사람이 직접 보고 누가 봐도 퀄리티가
# 떨어지지 않는다」다** (docs/DESIGN_LOOP.md 「끝나는 조건은 하나다」).
# 이 스크립트의 상한들은 **완료 조건이 아니라 폭주 방지**이고 기본으로 꺼져 있다.
#
# 갈래 `[플레이]` 는 **루프가 아예 손대지 않는다** — 세션을 열지 않고 멈추고 사람을
# 부른다. 「어울리나」의 절반과 「적합한가」의 대부분은 돌려봐야 알기 때문이다.
#
# 항목 상태 셋:
#   - [ ]  미완료            루프가 집는다
#   - [~]  **사람 확인 대기**  화면에 보이는 것이 바뀌었다. 루프는 건너뛰고 다음으로
#   - [x]  완료              화면이 안 바뀌는 것(검사 추가·코드 정리)만 루프가 닫는다
#
# **화면이 바뀌는 항목은 루프가 못 닫는다** — `- [~]` 로 두고 다음 항목으로 간다.
# 안 그러면 항목 하나에 영원히 물리고, 무엇보다 **자는 못난 것을 걸러낼 뿐 좋은
# 것을 판정하지 못한다.**
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=env.sh
source "$ROOT/env.sh"

HARNESS="$ROOT/.harness/design"
mkdir -p "$HARNESS"
LOG="$ROOT/.harness/design.log"
STOP_FILE="$HARNESS/STOP"
WARNING_FILE="$HARNESS/WARNING"
REPEAT_FILE="$HARNESS/repeat_count"
LAST_ITEM_FILE="$HARNESS/last_item"
COST_FILE="$HARNESS/total_cost"
LAPS=0
QUEUE="$ROOT/docs/DESIGN_QUEUE.md"
P_MAKE="$ROOT/docs/PROMPT_DESIGN.md"
P_EYE="$ROOT/docs/PROMPT_CRITIC.md"

# 한 바퀴에 두 세션을 부르므로 각각의 제한은 절반으로 본다.
DESIGN_LAP_TIMEOUT="${DESIGN_LAP_TIMEOUT:-$((LAP_TIMEOUT_SECONDS))}"
EYE_TIMEOUT="${EYE_TIMEOUT:-900}"        # 보는 세션은 짧다 — 그림 몇 장 보고 쓰는 게 전부다
## 세션이 도는 동안 갤러리를 몇 초마다 갱신할 것인가. 한 바퀴가 20분인데 끝나야만
## 갱신되면 그동안 사람이 아무것도 못 본다(2026-09-10).
GALLERY_PUSH_SECONDS="${GALLERY_PUSH_SECONDS:-90}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

notify() {
  [[ "${NOTIFY:-1}" == "1" ]] || return 0
  command -v osascript >/dev/null 2>&1 || return 0
  osascript -e "display notification \"${2//\"/}\" with title \"Gunfarm — 그림\" subtitle \"${1//\"/}\" sound name \"${NOTIFY_SOUND:-Glass}\"" \
    >/dev/null 2>&1 || true
}

# 갤러리만 그린다 — **기존 대시보드(docs/index.html)는 건드리지 않는다.**
# 두 페이지가 서로를 못 깨게 스크립트도 파일도 따로다(docs/DESIGN_LOOP.md 「갤러리」).
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

render_and_push_gallery() {
  /usr/bin/python3 "$ROOT/scripts/render_design.py" >>"$LOG" 2>&1 || return 0
  git_lock || { log "경고: git 자물쇠를 못 얻었다 — 이번 갱신은 건너뛴다"; return 0; }
  git -C "$ROOT" add docs/design.html docs/design_reference >/dev/null 2>&1
  if ! git -C "$ROOT" diff --cached --quiet 2>/dev/null; then
    git -C "$ROOT" commit -q -m "chore(gallery): 그림 갤러리 갱신" >>"$LOG" 2>&1
    git -C "$ROOT" pull -q --rebase "$PUSH_REMOTE" "$PUSH_BRANCH" >>"$LOG" 2>&1
    git -C "$ROOT" push -q "$PUSH_REMOTE" "HEAD:$PUSH_BRANCH" >>"$LOG" 2>&1 \
      || log "경고: 갤러리 push 실패 (다음 바퀴에 다시 시도)"
  fi
  git_unlock
}

halt() {
  printf '%s\n\n(%s)\n' "$1" "$(date '+%Y-%m-%d %H:%M:%S')" > "$WARNING_FILE"
  log "== 멈춤: $1"
  render_and_push_gallery
  notify "그림 루프가 멈췄습니다" "$(printf '%s' "$1" | head -1)"
  exit "${2:-1}"
}

# 번호가 가장 작은 미완료 항목. 출력: "<번호><TAB><본문>"
next_item() {
  grep -E '^- \[ \] *#d[0-9]+' "$QUEUE" 2>/dev/null \
    | sed -E 's/^- \[ \] *#d([0-9]+) *(.*)$/\1'$'\t''\2/' \
    | sort -n -k1,1 | head -1
}

CREDIT_RE='usage limit|session limit|rate limit|limit reached|hit your [a-z ]*limit|Credit balance is too low|insufficient credit|quota exceeded|Please run /login'

# 프로세스와 **그 자식들을 전부** 죽인다.
# `kill $pid` 는 claude 만 죽인다 — 그 밑에서 돌던 Godot 이 고아로 남아 몇십 분씩
# CPU 를 먹는다(2026-09-10 실측: `ppid 1` 짜리 38분 된 qa_player_walk 가 살아 있었다).
kill_tree() {
  local pid="$1" sig="${2:-TERM}" c
  for c in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$c" "$sig"; done
  kill "-$sig" "$pid" 2>/dev/null
}

# `claude -p` 한 번. $1=프롬프트파일 $2=제한초 $3=결과JSON. 종료코드를 그대로 돌려준다.
run_session() {
  local prompt="$1" limit="$2" out="$3" pid start rc
  claude -p "$(cat "$prompt")" \
    --model "$MODEL" \
    --permission-mode "$PERMISSION_MODE" \
    --no-session-persistence \
    --output-format json \
    --add-dir "$ROOT" \
    >"$out" 2>>"$LOG" &
  pid=$!
  start=$(date +%s)
  local last_push=$start now
  # **세션이 도는 동안에도 갤러리를 갱신한다** (2026-09-10 사람 지적: 한 바퀴가
  # 20분인데 그동안 아무것도 안 보였다). 세션이 `docs/design_reference/` 에 그림을
  # 떨어뜨리는 즉시 갤러리에 뜬다. `render_and_push_gallery` 는 바뀐 게 없으면
  # 커밋하지 않으므로 자주 불러도 git 이 지저분해지지 않는다.
  #
  # 벽시계로 잰다 — 맥이 자면 sleep 타이머가 같이 멈춘다(loop.sh 에서 겪은 것).
  while kill -0 "$pid" 2>/dev/null; do
    sleep 15
    now=$(date +%s)
    if (( now - start >= limit )); then
      log "   ${limit}s 넘김 — 세션을 종료한다"
      kill_tree "$pid" TERM; sleep 10; kill_tree "$pid" KILL; break
    fi
    if (( now - last_push >= GALLERY_PUSH_SECONDS )); then
      render_and_push_gallery
      last_push=$now
    fi
  done
  wait "$pid"; rc=$?
  kill_tree "$pid" KILL 2>/dev/null      # 세션이 끝나도 자식이 남을 수 있다
  return $rc
}

# ── 자(QA) — **루프가 직접 돌린다** ──────────────────────────────────────
# 2026-09-10 까지는 세션이 스스로 QA 를 돌렸다고 「말하면」 믿었다. 그래서 건너뛰어도,
# 실패해도 루프가 몰랐다 — 판정자가 판정받는 쪽과 같았다는 뜻이다.
# 이제 **루프가 직접 돌리고 결과를 measured.md 에 적는다.** 불통과면 그 바퀴는
# 사람에게 보이지 않고 미달로 되돌린다(docs/DESIGN_LOOP.md 「판정자는 셋」).
run_design_qa() {
  local work="$1" ok=1 out
  : > "$work/measured.md"
  {
    printf '# 자(QA) — 루프가 직접 돌린 것\n\n'
    printf '%s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  } >> "$work/measured.md"
  for q in qa_sprite_check qa_character_sheets; do
    [[ -f "$ROOT/game/qa/$q.py" ]] || continue
    out="$("$PYTHON_BIN" "$ROOT/game/qa/$q.py" 2>&1)"
    if (( $? == 0 )); then
      printf '## %s — 통과\n\n```\n%s\n```\n\n' "$q" "$(printf '%s' "$out" | tail -25)" >> "$work/measured.md"
    else
      ok=0
      printf '## %s — **불통과**\n\n```\n%s\n```\n\n' "$q" "$(printf '%s' "$out" | tail -40)" >> "$work/measured.md"
      log "   자(QA) 불통과: $q"
    fi
  done
  return $(( ok ? 0 : 1 ))
}

# 세션 하나가 쓴 돈을 누적에 더하고, 누적을 돌려준다.
add_cost() {
  /usr/bin/python3 -c "
import json
c = 0.0
try:
    c = float(json.load(open('$1')).get('total_cost_usd') or 0)
except Exception:
    pass
prev = 0.0
try:
    prev = float(open('$COST_FILE').read().strip() or 0)
except Exception:
    pass
t = prev + c
open('$COST_FILE', 'w').write('%.4f' % t)
print('%.4f %.2f' % (c, t))
" 2>/dev/null || echo "0 0"
}

# --- 시작 전 확인 ---
for f in "$QUEUE" "$P_MAKE" "$P_EYE"; do
  [[ -f "$f" ]] || { echo "$f 없음"; exit 1; }
done
command -v claude >/dev/null || { echo "claude CLI 없음"; exit 1; }

rm -f "$WARNING_FILE"
log "== 그림 루프 시작 (pid $$, 누적상한 \$$DESIGN_MAX_TOTAL_USD, 최대 ${DESIGN_MAX_LAPS}바퀴, 누적 \$$(cat "$COST_FILE" 2>/dev/null || echo 0))"

while :; do
  [[ -f "$STOP_FILE" ]] && { rm -f "$STOP_FILE"; log "== STOP 파일 — 정상 종료"; exit 0; }

  LAPS=$((LAPS + 1))
  if (( DESIGN_MAX_LAPS > 0 && LAPS > DESIGN_MAX_LAPS )); then
    halt "한 번에 ${DESIGN_MAX_LAPS}바퀴를 돌았습니다 — 사람이 한 번 보라는 뜻입니다.
갤러리: https://kimtuna.github.io/Gunfarm/design.html
이어서 돌리려면 ./ctl.sh design start (누적 비용은 그대로 이어집니다)" 0
  fi

  ITEM="$(next_item)"
  if [[ -z "$ITEM" ]]; then
    WAITING="$(grep -cE '^- \[~\]' "$QUEUE" 2>/dev/null)"; WAITING="${WAITING:-0}"
    render_and_push_gallery
    if (( WAITING > 0 )); then
      halt "큐에 남은 것이 없습니다 — **사람이 확인할 것 ${WAITING}건**이 갤러리에 있습니다.
https://kimtuna.github.io/Gunfarm/design.html
보시고 퀄리티가 떨어지지 않으면 - [x], 미달이면 - [ ] 로 되돌린 뒤 ./ctl.sh design start" 0
    fi
    halt "그림 큐가 비었습니다. docs/DESIGN_QUEUE.md 에 항목을 넣고 ./ctl.sh design start" 0
  fi

  NUM="${ITEM%%$'\t'*}"; TEXT="${ITEM#*$'\t'}"
  # 갈래 — 본문 맨 앞의 [바탕]/[자]/[취향]
  KIND="$(printf '%s' "$TEXT" | sed -nE 's/^\[([^]]+)\].*/\1/p')"
  KIND="${KIND:-자}"

  LAST="$(cat "$LAST_ITEM_FILE" 2>/dev/null || echo)"
  if [[ "$LAST" == "$NUM" ]]; then
    COUNT=$(( $(cat "$REPEAT_FILE" 2>/dev/null || echo 0) + 1 ))
  else
    COUNT=1
  fi
  echo "$NUM" > "$LAST_ITEM_FILE"; echo "$COUNT" > "$REPEAT_FILE"

  if (( COUNT > STUCK_REPEAT_LIMIT )); then
    halt "#d$NUM 이 ${STUCK_REPEAT_LIMIT}회 연속 미완료입니다 — 접근이 틀렸을 수 있습니다.
$TEXT"
  fi

  # **[플레이] 항목은 루프가 못 한다** — 사람이 게임을 직접 켜서 보는 자리다.
  # 세션을 열지 않고 바로 멈춘다(docs/DESIGN_LOOP.md 「PNG 로 판정할 수 있는 것과 없는 것」).
  if [[ "$KIND" == "플레이" ]]; then
    render_and_push_gallery
    halt "#d$NUM — **사람이 게임을 직접 켜서 볼 차례입니다.**

  /Applications/Godot.app/Contents/MacOS/Godot --path game

$(printf '%s' "$TEXT" | head -1)

갤러리(캡처·GIF)로는 못 보는 것들입니다 — 움직여야 보입니다.
보시고 괜찮으면 그 항목을 - [x] 로, 미달이면 문제인 항목을 - [ ] 로 되돌린 뒤
./ctl.sh design start" 0
  fi

  WORK="$HARNESS/d$NUM"
  mkdir -p "$WORK"
  echo "$NUM" > "$HARNESS/current"
  echo "$KIND" > "$WORK/kind"
  log "-- 바퀴 시작: #d$NUM [$KIND] (연속 ${COUNT}/${STUCK_REPEAT_LIMIT}회차) — $TEXT"
  render_and_push_gallery

  LOG_MARK="$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')"; LOG_MARK="${LOG_MARK:-0}"
  OUT_EYE=""

  # ── ② 만드는 세션 ────────────────────────────────────────────────────────
  OUT_MAKE="$WORK/make_$(date +%s).json"
  run_session "$P_MAKE" "$DESIGN_LAP_TIMEOUT" "$OUT_MAKE"; RC=$?
  (( RC == 143 || RC == 137 )) && log "경고: 만드는 세션이 타임아웃으로 종료됨"
  (( RC != 0 && RC != 143 && RC != 137 )) && log "경고: 만드는 세션 종료코드 $RC"

  if grep -qiE "$CREDIT_RE" "$OUT_MAKE" 2>/dev/null \
     || tail -n "+$((LOG_MARK + 1))" "$LOG" 2>/dev/null | grep -qiE "$CREDIT_RE"; then
    HIT="$(grep -oiE "[^\"]*($CREDIT_RE)[^\"]*" "$OUT_MAKE" 2>/dev/null | head -1)"
    RESET_AT="$(/usr/bin/python3 "$ROOT/scripts/parse_reset.py" "$HIT" 2>/dev/null)"
    echo "$((COUNT - 1))" > "$REPEAT_FILE"     # 한도는 연속 실패로 세지 않는다
    if [[ -n "$RESET_AT" ]]; then
      WAKE=$((RESET_AT + 60))
      log "== 한도에 걸림 — $(date -r "$RESET_AT" '+%H:%M') 리셋. 그때까지 자고 이어서 돈다"
      while (( $(date +%s) < WAKE )); do
        [[ -f "$STOP_FILE" ]] && { rm -f "$STOP_FILE"; log "== 대기 중 STOP"; exit 0; }
        sleep 30
      done
      continue
    fi
    halt "한도에 걸렸는데 리셋 시각을 못 읽었습니다: $HIT"
  fi

  # ── ③ 보는 세션 ─────────────────────────────────────────────────────────
  # 만드는 세션이 그림을 하나도 안 남겼으면 볼 것이 없다 — 건너뛴다.
  if compgen -G "$WORK/*.png" >/dev/null || [[ -s "$WORK/note.md" ]]; then
    OUT_EYE="$WORK/eye_$(date +%s).json"
    run_session "$P_EYE" "$EYE_TIMEOUT" "$OUT_EYE"; RC2=$?
    (( RC2 != 0 )) && log "경고: 보는 세션 종료코드 $RC2 (비평 없이 진행)"
  else
    log "   만드는 세션이 그림도 note.md 도 안 남겼다 — 보는 세션을 건너뛴다"
  fi

  # ── 비용 ────────────────────────────────────────────────────────────────
  read -r LAP_COST TOTAL_COST <<<"$(add_cost "$OUT_MAKE")"
  if [[ -n "${OUT_EYE:-}" && -f "${OUT_EYE:-/nonexistent}" ]]; then
    read -r EYE_COST TOTAL_COST <<<"$(add_cost "$OUT_EYE")"
    LAP_COST="$(/usr/bin/python3 -c "print('%.4f' % (float('$LAP_COST')+float('$EYE_COST')))" 2>/dev/null || echo "$LAP_COST")"
  fi
  log "   비용: \$$LAP_COST  (누적 \$$TOTAL_COST)"
  if /usr/bin/python3 -c "import sys; sys.exit(0 if float('$DESIGN_MAX_TOTAL_USD') > 0 and float('$TOTAL_COST') >= float('$DESIGN_MAX_TOTAL_USD') else 1)" 2>/dev/null; then
    render_and_push_gallery
    halt "누적 비용이 상한(\$$DESIGN_MAX_TOTAL_USD)에 닿았습니다 — 지금까지 \$$TOTAL_COST.
갤러리: https://kimtuna.github.io/Gunfarm/design.html
계속하려면 env.sh 의 DESIGN_MAX_TOTAL_USD 를 올리고 ./ctl.sh design start" 0
  fi

  # ── ④ 자(QA) — **루프가 직접 돌린다. 세션의 말을 믿지 않는다.** ──────────
  if run_design_qa "$WORK"; then
    QA_OK=1
  else
    QA_OK=0
    # 세션이 `- [x]` 나 `- [~]` 로 바꿔놨어도 **되돌린다** — 깨진 것을 사람에게
    # 보이거나 닫으면 안 된다(docs/DESIGN_LOOP.md 「QA 불통과면 커밋하지 않는다」).
    /usr/bin/python3 - "$QUEUE" "$NUM" <<'PYEOF'
import io, re, sys
p, num = sys.argv[1], sys.argv[2]
s = io.open(p, encoding='utf-8').read()
s2 = re.sub(r'^- \[[x~X]\]([^#\n]*#d%s(?:[^0-9]|$))' % num, r'- [ ]\1', s, flags=re.M)
if s2 != s:
    io.open(p, 'w', encoding='utf-8').write(s2)
    print("  QA 불통과라 #d%s 를 - [ ] 로 되돌렸다" % num)
PYEOF
    log "   자(QA) 불통과 — #d$NUM 을 미달로 되돌린다"
  fi

  render_and_push_gallery

  # ── ⑤ 판정 ──────────────────────────────────────────────────────────────
  if grep -qE "^- \[[xX]\][^#]*#d${NUM}([^0-9]|$)" "$QUEUE"; then
    log "-- 완료: #d$NUM"
    rm -f "$REPEAT_FILE" "$LAST_ITEM_FILE"
  elif grep -qE "^- \[~\][^#]*#d${NUM}([^0-9]|$)" "$QUEUE"; then
    log "-- 사람 확인 대기: #d$NUM"
    notify "확인해 주세요 — #d$NUM" "$(printf '%s' "$TEXT" | head -1)"
    rm -f "$REPEAT_FILE" "$LAST_ITEM_FILE"
  else
    log "-- 미완료로 남음: #d$NUM (다음 바퀴 재시도)"
  fi

  sleep "${WAIT_BETWEEN_LAPS:-20}"
done
