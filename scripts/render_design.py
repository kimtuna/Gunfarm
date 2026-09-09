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
QUEUE = os.path.join(ROOT, "docs", "feedback", "DESIGN_QUEUE.md")
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
        label, color = BADGE[state]
        thumbs = "".join(
            '<figure><a href="design_reference/{n}" target="_blank">'
            '<img src="design_reference/{n}" alt="{n}" loading="lazy"></a>'
            '<figcaption>{cap}</figcaption></figure>'.format(
                n=e(p), cap=("r%d" % r) if r else e(p))
            for r, p in pics)
        if not thumbs:
            thumbs = '<p class="none">아직 그림이 없습니다.</p>'
        body = ['<div class="revs">%s</div>' % thumbs]
        if hist:
            body.append('<h4>회차 이력 — 무엇을 보완해 왔나</h4><pre>%s</pre>' % e(hist))
        if note:
            body.append('<h4>만든 세션이 남긴 것</h4><pre>%s</pre>' % e(note))
        if crit:
            body.append('<h4>보는 세션의 「잴 것」</h4><pre>%s</pre>' % e(crit))
        blocks.append(
            '<details{op}><summary>'
            '<span class="badge" style="background:{c}">{lab}</span>'
            '<span class="num">#d{num}</span>'
            '<span class="kind">{kind}</span>'
            '<span class="title">{title}</span>'
            '<span class="count">{cnt}회차</span>'
            '</summary><div class="body">{body}</div></details>'.format(
                op=" open" if first and state != "done" else "",
                c=color, lab=label, num=num, kind=e(kind), title=e(title),
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
.title{{flex:1;min-width:200px}}
.count{{color:var(--dim);font-size:12px;font-variant-numeric:tabular-nums}}
.body{{padding:4px 14px 16px;border-top:1px solid var(--line)}}
.revs{{display:flex;flex-wrap:wrap;gap:12px;margin:10px 0}}
figure{{margin:0}}
figcaption{{color:var(--dim);font-size:11px;margin-top:4px;text-align:center}}
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
큐는 <code>docs/feedback/DESIGN_QUEUE.md</code>.
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
