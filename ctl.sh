#!/usr/bin/env bash
# ctl.sh — 루프 제어.
#
#   ./ctl.sh start          launchd 등록 + 즉시 시작 (확인 안 되면 직접 백그라운드 실행으로 폴백)
#   ./ctl.sh stop           즉시 중단 (진행 중인 바퀴도 죽인다)
#   ./ctl.sh graceful-stop  STOP 파일 생성 — 지금 바퀴를 끝내고 멈춘다
#   ./ctl.sh status         돌고 있는지 / 마지막 로그 / 경고
#   ./ctl.sh logs           로그 따라가기
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/env.sh"

LABEL="com.gunfarm.loop"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HARNESS="$ROOT/.harness"
LOG="$HARNESS/loop.log"
PIDFILE="$HARNESS/loop.pid"
mkdir -p "$HARNESS"

# 실제로 loop.sh 프로세스가 살아 있는가? 살아있으면 PID를 출력한다.
running_pid() {
  local pid
  pid="$(pgrep -f "bash $ROOT/loop.sh" 2>/dev/null | head -1)"
  [[ -z "$pid" ]] && pid="$(pgrep -f "$ROOT/loop.sh" 2>/dev/null | head -1)"
  [[ -n "$pid" ]] && echo "$pid"
}

write_plist() {
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/loop.sh</string>
  </array>
  <key>WorkingDirectory</key><string>$ROOT</string>
  <key>StandardOutPath</key><string>$HARNESS/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$HARNESS/launchd.err.log</string>
  <key>RunAtLoad</key><false/>
  <key>KeepAlive</key><false/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
</dict></plist>
PLISTEOF
}

# 로그의 "루프 시작" 줄 개수 — 실제로 한 번이라도 떴는지 판정하는 기준.
# 큐가 비었거나 즉시 멈추는 경우 루프는 1초 안에 끝나서 pgrep 으로는 못 잡는다.
started_count() { grep -c '== 루프 시작' "$LOG" 2>/dev/null || true; }

cmd_start() {
  if pid="$(running_pid)"; then
    echo "이미 돌고 있습니다 (pid $pid). 멈추려면 ./ctl.sh stop"
    return 0
  fi
  rm -f "$HARNESS/STOP"

  local uid before i pid
  uid="$(id -u)"
  before="$(started_count)"; before="${before:-0}"

  write_plist
  launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1
  if launchctl bootstrap "gui/$uid" "$PLIST" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$uid/$LABEL" >/dev/null 2>&1
  fi

  # launchd 의 kickstart 는 환경에 따라 조용히 실패한다 — 실제로 떴는지 몇 초 안에 확인한다.
  for i in 1 2 3 4 5 6 7 8; do
    sleep 1
    if pid="$(running_pid)"; then
      echo "$pid" > "$PIDFILE"
      echo "시작됨 — launchd ($LABEL), pid $pid"
      return 0
    fi
    # 떴다가 이미 끝났을 수도 있다 (큐가 비었거나 즉시 멈춤) — 그것도 성공이다.
    if [[ "$(started_count)" != "$before" ]]; then
      echo "시작됐다가 이미 끝났습니다 (큐가 비었거나 즉시 멈춤). ./ctl.sh status 로 확인하세요."
      return 0
    fi
  done

  echo "launchd 로 뜬 것을 확인하지 못했습니다 — 직접 백그라운드 실행으로 폴백합니다."
  launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1
  nohup /bin/bash "$ROOT/loop.sh" >>"$HARNESS/nohup.log" 2>&1 &
  local fallback=$!
  sleep 2
  if kill -0 "$fallback" 2>/dev/null; then
    echo "$fallback" > "$PIDFILE"
    echo "시작됨 — 직접 실행, pid $fallback"
  elif [[ "$(started_count)" != "$before" ]]; then
    echo "시작됐다가 이미 끝났습니다 (큐가 비었거나 즉시 멈춤). ./ctl.sh status 로 확인하세요."
  else
    echo "실패: 루프를 시작하지 못했습니다. $HARNESS/nohup.log 를 확인하세요." >&2
    return 1
  fi
}

cmd_stop() {
  local uid; uid="$(id -u)"
  launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1
  local pid stopped=0
  while pid="$(running_pid)"; do
    kill -TERM "$pid" 2>/dev/null
    stopped=1
    sleep 1
    if pid="$(running_pid)"; then kill -KILL "$pid" 2>/dev/null; sleep 1; fi
    break
  done
  # 진행 중이던 claude 세션도 같이 정리
  pkill -f "claude -p" >/dev/null 2>&1
  rm -f "$PIDFILE"
  (( stopped )) && echo "중단했습니다." || echo "돌고 있지 않았습니다."
}

cmd_graceful_stop() {
  if running_pid >/dev/null; then
    touch "$HARNESS/STOP"
    echo "STOP 파일을 만들었습니다 — 지금 바퀴가 끝나면 멈춥니다."
  else
    echo "돌고 있지 않습니다."
  fi
}

cmd_status() {
  if pid="$(running_pid)"; then
    echo "● 돌고 있음 (pid $pid)"
  else
    echo "○ 멈춰 있음"
  fi
  if [[ -f "$HARNESS/WARNING" ]]; then
    echo
    echo "⚠ 경고:"
    sed 's/^/   /' "$HARNESS/WARNING"
  fi
  local remaining done_n
  # grep -c 는 0건일 때도 "0"을 찍고 exit 1 을 낸다 — `|| echo 0` 을 붙이면 "0\n0" 이 된다.
  remaining="$(grep -cE '^- \[ \] *#[0-9]+' "$ROOT/docs/feedback/INBOX.md" 2>/dev/null)"
  done_n="$(grep -ciE '^- \[x\] *#[0-9]+' "$ROOT/docs/feedback/INBOX.md" 2>/dev/null)"
  remaining="${remaining:-0}"; done_n="${done_n:-0}"
  echo
  echo "INBOX: 완료 $done_n / 남음 $remaining"
  if [[ -f "$LOG" ]]; then
    echo
    echo "최근 로그:"
    tail -12 "$LOG" | sed 's/^/   /'
  fi
}

case "${1:-status}" in
  start)          cmd_start ;;
  stop)           cmd_stop ;;
  graceful-stop)  cmd_graceful_stop ;;
  status)         cmd_status ;;
  logs)           tail -f "$LOG" ;;
  *) echo "사용법: $0 {start|stop|graceful-stop|status|logs}" >&2; exit 2 ;;
esac
