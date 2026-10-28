# EX02 Report: Shared State

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Set up

All programs are written in Python, and we ran them in two settings:

- **Locally:** both nodes (and Redis) on one laptop, communicating over `127.0.0.1`.
- **Laptop + AWS:** node A runs on a laptop in Innsbruck, node B and Redis run on an EC2 instance (`t2.micro`, region `us-east-1`). This way the nodes really are on separate computers and communicate over the internet.

The EC2 instance is created with Terraform (`terraform/main.tf`). Its `user_data` installs Docker and Python and starts Redis in a container, so the VM is ready right after `terraform apply`. The security group only allows traffic from the laptop's public IP (`/32`). Terraform asks for this IP on `apply`, so it is never hardcoded in the file (it changes when we switch networks, and the repository is public).

```hcl
ingress {
  description = "task 1: node B (UDP)"
  from_port   = 5002
  to_port     = 5002
  protocol    = "udp"
  cidr_blocks = ["${var.my_ip}/32"] # who may connect (IP range)
}

ingress {
  description = "task 2: redis"
  from_port   = 6379
  to_port     = 6379
  protocol    = "tcp"
  cidr_blocks = ["${var.my_ip}/32"]
}
```

Plus SSH on port 22 and an egress rule so that the VM can download packages. Port 5002 is UDP because our nodes use UDP (Task 1), and port 6379 is TCP because this is what Redis uses: every command must arrive and gets an answer. 

**NAT:** the laptop is behind a home router, which only lets in the replies to packets the laptop sent first. So node B on the VM cannot send to node A on its own. Instead, A always sends first, and B replies to the address A's message came from.

---

## Task 1 - Replicated Counter

In this exercise we are talking about replicated state. Replicated state means that every node keeps its own copy of the data. The nodes have to exchange messages and merge the copies to keep them consistent. Unlike single-copy state (Task 2), there is no one authoritative copy.

### 1.1 Max-merge synchronisation

The goal was to create two nodes, both of them keep their own counters and they synchronise by exchanging values (`node.py`).

In our program every node keeps its own copy (replica) of the counter. We initialise it together with a lock to protect the counter from simultaneous access by the two threads we will be running inside one node:

```python
counter = 0
lock = threading.Lock()
```

The idea is to start one program twice with different arguments. `my_port` is used for receiving, `peer_host` and `peer_port` for sending. We can use any free port number from 1024 to 49151. 0–1023 are reserved for system services like SSH or HTTP, and we have to avoid ports that are already used on our machine, like 6379, which Redis uses (we need it in Task 2).

```python
my_port = int(sys.argv[1])
peer_host = sys.argv[2]
peer_port = sys.argv[3]

if peer_host == "-":
    peer_addr = None
else:
    peer_addr = (peer_host, int(peer_port))
```

`-` means "I do not know my peer yet". This is needed for node B on the VM because of the NAT: B can't know the laptop's address in advance and learns it from A's first message.

We have to initialise the socket for the two nodes to communicate with each other:

```python
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
```

The first argument specifies the family of addresses our socket is suited for, in our case IPv4 addresses. Other options would be `AF_INET6` for IPv6 or `AF_UNIX` for files on the same machine. The second argument specifies how the messages are carried. In our case it is `SOCK_DGRAM` (datagram, a single standalone packet), which means UDP. The socket is the tool our program uses to talk to the network, UDP is the protocol (the rules) it uses.

We chose UDP because it doesn't need any connection setup, unlike TCP (`SOCK_STREAM`), and one counter value fits in one packet. Also, every message contains the node's whole counter value, not just "+1". If one message gets lost, the next sync fixes it anyway. UDP can lose, duplicate and reorder messages, which is what we look at in Task 1.3.

Then we have to bind the socket to the port:

```python
sock.bind(("0.0.0.0", my_port))
```

The first argument is the host: `0.0.0.0` means we listen on every network connection the computer has (loopback, Wi-Fi, ...). `my_port` is the port we watch to receive new messages.

Then we have defined a `listen()` function that loops forever and waits for data to be received. The data is the value of the other node's counter. The function performs the update, with lock, by taking the max value. `recvfrom(1024)` waits until a packet arrives and reads up to 1024 bytes of it, which is more than enough for a number. It also returns the sender's address, which we remember as `peer_addr`, so our replies go back to wherever the last message came from.

The network carries bytes, so the receiver converts bytes to string to int with `int(data.decode())`, and the sender in the main thread does the opposite with `str(counter).encode()`.

```python
def listen():
    global counter, peer_addr
    while True:
        data, sender = sock.recvfrom(1024)
        num = int(data.decode())
        with lock:
            counter = max(counter, num)
            peer_addr = sender
```

We need two threads because `input()` and `recvfrom()` are both blocking: the program stops on that line until something arrives. With only one thread the node could either wait for our commands or for messages, but not both. So we create a background thread whose only job is to `listen()`. The thread dies when the main program terminates (`daemon=True`):

```python
threading.Thread(target=listen, daemon=True).start()
```

Then the main thread starts an infinite loop where we read input from the command line:

- `inc` increments the counter (with lock)
- `sync` sends our counter to the peer (only possible once we know the peer)
- `print` prints the counter
- `quit` breaks the loop and ends the program

```python
while True:
    cmd = input("> ")
    if cmd == "inc":
        with lock:
            counter += 1
    elif cmd == "sync":
        if peer_addr is None:
            print("peer not known yet, wait for a message from the other node")
        else:
            sock.sendto(str(counter).encode(), peer_addr)
    elif cmd == "print":
        print(counter)
    elif cmd == "quit":
        break
```

And so we start the program twice, once as node B and once as node A:

**Locally:**

```bash
python3 node.py 5002 - -                # node B
python3 node.py 5001 127.0.0.1 5002     # node A
```

**Laptop + AWS:**

```bash
python3 node.py 5002 - -                # node B, on the VM
python3 node.py 5001 <VMs IP> 5002     # node A, on the laptop
```

Experimenting:

```bash
anna@Annas-MacBook-Air task1 % python3 node.py 5001 127.0.0.1 5002
> inc
> inc
> inc
> sync
```

```bash
anna@Annas-MacBook-Air task1 % python3 node.py 5002 - -
> print
3
```

Now we try to increment both nodes first, and only then sync them:

```bash
anna@Annas-MacBook-Air task1 % python3 node.py 5001 127.0.0.1 5002
> inc
> inc
> inc
> sync
> print
5
```

```bash
anna@Annas-MacBook-Air task1 % python3 node.py 5002 - -
> inc
> inc
> inc
> inc
> inc
> sync
> print
5
```

Both nodes agree on 5, but 8 increments happened.


So, synchronisation works, however: 

### 1.2 Convergence != we're good

If we do what's asked of us in Task 1.2:
- Initially, both counters are zero.
- A increments its counter once.
- At the same time, B increments its counter once.
- Both nodes exchange their counter values.

```bash
anna@Annas-MacBook-Air task1 % python3 node.py 5001 127.0.0.1 5002
> sync
> inc
> sync
> print
1
```

```bash
anna@Annas-MacBook-Air task1 % python3 node.py 5002 - -
> sync
> inc
> sync
> print
1
```

We do not get the value we expected (2).

The problem is **concurrency**: two events are concurrent if neither knew about the other when it happened (no matter if they happened at the exact same time or an hour apart). A increments its counter and doesn't notify B, so B still has 0. Then B increments too, still not knowing about A's increment. Both increments happened in secret. When they sync, each node only receives the number 1 and can't tell whether it's the other node's own increment or the same one it already counted. `max(1, 1)` assumes the second, so both nodes end up at 1 and one increment is silently lost.

If we do the same increments and syncs one after the other (A: `inc`, `sync` → B: `inc`, `sync`), we get 2, because B already knew about A's increment when it did its own.

In our case both nodes agreeing on 1 is wrong. So convergence only guarantees that the replicas end up the same, not that no information is lost on the way.

### 1.3 Lost, duplicated, wrong order

> What happens if a synchronisation message is lost?

UDP does not detect or resend lost packets, so a synchronisation message can simply disappear on its way. In that case the system finds itself in a temporarily inconsistent state: A already has the new value, but B still has the old one. This lasts until a command to synchronise is sent again and the message actually arrives. Because in our implementation every message carries the whole counter ("my counter is 3") and not just an increment ("+1"), the next synchronisation message that gets through brings B fully up to date, no matter how many messages were lost before. So, UDP doesn't protect, but the design of our messages does. In case a message only contained "+1", a lost message would mean a permanently lost increment.

However, if the lost message was the last one, there is a problem, because in our program synchronisation is manual. If nobody types `sync` again, the nodes stay different forever. If synchronisation happened automatically, for example every few seconds, a lost message would always be repaired by the next one and the nodes would eventually converge.

> What happens if the same message is received twice?

In this case nothing dramatic happens, once again because in our implementation it's the whole counter that travels and not the increment. B just compares the same value with `max` again, which gives the same result, no matter if the duplicate arrives 2 or 500 times. In case our messages contained "+1", every duplicate would be counted again and the counter would end up too high.

> What happens if an older message arrives after a newer one?

Our counter only ever goes up. So an older message always contains a value that's smaller than or equal to what B already has, and `max` simply throws it away. Example: A sends "1" and then "2", but B receives "2" first and "1" afterwards: max(0, 2) = 2, then max(2, 1) = 2. If B overwrote its counter with the received value instead, the late message would push it back from 2 to 1.

> Which situations cause problems for your implementation?

Only the lost message, and only if it was the last one. Duplicates and late messages are harmless thanks to `max` and the fact that the whole counter travels. 

The real problem of our implementation is concurrent increments, where an increment is lost even though every message arrives correctly.

### 1.4 How not to lose concurrent increments

In 1.2 we saw that `max` loses increments when A and B increment concurrently, because a single number doesn't tell the receiver *whose* increments it contains. To fix this, every node now keeps two counters instead of one: one for the increments performed by A and one for the increments performed by B (`node_conc.py`).

```python
counter_a = 0
counter_b = 0
lock = threading.Lock()
```

**Each node only ever increments its own slot**. A only changes `counter_a`, B only changes `counter_b`. So that a node knows which slot is its own, we pass its id as a fourth command-line argument:

**Locally:**

```bash
python3 node_conc.py 5002 - - B                 # node B
python3 node_conc.py 5001 127.0.0.1 5002 A      # node A
```

**Laptop + AWS:**

```bash
python3 node_conc.py 5002 - - B                 # node B, on the VM
python3 node_conc.py 5001 <VMs IP> 5002 A      # node A, on the laptop
```

```python
my_id = sys.argv[4]

if my_id not in ("A", "B"):
    print("fourth argument must be A or B")
    sys.exit(1)
```

The check makes the program stop right away if we start it with a wrong id, instead of running a node that silently ignores `inc`.

We have one `inc` command, and the node decides which slot to increment based on its id (with lock, since the listener thread also changes the counters):

```python
def increment():
    global counter_a, counter_b
    with lock:
        if my_id == "A":
            counter_a += 1
        elif my_id == "B":
            counter_b += 1
```

When synchronising, we send **both** counters as one string, e.g. `"1,0"`, and not the total. If we only sent the total, the receiver would again get one number without knowing whose increments are in it, which is exactly the problem from 1.2.

```python
def send_state(ask_reply=False):
    with lock:
        msg = f"{counter_a},{counter_b}"
        addr = peer_addr
    if ask_reply:
        msg += ",?"
    sock.sendto(msg.encode(), addr)
```

The `,?` is a "please answer me flag" on the message used for the bench in Task 3 to measure how long the sync takes 

The receiver splits the string back into two numbers and merges them **slot by slot with max**:

```python
def listen():
    global counter_a, counter_b, peer_addr
    while True:
        data, sender = sock.recvfrom(1024)
        parts = data.decode().split(",")
        a = int(parts[0])
        b = int(parts[1])
        with lock:
            counter_a = max(counter_a, a)
            counter_b = max(counter_b, b)
            peer_addr = sender
        if len(parts) == 3 and parts[2] == "?":
            send_state()
        reply_received.set()
```

`Max` properly works now because each slot is now only one node's own history. `counter_a` only ever counts A's increments, so the bigger value really does include the smaller one, and nothing gets mixed up. 

We could not merge by adding the slots instead: if B's `[0, 1]` arrived twice, A would get `[1, 1] + [0, 1] = [1, 2]`, so 3 instead of 2, and every duplicate would be counted again.

The value of the counter is the **sum** of both slots, because that's the total number of increments:

```python
elif cmd[0] == "print":
    with lock:
        print(f"{counter_a + counter_b}   (A: {counter_a}, B: {counter_b})")
```

So **max** is used to check which version of A's or B's is fitting, and **sum** is for reading how many increments happened altogether:.

Testing the scenario from 1.2 again:

| Step | A `[a, b]` → value | B `[a, b]` → value |
| :--- | :--- | :--- |
| start | `[0, 0]` → 0 | `[0, 0]` → 0 |
| A: `inc` | `[1, 0]` → 1 | `[0, 0]` → 0 |
| B: `inc` | `[1, 0]` → 1 | `[0, 1]` → 1 |
| A: `sync` | `[1, 0]` → 1 | `[1, 1]` → **2** |
| B: `sync` | `[1, 1]` → **2** | `[1, 1]` → **2** |
| A: `sync` again (duplicate) | `[1, 1]` → 2 | `[1, 1]` → 2 |


```bash
anna@Annas-MacBook-Air task1 % python3 node_conc.py 5001 127.0.0.1 5002 A
> inc
> sync
> sync
> print
2  (A: 1, B: 1)
```

```bash
anna@Annas-MacBook-Air task1 % python3 node_conc.py 5002 - - B           
> inc
> sync
> print
2  (A: 1, B: 1)
```



Both nodes end up with 2. So this time they don't only agree, they also have the **correct** value, and both increments survive even though they happened concurrently.

This kind of counter is called a **G-Counter** (grow-only counter). It is one of the simplest **CRDTs** (Conflict-free Replicated Data Types): data types whose replicas can be updated independently and always converge to the same correct value when they merge, no matter in which order or how often the messages arrive.

---

## Task 2 - Single-copy Counter

In this task we look at single-copy state. The nodes do not keep their own copies anymore. Instead there is **only one** counter, stored in a shared data store, and both nodes read and update that one copy. The nodes also never talk to each other directly, only to the store.


### What is Redis?

Redis is a key-value store that keeps its data in memory, which makes it very fast. It's like a big Python dictionary that lives in its own process and that several programs can access over the network. We store a value under a key (`SET counter 5`) and read it again (`GET counter`). Redis listens on port 6379 by default.

Important for this task is the fact that Redis executes commands one after another, using a single main thread for this. Even if many clients send commands at the same time, Redis never runs two commands simultaneously. Every command is executed completely before the next one starts.

### Set up

Locally we run Redis in a Docker container; on the VM it is started by Terraform's `user_data` (see Set up at the top):

```bash
docker run -d --name redis -p 6379:6379 redis
docker exec -it redis redis-cli ping    # if it answers PONG, Redis is alive :)
```

We talk to Redis from Python with the `redis` library, installed in a virtual environment (`pip install redis`). All scripts take the Redis host and the number of increments as arguments, so the same code runs on the laptop (host = the VM's IP) and on the VM (host = `localhost`):

```python
host = sys.argv[1]
n = int(sys.argv[2]) # for the number of increments to do

r = redis.Redis(host=host, port=6379)
r.ping()
```

`reset.py <host>` sets the counter back to 0 before each experiment. To run two nodes at the same time from one terminal, we start the script twice: `&` starts each program in the background, so both start practically at the same moment, and `wait` waits until both are done.

### 2.1 Safe increment

For a safe increment we use the Redis command `INCR` (`safe.py`):

```python
for i in range(n):
    r.incr("counter")
```

`INCR` reads the value, adds 1 and writes it back, but all of this happens inside Redis, as one single step. The value never travels to Python and back. The operation is atomic.

We tried it locally: 

```bash
(dissy) anna@Annas-MacBook-Air src % python3 safe.py & python3 safe.py & wait
1997
2000
```

Each script prints the counter when it finishes. The first one prints 1997 because the other one still had 3 increments to go. The final value is **2000**, so no increment was lost. 


And on VM & local machine it's the same: 

```bash
[ec2-user@ip-172-31-83-62 task2]$ python3 safe.py localhost 100
128
total time: 13.312 ms
per_increment: 0.133 ms
```
The VM finished earlier, at that moment the counter was 128 so the laptop had done 28 of its increments .

```bash
(dissy) anna@Annas-MacBook-Air task2 % python3 safe.py 100.26.102.233 100
200
total time: 23457.659 ms
per_increment: 234.577 ms
```

The same holds on AWS: laptop and VM incrementing concurrently (100 each) end at **200**. Laptop takes long because we're travelling to Virginia

> Why does this work without the nodes exchanging synchronization messages?

In Task 1, every node had its own copy of the counter, so the nodes had to send messages to tell each other about their increments and merge the copies. Now there is only one copy, and it lives in Redis. Both nodes send their increments to the same place, so there is nothing to merge and nobody has to be told about anything: the next `GET` from any node simply sees the current value. The synchronization still happens, but it happens **inside the store**: Redis executes the `INCR` commands one after another, so two increments can never get in each other's way. The store is the single point where everything is coordinated.

### 2.2 Concurrent increments

> What could go wrong if both nodes read the current value, increment it locally, and then write the result back?

To show this we also wrote a naive version that increments with `GET` and `SET` (`naive.py`):

```python
for i in range(n):
    value = int(r.get("counter"))
    value = value + 1
    r.set("counter", value)
```

Here, the increment is done in three steps: we read the value from Redis, add 1 in Python and write it back. When only one node runs the program, everything is fine (+1000, nothing lost). When we run both nodes at the same time, we get a problem:

```bash
(dissy) anna@Annas-MacBook-Air src % python3 naive.py & python3 naive.py & wait
1035
1036
```

2000 increments happened, but the counter is only at 1036, so almost half of them were lost. What happened:

| Step | A | B | Redis |
| :--- | :--- | :--- | :--- |
| 1 | `GET` → 5 | | 5 |
| 2 | | `GET` → 5 | 5 |
| 3 | 5 + 1 = 6 | | 5 |
| 4 | | 5 + 1 = 6 | 5 |
| 5 | `SET 6` | | 6 |
| 6 | | `SET 6` | **6** (should be 7) |

B reads the value somewhere between A's read and A's write → both nodes calculate the same new value → one increment gets overwritten. This is called the **lost update problem**. It doesn't need to happen at the exact same moment: it's enough that the other node reads in the gap between our `GET` and our `SET`. `GET` and `SET` are two separate requests, so there is always a gap, and the result varies from run to run because it depends on the timing:

| Setup | Expected | Final counter | Lost |
| :--- | :--- | :--- | :--- |
| laptop, local Redis, 2 × 1000 (run 1) | 2000 | 1036 | 964 (48%) |
| laptop, local Redis, 2 × 1000 (run 2) | 2000 | 1038 | 962 (48%) |
| laptop, local Redis, 2 × 1000 (run 3) | 2000 | 1037 | 963 (48%) |
| laptop, local Redis, 2 × 1000 (run 4) | 2000 | 1054 | 946 (47%) |
| laptop (20) + VM (1000), VM's Redis | 1020 | 497 | 523 (51%) |

Across the internet the problem gets even more dramatic. The laptop needs ~300 ms per naive increment (two round trips to Virginia), so the gap between its `GET` and its `SET` is ~150 ms. The VM does a naive increment in 0.27 ms, so it can fit hundreds of increments into that one gap:

```bash
[ec2-user@ip-172-31-83-62 task2]$ python3 naive.py localhost 1000
837
```

```bash
(dissy) anna@Annas-MacBook-Air task2 % python3 naive.py 44.203.174.206 20
497
```

The VM finished first and saw 837, but the final counter is only 497, so the counter went **down**. A `SET` doesn't add anything, it overwrites the value with whatever the node calculated:

| | Laptop | VM | Redis |
| :--- | :--- | :--- | :--- |
| 1 | `GET` → ~476 | | ~476 |
| 2 | calculates 477, `SET 477` on its way (~150 ms) | | ~476 |
| 3 | | runs its whole loop, finishes, prints 837 | 837 |
| 4 | `SET 477` arrives | | **477** |
| 5 | its remaining increments, prints 497 | | 497 |

A single stale write from the slow node wiped out ~360 increments of the fast node at once. (The exact values in steps 1–2 are reconstructed from the two printed numbers.)


> How does the data store prevent this problem?

With `INCR` there is no gap: the read, the +1 and the write all happen inside Redis, in one command. And since Redis executes commands one after another, the `INCR` from A and the `INCR` from B can never be mixed up. One is always completely finished before the other one starts, so instead of two nodes reading the same old value, Redis applies the increments in a row: 5 → 6 → 7. Also, the node never sends a *value*, only "add 1", so a slow node can never push the counter back like in the AWS experiment above.

| Version | Expected | Result | Lost |
| :--- | :--- | :--- | :--- |
| `naive.py` (`GET` → +1 → `SET`), local | 2000 | 1036 | 964 |
| `naive.py`, laptop + VM | 1020 | 497 | 523 |
| `safe.py` (`INCR`), local | 2000 | 2000 | 0 |
| `safe.py`, laptop + VM | 200 | 200 | 0 |

> What happens when one node attempts to update the counter while another update is in progress?

Redis executes commands one at a time. This makes each `INCR` atomic, and it also means a second `INCR` simply waits until the first one is finished. But one `INCR` takes only about a microsecond inside Redis, so this wait is so short that for the node the update **completes practically immediately**, and it never fails or has to be retried.

Our measurements support this (details in 3.1): when the laptop and the VM incremented at the same time, neither got slower (laptop 157 → 148 ms, VM 0.135 → 0.142 ms per increment), and both nodes' increments simply ended up in the counter in the order they arrived. While the laptop had done only 28 of its increments, the VM managed all 100 (in 2.1).


---

## Task 3 - Comparison

### 3.1 Measurements

Timing is done inside the programs with `time.perf_counter()`, so that only the operations themselves are measured, not Python startup or connecting to Redis.

**Replicated counter.** We benchmark the improved counter (`node_conc.py`). 

The `bench 100` command does 100 increments, each followed by a sync, and measures both parts separately. With UDP, `sendto()` returns immediately (the packet has left, but nothing tells us it arrived), so timing it alone would measure nothing useful. Instead, the node sends its state with a `?` ("please answer"), the other node merges it and sends its own state back, and we stop the timer when that answer arrives. At that point **both replicas have each other's state**, which is the time to synchronize both replicas.

```python
for i in range(n):
    start = time.perf_counter()
    increment()
    local_time += time.perf_counter() - start

    reply_received.clear()
    start = time.perf_counter()
    send_state(ask_reply=True)
    if not reply_received.wait(timeout=2):   # UDP: request or reply may be lost
        lost += 1
    sync_time += time.perf_counter() - start
```

| Setup | Bench run on | Local update | Sync round trip | Lost |
| :--- | :--- | :--- | :--- | :--- |
| localhost | A | 0.0010 ms | 0.242 ms | 0 |
| localhost | B | 0.0014 ms | 0.235 ms | 0 |
| laptop ↔ AWS | A (laptop) | 0.0177 ms | 144.1 ms | 0 |
| laptop ↔ AWS | B (VM) | 0.0031 ms | 144.8 ms | 0 |

Updating the local state is basically free: it is just changing a variable in memory, so it takes microseconds. Synchronizing costs one network round trip: ~0.24 ms on localhost and ~144 ms between Innsbruck and Virginia, because every sync crosses the Atlantic twice. 


**Single-copy counter.** We measured 100 increments with `safe.py` and, for comparison, `naive.py`:

| Node runs on | Redis on | `INCR` | naive (`GET` + `SET`) |
| :--- | :--- | :--- | :--- |
| laptop | VM | 157.1 ms | 304–332 ms |
| VM | VM (same machine) | 0.135 ms | 0.271 ms |

Every single update costs one round trip to the store: send the command, wait for Redis's answer. Across the Atlantic that is ~157 ms, almost the same as a sync round trip in Task 1 (the extra ~13 ms is TCP and Redis's reply handling on top of the bare UDP packet). The naive version needs two round trips (`GET` and `SET`), so it is also about twice as slow, which means `INCR` is not only correct but also faster. Even when Redis runs on the same machine, an `INCR` (0.135 ms) is ~40× slower than a local update in Task 1, because it still goes through the network stack (TCP through Docker's port mapping) into the Redis process and back.

**Concurrent updates (`INCR`):**

| Setup | Alone | Concurrent | Final counter |
| :--- | :--- | :--- | :--- |
| 2 nodes on the VM (1 vCPU), 100 each | 0.137 ms | 0.301 / 0.434 ms | 200 ✓ |
| 2 nodes on the laptop, local Redis, 1000 each | 0.287–0.489 ms | 0.234 / 0.234 ms | 2000 ✓ |
| laptop + VM, VM's Redis, 100 each | 157 ms / 0.135 ms | 148 ms / 0.142 ms | 200 ✓ |

(On the laptop we used 1000 increments, because with 100 a run is over in ~30 ms, which is shorter than starting the second Python process, so the two runs would not actually overlap.)

On the VM, concurrent updates were 2–3× slower. Since Redis executes each `INCR` in microseconds, waiting in Redis's queue can't explain this. More likely, the two nodes and Redis compete for the VM's single vCPU (`t2.micro`). To check this, we ran the same test on the laptop (many cores): there, concurrency caused no slowdown at all (the variation between single runs was bigger than any effect of concurrency). And with the nodes on different machines (laptop + VM), neither got slower. So with `INCR`, concurrent updates don't slow each other down; the slowdown on the VM came from the shared CPU.

Side note: local Redis on the laptop (~0.3 ms) is slower than Redis on the VM (0.135 ms), even though the laptop is the faster computer. On a Mac, Docker runs inside a hidden Linux VM, so `localhost:6379` takes an extra hop into that VM.

**Comparison.** In the replicated approach, an increment is local and costs microseconds; only synchronization costs a round trip, and because every message carries the whole state, one sync can cover any number of increments. In the single-copy approach, *every* increment costs a round trip to the store. For 100 increments on AWS this means one sync of ~145 ms (replicated, if we sync once at the end) versus ~15.7 s (single-copy).

### 3.2 Questions

> 1. Where does synchronization happen in each implementation?

In the **replicated** implementation, synchronization happens in the nodes themselves: they exchange their state by messages, and each node merges what it receives with `max` (per slot) in its listener thread. (Inside each node, the lock additionally synchronizes the two threads, but that's not the distributed part.) In the **single-copy** implementation, synchronization happens in the data store: Redis executes the commands one after another, so the `INCR`s of both nodes are applied in a row. The nodes themselves never coordinate and don't even know about each other.

> 2. What happens if the two nodes cannot communicate temporarily?

**Replicated:** both nodes keep working. Each node can still increment its own slot and read its value, but the replicas drift apart, so each node only sees its own increments (plus what it knew from the last sync). Once communication resumes and the nodes sync, both histories get merged with `max` per slot, and no increment is lost. 

**Single-copy:** the nodes never talk to each other anyway, so this doesn't affect them at all. What matters is whether each node can reach the store (see question 3).

> 3. What happens if the shared data store is unavailable?

**Replicated:** there is no shared store, so this case doesn't exist. Every node holds a full copy and can always work locally.

**Single-copy:** nothing works anymore. No node can increment or even read the counter, because the only copy is in the store; the `redis` library raises a connection error. The store is a single point of failure. The same happens to a node that can't reach the store, e.g. our laptop if its internet connection drops: it can't do anything, even though the store itself is fine.

> 4. Which approach would you choose if increments must be immediately visible to both nodes? Why?

The **single-copy** approach. There is only one copy, so as soon as Redis has executed an `INCR`, the next read from any node sees the new value. In the replicated approach, an increment is only visible to the other node after the next sync arrives, so the nodes can see different values in the meantime (eventual consistency).

The price is what we measured in 3.1 and discussed in question 3: every update costs a round trip to the store (~157 ms from the laptop to Virginia instead of microseconds), and if the store is unreachable, no node can work. The replicated approach makes the opposite trade: always available and fast, but only eventually consistent. There is a trade-off between consistency (single-copy) and availability (replicated).
