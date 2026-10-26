import socket, threading, sys

# 1. state: the counter and a lock 
counter = 0
lock = threading.Lock()


#2. network: creade a UDP socket, bind it to a port 
# the peer's address is a (host, port) tuple
my_port = int(sys.argv[1])
peer_port = int(sys.argv[2])

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    #binding host and port.
sock.bind(("0.0.0.0", my_port)) 
# 0.0.0.0 is the host - listen on every network connection this computer has
# my_port is the port we're waiting to receive messages to

# 3. function listen(): loop foreve
#  receive a message -> turn in into int and merge with max (under the lock) 
def listen():
    global counter
    while(True): 
        data, sender = sock.recvfrom(1024)  # revcfrom returns tuple though sender's not used by us :) 
        num = int(data.decode())
        with lock:
            counter = max(counter, num)
   


# start listen() in a background thread
# target is the job 
# daemon = True means that the thread is dead when main thread dies 
threading.Thread(target=listen, daemon=True).start()

# 5. main loop: read input 
#   inc -> counter++
#   sync -> send counted to peer
#   show -> print coutner


while True: 
    cmd = input("> ")
    if cmd == "inc":
        with lock:
            counter += 1
    elif cmd == "sync":
        sock.sendto(str(counter).encode(), ("127.0.0.1", peer_port))
    elif cmd == "print":
        print(counter)
    elif cmd == "quit":
        break