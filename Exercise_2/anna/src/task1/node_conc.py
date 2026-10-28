import socket, threading, sys, time

# usage: python3 node_conc.py <my_port> <peer_host> <peer_port> <A|B>
# laptop(A): python3 node_conc.py 5001 <vm_ip> 5002 A
# VM(B): python3 node_conc.py 5002 - - B
# "-" = peer not known yet, B learns A's adddress from A's first message


counter_a = 0
counter_b = 0 
lock = threading.Lock()

my_port = int(sys.argv[1])
peer_host = sys.argv[2]
peer_port = sys.argv[3]
my_id = sys.argv[4]

if my_id not in("A", "B"):
    print("third argument must be A or B")
    sys.exit(1)


#where we send out state to; none = we dont know the peer yet

if(peer_host == "-"):
    peer_addr = None
else: 
    peer_addr = (peer_host, int(peer_port))


#set by the listener whenever a message arrives (used to time a sync round trip)
reply_received = threading.Event()


sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", my_port))


def send_state(ask_reply=False):
    with lock:
        msg = f"{counter_a}, {counter_b}"
        addr = peer_addr
    if ask_reply:
        msg += ",?"
    sock.sendto(msg.encode(), addr)

def listen():
    global counter_a, counter_b, peer_addr
    while(True):
        data, sender = sock.recvfrom(1024)
        text = data.decode()
        parts = text.split(",")
        a = int(parts[0])
        b = int(parts[1])
        with lock:
            counter_a = max(counter_a, a)
            counter_b = max(counter_b, b)
            # reply to wherever the message came form (needed behind a home router)

            peer_addr = sender
        if len(parts) == 3 and parts[2] == "?":
            send_state()
        reply_received.set()

def increment():
    global counter_a, counter_b
    with lock:
        if my_id == "A":
            counter_a += 1
        elif my_id == "B":
            counter_b += 1

def bench(n):
    #task 3.1: n incrementsm each followed by a sync round trip
    local_time = 0.0
    sync_time = 0.0
    lost = 0
    for i in range(n):
        start = time.perf_counter()
        increment()
        local_time += time.perf_counter() - start

        reply_received.clear()
        start = time.perf_counter()
        send_state(ask_reply=True)
        if not reply_received.wait(timeout=2):
            lost += 1
        sync_time += time.perf_counter() - start

    print(f"{n} increments")
    print(f"local updates: total {local_time * 1000:.4f} ms, per increment {local_time / n * 1000:.6f} ms")
    print(f"sync round trips: total {sync_time * 1000:.3f} ms, per sync {sync_time / n * 1000:.3f} ms lost {lost}")



threading.Thread(target=listen, daemon=True).start()

while True:
    try:
        cmd = input("> ").split()
    except (EOFError, KeyboardInterrupt):
        break
    if not cmd: 
        continue
    if cmd[0] == "inc":
        increment()
    elif cmd[0] == "sync":
        if peer_addr is None:
            print("peer not known yet, wait for a message form the other node")
        else:
            send_state()
    elif cmd[0] == "print":
        with lock:
            print(f"{counter_a + counter_b}  (A: {counter_a}, B: {counter_b})")
    elif cmd[0] == "bench":
        if peer_addr is None:
            print("peer not known yet (wait for a message from the other node)")
        else:
            bench(int(cmd[1]) if len(cmd) > 1 else 100)
    elif cmd[0] == "quit":
        break