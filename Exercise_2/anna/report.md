# EX0X Report: [Exercise Title]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Task 1 - Replicated Counter
In this exercise we are talking about replicated state. Replicated state means that every node keeps its own copy of the data. The nodes have to exchange messages and merge the copies to keep them consistent. Unlike single-copy state (Task 2), there is no one authoritative copy. 

### 1.1 Program where each node updates its own counter (change this lol)
The goal was to create two nodes, both of them keep their own counters and they synchronise by exchanging values. 

In our program every node keepts its own copy (replica) of the counter.We initialise it together with a lock to protect the counter from simultaneous access by the two threads we will be running inside one node: 

```python
counter = 0
lock = threading.Lock()
```

The idea is to start one program twice with two different ports (for example 5001 and 5002). my_port would be used for receiving and peer_port for sending. We can use any port number from 1024 to 49151 

0-1023 are reserved for system services like ssh or http and we have to avoid ports that are alreasy used on our machine, like 6379 which Redis uses (we need it in task 2)

```python
my_port = int(sys.argv[1])
peer_port = int(sys.argv[2])
```

We have to initialise the socket for the two nodes to communicate with each other:

```python
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
```
first argument specifies the family of addresses our socket is suited for, in our case its IPv4 addresses. Other cases options would be AF_INET6 for IPv6 or AF_UNIX for files on the same machine. 
second argument specifies how th messages are caried. In our case it is SOCK_DGRAM (datagram, a single standalone packet)

-> we chose UDP protocol for communication because it doesn't need no connection setup, unlike TCP (SOCK_STREAM) and one counter value fits in one packet. Also, every message contrains the node's whole counter value, not just "+1". If one message gets lost, the next sync fixes it enyway. UDP can lose, ducplicate and reorder messages, which is what we look at in task 1.3


then we have to bind the socket to the port:
```python
sock.bind(("0.0.0.0", my_port)) 
```

first arugment is the host, in this case we listen to every network we have access to, like all the incoming things. 

my_port is the port we watch to receive new messages



Then we have defined a listen() function that loops forever and waits for data to be received. The data is the value of the counter. The function performs the update, with lock, by finding out max value.
recvfrom(1024) waits until a packet arrives and reads up to 1024 btes of it, which is more than enough for a number. 

The network carries bytes, so the receiver converts bytes to string to int with int(data.decode()) and the sender in the main thread does the opposite with (str(counter).encode()).

```python
def listen():
    global counter
    while(True): 
        data, sender = sock.recvfrom(1024)
        num = int(data.decode())
        with lock:
            counter = max(counter, num)
```


We need two threads because input() and recvfrom() are both blocking. With only one thread the node could either wait for our commants or for messages, but not both. 

So, we create a background thread whose only job is to listen(), 
the thread dies, when the main program terminates (daemon=True):
```python
threading.Thread(target=listen, daemon=True).start()
```

Then, the main thread starts an infinite loop where we read input from the command line: 

- inc increments the counter with lock, whithin main thread
- sync for synching sends our counter to peer's port. the address is hardcoded to this maching. 
- print for printing 
- quit for breaking the loop).

```python
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
```



And so we start the program twice, in two terminals:


```bash
python3 node.py 5001 5002   # node A
python3 node.py 5002 5001   # node B
```
experimenting: 

```bash
anna@Annas-MacBook-Air src % python3 node.py 5001 5002
> inc
> inc
> inc
> sync
```


```bash 
anna@Annas-MacBook-Air src % python3 node.py 5002 5001
> print
3
```

tadaaa syncronisation works, however!



### 1.2 Convergence != we're good 

if we do what's asked of us in task 1.2:
- Initially, both counters are zero.
- A increments its counter once.
- At the same time, B increments its counter once.
- Both nodes exchange their counter values

```bash 
anna@Annas-MacBook-Air src % python3 node.py 5001 5002
> inc
> sync
> print
1
```
```bash 
anna@Annas-MacBook-Air src % python3 node.py 5002 5001
> inc
> sync
> print
1
```

We do not get the value we expected (2). 

The problem is concurrency - two events happened and neither node knew about the other when it happened. A increments its counter and doesn't notify B, so B still has 0. Then, B increments 2, still not knowing about A's increment. Both increments happened in sectet. When they sync, each node only receives the number 1 and can't tell whether it's the other node's own increment or the same one it already counted. max(1, 1)assumes the second, so both nodes end up at 1 and one increment is sinently lost. 

If we do thesame increments and sync one after the other: 

A: inc, sync -> B: inc, sync, we get 2 because the nodes are aware of each other's doings.

In our case both nodes agreeing on 1 is wrong. So convergence only guarantees that the replicas of the counter end up the same, it does not guarantee that no information was lost on the way.  



### Table Sample
| Parameter | Value | Description |
| :--- | :--- | :--- |
| **Config A** | `100` | Sample setting |
| **Config B** | `200` | Sample setting |

---

## Task 2 - [Title]

### Code Sample
```python
# Insert your source code snippet here
def main():
    print("Distributed Systems Exercise")

if __name__ == "__main__":
    main()
```

### Figure Sample

Insert images or screenshots of your results, architectures, or execution outputs.

## Discussion Questions

>Question 1: What are your observations regarding...?

Your answer here...

>Question 2: Explain the trade-offs between...

Your answer here...

<!--
Delete this guide section before submitting — it must not appear in the report PDF.

How to generate the PDF (this repo):
- This is the template. Copy it to your folder as the report source:
    cp report.template.md Exercise_<N>/<you>/report.md
  then fill in the sections above.
- Build it with the Makefile (renders report.md -> dist/exc0N_report_<STUDENT_ID>.pdf):
    make submit EX=<N>
  (set your UIBK username once in .env; see the repo README "Setup"). Uses `npx md-to-pdf`.

Alternatives if you prefer:
- VS Code: install the "Markdown PDF" extension, right-click -> Markdown PDF: Export (pdf).
- Browser: open the Markdown preview, Cmd/Ctrl+P -> Save as PDF.
-->
