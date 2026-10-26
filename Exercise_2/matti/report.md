# EX02 Report: [Shared State]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Task 1 - [Replicated counter]

### Infrastructure

`task1.tf` provisions one security group (SSH and port 8000) and two t2.micro
EC2 instances (`task1-node-A`, `task1-node-B`) running Amazon Linux 2023. Once
the instances are up, a `terraform_data` resource connects to each one via SSH
(`labsuser.pem`), waits for `user_data` to finish, and uploads `app-task-1/` to
the home directory. Changing any file in `app-task-1/` re-uploads the code on
the next `apply`, without recreating the instances.

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

public_ip = {
  "A" = "3.85.40.150"
  "B" = "107.22.52.150"
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
  `[ec2-user@ip-172-31-47-197 app-task-1]$`).

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
