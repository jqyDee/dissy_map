import time
import socket
import threading
import argparse

class ReplicatedNode:
    def __init__(self, node_name: str, local_port: int, peer_ip: int, peer_port: int):
        self.node_name = node_name
        self.local_port = local_port
        self.peer_ip = peer_ip
        self.peer_port = peer_port
        self.counter = 0
        self.counter_peer = 0
        self.lock = threading.Lock()
        self.running = True

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", self.local_port))

    def increment(self):
        with self.lock:
            self.counter += 1
            print(f"local increment on {self.node_name}: counter: {self.counter}")

    def listen(self):
        self.sock.settimeout(0.5)
        while self.running:
            try:
                data, _ = self.sock.recvfrom(1024)
                received_val = int(data.decode("utf-8"))
                with self.lock:
                    old_val = self.counter_peer
                    self.counter_peer = max(self.counter_peer, received_val)
                    print(f"[{self.node_name}] RECV {received_val}, updated: {old_val} -> {self.counter}")
            except socket.timeout:
                continue

    def send_state(self):
        with self.lock:
            msg = str(self.counter).encode("utf-8")
            try:
                self.sock.sendto(msg, (self.peer_ip, self.peer_port))
            except Exception as e:
                print(f"Error: {e}")

    def sync_loop(self, sync_interval_sec: float = 0.05):
        while self.running:
            self.send_state()
            time.sleep(sync_interval_sec)

    def stop(self):
        self.running = False
        self.sock.close()

if __name__ == "__main__":

    # use args like this, eg:
    # python3 counter.py --id A --port 5001 --peer-port 5002
    # python3 counter.py --id B --port 5002 --peer-port 5001
    parser = argparse.ArgumentParser(description="Task 1.1 Naive Counter Node")
    parser.add_argument("--id", required=True, help="Node ID (e.g., A or B)")
    parser.add_argument("--port", type=int, required=True, help="Local listen port")
    parser.add_argument("--peer-ip", default="127.0.0.1", help="Target peer IP (EC2 Private/Public IP)")
    parser.add_argument("--peer-port", type=int, required=True, help="Target peer port")
    args = parser.parse_args()

    node = ReplicatedNode(args.id, args.port, args.peer_ip, args.peer_port)

    listener = threading.Thread(target=node.listen, daemon=True)
    listener.start()

    sender = threading.Thread(target=node.sync_loop, daemon=True)
    sender.start()

    start_time = time.time()

    
    N = 100
    
    for _ in range(N):
        time.sleep(0.1)
        node.increment()
        print(f"[{node.node_name}] INC to {node.counter}")


    while True:
        continue