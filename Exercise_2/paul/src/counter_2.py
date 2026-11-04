import time
import argparse
import redis

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Task 2 Single-copy Counter Node")
    parser.add_argument("--id", required=True, help="Node ID (e.g., A or B)")
    parser.add_argument("--redis-ip", required=True, help="Redis server private IP")
    parser.add_argument("--redis-port", type=int, default=6379)
    parser.add_argument("--n", type=int, default=100, help="Number of increments")
    parser.add_argument("--delay", type=float, default=0.0, help="Sleep between increments in seconds (0 for benchmark)")
    args = parser.parse_args()

    r = redis.Redis(host=args.redis_ip, port=args.redis_port, decode_responses=True)

    other = "B" if args.id == "A" else "A"

    # A resets everything (counter + both barrier keys) so stale state from
    # previous runs doesn't cause B's ready signal to be seen before B starts.
    # Safe in manual mode since A is always started first.
    if args.id == "A":
        r.delete("counter", "ready_A", "ready_B")
        print(f"[{args.id}] Counter and barrier reset")

    r.set(f"ready_{args.id}", 1)
    print(f"[{args.id}] Waiting for peer...")
    while not r.exists(f"ready_{other}"):
        time.sleep(0.1)
    print(f"[{args.id}] Both ready — starting")

    start = time.time()

    for i in range(args.n):
        new_val = r.incr("counter")
        print(f"[{args.id}] increment {i + 1}/{args.n} -> counter = {new_val}")
        if args.delay > 0:
            time.sleep(args.delay)

    elapsed = time.time() - start
    final = r.get("counter")

    print(f"[{args.id}] Done: {args.n} increments in {elapsed:.3f}s  ({elapsed / args.n * 1000:.2f} ms/op)")
    print(f"[{args.id}] Observed final counter value: {final}  (expected 200 when both nodes finish)")
