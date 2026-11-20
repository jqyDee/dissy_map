"""Task 3.6: many auctions with randomly injected faults + invariant check.

Runs on your LAPTOP and drives the five nodes:
  remote (EC2, over SSH):  python3 chaos.py --tf-dir .. --auctions 30
  local  (dev, processes): python3 chaos.py --local --zk 127.0.0.1:2181 --auctions 5

Faults: crash (kill -9 + restart), freeze (SIGSTOP/SIGCONT, longer than the
session timeout => session expiry), disconnect (iptables drop on 2181, remote only).
"""
import argparse
import json
import os
import random
import subprocess
import sys
import threading
import time
from collections import Counter

KEY = os.path.expanduser("~/.ssh/labsuser.pem")
PID = "$(cat ~/bot.pid 2>/dev/null)"


class Cluster:
    def __init__(self, args):
        self.local = args.local
        self.zk = args.zk
        self.python = sys.executable if args.local else "python3"
        self.app = os.path.dirname(os.path.abspath(__file__))
        if args.local:
            self.nodes = {n: None for n in "ABCDE"}
        else:  # {"A": "<public ip>", ...} from `output "nodes"` in Terraform
            self.nodes = json.loads(subprocess.check_output(
                ["terraform", "output", "-json", "nodes"], cwd=args.tf_dir))

    def sh(self, node, cmd, timeout=60):
        if self.local:
            home = f"/tmp/chaos-home/{node}"
            os.makedirs(home, exist_ok=True)
            env = {**os.environ, "HOME": home, "ZK_HOSTS": self.zk}
            argv = ["bash", "-c", cmd]
            return subprocess.run(argv, cwd=self.app, env=env, capture_output=True,
                                  text=True, timeout=timeout)
        argv = ["ssh", "-i", KEY, "-o", "StrictHostKeyChecking=no", "-o", "LogLevel=ERROR",
                f"ec2-user@{self.nodes[node]}", f"cd ~/app && {cmd}"]
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)

    def node_cmd(self, node, aid, cmd):
        return f"{self.python} node.py --quiet --name {node} --auction {aid} {cmd}"

    def run(self, node, aid, cmd):
        return self.sh(node, self.node_cmd(node, aid, cmd)).stdout

    def start_bot(self, node, aid, secs):
        self.sh(node, f"nohup {self.node_cmd(node, aid, f'bot {secs:.0f}')} "
                      f">> ~/bot.log 2>&1 < /dev/null &")


# --- faults (each runs in its own thread, so faults overlap) ----------------
def crash(c, node, aid, rest):
    c.sh(node, f"kill -9 {PID}")
    time.sleep(random.uniform(1, 3))
    c.start_bot(node, aid, rest)  # restarted node must re-read state from ZK


def freeze(c, node, aid, rest):
    secs = random.uniform(2, 8)  # > 4 s session timeout => sometimes expires
    c.sh(node, f"kill -STOP {PID}; sleep {secs:.1f}; kill -CONT {PID}")


def disconnect(c, node, aid, rest):
    secs = random.uniform(2, 8)
    rule = "OUTPUT -p tcp --dport 2181 -j DROP"
    c.sh(node, f"sudo iptables -I {rule}; sleep {secs:.1f}; sudo iptables -D {rule}")


# --- invariants ---------------------------------------------------------------
def check(dump, claims):
    state, log = dump["state"], dump["log"]
    errs = []
    ops = [e["op"] for e in log]
    bids = [e for e in log if e["op"] == "bid"]
    if state["status"] != "CLOSED":
        errs.append("auction not closed")
    if ops.count("close") != 1:
        errs.append(f"{ops.count('close')} close operations in log")
    elif "bid" in ops[ops.index("close"):]:
        errs.append("bid committed after close")
    amounts = [b["amount"] for b in bids]
    if any(a >= b for a, b in zip(amounts, amounts[1:])):
        errs.append(f"accepted bids not strictly increasing: {amounts}")
    expected = {"bidder": bids[-1]["bidder"], "amount": bids[-1]["amount"]} if bids else None
    if state["winner"] != expected:
        errs.append(f"winner {state['winner']} != highest accepted bid {expected}")
    committed = {b["op_id"] for b in bids}
    for cl in claims:
        if cl["op"] == "bid" and "op_id" in cl:
            if cl["ok"] is True and cl["op_id"] not in committed:
                errs.append(f"node {cl['node']} claimed accepted, but not in ZK: {cl}")
            if cl["ok"] is False and cl["op_id"] in committed:
                errs.append(f"node {cl['node']} claimed rejected, but committed: {cl}")
        if cl["op"] == "close" and cl["winner"] != state["winner"]:
            errs.append(f"node {cl['node']} reported different winner {cl['winner']}")
    return errs


def run_auction(c, aid, dur, faults, stats):
    names = list(c.nodes)
    c.run(names[0], aid, "open chaos-item")
    for n in names:
        c.start_bot(n, aid, dur)
    started, threads = time.time(), []
    while time.time() - started < dur * 0.6:          # inject faults while bidding
        time.sleep(random.uniform(0.5, 2.0))
        f = random.choice(faults)
        stats[f.__name__] += 1
        rest = max(1.0, dur - (time.time() - started))
        t = threading.Thread(target=f, args=(c, random.choice(names), aid, rest))
        t.start()
        threads.append(t)

    # two nodes close at the same time, while bots are still bidding
    closers = [threading.Thread(target=c.run, args=(n, aid, "close"))
               for n in random.sample(names, 2)]
    for t in closers:
        t.start()
    for t in closers + threads:
        t.join()

    # a closer may have been cut off by a fault: make sure SOMEONE closed it
    dump = None
    for n in random.sample(names, len(names)):
        out = c.run(n, aid, "dump").strip().splitlines()
        if out and out[-1].startswith("{"):
            dump = json.loads(out[-1])
            if dump["state"]["status"] == "CLOSED":
                break
            c.run(n, aid, "close")
    dump = json.loads(c.run(names[0], aid, "dump").strip().splitlines()[-1])

    for n in names:  # stop leftovers, undo faults
        c.sh(n, f"kill -CONT {PID} 2>/dev/null; kill -9 {PID} 2>/dev/null; true")

    claims = []
    for n in names:
        for line in c.sh(n, "cat ~/claims.jsonl 2>/dev/null").stdout.splitlines():
            cl = json.loads(line)
            if cl.get("auction") == aid:
                claims.append(cl)
    stats["badversion_retries"] += sum(cl.get("retries", 0) for cl in claims if cl["op"] == "stats")
    stats["accepted_bids"] += sum(1 for e in dump["log"] if e["op"] == "bid")
    return check(dump, claims), dump["state"]["winner"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--local", action="store_true", help="nodes = local processes")
    p.add_argument("--zk", default="127.0.0.1:2181", help="ZK address (local mode)")
    p.add_argument("--tf-dir", default="..", help="dir with the Terraform state (remote mode)")
    p.add_argument("--auctions", type=int, default=20)
    p.add_argument("--duration", type=float, default=15, help="seconds of bidding per auction")
    args = p.parse_args()

    c = Cluster(args)
    faults = [crash, freeze] if args.local else [crash, freeze, disconnect]
    prefix = f"chaos{int(time.time())}"
    stats, failed = Counter(), 0
    for i in range(args.auctions):
        aid = f"{prefix}-{i}"
        errs, winner = run_auction(c, aid, args.duration, faults, stats)
        failed += bool(errs)
        print(f"{aid}: {'OK' if not errs else 'VIOLATION'}  winner={winner}", flush=True)
        for e in errs:
            print(f"   - {e}")

    print("\n| metric | value |\n|---|---|")
    print(f"| auctions | {args.auctions} |")
    for k, v in sorted(stats.items()):
        print(f"| {k} | {v} |")
    print(f"| auctions with invariant violations | {failed} |")


if __name__ == "__main__":
    main()
