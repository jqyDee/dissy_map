import os
import random
import socket
import threading
import time
from datetime import datetime

NODE_ID = os.environ["NODE_ID"]
PEER = os.environ["PEER"]
PORT = 8000
INCREMENT_FOR = float(os.environ.get("INCREMENT_FOR", "10"))  # seconds
SYNC_DELAY = float(os.environ.get("SYNC_DELAY", "0"))

peer_increments = 0  # increments done by the peer node
local_increments = 0  # increments done by this node, to compare with the result

lock = threading.Lock()

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", PORT))


def receive():
    global peer_increments
    while True:
        data, _ = sock.recvfrom(64)
        with lock:
            peer_increments = max(peer_increments, int(data))


def send():
    time.sleep(SYNC_DELAY)
    while True:
        with lock:
            value = local_increments
        sock.sendto(str(value).encode(), (PEER, PORT))
        time.sleep(0.5)


threading.Thread(target=receive, daemon=True).start()
threading.Thread(target=send, daemon=True).start()

start = time.time()
while True:
    now = datetime.now()
    ts = now.isoformat(timespec="milliseconds")
    incrementing = time.time() - start < INCREMENT_FOR
    if incrementing and random.random() < 0.5:
        with lock:
            local_increments += 1
    with lock:
        counter = peer_increments + local_increments  # global counter value
        phase = "incrementing" if incrementing else "stopped"
        print(
            f"[{NODE_ID};{ts}] {phase:12} counter={counter:3} peer_counter={peer_increments} own_increments={local_increments}",
            flush=True,
        )
    time.sleep(1)
