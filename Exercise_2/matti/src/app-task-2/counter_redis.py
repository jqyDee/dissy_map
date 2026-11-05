import os
import time
from datetime import datetime

import redis

NODE_ID = os.environ["NODE_ID"]
MODE = os.environ.get("MODE", "incr")  # incr | naive | lock
N = int(os.environ.get("N", "100"))
START_AT = float(
    os.environ.get("START_AT", "0")
)  # unix time, both nodes start together

r = redis.Redis(host=os.environ["REDIS_HOST"])
own_counter = 0


def increment():
    global own_counter

    own_counter += 1
    if MODE == "incr":
        r.incr("counter")
    elif MODE == "naive":
        value = int(r.get("counter") or 0)
        r.set("counter", value + 1)
    elif MODE == "lock":
        with r.lock("counter_lock", sleep=0.001):
            value = int(r.get("counter") or 0)
            r.set("counter", value + 1)


while time.time() < START_AT:
    time.sleep(0.001)

durations = []
for _ in range(N):
    t0 = time.perf_counter()
    increment()
    durations.append(time.perf_counter() - t0)

    now = datetime.now()
    ts = now.isoformat(timespec="milliseconds")
    print(
        f"[{NODE_ID};{ts}] {MODE:12} own_counter={own_counter:3}",
        flush=True,
    )

total = sum(durations)
print(
    f"[{NODE_ID}] mode={MODE} n={N} total={total * 1000:.1f}ms "
    f"avg={total / N * 1000:.3f}ms max={max(durations) * 1000:.3f}ms",
    flush=True,
)
time.sleep(2)  # let the other node finish
print(f"[{NODE_ID}] final counter={int(r.get('counter'))}", flush=True)
