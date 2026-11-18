# EX05 Report: Fault Tolerance & Coordination

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Background


We need a coordination service to make sure that multiple servers stay in sync, agree on a shared state and recover from failures. It is also easier than implementing a consensus algorithm ourselves every time: ZooKeeper runs a consensus protocol (Zab, similar to Raft) internally, and the application just uses the primitives it offers.

ZooKeeper stores a tree of **znodes**. A **persistent** znode stays until someone deletes it. An **ephemeral** znode is tied to the client's **session**: it is deleted automatically when the session ends (crash, `zk.stop()`, or being disconnected for longer than the session timeout). Every znode has a **stat** with a **version**, which counts how many times its data has been changed: every successful `set` increases it by one.

## Setup

- 1 ZooKeeper VM, ZooKeeper runs as a Docker container
- 5 node VMs on AWS, created with Terraform (`count = 5`); everything was also tested locally first
- `user_data` installs Python + kazoo and copies `auction.py` onto every node automatically
- nodes reach ZooKeeper via its private IP; port 2181 is only open inside the security group (`self = true`)
- start a node: `python3 auction.py --name A --zk <zk_private_ip>:2181 [--delay 5]`

**Naming in the experiment output:** uppercase letters (A–E) are the **nodes**, lowercase `a` and `b` are the **participants** (bidders). A participant can bid through any node, e.g. participant `a` bidding through node B.

## Task 1 – Distributed Auction

The nodes never talk to each other directly. The whole auction state is stored as JSON in **one persistent znode `/auction`**, and every node reads and writes this znode. The JSON has three fields:

```python
state = {
    "open": True,          # auction is open at the start
    "highest_bid": 0,      # 0 so that the first real bid is always higher
    "bidder_id": None      # nobody has bid yet -> no winner
}
```

The CLI offers three operations:
- `bid <participant> <amount>` – place a bid (only accepted if it is higher than `highest_bid` and the auction is open)
- `query` – show the highest bid and the bidder
- `close` – close the auction and print the winner, or "no winner" if nobody bid

Extra commands: `reset` (start a new auction, otherwise the same auction would run forever), `nodes` (list living nodes) and `exit`.

A `DataWatch` on `/auction` prints every change on every node automatically (event-driven updates instead of polling).

**Experiment:** bids were submitted through nodes A, C and D. All 5 nodes printed the same sequence of updates (v1 → v2 → v3 → v4) and `query` showed the same state everywhere. A bid equal to the highest bid (`bid a 10` on B) was rejected.

## Task 2 – Concurrent Bids

Every write in `bid()` and `close()` follows the same pattern: the node reads `/auction` together with its version, checks the rules locally (is the auction open? is the bid higher than `highest_bid`?), and then writes the new state with `zk.set(..., version=stat.version)`. ZooKeeper only accepts this write if the znode is still at the version the node read. If another node changed the auction in the meantime, the write fails with `BadVersionError`, and the node goes back to the start, reads the new state and checks again. This is called optimistic concurrency control: no locks, but a write never succeeds on outdated data.

Because all state is in **one** znode, every operation competes for the same version, so the four requirements follow directly:
- **No lower bid over a higher one:** if two bids read the same version, only one write succeeds. The other one re-reads and is checked against the new highest bid. It is accepted only if it is still higher.
- **Closed only once:** two closes read "open" at the same version, but only one `set` succeeds. The other retries, sees `open: False` and is rejected.
- **No bids after closing:** a bid checks `open` before writing. A bid that read "open" just before the close fails the version check, retries, and is then rejected.
- **Bid concurrent with close:** whichever write comes first wins. If the bid wins, the close retries and includes it in the result. If the close wins, the bid retries and is rejected. There is no in-between state.

A local lock would not work here, because it only protects one process, and the nodes run on different machines.

**Experiment:** to make the race visible, we added a `--delay` option that sleeps between reading and writing. Nodes D and E (both `--delay 5`) bid at the same time: D's bid of 17 was written first (v3), E's write failed with "conflict, retrying", E re-read v3, saw 80 > 17, and its bid was accepted as v4. Both bids were handled correctly and none was lost.

```
[E]> bid b 80
[update v3] highest bid: 17 by b
conflict, retrying
bid accepted
[E]> [update v4] highest bid: 80 by b
```

## Task 3 – Crash Recovery and Stale State

**State is not lost:** the auction is stored in the persistent znode `/auction`, not in the memory of any node, so it survives node crashes (and even a ZooKeeper container restart).

**Restarted nodes get the current state:** a node keeps no local copy. On startup, the `DataWatch` reads `/auction` immediately, and every `bid`, `close` and `query` reads fresh from ZooKeeper before acting.

**Stale nodes cannot overwrite newer state:** every write is conditional on the version the node just read. A node that acts on an old view fails the version check, re-reads, and its checks are applied to the real current state.

**No changes without ZooKeeper:** `bid`, `close` and `reset` first check `zk.connected` and reject the operation if the node is disconnected. If the connection drops during an operation, kazoo raises `ConnectionLoss`/`SessionExpiredError`, and the node reports it instead of crashing. In that case the node cannot know whether the last write arrived, so the right step is to reconnect and `query`.

**Failure detection:** each node registers an ephemeral znode `/nodes/<name>`. The `nodes` command lists the living nodes.

**Experiment (AWS):** A bid 50 and was then terminated. `nodes` on B showed `['B','C','D','E']`. Through B, a bid of 99 was placed and the auction was closed. After restarting, A immediately received the closed state (v3), `query` showed the winner, and both new bids on A were rejected:

```
[update v3] highest bid: 99 by a
auction closed
[A]> query
highest bid: 99 by a
[A]> bid a 60
rejected: the auction is not open
```

**Experiment (local):** we stopped ZooKeeper (`docker stop zk`) while A was running: bids were rejected with "rejected: not connected to ZooKeeper", and after restarting ZooKeeper, `query` returned the correct state.

**Observations:**
- With Ctrl+C, the node calls `zk.stop()` and closes its session cleanly, so `/nodes/A` disappears at once. After a real crash, it would only disappear after the session timeout.
- When ZooKeeper was down longer than the session timeout, A's session expired. After reconnecting, A worked again but was no longer in `/nodes`, because kazoo starts a new session and does not recreate the ephemeral znode. A fix would be a connection-state listener that re-registers the node after reconnecting.

## Questions

### How is the auction state represented in ZooKeeper?
As JSON in one persistent znode `/auction` with the fields `open`, `highest_bid` and `bidder_id` (see Task 1). In addition, every node has an ephemeral znode `/nodes/<name>`.

### Which parts must be persistent?
The auction (`/auction`) must be persistent: it must survive node crashes and keep the shared state for all nodes, and also keep the **final result after closing**, otherwise a restarted node could not see the winner. The node registrations (`/nodes/<name>`) are ephemeral, because nodes may disconnect and reconnect, and their entry should disappear when they fail.

### Which ZooKeeper mechanisms prevent conflicting updates from concurrent nodes?
Optimistic concurrency control with the version number: a node reads the version, writes with `set(version=v)`, and ZooKeeper rejects the write if someone else changed the znode in the meantime. The losing node re-reads and re-checks. This works because ZooKeeper applies all writes one at a time in a single total order (atomic broadcast via Zab), so only one write per version can succeed.

### What happens if two nodes try to close the auction simultaneously?
Both read "open" at the same version. The first `set` succeeds, the second gets `BadVersionError`, retries, now sees `open: False` and is rejected with "already closed". There is exactly one final result.

### How does a restarted node obtain the correct auction state?
The state lives in ZooKeeper, not in the node's memory, so a restarted node simply reads `/auction`: the `DataWatch` does this immediately on startup, and every operation reads fresh before acting.

### What happens if an application node cannot reach ZooKeeper? Why might rejecting operations be preferable to continuing with locally cached state?
The node is not allowed to modify the auction: bids and closes are rejected. Rejecting is preferable because the locally cached state can be stale: while the node was cut off, other nodes may have placed bids or closed the auction. Acting on the old view could accept a bid after the close or announce a different winner, giving two conflicting results. We choose consistency over availability: better "rejected" than wrong.
