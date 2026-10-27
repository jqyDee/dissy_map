import socket, threading, sys


counter_a = 0
counter_b = 0 
lock = threading.Lock()

my_port = int(sys.argv[1])
peer_port = int(sys.argv[2])
my_id = sys.argv[3]

if my_id not in("A", "B"):
    print("third argument must be A or B")
    sys.exit(1)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", my_port))

def listen():
    global counter_a, counter_b
    while(True):
        data, sender = sock.recvfrom(1024)
        text = data.decode()
        parts = text.split(",")
        a = int(parts[0])
        b = int(parts[1])
        with lock:
            counter_a = max(counter_a, a)
            counter_b = max(counter_b, b)


threading.Thread(target=listen, daemon=True).start()

while True:
    cmd = input("> ")
    if cmd == "inc":
        with lock:
            if(my_id == 'A'):
                counter_a += 1
            elif(my_id == 'B'):
                counter_b += 1
    elif cmd == "sync":
        sock.sendto(f"{counter_a}, {counter_b}".encode(), ("127.0.0.1", peer_port))
    elif cmd == "print":
        print(counter_a + counter_b)
    elif cmd == "quit":
        break