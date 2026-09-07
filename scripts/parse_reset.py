#!/usr/bin/env python3
"""한도 메시지에서 "언제 풀리는지"를 읽어 epoch 초로 찍는다.

`loop.sh` 가 한도를 감지했을 때 부른다. 읽어내지 못하면 아무것도 찍지 않고 1 로 끝내고,
그러면 `loop.sh` 는 예전처럼 멈춰서 사람을 기다린다 — **못 읽었는데 대충 짐작해서 자면
안 된다.** 잘못 짐작하면 루프가 조용히 몇 시간을 놀거나, 반대로 너무 일찍 깨서 한도에
다시 부딪히며 재시도를 태운다.

실제로 받은 문구:
    You've hit your session limit · resets 9:50am (Asia/Seoul)

시스템 python3(3.9)로 돈다 — 대시보드 렌더러와 같은 이유로 venv 를 쓰지 않는다.
"""
import re
import sys
from datetime import datetime, timedelta

# "resets 9:50am" / "resets 10pm" / "resets at 09:50" 를 모두 받는다.
PAT = re.compile(
    r"reset[s]?\s*(?:at\s*)?(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)?",
    re.IGNORECASE,
)

# 이 시간을 넘겨 기다려야 한다면 파싱이 틀렸다고 본다 — 자는 대신 멈춰서 사람에게 넘긴다.
MAX_WAIT_HOURS = 12


def main():
    text = " ".join(sys.argv[1:])
    m = PAT.search(text)
    if not m:
        return 1

    hour = int(m.group(1))
    minute = int(m.group(2) or 0)
    ampm = (m.group(3) or "").replace(".", "").lower()

    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return 1

    if ampm == "pm" and hour != 12:
        hour += 12
    elif ampm == "am" and hour == 12:
        hour = 0
    elif not ampm and hour > 23:
        return 1

    # 메시지는 지역 시각으로 온다("(Asia/Seoul)"). 이 기계의 시계와 같은 지역이라고 보고
    # 로컬 시각으로 다룬다 — 하네스는 이 기계에서만 돌기 때문에 안전한 가정이다.
    now = datetime.now()
    reset = now.replace(hour=hour, minute=minute, second=0, microsecond=0)

    # 이미 지난 시각이면 내일 그 시각이다(밤에 걸려서 아침에 풀리는 경우).
    # 다만 방금 지난 것(몇 분 이내)은 "막 풀린 것"이라 내일로 밀지 않는다.
    if reset <= now - timedelta(minutes=5):
        reset += timedelta(days=1)

    wait = (reset - now).total_seconds()
    if wait > MAX_WAIT_HOURS * 3600:
        return 1

    print(int(reset.timestamp()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
