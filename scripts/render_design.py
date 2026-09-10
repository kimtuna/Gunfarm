#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""docs/design.html — 그림 갤러리.

**기존 대시보드(scripts/render_dashboard.py → docs/index.html)를 건드리지 않는다.**
두 페이지가 서로를 못 깨게 스크립트도 출력 파일도 따로다
(docs/DESIGN_LOOP.md 「갤러리」, 2026-09-10 사람 결정).

시스템 파이썬(/usr/bin/python3)으로 돈다 — Pillow 같은 것을 안 쓴다.
"""
import html
import os
import re
import subprocess
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUEUE = os.path.join(ROOT, "docs", "DESIGN_QUEUE.md")
REFDIR = os.path.join(ROOT, "docs", "design_reference")
WORKDIR = os.path.join(ROOT, ".harness", "design")
OUT = os.path.join(ROOT, "docs", "design.html")

# 이 루프가 만든 그림만 모은다 — `d<번호>_...` 로 시작하는 것.
# 그 규칙이 없으면 예전 참고 자료 수십 장이 갤러리에 섞인다.
PAT = re.compile(r"^d(\d+)_(.+?)(?:_r(\d+))?\.png$")

e = html.escape


def queue_items():
    """[(번호, 상태, 갈래, 제목)] — 큐에 적힌 순서 그대로."""
    out = []
    try:
        with open(QUEUE, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"^- \[([ x~X])\] *#d(\d+) *(.*)$", line)
                if not m:
                    continue
                mark, num, text = m.group(1), int(m.group(2)), m.group(3)
                kind = ""
                k = re.match(r"^\[([^\]]+)\]", text)
                if k:
                    kind = k.group(1)
                    text = text[k.end():]
                title = re.sub(r"\*\*", "", text).strip()
                state = {" ": "todo", "~": "wait"}.get(mark, "done")
                out.append((num, state, kind, title))
    except OSError:
        pass
    return out


def shots(num):
    """이 항목이 만든 PNG — **회차 순서(r1 → r2 → r3)로.**

    한 바퀴에 한 장씩 쌓아 올리는 방식이라(docs/DESIGN_LOOP.md 「한 바퀴에 한 장만
    그린다」), 사람이 **무엇이 나아졌는지 견줄 수 있게** 옛것부터 보여준다.
    """
    try:
        names = os.listdir(REFDIR)
    except OSError:
        return []
    got = []
    for n in names:
        m = PAT.match(n)
        if m and int(m.group(1)) == num:
            rev = int(m.group(3)) if m.group(3) else 0
            p = os.path.join(REFDIR, n)
            got.append((rev, os.path.getmtime(p), n))
    got.sort()
    return [(r, n) for r, _, n in got]


def read(*parts):
    try:
        with open(os.path.join(*parts), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def git(*args):
    try:
        return subprocess.run(["git", "-C", ROOT, *args], capture_output=True,
                              text=True, timeout=10).stdout.strip()
    except Exception:
        return ""


BADGE = {"todo": ("진행 중", "#c8862a"), "wait": ("확인해 주세요", "#2f7fd0"),
         "done": ("완료", "#3f8a4a")}

## 갈래마다 **사람이 무엇으로 판정하는가.** 이게 없으면 갤러리를 보는 사람이
## "이건 내가 봐야 하는 건가 기계가 보는 건가"를 매번 다시 판단해야 한다.
JUDGE = {
    "플레이": ("★ 감독이 <b>게임을 켜서</b> 판정",
               "돌려봐야 아는 것들입니다 — 움직일 때 되풀이가 보이나, 밀도가 맞나, "
               "클릭 타이밍이 맞나. 캡처로는 알 수 없습니다.<br>"
               "<code>/Applications/Godot.app/Contents/MacOS/Godot --path game</code>"),
    "취향":   ("★ 감독이 <b>눈으로</b> 판정",
               "기계가 못 재는 것입니다 — 모양·비율·색감이 「누가 봐도 퀄리티가 "
               "떨어지지 않는가」."),
    "바탕":   ("기계(QA)가 판정",
               "화면이 안 바뀌는 배관이면 루프가 스스로 닫습니다. 화면이 바뀌면 "
               "그때는 감독 확인이 필요합니다."),
    "자":     ("기계(QA)가 판정",
               "잴 수 있는 것입니다. 통과하면 루프가 닫습니다."),
}


def revisions(text):
    """history.md → {회차: 그 회차 본문} — `## r<N>` 로 쪼갠다.

    **빈 이력이면 빈 dict 다.** 한때 `[]` 를 돌려줘서 부르는 쪽의 `.get()` 이 터졌다.
    """
    out = []
    if not text:
        return {}
    parts = re.split(r"^##\s*r(\d+)\b[^\n]*$", text, flags=re.M)
    # parts = [머리말, 번호, 본문, 번호, 본문, ...]
    for i in range(1, len(parts) - 1, 2):
        try:
            out.append((int(parts[i]), parts[i + 1].strip()))
        except ValueError:
            pass
    return dict(out)


def main():
    items = queue_items()
    # 볼 것이 있는 순서: 사람이 고를 것 → 진행 중 → 완료.
    # **진행 중만 번호 오름차순**이다 — 루프가 집는 순서가 곧 사람이 궁금한 순서다.
    # 나머지는 새것이 위로 온다.
    rank = {"wait": 0, "todo": 1, "done": 2}
    items.sort(key=lambda it: (rank[it[1]], it[0] if it[1] == "todo" else -it[0]))

    # 기본으로 펼치는 것은 **맨 위 하나뿐**이다 — 과정이 쌓여도 페이지가 안 길어진다.
    blocks = []
    first = True
    for num, state, kind, title in items:
        pics = shots(num)
        hist = read(WORKDIR, "d%d" % num, "history.md")
        note = read(WORKDIR, "d%d" % num, "note.md")
        crit = read(WORKDIR, "d%d" % num, "critique.md")
        meas = read(WORKDIR, "d%d" % num, "measured.md")
        label, color = BADGE[state]
        revs = revisions(hist)
        who, why = JUDGE.get(kind, ("", ""))
        body = []
        # **누가 판정하는가를 맨 위에.** 사람이 갤러리를 열자마자 알아야 한다.
        if who:
            cls = "judge play" if kind == "플레이" else (
                  "judge taste" if kind == "취향" else "judge auto")
            extra = ('<div class="tolook">%s</div>' % e(note)) if (note and state != "done") else ""
            body.append('<div class="%s"><b>%s</b><p>%s</p>%s</div>'
                        % (cls, who, why, extra))
        # **회차마다 그림 + 왜 그 회차가 필요했나를 나란히.**
        if pics:
            rows = []
            for r, fn in pics:
                reason = revs.get(r, "")
                rows.append(
                    '<div class="rev">'
                    '<a href="design_reference/{fn}" target="_blank">'
                    '<img src="design_reference/{fn}" alt="{fn}" loading="lazy"></a>'
                    '<div class="why"><span class="rno">{cap}</span>{reason}</div>'
                    '</div>'.format(
                        fn=e(fn), cap=("r%d" % r) if r else "—",
                        reason=('<pre>%s</pre>' % e(reason)) if reason
                               else '<p class="none">이 회차의 사유가 안 적혀 있습니다.</p>'))
            body.append("".join(rows))
        else:
            body.append('<p class="none">아직 그림이 없습니다.</p>')
        if meas:
            fail = "불통과" in meas
            body.append('<h4>자(QA) — 루프가 직접 잰 것%s</h4><pre>%s</pre>'
                        % (' <span class="bad">불통과</span>' if fail else '', e(meas)))
        if crit:
            body.append('<h4>보는 세션의 「잴 것」</h4><pre>%s</pre>' % e(crit))
        blocks.append(
            '<details{op}><summary>'
            '<span class="badge" style="background:{c}">{lab}</span>'
            '<span class="num">#d{num}</span>'
            '<span class="kind{playcls}">{kind}</span>'
            '<span class="title">{title}</span>'
            '<span class="count">{cnt}회차</span>'
            '{judge}'
            '</summary><div class="body">{body}</div></details>'.format(
                op=" open" if first and state != "done" else "",
                c=color, lab=label, num=num, kind=e(kind), title=e(title),
                playcls=(" play" if kind == "플레이" else ""),
                judge=('<span class="me">내가 볼 것</span>' if kind in ("플레이", "취향") else ''),
                cnt=len(pics), body="".join(body)))
        first = False

    if not blocks:
        blocks = ['<p class="none">큐가 비어 있습니다.</p>']

    page = """<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gunfarm — 그림 갤러리</title>
<style>
:root{{--bg:#15161a;--fg:#e6e6ea;--dim:#9a9aa6;--line:#2c2e36;--card:#1c1e24}}
*{{box-sizing:border-box}}
body{{margin:0;padding:24px 16px 64px;background:var(--bg);color:var(--fg);
 font:15px/1.6 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif}}
.wrap{{max-width:1100px;margin:0 auto}}
a{{color:#79b8ff}}
h1{{font-size:20px;margin:0 0 4px}}
.sub{{color:var(--dim);font-size:13px;margin:0 0 20px}}
details{{background:var(--card);border:1px solid var(--line);border-radius:10px;
 margin:0 0 10px;overflow:hidden}}
summary{{cursor:pointer;padding:12px 14px;display:flex;align-items:center;gap:10px;
 flex-wrap:wrap;list-style:none}}
summary::-webkit-details-marker{{display:none}}
.badge{{color:#fff;font-size:11px;padding:2px 8px;border-radius:99px;white-space:nowrap}}
.num{{font-variant-numeric:tabular-nums;color:var(--dim);font-size:13px}}
.kind{{font-size:11px;color:var(--dim);border:1px solid var(--line);
 padding:1px 6px;border-radius:4px}}
.kind.play{{color:#ffd479;border-color:#7a6330;background:#2a2418}}
.title{{flex:1;min-width:200px}}
.count{{color:var(--dim);font-size:12px;font-variant-numeric:tabular-nums}}
.body{{padding:4px 14px 16px;border-top:1px solid var(--line)}}
.judge{{border-radius:8px;padding:10px 12px;margin:12px 0;font-size:13px;
 border:1px solid var(--line)}}
.judge b{{display:block;margin-bottom:4px}}
.judge p{{margin:0;color:var(--dim);font-size:12px;line-height:1.5}}
.judge.play{{background:#2a2418;border-color:#7a6330;color:#ffd479}}
.judge.taste{{background:#182430;border-color:#31597a;color:#9fd0ff}}
.judge.auto{{background:#1a1d1a;border-color:#33473a;color:#9ec9a8}}
.tolook{{margin-top:8px;padding-top:8px;border-top:1px dashed var(--line);
 color:var(--fg);font-size:12.5px;white-space:pre-wrap}}
.bad{{background:#a33;color:#fff;font-size:10px;padding:1px 6px;border-radius:99px}}
.me{{background:#2f7fd0;color:#fff;font-size:10px;padding:1px 6px;border-radius:99px}}
.rev{{display:flex;gap:14px;align-items:flex-start;padding:12px 0;
 border-top:1px solid var(--line);flex-wrap:wrap}}
.rev img{{max-width:min(420px,100%)}}
.why{{flex:1;min-width:240px}}
.rno{{display:inline-block;background:#2c2e36;color:var(--fg);font-size:11px;
 padding:1px 8px;border-radius:99px;margin-bottom:6px}}
.body img{{max-width:100%;image-rendering:pixelated;border-radius:6px;
 border:1px solid var(--line);display:block}}
h4{{font-size:12px;color:var(--dim);margin:16px 0 6px;font-weight:600}}
pre{{white-space:pre-wrap;word-break:break-word;background:#101116;border:1px solid var(--line);
 border-radius:8px;padding:10px 12px;font-size:12.5px;color:#cfd0d8;overflow-x:auto}}
.none{{color:var(--dim);font-size:13px}}
footer{{color:var(--dim);font-size:12px;margin-top:24px;border-top:1px solid var(--line);
 padding-top:12px}}
</style></head><body><div class="wrap">
<p class="sub"><a href="./">← 진행 대시보드</a></p>
<h1>그림 갤러리</h1>
<p class="sub">그림·모션 루프가 만든 후보들. 규칙은 <code>docs/DESIGN_LOOP.md</code>,
큐는 <code>docs/DESIGN_QUEUE.md</code>.
<b>「확인해 주세요」</b>가 붙은 것은 <b>사람이 직접 보고 「누가 봐도 퀄리티가 떨어지지 않는다」</b>고 판단해야 넘어갑니다 — 그것이 이 루프의 유일한 완료 조건입니다.</p>
{blocks}
<footer>마지막 갱신 {now} · {commit}</footer>
</div></body></html>""".format(
        blocks="\n".join(blocks),
        now=time.strftime("%Y-%m-%d %H:%M"),
        commit=e(git("log", "-1", "--pretty=%h %s")) or "(커밋 없음)")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page)
    n_wait = sum(1 for _, s, _, _ in items if s == "wait")
    print("design gallery: %d항목 (확인 대기 %d) -> %s" % (len(items), n_wait, OUT))


if __name__ == "__main__":
    main()
