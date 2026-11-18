"""Auction node: interactive CLI, one-shot command, or bot (for chaos runs).

python3 node.py --name A                    # REPL
python3 node.py --name A bid alice 100      # one command, then exit
python3 node.py --name A --auction a7 bot 20  # random bids for 20 s
"""

import argparse
import json
import os
import random
import socket
import threading
import time

from auction import ROOT, Auction, NotConnected, state_path
from kazoo.client import KazooClient, KazooState
from kazoo.exceptions import KazooException, NodeExistsError, NoNodeError

MEMBERS = "/members"
CLAIMS = os.path.expanduser("~/claims.jsonl")


def fmt(s):
    top = f"{s['bidder']}:{s['amount']}" if s["amount"] is not None else "none"
    extra = f"  winner={s['winner']}" if s["status"] == "CLOSED" else ""
    return f"[{s['auction_id']}] {s['item']!r} {s['status']} highest={top}{extra}"


def claim(**kw):
    """Record what this node TOLD the user. The chaos checker compares it with ZK."""
    with open(CLAIMS, "a") as f:
        f.write(json.dumps({**kw, "t": time.time()}) + "\n")


def run(auction, words, node):
    cmd, *rest = words
    if cmd == "open":
        ok = auction.open(" ".join(rest) or "item")
        print("opened" if ok else "already exists, not touching it")
    elif cmd == "bid":
        ok, msg = auction.bid(rest[0], int(rest[1]))
        claim(
            node=node,
            auction=auction.aid,
            op="bid",
            bidder=rest[0],
            amount=int(rest[1]),
            ok=ok,
        )
        print(msg)
    elif cmd == "show":
        state, ver = auction.read()
        print(f"v{ver} {fmt(state)}")
    elif cmd == "close":
        winner, msg = auction.close()
        claim(node=node, auction=auction.aid, op="close", winner=winner)
        print(f"winner: {winner or 'none (no bids)'} ({msg})")
    elif cmd == "log":
        for e in auction.history():
            print(e)
    elif cmd == "dump":  # machine-readable, used by chaos.py
        state, ver = auction.read()
        print(json.dumps({"state": state, "version": ver, "log": auction.history()}))
    elif cmd == "bot":
        bot(auction, float(rest[0]) if rest else 20.0, node)
    else:
        print(
            "commands: open <item> | bid <who> <amount> | show | close | log | dump | bot <secs> | quit"
        )


def bot(auction, seconds, node):
    with open(os.path.expanduser("~/bot.pid"), "w") as f:
        f.write(str(os.getpid()))
    end = time.time() + seconds
    while time.time() < end:
        try:
            state, _ = auction.read()
            if state["status"] == "CLOSED":
                break
            amount = (state["amount"] or 0) + random.randint(1, 20)
            op_id = os.urandom(8).hex()
            ok, msg = auction.bid(f"{node}-bidder", amount, op_id=op_id)
            claim(
                node=node,
                auction=auction.aid,
                op="bid",
                op_id=op_id,
                amount=amount,
                ok=ok,
            )
            print(f"[bot] bid {amount}: {msg}", flush=True)
        except (NotConnected, KazooException) as e:
            print(f"[bot] refused/failed: {type(e).__name__}: {e}", flush=True)
            time.sleep(0.5)
        time.sleep(random.uniform(0.05, 0.5))
    claim(node=node, auction=auction.aid, op="stats", retries=auction.retries)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--zk", default=os.environ.get("ZK_HOSTS", "127.0.0.1:2181"))
    p.add_argument("--name", default=socket.gethostname())
    p.add_argument("--auction", default="a1")
    p.add_argument("--timeout", type=float, default=4.0, help="ZK session timeout (s)")
    p.add_argument(
        "--delay", type=float, default=0.0, help="debug: sleep between read and write"
    )
    p.add_argument("--quiet", action="store_true", help="no watch output")
    p.add_argument("cmd", nargs="*", help="run one command and exit")
    args = p.parse_args()

    zk = KazooClient(hosts=args.zk, timeout=args.timeout)
    connected = threading.Event()
    lost = {"flag": False}

    def register():
        path = f"{MEMBERS}/{args.name}"
        try:
            zk.create(path, args.name.encode(), ephemeral=True, makepath=True)
        except NodeExistsError:
            # Leftover from OUR previous (crashed) session that hasn't expired yet.
            zk.delete(path)
            zk.create(path, args.name.encode(), ephemeral=True)

    def on_conn(state):  # runs in kazoo's thread: set flags only, never block
        if state == KazooState.CONNECTED:
            connected.set()
            print("[conn] CONNECTED", flush=True)
            if lost["flag"]:  # new session: our ephemeral node is gone
                lost["flag"] = False
                zk.handler.spawn(register)
        else:
            connected.clear()
            if state == KazooState.LOST:
                lost["flag"] = True
            print(f"[conn] {state}: operations refused until reconnected", flush=True)

    zk.add_listener(on_conn)
    zk.start(timeout=10)
    if zk.state == KazooState.CONNECTED:
        connected.set()
    zk.ensure_path(ROOT)
    zk.ensure_path(MEMBERS)
    register()

    auction = Auction(
        zk,
        args.auction,
        connected,
        args.name,
        delay=args.delay,
        log=lambda m: print(m, flush=True),
    )

    if not args.quiet:

        @zk.ChildrenWatch(MEMBERS)
        def on_members(children):
            print(f"[members] {sorted(children)}", flush=True)

        @zk.DataWatch(state_path(args.auction))
        def on_change(data, stat):
            if data is None:
                print(
                    f"[watch] auction {args.auction} does not exist yet, use: open <item>",
                    flush=True,
                )
            else:
                print(f"[watch v{stat.version}] {fmt(json.loads(data))}", flush=True)

    def safe_run(words):
        try:
            run(auction, words, args.name)
        except NotConnected as e:
            print(f"REFUSED: {e}")
        except NoNodeError:
            print(f"auction {args.auction} does not exist, use: open <item>")
        except (IndexError, ValueError):
            print("bad arguments")
        except KazooException as e:
            print(f"ZooKeeper error: {type(e).__name__}, nothing claimed")

    if args.cmd:
        safe_run(args.cmd)
    else:
        while True:
            try:
                line = input(f"{args.name}> ").split()
            except EOFError:
                break
            if not line:
                continue
            if line[0] in ("quit", "exit"):
                break
            safe_run(line)
    zk.remove_listener(on_conn)  # don't report our own clean shutdown as LOST
    zk.stop()


if __name__ == "__main__":
    main()
