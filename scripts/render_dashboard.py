#!/usr/bin/env python3
"""docs/index.html 을 다시 그린다. loop.sh 가 매 바퀴 호출한다.

README.md "대시보드는 최소한으로 유지한다" — 남은/완료 개수, 다음 항목,
마지막 커밋, 경고 배너. 그 이상은 넣지 않는다.
"""
import html
import re
import subprocess
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INBOX = ROOT / "docs" / "feedback" / "INBOX.md"
STATUS = ROOT / "docs" / "STATUS.md"
WARN = ROOT / ".harness" / "WARNING"
OUT = ROOT / "docs" / "index.html"

# 완료 항목은 `- [x] (2026-09-06) #1 ...` 처럼 번호 앞에 완료 날짜가 붙는다.
# 체크박스와 #번호 사이에 뭐가 오든 삼킨다.
ITEM_RE = re.compile(r"^- \[( |x|X)\]\s*[^#]*#(\d+)\s*(.*)$")


def read_inbox():
    done, todo = [], []
    if not INBOX.exists():
        return done, todo
    for line in INBOX.read_text(encoding="utf-8").splitlines():
        m = ITEM_RE.match(line.strip())
        if not m:
            continue
        (done if m.group(1).lower() == "x" else todo).append((int(m.group(2)), m.group(3).strip()))
    todo.sort(key=lambda t: t[0])
    return done, todo


def git(*args):
    try:
        return subprocess.run(["git", "-C", str(ROOT), *args],
                              capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception:
        return ""


def main():
    done, todo = read_inbox()
    nxt = todo[0] if todo else None
    warning = WARN.read_text(encoding="utf-8").strip() if WARN.exists() else ""
    last_commit = git("log", "-1", "--pretty=%h  %s")
    last_commit_when = git("log", "-1", "--pretty=%cd", "--date=format:%Y-%m-%d %H:%M")
    now_dt = datetime.now(timezone(timedelta(hours=9)))
    now = now_dt.strftime("%Y-%m-%d %H:%M KST")
    stamp = now_dt.strftime("%Y%m%d%H%M%S")

    status_head = ""
    if STATUS.exists():
        lines = STATUS.read_text(encoding="utf-8").splitlines()
        try:
            i = lines.index("## 마지막 갱신")
            status_head = "\n".join(lines[i + 1:i + 8]).strip()
        except ValueError:
            pass

    e = html.escape
    banner = (f'<div class="warn"><strong>루프 멈춤</strong><pre>{e(warning)}</pre></div>'
              if warning else "")
    next_html = (f'<span class="num">#{nxt[0]}</span> {e(nxt[1])}' if nxt
                 else '<span class="idle">큐가 비었습니다 — 루프는 세션을 열지 않고 종료합니다.</span>')
    todo_rows = "\n".join(
        f'<li><span class="num">#{n}</span> {e(t)}</li>' for n, t in todo[:15]) or '<li class="idle">없음</li>'

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gunfarm — 진행 상황</title>
<style>
:root {{ color-scheme: light dark; --bg:#faf9f6; --fg:#23201b; --dim:#6b665c; --line:#ddd8cc; --card:#fff; --accent:#3c6e47; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#16150f; --fg:#e8e4d8; --dim:#8f897a; --line:#2f2c22; --card:#1e1c14; --accent:#7bb98a; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; padding:2rem 1rem; background:var(--bg); color:var(--fg);
  font:15px/1.6 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Noto Sans KR",sans-serif; }}
main {{ max-width:760px; margin:0 auto; }}
h1 {{ font-size:1.5rem; margin:0 0 .2rem; }}
.sub {{ color:var(--dim); margin:0 0 1.6rem; font-size:.9rem; }}
.cards {{ display:flex; gap:.75rem; margin-bottom:1.5rem; flex-wrap:wrap; }}
.card {{ flex:1 1 120px; background:var(--card); border:1px solid var(--line); border-radius:10px; padding:.9rem 1rem; }}
.card b {{ display:block; font-size:1.9rem; line-height:1.1; color:var(--accent); font-variant-numeric:tabular-nums; }}
.card span {{ color:var(--dim); font-size:.8rem; }}
section {{ background:var(--card); border:1px solid var(--line); border-radius:10px; padding:1rem 1.2rem; margin-bottom:1rem; }}
h2 {{ font-size:.78rem; letter-spacing:.08em; text-transform:uppercase; color:var(--dim); margin:0 0 .6rem; font-weight:600; }}
ul {{ margin:0; padding-left:1.1rem; }} li {{ margin:.15rem 0; }}
.num {{ color:var(--accent); font-weight:600; font-variant-numeric:tabular-nums; }}
.idle {{ color:var(--dim); }}
pre {{ margin:.4rem 0 0; white-space:pre-wrap; font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; }}
code {{ font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; }}
.warn {{ background:#7a2618; color:#fff; border-radius:10px; padding:1rem 1.2rem; margin-bottom:1.2rem; }}
footer {{ color:var(--dim); font-size:.8rem; text-align:center; margin-top:2rem; }}
</style></head><body><main>
<h1>Gunfarm</h1>
<p class="sub">당신의 농장은 병참기지다. — 자율 개발 루프 진행 상황</p>
{banner}
<div class="cards">
  <div class="card"><b>{len(done)}</b><span>완료</span></div>
  <div class="card"><b>{len(todo)}</b><span>남음</span></div>
</div>
<section><h2>다음 항목</h2>{next_html}</section>
<section><h2>대기 중인 항목</h2><ul>{todo_rows}</ul></section>
<section><h2>마지막 커밋</h2><code>{e(last_commit) or '(없음)'}</code>
  <p class="sub" style="margin:.3rem 0 0">{e(last_commit_when)}</p></section>
<section><h2>STATUS — 마지막 갱신</h2><pre>{e(status_head) or '(비어있음)'}</pre></section>
<footer>갱신: {now} · <span id="live">자동 새로고침 켜짐</span></footer>
</main>
<script>
// 루프는 매 바퀴 이 페이지를 다시 그려서 push 하지만, 브라우저는 스스로 갱신하지 않는다.
// 게다가 GitHub Pages 는 HTML 에 cache-control: max-age=600 을 붙여서 그냥 새로고침하면
// 최대 10분간 옛 페이지가 나온다 — 그래서 매번 다른 쿼리스트링을 붙여 CDN 캐시를 우회한다.
(function () {{
  var STAMP = "{stamp}";
  var EVERY = 45000;
  var el = document.getElementById("live");
  function tick() {{
    fetch(location.pathname + "?_=" + Date.now(), {{ cache: "no-store" }})
      .then(function (r) {{ return r.ok ? r.text() : null; }})
      .then(function (html) {{
        if (!html) return;
        var m = html.match(/var STAMP = "(\\d+)"/);
        if (m && m[1] !== STAMP) {{
          // 바뀌었다 — 캐시를 타지 않는 새 URL 로 갈아탄다.
          location.replace(location.pathname + "?t=" + Date.now());
        }} else if (el) {{
          el.textContent = "자동 새로고침 켜짐 · 확인 " +
            new Date().toLocaleTimeString("ko-KR", {{ hour12: false }});
        }}
      }})
      .catch(function () {{ if (el) el.textContent = "자동 새로고침 — 연결 실패"; }});
  }}
  setInterval(tick, EVERY);
  tick();
}})();
</script>
</body></html>
""", encoding="utf-8")
    print(f"dashboard: done={len(done)} todo={len(todo)} -> {OUT}")


if __name__ == "__main__":
    sys.exit(main())
