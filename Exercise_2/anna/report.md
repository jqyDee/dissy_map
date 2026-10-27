# EX0X Report: [Exercise Title]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Task 1 - Replicated Counter
In this exercise we are talking about replicated state. Replicated state means that every node keeps its own copy of the data. The nodes have to exchange messages and merge the copies to keep them consistent. Unlike single-copy state (Task 2), there is no one authoritative copy. 

### 1.1 Program where each node updates its own counter (change this lol)
The goal was to create two nodes, both of them keep their own counters and they synchronise by exchanging values. 

In our program every node keepts its own copy (replica) of the counter. We initialise it together with a lock to protect the counter from simultaneous access by the two threads we will be running inside one node: 

```python
counter = 0
lock = threading.Lock()
```

The idea is to start one program twice with two different ports (for example 5001 and 5002). `my_port` would be used for receiving and `peer_port` for sending. We can use any port number from 1024 to 49151 

0-1023 are reserved for system services like ssh or http and we have to avoid ports that are alreasy used on our machine, like 6379 which Redis uses (we need it in task 2)

```python
my_port = int(sys.argv[1])
peer_port = int(sys.argv[2])
```

We have to initialise the socket for the two nodes to communicate with each other:

```python
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
```
first argument specifies the family of addresses our socket is suited for, in our case its IPv4 addresses. Other cases options would be `AF_INET6` for IPv6 or `AF_UNIX` for files on the same machine. 
second argument specifies how th messages are caried. In our case it is `SOCK_DGRAM` (datagram, a single standalone packet)

-> we chose UDP protocol for communication because it doesn't need no connection setup, unlike TCP (`SOCK_STREAM`) and one counter value fits in one packet. Also, every message contrains the node's whole counter value, not just "+1". If one message gets lost, the next sync fixes it enyway. UDP can lose, ducplicate and reorder messages, which is what we look at in task 1.3


then we have to bind the socket to the port:
```python
sock.bind(("0.0.0.0", my_port)) 
```

first arugment is the host, in this case we listen to every network we have access to, like all the incoming things. 

`my_port` is the port we watch to receive new messages



Then we have defined a `listen()` function that loops forever and waits for data to be received. The data is the value of the counter. The function performs the update, with lock, by finding out max value.
`recvfrom(1024)` waits until a packet arrives and reads up to 1024 btes of it, which is more than enough for a number. 

The network carries bytes, so the receiver converts bytes to string to int with `int(data.decode())` and the sender in the main thread does the opposite with `(str(counter).encode())`.

```python
def listen():
    global counter
    while(True): 
        data, sender = sock.recvfrom(1024)
        num = int(data.decode())
        with lock:
            counter = max(counter, num)
```


We need two threads because `input()` and `recvfrom()` are both blocking. With only one thread the node could either wait for our commants or for messages, but not both. 

So, we create a background thread whose only job is to `listen()`, 
the thread dies, when the main program terminates `(daemon=True)`:
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
Experimenting: 

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

Tadaaa syncronisation works, however!



### 1.2 Convergence != we're good 

If we do what's asked of us in task 1.2:
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

The problem is concurrency - two events happened and neither node knew about the other when it happened. A increments its counter and doesn't notify B, so B still has 0. Then, B increments 2, still not knowing about A's increment. Both increments happened in sectet. When they sync, each node only receives the number 1 and can't tell whether it's the other node's own increment or the same one it already counted. `max(1, 1)` assumes the second, so both nodes end up at 1 and one increment is sinently lost. 

If we do thesame increments and sync one after the other: 

A: inc, sync -> B: inc, sync, we get 2 because the nodes are aware of each other's doings.

In our case both nodes agreeing on 1 is wrong. So convergence only guarantees that the replicas of the counter end up the same, it does not guarantee that no information was lost on the way.  



### 1.3 Lost, duplicated, wrong order

1.  What happens if A synchronization message is lost?
    
    
    UPD does not detect or resend lost packets, so a synchronisation message can simply disappear on its way. In that case the systen finds itself in a temporarily inconsistent state, until a command to synchronise is sent again and the message actually arrives. Because in our implementation the message carries the whole counter and not just an increment, so the next syncronisation message that goes trough brings everybody up to date, no matter how many messages were lost before. However, if the lost message was the last one, there is a problem, because in our program syncronisation is manual. So, if nobody types sync again, the nodes stay different forever. If synchronisation was happening automatically, for example, exery few seconds, a lost message would always be repaired by the next one and the nodes would eventually converge.

2. What happens if the same message is received twice?

    In this case, nothing dramatic happens, because in our implementation it's the counter that travels and not the increment. So, we would just compare the same things multiple times which will result in the same outcome, no matter if the duplicate is sent 2 or 500 times. 

3. What happens if an older message arrives after a newer one? 
    
    An older message contains a value that's smaller or equal to what B already has, so max throws it away. 

4. Which situations cause problems for your implementation? Explain briefly.
    
    Only the situation with the lost message and only if it was the last message. Duplicated and late messages are okay thanks to the max function and the fact that the counter variable travels. Also, the problem of our implementation is the concurrent increments (like in 1.2)


### 1.4 Modification to save concurrent increments.

In 1.2 we saw that `max` loses increments when A and B increment concurrently, because a single number doesn't tell the receiver *whose* increments it contains. To fix this, every node now keeps two counters instead of one: one for the increments performed by A and one for the increments performed by B.

```python
counter_a = 0
counter_b = 0
lock = threading.Lock()
```

**Each node only ever increments its own slot**. A only changes `counter_a`, B only changes `counter_b`. So that a node knows which slot is its own, we pass its id as a third command-line argument:

```bash
python3 node_gcounter.py 5001 5002 A   # node A
python3 node_gcounter.py 5002 5001 B   # node B
```

```python
my_id = sys.argv[3]

if my_id not in ("A", "B"):
    print("third argument must be A or B")
    sys.exit(1)
```

The check makes the program stop right away if we start it with a wrong id, instead of running a node that silently ignores `inc`.

We have one `inc` command, and the node decides which slot to increment based on its id (with lock, since the listener thread also changes the counters):

```python
if cmd == "inc":
    with lock:
        if my_id == "A":
            counter_a += 1
        elif my_id == "B":
            counter_b += 1
```


When synchronising, we send **both** counters as one string, e.g. `"1,0"`, and not the total. If we only sent the total, the receiver would again get one number without knowing whose increments are in it, which is exactly the problem from 1.2.

```python
elif cmd == "sync":
    sock.sendto(f"{counter_a},{counter_b}".encode(), ("127.0.0.1", peer_port))
```

The receiver splits the string back into two numbers and merges them **slot by slot with max**:

```python
def listen():
    global counter_a, counter_b
    while True:
        data, sender = sock.recvfrom(1024)
        parts = data.decode().split(",")
        a = int(parts[0])
        b = int(parts[1])
        with lock:
            counter_a = max(counter_a, a)
            counter_b = max(counter_b, b)
```

Why does `max` suddenly work, when it failed in 1.2? Because each slot is now only one node's own history. `counter_a` only ever counts A's increments, so the bigger value really does include the smaller one, and nothing gets mixed up. The merge also keeps all the good properties from 1.3: duplicates change nothing, and late messages are ignored (the slots only grow).

The value of the counter is the **sum** of both slots, because that's the total number of increments:

```python
elif cmd == "print":
    print(counter_a + counter_b)
```

So **max** checks which version of A or B's history is newer and **sum** reads how many increments happened altogether.

Testing the scenario from 1.2 again:

| Step | A `[a, b]` → value | B `[a, b]` → value |
| :--- | :--- | :--- |
| start | `[0, 0]` → 0 | `[0, 0]` → 0 |
| A: `inc` | `[1, 0]` → 1 | `[0, 0]` → 0 |
| B: `inc` | `[1, 0]` → 1 | `[0, 1]` → 1 |
| A: `sync` | `[1, 0]` → 1 | `[1, 1]` → **2** |
| B: `sync` | `[1, 1]` → **2** | `[1, 1]` → **2** |
| A: `sync` again (duplicate) | `[1, 1]` → 2 | `[1, 1]` → 2 |


Both nodes end up with 2. So this time they don't only agree, they also have the **correct** value, and both increments survive even though they happened concurrently.

This kind of counter is called a **G-Counter** (grow-only counter). It is one of the simplest **CRDTs** (Conflict-free Replicated Data Types): data types whose replicas can be updated independently and always converge to the same correct value when they merge, no matter in which order or how often the messages arrive.







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
