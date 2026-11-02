import socket, threading, sys


#usage: python3 node.py <my_port> <peer_host> <peer_port>
# laptop(A): python3 node.py 5001 <vm_ip> 5002
# VM(B): python3 node.py 5002 - -
# "-" ) peer not known yet, B learns A's address from A's first message

# 1. state: the counter and a lock 
counter = 0
lock = threading.Lock()


#2. network: creade a UDP socket, bind it to a port 
# the peer's address is a (host, port) tuple
my_port = int(sys.argv[1])
peer_host = sys.argv[2]
peer_port = sys.argv[3]


#where we send out state to; none = we dont know the peer yet
if(peer_host == "-"):
    peer_addr = None
else: 
    peer_addr = (peer_host, int(peer_port))

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    #binding host and port.
sock.bind(("0.0.0.0", my_port)) 
# 0.0.0.0 is the host - listen on every network connection this computer has
# my_port is the port we're waiting to receive messages to

# 3. function listen(): loop forever
#  receive a message -> turn in into int and merge with max (under the lock) 
def listen():
    global counter, peer_addr
    while(True): 
        data, sender = sock.recvfrom(1024) 
        num = int(data.decode())
        with lock:
            counter = max(counter, num)

            #reply to whoever the message came form (needed behind a home router)
            peer_addr = sender
   


# start listen() in a background thread
# target is the job 
# daemon = True means that the thread is dead when main thread dies 
threading.Thread(target=listen, daemon=True).start()

# 5. main loop: read input 
#   inc -> counter++
#   sync -> send counted to peer
#   show -> print coutner


while True: 
    try: 
        cmd = input("> ")
    except (EOFError, KeyboardInterrupt):
        break
    if cmd == "inc":
        with lock:
            counter += 1
    elif cmd == "sync":
        if peer_addr is None:
            print("peer not known yet, wait for a message from the other node")
        else:
            sock.sendto(str(counter).encode(),peer_addr)
    elif cmd == "print":
        print(counter)
    elif cmd == "quit":
        break