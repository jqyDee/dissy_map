import os
import queue
import socket
import threading
import time
from datetime import datetime

NODE_ID = os.environ["NODE_ID"]
PEER = os.environ["PEER"]
PORT = 8000
N = int(os.environ.get("N", "100"))
START_AT = float(os.environ.get("START_AT", "0"))  # unix time, both nodes start together

local_increments = 0  # only written by the main thread
peer_increments = 0  # only written by the receive thread
acks = queue.Queue()

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", PORT))


def receive():
    global peer_increments
    while True:
        data, addr = sock.recvfrom(64)
        kind, value = data.decode().split()
        if kind == "STATE":
            peer_increments = max(peer_increments, int(value))
            sock.sendto(f"ACK {value}".encode(), addr)
        else:  # ACK from the peer
            acks.put(int(value))


def sync(value):
    """Send own state to the peer and block until the peer acknowledged it."""
    while True:
        sock.sendto(f"STATE {value}".encode(), (PEER, PORT))
        try:
            while acks.get(timeout=0.5) < value:
                pass  # ack of an older message, keep waiting
            return
        except queue.Empty:
            pass  # message or ack lost -> resend


threading.Thread(target=receive, daemon=True).start()

while time.time() < START_AT:
    time.sleep(0.001)

local_s = sync_s = 0.0
for _ in range(N):
    t0 = time.perf_counter()
    local_increments += 1
    t1 = time.perf_counter()
    sync(local_increments)
    t2 = time.perf_counter()
    local_s += t1 - t0
    sync_s += t2 - t1
    
    now = datetime.now()
    ts = now.isoformat(timespec="milliseconds")
    counter = local_increments + peer_increments
    print(
        f"[{NODE_ID};{ts}] counter={counter:3} peer_counter={peer_increments} own_increments={local_increments}",
        flush=True,
    )

print(f"[{NODE_ID}] n={N} local={local_s * 1000:.3f}ms sync={sync_s * 1000:.1f}ms "
      f"avg_sync={sync_s / N * 1000:.3f}ms", flush=True)
time.sleep(2)  # keep acking the peer until it is done
print(f"[{NODE_ID}] final counter={local_increments + peer_increments}", flush=True)
