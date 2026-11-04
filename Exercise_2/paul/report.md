# EX0X Report: [Shared State]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  

---

## Infrastructure (Terraform)

All EC2 instances, security groups, and deployment steps are defined in Terraform and split across multiple `.tf` files in the `src/` directory. Terraform loads all of them automatically. The configuration uses a declarative approach: describe the desired state, and Terraform figures out what to create, modify, or destroy.

#### `variable` block
Declares an input parameter. Terraform uses the `default` value unless overridden at apply time via `-var`.
```
variable "counter_script" {
  description = "Which script to run: counter_1_1.py or counter_1_4.py"
  default     = "counter_1_1.py"
}
```

#### `data` block
Reads existing information from the cloud provider without creating anything. Here it looks up the latest Amazon Linux 2023 AMI ID dynamically so the configuration does not hard-code an image ID that may become outdated.
```
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

#### `resource` block
The core of Terraform — declares actual infrastructure to create. Resource types used across both tasks:

- `aws_security_group` — defines firewall rules per task (SSH, UDP 5001–5002 for task 1, TCP 6379 restricted to counter nodes for task 2).
- `aws_instance` — creates EC2 virtual machines. `user_data` is a shell script that runs once on first boot to install dependencies.
- `null_resource` — used to run local or remote logic at apply time

#### `provisioner` block
Runs imperative steps inside a `null_resource`. Two types are used:

- **`file`** — copies a local file to the remote instance over SSH.
- **`remote-exec`** — runs shell commands on the remote instance over SSH. Used to wait for boot (`cloud-init status --wait`), install packages, and deploy scripts.

Each provisioner requires a `connection` block specifying host, user, and SSH key.

#### Why `null_resource` instead of `user_data`

Node A's script needs node B's private IP, and node B's script needs node A's private IP. `user_data` is fixed at instance creation time — both IPs are unknown simultaneously, creating a circular dependency. `null_resource` runs *after* Terraform has created both instances and resolved their IPs, breaking the cycle. Nodes communicate via private IPs within the same VPC.

#### `output` block
Prints values after `terraform apply` completes. I use it to print IPs of instances and pre-arranged commands for ssh-connection or the benchmark execution

#### How to run

```bash
terraform init                                        # once
terraform apply                                       # task 1: spin up nodes, deploy scripts
terraform apply -var="counter_script=counter_1_4.py" # switch to 1.4 script
terraform destroy                                     # tear down everything
```

After apply, use the printed `ssh_node_a` / `ssh_node_b` to connect. Task 1 logs: `tail -f ~/counter.log`.

---

## Task 1 - [Replicated Counter]

### 1.1

My python program implements a class Node which keeps track of its own counter, port, peer_ip peer_port and establishes a UDP-Socket, among other things:
```
def __init__(self, node_name: str, local_port: int, peer_ip: int, peer_port: int):
        self.node_name = node_name
        self.local_port = local_port
        self.peer_ip = peer_ip
        self.peer_port = peer_port
        self.counter = 0
        self.lock = threading.Lock()
        self.running = True

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", self.local_port))
```

It can increment its own counter:
```
def increment(self):
        with self.lock:
            self.counter += 1
```

It has a thread listening on its port via this function, where we can also the the required protocol of updating its own counter using `counter = max(local_counter, received_counter)`
```
def listen(self):
        self.sock.settimeout(0.5)
        while self.running:
            try:
                data, _ = self.sock.recvfrom(1024)
                received_val = int(data.decode("utf-8"))
                with self.lock:
                    old_val = self.counter
                    self.counter = max(self.counter, received_val)
                    print(f"[{self.node_name}] RECV {received_val}, updated: {old_val} -> {self.counter}")
            except socket.timeout:
                continue
```

It also has a sender thread which sends updates to its peer node. It runs the function increment 100 times while sending and receiving updates.
In my current implemention it runs increment() every 0.1 seconds and sends an update every 0.05 seconds in order to demonstrate the flaws of this protocol.

With this configuration both counters agree on the value of 152 after increments stopped and synchronization keeps running. As we can see 48 increments were lost somewhere along the way.



### 1.2
| Action | Node | Counter |
| :--- | :--- | :--- |
| initial state | A/B | 0/0 |
| A increments once | A/B | 1/0 |
| at the same time, B increments once | A/B | 1/1 |
| after syncing | A/B | 1/0 |

As we can see in the figure above, even though combined the counters have been incremented twice, both nodes agree that the value is 1.
This happens because B increments before even knowing that A has already incremented, when sharing their state they agree on 1 which is wrong.

### 1.3
Consider what happens if:
#### A synchronization message is lost:
This doesn't change the fact that the counters will be eventually consistent. The local counter of the sender is not lost and the next synchronization message will get both counters to the same state. However the value might be wrong afterwards. Imagine Node A increments to 5 and sends the message to B who is at 0. This message is lost, B increments to 3 and only then receives the next synchronization message of A containing 5. B will update its counter to 5 and the counters are consistent. However the correct value would be 8.

#### The same message is received twice:
Receiving the same message twice itself is not a problem. When B receives a message from A it will update its own counter to:
counter = max(local_counter, received_counter)
This will not change when the same message is received twice. Lets see what happens when B increments between receiving this message twice:
B's counter is set to the max of its current state and the received value. It then increments by one and is again set to the max of its own value and the received value.
Either: The first received value was higher then the original counter, then the counters current state is `received_value + 1` and `max(received_value+1, received_value) = received_value + 1` which is correct.
Or: the counter was higher than the first received value, then the current state is `local_counter + 1`
and `max(local_counter + 1, received_value) = local_counter + 1` because the counter was already higher than the received value, this is also correct.

#### An older message arrives after a new one:
Since the counter can never decrease, this is also not an issue concerning consistency. Of course with all three scenarios it is always possible that the counters don't reflect the actual amount of increments that happened, but they will be consistent.

### 1.4

We modify our node class to keep track of the peers counter as well:

```
def __init__(self, node_name: str, local_port: int, peer_port: int):
        self.node_name = node_name
        self.local_port = local_port
        self.peer_port = peer_port
        self.counter = 0
        self.counter_peer = 0
        self.lock = threading.Lock()
        self.running = True

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", self.local_port))
```

In turn we update the listen function from updating its own counter `self.counter = max(self.counter, received_val` to updating the peer counter `self.counter_peer = max(self.counter_peer, received_val)`

We could also add another variable equalling the sum of both the own and peer counter, which will always reflect the true amount of increments.

After increments stop both of the instances running the program will print `[A] RECV 100 | own counter: 100 | peer counter: 100` and `[B] RECV 100 | own counter: 100 | peer counter: 100` forever, giving the correct combined amount of 200 increments.

---

## Task 2 - [Single-copy Counter]

Instead of each node maintaining its own replica, both nodes share a single counter stored in **Redis** — an in-memory key-value store. I chose Redis because its `INCR` command is natively atomic and Redis processes commands single threaded, making it easy to implement a race-free counter without any application-level locking or synchronization messages.

### Infrastructure

A third EC2 instance (`exc02-redis`) is added to the existing Terraform setup via `task2.tf`. Its `user_data` installs Redis, reconfigures it to listen on `0.0.0.0` instead of localhost, and starts the service. A separate security group (`redis_sg`) restricts port 6379 to only accept connections from instances in the counter nodes' security group — not reachable from the public internet.

Both node A and node B connect to Redis using its **private IP** (same VPC).

Provisioning is controlled by the `enable_task2` variable:

```bash
terraform apply -var="enable_task2=true"   # add Redis node, deploy counter_2.py
terraform apply -var="enable_task2=false"  # tear down Redis node only
```

After apply, the `run_task2_node_a` and `run_task2_node_b` outputs print t
he exact commands to paste into each SSH session. Start node A first — it
resets the counter and barrier keys, then waits. Start node B in the secon
d terminal; once B signals ready, both begin incrementing simultaneously.

Without a delay, 100 increments complete in ~30 ms, so one node finishes b
efore you can switch terminals. Use `--delay 0.05` to slow it down and observe interleaving:

```
# node A terminal
python3 -u ~/counter_2.py --id A --redis-ip <redis_ip> --delay 0.05

# node B terminal
python3 -u ~/counter_2.py --id B --redis-ip <redis_ip> --delay 0.05

tail -f ~/counter2.log   # watch output
```

### 2.1

The increment operation uses Redis's built-in `INCR` command:

```python
r = redis.Redis(host=args.redis_ip, port=6379, decode_responses=True)

for i in range(args.n):
    new_val = r.incr("counter")
    print(f"[{args.id}] increment {i + 1}/{args.n} -> counter = {new_val}")
```

`INCR` reads the current value, increments it by one, and writes it back — all as a single atomic server-side operation. Both nodes run 100 increments each concurrently. The final counter value is consistently **200**, which is the correct total.

No synchronization messages between the application nodes are needed because Redis itself acts as the single source of truth. Any node reading the counter after all increments are complete will see the correct value immediately.

### 2.2

Consider what happens if both nodes use a naive read-modify-write approach instead of `INCR`:

```python
val = int(r.get("counter"))   # node A reads 42, node B also reads 42
val += 1                       # node A computes 43, node B computes 43
r.set("counter", val)          # node A writes 43, node B writes 43 — one increment lost
```

Both nodes read the same value before either has written back. Both compute the same result and write it. One of the two increments is silently lost. This is a classic race condition.

Redis prevents this with `INCR` because the entire operation executes atomically inside the Redis server. If both nodes send `INCR` at exactly the same moment, Redis queues the commands and executes them one after the other. The second node's `INCR` does not read a stale value — it reads the already-updated result from the first. The second update neither waits nor fails; it completes immediately with the correct incremented value.

This means consistency is enforced by the data store, not by the application. The application nodes need no coordination logic with each other.

In practice, when both nodes ran concurrently, one node observed counter values 1–100 and the other observed 101–200. The final value was 200, which is correct. The apparent batching happens because Redis is single-threaded: whichever node has lower latency to Redis dominates the command queue and completes all its increments first. The slower node's commands are serialized after. The total is always exact regardless of ordering.

By intentionally slowing down the speed of the INCS, we can observe that the 100 INCS of node A and the 100 INCS of node B intertwine.

---

## Task 3 - Comparison

### 3.1 — Timing measurements

Benchmarks were run using `benchmark.sh`, a shell script that SSHs into both EC2 nodes simultaneously and runs the counter scripts with `--delay 0` (no artificial sleep) to measure raw operation latency. The benchmark command with correct IPs is printed by `terraform output benchmark`.

```bash
./benchmark.sh <node_a_pub> <node_a_priv> <node_b_pub> <node_b_priv> <redis_priv>
```

Both nodes are `t2.micro` instances in `us-east-1`. The Redis instance is in the same VPC.

#### Replicated counter (Task 1)

| Metric | Node A | Node B |
| :--- | :--- | :--- |
| 100 local increments | 0.001 s | 0.001 s |
| Local update latency | 0.01 ms/op | 0.01 ms/op |
| Sync convergence time | 200 ms | 200 ms |

The local increment (`self.counter += 1` under a threading lock) is a pure in-memory operation and takes ~0.01 ms regardless of network conditions. The sync convergence time of 200 ms reflects the measurement method: the script waits for 4 consecutive sync intervals (4 × 50 ms) without a counter change before declaring convergence. The actual network round-trip between nodes within the same AWS region is sub-millisecond, so the true convergence latency is closer to one sync interval (~50 ms) plus UDP RTT.

#### Single-copy counter (Task 2)

| Metric | Node A | Node B |
| :--- | :--- | :--- |
| 100 increments | 0.030 s | 0.030 s |
| Redis INCR latency | 0.30 ms/op | 0.30 ms/op |

Each `r.incr()` call is a full network round-trip to the Redis instance. Both nodes complete 100 increments in 30 ms at 0.30 ms/op — symmetric because both instances are in the same AWS availability zone as the Redis node, giving equal latency.

Compared to the replicated counter, a single Redis INCR is ~30× slower than a local memory increment (0.30 ms vs 0.01 ms). However, the single-copy approach makes the result immediately visible to all nodes without any additional synchronization step.

### 3.2

**1. Where does synchronization happen in each implementation?**

In the replicated counter, synchronization happens in the application layer: each node periodically sends its counter value to the peer over UDP, and the receiving node merges with `max(local, received)`. There is no central authority — nodes synchronize directly with each other.

In the single-copy counter, synchronization happens inside Redis. The data store serializes all concurrent `INCR` commands server-side. The application nodes never communicate with each other at all; they only talk to Redis.

**2. What happens if the two nodes cannot communicate temporarily?**

Replicated counter: both nodes continue to increment their local counters independently. When communication resumes, the next sync message brings them back into agreement (eventual consistency). With the naive 1.1 protocol increments may be lost; with the GCounter approach from 1.4 the total is correct once both sides sync.

Single-copy counter: a communication outage between the two counter nodes has no effect — they never talk to each other. Both continue hitting Redis normally as long as Redis is reachable.

**3. What happens if the shared data store is unavailable?**

Replicated counter: not applicable — there is no shared data store. The system keeps running regardless.

Single-copy counter: both nodes fail completely. Every `r.incr()` call raises a connection error. No increments can be recorded until Redis recovers. There is no local state to fall back on.

**4. Which approach would you choose if increments must be immediately visible to both nodes? Why?**

The single-copy approach. With a replicated counter, a newly incremented value only becomes visible to the peer after the next synchronization message arrives — there is always a delay of at least one sync interval (~50 ms in this setup). With Redis, any node that reads the counter immediately after an `INCR` sees the updated value, since there is only one authoritative copy. Visibility is instant by design.

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
