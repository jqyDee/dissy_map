# EX02 Report: [Shared State]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Task 1 - [Replicated counter]

### Infrastructure

`task1.tf` provisions one security group (SSH and port 8000) and two t2.micro
EC2 instances (`A`, `B`) running Amazon Linux 2023. Once the instances are up, a
`terraform_data` resource connects to each one via SSH (`labsuser.pem`), waits
for `user_data` to finish, and uploads `app-task-1/` to the home directory.
Changing any file in `app-task-1/` reuploads the code on the next `apply`,
without recreating the instances.

```bash
terraform init
terraform apply -var task_1=true     # provision VMs and upload code
terraform destroy -var task_1=true   # tear everything down
```

### Task 1.1

Use terraform to provision 2 EC2 instances and directly transfer the application
onto each machine. Both machines run the exact same application.

The application (`counter.py`) increments its local counter at random for 10
seconds and then stops. In the background, one thread sends the current counter
to the peer via UDP every 0.5 seconds, and another thread merges every received
value into the local counter:

```python
def receive():
    global counter
    while True:
        data, _ = sock.recvfrom(64)
        with lock:
            counter = max(counter, int(data))
```

You will now have as terraform output 2 public IP addresses to connect/reach
each machine.

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

task_1 = {
  "A" = {
    "private" = "172.31.34.114"
    "public" = "34.207.135.30"
  }
  "B" = {
    "private" = "172.31.36.51"
    "public" = "54.145.187.166"
  }
}
```

To run the application connect to each of the 2 instances respectively and start
the application. Try to start the application quick after another.

```bash
# terminal 1
ssh -i ~/.ssh/labsuser.pem ec2-user@<A public>
cd app-task-1 && NODE_ID=A PEER=<B private> python3 counter.py
# terminal 2
ssh -i ~/.ssh/labsuser.pem ec2-user@<B public>
cd app-task-1 && NODE_ID=B PEER=<A private> python3 counter.py
```

> Note: To find the private IPs of the nodes in our automatically created VPC,
  use the ip shown after that `@` in the shell prompts (e.g.
  `[ec2-user@ip-172-31-47-197 app-task-1]$`) or the ones output by `terraform
  apply`.

While incrementing, the two counters differ. Only after both programs have
`stopped` incrementing do both counters hold the same value (which is not
necessarily the correct one, see Task 1.2):

**Output Node A:**
```
[ec2-user@ip-172-31-47-197 app-task-1]$ NODE_ID=A PEER=172.31.42.121 python3 counter.py
[A;2026-10-26T21:40:53.554] incrementing counter=  0 own_increments=0
[A;2026-10-26T21:40:54.555] incrementing counter=  3 own_increments=1
[A;2026-10-26T21:40:55.556] incrementing counter=  5 own_increments=2
[A;2026-10-26T21:40:56.557] incrementing counter=  7 own_increments=3
[A;2026-10-26T21:40:57.558] incrementing counter=  7 own_increments=3
[A;2026-10-26T21:40:58.559] incrementing counter=  8 own_increments=3
[A;2026-10-26T21:40:59.561] incrementing counter=  9 own_increments=3
[A;2026-10-26T21:41:00.562] incrementing counter= 10 own_increments=3
[A;2026-10-26T21:41:01.563] incrementing counter= 11 own_increments=3
[A;2026-10-26T21:41:02.564] incrementing counter= 13 own_increments=4
[A;2026-10-26T21:41:03.565] stopped      counter= 13 own_increments=4
[A;2026-10-26T21:41:04.566] stopped      counter= 13 own_increments=4
[A;2026-10-26T21:41:05.567] stopped      counter= 13 own_increments=4
^C
```

**Output Node B:**
```
[ec2-user@ip-172-31-42-121 app-task-1]$ NODE_ID=B PEER=172.31.47.197 python3 counter.py
[B;2026-10-26T21:40:53.072] incrementing counter=  1 own_increments=1
[B;2026-10-26T21:40:54.073] incrementing counter=  2 own_increments=2
[B;2026-10-26T21:40:55.074] incrementing counter=  4 own_increments=3
[B;2026-10-26T21:40:56.075] incrementing counter=  6 own_increments=4
[B;2026-10-26T21:40:57.076] incrementing counter=  7 own_increments=4
[B;2026-10-26T21:40:58.077] incrementing counter=  8 own_increments=5
[B;2026-10-26T21:40:59.078] incrementing counter=  9 own_increments=6
[B;2026-10-26T21:41:00.079] incrementing counter= 10 own_increments=7
[B;2026-10-26T21:41:01.080] incrementing counter= 11 own_increments=8
[B;2026-10-26T21:41:02.082] incrementing counter= 12 own_increments=9
[B;2026-10-26T21:41:03.083] stopped      counter= 13 own_increments=9
[B;2026-10-26T21:41:04.084] stopped      counter= 13 own_increments=9
[B;2026-10-26T21:41:05.085] stopped      counter= 13 own_increments=9
^C
```

As expected, both counters eventually reach the same value (13) after both
nodes have stopped incrementing. Before that, the counters can differ, e.g. at
`21:40:54` node A shows 3 while node B shows 2, because the latest value of the
other node has not been received yet.

### Task 1.2

Consider the following situation:
* Initially, both counters are zero.
* A increments its counter once.
* At the same time, B increments its counter once.
* Both nodes exchange their counter values.

As both nodes increment at the same time, each node holds the value 1 before
the exchange. Node A receives the value 1 from node B, and node B receives the
value 1 from node A. Both compute `max(1, 1) = 1`, so nothing is updated. The
resulting counter value is **1** on both nodes, but it should be **2** (one
increment by A plus one increment by B).

Both nodes DO agree on the counter value, but the value is wrong. The `max`
merge treats the received value as a newer version of the same number, not as
separate increments made by another node. Concurrent increments therefore
overwrite each other instead of adding up. Agreement only means the replicas are
consistent, not that the value is correct. The first experiment in Task 1.4
shows this on the real system.

### Task 1.3

Each node periodically sends its full counter value (not single increments) via
UDP, and the receiver merges it with `max`:
* Lost message: Not permanent. The next periodic send carries the current value
  again, so convergence is only delayed. However, while increments are still
  happening, a node works with a stale value for longer, so concurrent
  increments (see 1.2) become more likely and more increments get lost.
* Duplicate message: No problem. `max` is idempotent: `max(c, x) = max(max(c,
  x), x)`.
* Older message after a newer one: No problem. The counter never decreases, so
  an old (smaller or equal) value is ignored: `max(local, old) = local`.

Only message loss causes a problem in our implementation, and only indirectly,
by making the lost-increment problem from Task 1.2 worse. Sending the full state
instead of increments ("+1") makes duplicates and reordering harmless.

### Task 1.4

To show the problem of our program from Task 1.1, let's start sending the state
only after both nodes have stopped incrementing. This is set through the
environment variable `SYNC_DELAY`, which delays the first send:

```python
def send():
    time.sleep(SYNC_DELAY)
    while True:
        ...
```

With `SYNC_DELAY=10` (equal to the 10 seconds of incrementing), no message is
sent while the nodes increment, so all increments happen concurrently. Running
our unsafe counter like this shows the problem:

**Output Node A:**
```
[ec2-user@ip-172-31-47-197 app-task-1]$ NODE_ID=A PEER=172.31.42.121 SYNC_DELAY=10 python3 counter.py
[A;2026-10-26T22:14:34.788] incrementing counter=  0 own_increments=0
[A;2026-10-26T22:14:35.789] incrementing counter=  0 own_increments=0
[A;2026-10-26T22:14:36.790] incrementing counter=  0 own_increments=0
[A;2026-10-26T22:14:37.791] incrementing counter=  0 own_increments=0
[A;2026-10-26T22:14:38.793] incrementing counter=  0 own_increments=0
[A;2026-10-26T22:14:39.794] incrementing counter=  1 own_increments=1
[A;2026-10-26T22:14:40.795] incrementing counter=  2 own_increments=2
[A;2026-10-26T22:14:41.796] incrementing counter=  2 own_increments=2
[A;2026-10-26T22:14:42.797] incrementing counter=  3 own_increments=3
[A;2026-10-26T22:14:43.798] incrementing counter=  3 own_increments=3
[A;2026-10-26T22:14:44.799] stopped      counter=  3 own_increments=3
[A;2026-10-26T22:14:45.800] stopped      counter=  5 own_increments=3
[A;2026-10-26T22:14:46.802] stopped      counter=  5 own_increments=3
[A;2026-10-26T22:14:47.803] stopped      counter=  5 own_increments=3
^C
```

**Output Node B:**
```
[ec2-user@ip-172-31-42-121 app-task-1]$ NODE_ID=B PEER=172.31.47.197 SYNC_DELAY=10 python3 counter.py
[B;2026-10-26T22:14:35.323] incrementing counter=  1 own_increments=1
[B;2026-10-26T22:14:36.324] incrementing counter=  2 own_increments=2
[B;2026-10-26T22:14:37.325] incrementing counter=  2 own_increments=2
[B;2026-10-26T22:14:38.326] incrementing counter=  3 own_increments=3
[B;2026-10-26T22:14:39.327] incrementing counter=  3 own_increments=3
[B;2026-10-26T22:14:40.328] incrementing counter=  3 own_increments=3
[B;2026-10-26T22:14:41.329] incrementing counter=  3 own_increments=3
[B;2026-10-26T22:14:42.330] incrementing counter=  4 own_increments=4
[B;2026-10-26T22:14:43.332] incrementing counter=  4 own_increments=4
[B;2026-10-26T22:14:44.333] incrementing counter=  5 own_increments=5
[B;2026-10-26T22:14:45.334] stopped      counter=  5 own_increments=5
[B;2026-10-26T22:14:46.335] stopped      counter=  5 own_increments=5
[B;2026-10-26T22:14:47.336] stopped      counter=  5 own_increments=5
[B;2026-10-26T22:14:48.337] stopped      counter=  5 own_increments=5
^C
```

Node A made 3 and node B made 5 increments, so the correct total is 8. Both nodes
agree on **5** (`max(3, 5)`), so 3 increments are lost.

> In a real system, this situation occurs e.g. during a network issue where
  synchronization messages do not get through for a while (a series of lost
  messages, see Task 1.3)..

To make sure our program displays the correct value, I introduced 2 counters,
as suggested by the instructions (`counter_safe.py`). Every node counts its own
increments and, instead of the global counter value, sends only its own count to
the other node. The receiving node stores the peer's count and computes the
counter as the sum of both:

```python
peer_increments = max(peer_increments, int(data))  # on receive
counter = local_increments + peer_increments       # displayed value
```

The peer's count has to be merged with `max` (not simply assigned), so that an
older message arriving late cannot overwrite a newer value. This works because
each count has exactly one writer: concurrent increments of A and B end up in
separate counts and are added up instead of overwriting each other. The
properties from Task 1.3 still hold, since each message still carries the full
state of its sender.

Running the safe counter with the same `SYNC_DELAY=10`:

**Output Node A:**
```
[ec2-user@ip-172-31-47-197 app-task-1]$ NODE_ID=A PEER=172.31.42.121 SYNC_DELAY=10 python3 counter_safe.py
[A;2026-10-26T22:17:16.895] incrementing counter=  1 peer_counter=0 own_increments=1
[A;2026-10-26T22:17:17.896] incrementing counter=  2 peer_counter=0 own_increments=2
[A;2026-10-26T22:17:18.897] incrementing counter=  3 peer_counter=0 own_increments=3
[A;2026-10-26T22:17:19.898] incrementing counter=  4 peer_counter=0 own_increments=4
[A;2026-10-26T22:17:20.899] incrementing counter=  4 peer_counter=0 own_increments=4
[A;2026-10-26T22:17:21.900] incrementing counter=  4 peer_counter=0 own_increments=4
[A;2026-10-26T22:17:22.902] incrementing counter=  4 peer_counter=0 own_increments=4
[A;2026-10-26T22:17:23.903] incrementing counter=  4 peer_counter=0 own_increments=4
[A;2026-10-26T22:17:24.904] incrementing counter=  4 peer_counter=0 own_increments=4
[A;2026-10-26T22:17:25.905] incrementing counter=  5 peer_counter=0 own_increments=5
[A;2026-10-26T22:17:26.906] stopped      counter= 13 peer_counter=8 own_increments=5
[A;2026-10-26T22:17:27.916] stopped      counter= 13 peer_counter=8 own_increments=5
^C
```

**Output Node B:**
```
[ec2-user@ip-172-31-42-121 app-task-1]$ NODE_ID=B PEER=172.31.47.197 SYNC_DELAY=10 python3 counter_safe.py
[B;2026-10-26T22:17:16.317] incrementing counter=  1 peer_counter=0 own_increments=1
[B;2026-10-26T22:17:17.319] incrementing counter=  2 peer_counter=0 own_increments=2
[B;2026-10-26T22:17:18.320] incrementing counter=  3 peer_counter=0 own_increments=3
[B;2026-10-26T22:17:19.321] incrementing counter=  4 peer_counter=0 own_increments=4
[B;2026-10-26T22:17:20.322] incrementing counter=  5 peer_counter=0 own_increments=5
[B;2026-10-26T22:17:21.323] incrementing counter=  6 peer_counter=0 own_increments=6
[B;2026-10-26T22:17:22.324] incrementing counter=  7 peer_counter=0 own_increments=7
[B;2026-10-26T22:17:23.325] incrementing counter=  7 peer_counter=0 own_increments=7
[B;2026-10-26T22:17:24.327] incrementing counter=  8 peer_counter=0 own_increments=8
[B;2026-10-26T22:17:25.328] incrementing counter=  8 peer_counter=0 own_increments=8
[B;2026-10-26T22:17:26.329] stopped      counter=  8 peer_counter=0 own_increments=8
[B;2026-10-26T22:17:27.336] stopped      counter= 13 peer_counter=5 own_increments=8
^C
```

Node A made 5 and node B made 8 increments. After the exchange, both nodes show
**13** = 5 + 8, the correct total, even though all increments happened
concurrently.

## Task 2 - [Single-copy counter]

### Provisioning

To provision the infrastructuer (2x EC2 instances running the applications, 1x
EC2 instance running Redis). This can be done through `terraform apply -var
task_2=true`. The instance configuration can be seen in `task1.tf`. There is 2
security groups, 1 for the 2 nodes EC2 instances, which simply exposes them to
ssh and incoming traffic. The 2nd group exposes the port of the Redis Instance
(Redis default port is `6379`). The full communication is happening through the
VPC of the Learners Lab.

### Why Redis

I use Redis for this exercise as Redis already has atomicity built-in. With
`INCR counter` on Redis, reads, and writes are all in one single command and run
on a single thread sequentially (e.g. in python `r.incr("counter")`). There also
is a Redis `.lock(...)` function to show the timing of Task 2.2..

```python
...
MODE = os.environ.get("MODE", "incr")  # incr | naive | lock
...
r = redis.Redis(host=os.environ["REDIS_HOST"])
...
def increment():
    ...
    if MODE == "incr":
        r.incr("counter")
    elif MODE == "naive":
        value = int(r.get("counter") or 0)
        r.set("counter", value + 1)
    elif MODE == "lock":
        with r.lock("counter_lock", sleep=0.001):
            value = int(r.get("counter") or 0)
            r.set("counter", value + 1)
```

To test different Redis synchronisation systems (or no synchronisation), there is a MODE env variable, that you need to provide.

| MODE | Descriptio |
| -- | -- |
| `'incr'` | Uses Redis' atomic `.incr(...)` function |
| `'naive'` | Reads the value from Redis, increments this value and stores it back. (No synchronisation) |
| `'lock'` | Uses Redis' lock `.lock(..., sleep=0.001)` function, to lock the Redis and then read and update the value (like `'naive'`) |

> It is important to have both system run simultaneously, so another env
  variable `START_AT` should be set to the future (e.g. 20secs into the future)
  for both nodes to start at the same time.

> Also make sure to delete the Redis entry before every run. To do this run
  `python3 -c "import redis;
  redis.Redis(host='<REDIS_HOST_PRIVATE_IP>').delete('counter')"`

To simplify this, a small bash script does the run for you. It deletes the Redis
entry, gets a time 5s into the future and starts `counter_redis.py` on both
nodes (connecting to them through ssh with the terraform IP output). The logs are
saved in `node_{a,b}.log` and the timing values are returned to the shell. By
default this script runs in `MODE = "incr"`. To change this provide another mode
from the table as the first argument for the script. To change the amount of
increments provide this as a second argument.

### Task 2.1

Running this with Redis' `incr(...)` function (`MODE = 'incr'`) or through the bash script `./run_task2.sh`, will yield the correct result:

**`node_A.log`**:
```
[A;2026-10-27T10:18:33.004] incr         own_counter=  1
[A;2026-10-27T10:18:33.004] incr         own_counter=  2
[A;2026-10-27T10:18:33.005] incr         own_counter=  3
[A;2026-10-27T10:18:33.005] incr         own_counter=  4
...
[A;2026-10-27T10:18:33.029] incr         own_counter= 97
[A;2026-10-27T10:18:33.029] incr         own_counter= 98
[A;2026-10-27T10:18:33.030] incr         own_counter= 99
[A;2026-10-27T10:18:33.030] incr         own_counter=100
[A] mode=incr n=100 total=26.9ms avg=0.269ms max=3.504ms
[A] final counter=200
```
**`node_B.log`**
```
[B;2026-10-27T10:18:33.004] incr         own_counter=  1
[B;2026-10-27T10:18:33.004] incr         own_counter=  2
[B;2026-10-27T10:18:33.005] incr         own_counter=  3
[B;2026-10-27T10:18:33.005] incr         own_counter=  4
...
[B;2026-10-27T10:18:33.030] incr         own_counter= 97
[B;2026-10-27T10:18:33.031] incr         own_counter= 98
[B;2026-10-27T10:18:33.031] incr         own_counter= 99
[B;2026-10-27T10:18:33.031] incr         own_counter=100
[B] mode=incr n=100 total=27.1ms avg=0.271ms max=3.707ms
[B] final counter=200
```

As already explained before, there is no need for synchronisation messages as
Redis `incr(...)` function is atomic by design. So 2 nodes incrementing the same
value at the same time will still produce the correct result. The 2 nodes are
indirectly synchronised by the Redis instance.

### Task 2.2

As stated above, we can already test this by using the `'naive'` mode to run
this example (`./run_task2.sh naive`)

**`node_A.log`**:
```
[A;2026-10-27T10:25:34.004] naive        own_counter=  1
[A;2026-10-27T10:25:34.004] naive        own_counter=  2
[A;2026-10-27T10:25:34.005] naive        own_counter=  3
[A;2026-10-27T10:25:34.005] naive        own_counter=  4
...
[A;2026-10-27T10:25:34.052] naive        own_counter= 97
[A;2026-10-27T10:25:34.052] naive        own_counter= 98
[A;2026-10-27T10:25:34.053] naive        own_counter= 99
[A;2026-10-27T10:25:34.053] naive        own_counter=100
[A] mode=naive n=100 total=50.0ms avg=0.500ms max=3.641ms
[A] final counter=113
```
**`node_B.log`**
```
[B;2026-10-27T10:25:34.004] naive        own_counter=  1
[B;2026-10-27T10:25:34.005] naive        own_counter=  2
[B;2026-10-27T10:25:34.005] naive        own_counter=  3
[B;2026-10-27T10:25:34.006] naive        own_counter=  4
...
[B;2026-10-27T10:25:34.051] naive        own_counter= 97
[B;2026-10-27T10:25:34.052] naive        own_counter= 98
[B;2026-10-27T10:25:34.052] naive        own_counter= 99
[B;2026-10-27T10:25:34.053] naive        own_counter=100
[B] mode=naive n=100 total=49.6ms avg=0.496ms max=4.008ms
[B] final counter=113
```

As we can see already, this does not yield the correct result of 200. The
problem here is that if both nodes read the value in the Redis at the same time
and then increment this, and naively write this back, one of the increments will
be lost. So an increment of +2 becomes an increment pf +1. With my chosen
implementation (`.incr(...)`) this does not happen as the value is incremented
atomically.

To see how a lock changes the Output lets run the apps with `'lock'`:

**`node_A.log`**:
```
[A;2026-10-27T10:31:27.005] lock         own_counter=  1
[A;2026-10-27T10:31:27.011] lock         own_counter=  2
[A;2026-10-27T10:31:27.012] lock         own_counter=  3
[A;2026-10-27T10:31:27.013] lock         own_counter=  4
...
[A;2026-10-27T10:31:27.195] lock         own_counter= 97
[A;2026-10-27T10:31:27.196] lock         own_counter= 98
[A;2026-10-27T10:31:27.197] lock         own_counter= 99
[A;2026-10-27T10:31:27.198] lock         own_counter=100
[A] mode=lock n=100 total=193.8ms avg=1.938ms max=20.500ms
[A] final counter=200
```
**`node_B.log`**
```
[B;2026-10-27T10:31:27.006] lock         own_counter=  1
[B;2026-10-27T10:31:27.007] lock         own_counter=  2
[B;2026-10-27T10:31:27.008] lock         own_counter=  3
[B;2026-10-27T10:31:27.009] lock         own_counter=  4
...
[B;2026-10-27T10:31:27.183] lock         own_counter= 97
[B;2026-10-27T10:31:27.184] lock         own_counter= 98
[B;2026-10-27T10:31:27.187] lock         own_counter= 99
[B;2026-10-27T10:31:27.188] lock         own_counter=100
[B] mode=lock n=100 total=183.3ms avg=1.833ms max=8.895ms
[B] final counter=200
```

With a Redis lock, we now get the correct result again. The problem here is,
that the time it takes to run through the full 100 increments on both nodes now
takes about 6x as long, as the nodes have to wait for each others lock to be
free. With either the atomic `incr(...)` or the Redis `.lock(...)`, both
counters will be always correct. 

## Task 3 - [Comparison]

As I have not implemented Task 1 to be easily comparable to Task 2's
application, I added a new application (`app-task-1/counter_bench.py`) for this.
In addition to holding 2 values for its own counter and the peers counter
(making it stable and always correct), I added ACK's to the application, to
measure the time how long synchronisation takes.

This can again be run through a bash script (`./run_task1_bench.sh`) which works
similar to the bash script in Task 2. Make sure to have the instances for Task 1
running with `terraform apply -var task_1=true -auto-accept`. Instead of the
mode as the first argument, this now takes the number of increments as the first
argument.

The Output for Task 1 (with ACK's and benchmarking) is:

**`node_A.log`**:
```
[A;2026-10-27T11:25:10.000] counter=  2 peer_counter=1 own_increments=1
[A;2026-10-27T11:25:10.001] counter=  4 peer_counter=2 own_increments=2
[A;2026-10-27T11:25:10.001] counter=  6 peer_counter=3 own_increments=3
[A;2026-10-27T11:25:10.002] counter=  9 peer_counter=5 own_increments=4
...
[A;2026-10-27T11:25:10.024] counter=193 peer_counter=96 own_increments=97
[A;2026-10-27T11:25:10.024] counter=195 peer_counter=97 own_increments=98
[A;2026-10-27T11:25:10.025] counter=197 peer_counter=98 own_increments=99
[A;2026-10-27T11:25:10.025] counter=199 peer_counter=99 own_increments=100
[A] n=100 local=0.086ms sync=21.0ms avg_sync=0.210ms
[A] final counter=200
```

**`node_B.log`**
```
[B;2026-10-27T11:25:10.001] counter=  2 peer_counter=1 own_increments=1
[B;2026-10-27T11:25:10.001] counter=  4 peer_counter=2 own_increments=2
[B;2026-10-27T11:25:10.001] counter=  6 peer_counter=3 own_increments=3
[B;2026-10-27T11:25:10.001] counter=  8 peer_counter=4 own_increments=4
...
[B;2026-10-27T11:25:10.024] counter=195 peer_counter=98 own_increments=97
[B;2026-10-27T11:25:10.025] counter=197 peer_counter=99 own_increments=98
[B;2026-10-27T11:25:10.025] counter=199 peer_counter=100 own_increments=99
[B;2026-10-27T11:25:10.025] counter=200 peer_counter=100 own_increments=100
[B] n=100 local=0.111ms sync=20.9ms avg_sync=0.209ms
[B] final counter=200
```

The Output for Task 2 (using the Redis' `incr(...)` function) is:

**`node_A.log`**:
```
[A;2026-10-27T11:46:15.004] incr         own_counter=  1
[A;2026-10-27T11:46:15.004] incr         own_counter=  2
[A;2026-10-27T11:46:15.004] incr         own_counter=  3
[A;2026-10-27T11:46:15.004] incr         own_counter=  4
...
[A;2026-10-27T11:46:15.029] incr         own_counter= 97
[A;2026-10-27T11:46:15.029] incr         own_counter= 98
[A;2026-10-27T11:46:15.029] incr         own_counter= 99
[A;2026-10-27T11:46:15.030] incr         own_counter=100
[A] mode=incr n=100 total=26.4ms avg=0.264ms max=3.446ms
[A] final counter=200
```

**`node_B.log`**
```
[B;2026-10-27T11:46:15.003] incr         own_counter=  1
[B;2026-10-27T11:46:15.004] incr         own_counter=  2
[B;2026-10-27T11:46:15.004] incr         own_counter=  3
[B;2026-10-27T11:46:15.004] incr         own_counter=  4
...
[B;2026-10-27T11:46:15.029] incr         own_counter= 97
[B;2026-10-27T11:46:15.029] incr         own_counter= 98
[B;2026-10-27T11:46:15.030] incr         own_counter= 99
[B;2026-10-27T11:46:15.030] incr         own_counter=100
[B] mode=incr n=100 total=27.2ms avg=0.272ms max=3.350ms
[B] final counter=200
```

### Task 3.1

All measurements use 100 increments per node, with both nodes starting at the
same time (see the bashscripts and `START_AT` env variable). All instances run
in the same availability zone (`availability_zone = "us-east-1b"` in the EC2
instance resource blocks) and communicate over their private IPs.

| Implementation | Nodes | Total (100 incr.) | Avg per increment | Max | Final counter |
| -- | -- | -- | -- | -- | -- |
| Replicated, local update | A+B | 0.09 – 0.11 ms | ~0.001 ms | – | 200 |
| Replicated, synchronization (ACK) | A+B | ~21 ms | 0.21 ms | – | 200 |
| Redis `incr` | A only | ~29 ms | 0.29 ms | 3.3 ms | 100 |
| Redis `incr` | A+B | ~27 ms | 0.27 ms | 3.7 ms | 200 |
| Redis `naive` | A+B | ~50 ms | 0.50 ms | 4.0 ms | 113 |
| Redis `lock` | A only | ~112 ms | 1.12 ms | 9.8 ms | 100 |
| Redis `lock` | A+B | 183 – 194 ms | 1.8 – 1.9 ms | 20.5 ms | 200 |

* Replicated: Updating the local state is practically free (about 1 mikrosecond
    per increment), as it only increments an integer in memory. The time is spent on
    synchronizing the replicas: each sync takes one network round trip (send state,
    wait for the ACK), which is about 0.21 ms. In Task 1.4, this runs in the
    background, so an increment itself only costs the local update (This is also why
    I introduced the `counter_bench.py` script). The ACK is only needed to measure
    the synchronization time.

* Single-copy: Every increment is a request to Redis and therefore costs at
    least one network round trip. `incr` needs exactly one round trip (0.27 ms),
    which is roughly the same as one replicated synchronization. `naive` needs two
    round trips (To `GET` the value from Redis, increment it and `SET` it back
    to Redis), so it takes twice as long, and is still wrong. `lock` needs about
    four round trips (In addition to the `GET` and `SET`, it has to acquire
    the lock, and release it) and additionally has to wait whenever the
    other node holds the lock. This makes it about 7x slower than `incr`,
    with single increments taking up to 20 ms.

* Effect of concurrency: For `incr`, concurrency has no measurable effect
    (0.29 ms with one node, 0.27 ms with both, which is within measurement noise).
    Redis executes the commands of both nodes one after another, and a single
    `INCR` only takes microseconds, so the second request practically never has to
    wait. For `lock`, concurrency clearly matters: with one node an increment takes
    1.12 ms (about four round trips), with both nodes 1.8 - 1.9 ms. The additional
    0.7 ms per increment is the time a node waits until the other node releases
    the lock.

### Task 3.2

+ Where does synchronization happen in each implementation?

    In the replicated counter, synchronization happens in the application itself:
    the nodes exchange their state via messages and merge it (`max` of the own
    and incoming value). The update itself is done in its own state without any
    coordination needed. In the single-copy counter, synchronization happens in
    the data store. Redis executes commands one after another on a single
    thread, so `INCR` is atomic, and the lock is also managed by Redis. The two
    nodes never communicate with each other.

+ What happens if the two nodes cannot communicate temporarily?

    Replicated: both nodes can still increment their local counters, but they do
    not see the increments of the other node, so their values diverge. Once
    communication resumes, the next sync message carries the full state and both
    nodes converge to the correct value again (no increments are lost, see
    Task 1.4). This is one of the most basic varients of a state based CRDT.

    Single-copy: nothing changes, as the nodes do not communicate with
    each other anyway. As long as both can reach Redis, the counter stays correct
    and up to date.

+ What happens if the shared data store is unavailable?

    Single-copy: no node can read or increment the counter anymore, the requests
    fail (redis-py raises a `ConnectionError`). The data store is a single point of
    failure for the whole system. To work around this the nodes could store
    cached increments, and when Redis comes back online they could use a lock to
    update the Single-copy to have the counter be correct, even tho Redis is
    down.

    Replicated: not affected at all, as there is no shared data store.
   
+ Which approach would you choose if increments must be immediately visible
    to both nodes? Why?

    The single-copy approach. There is only one authoritative copy of the counter,
    so as soon as `INCR` returns, every following read from any node sees the new
    value. In the replicated approach, an increment only becomes visible to the
    other node once the synchronization message arrives, and during a network
    interruption not at all (eventual consistency). The price is that every
    increment costs a network round trip and the counter is unavailable when
    Redis is down.
