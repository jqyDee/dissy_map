# EX04 Report: Leader Election

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---


## Background

In a symmetric system, every node is equal. While this is robust, it makes it very difficult to agree on one order of operations. With one leader that orders and decides everything, coordination becomes simple. If the leader fails, the system has to choose a new one by itself.

An election has to satisfy two properties: 
- there must never be more than one leader (in Raft - per term).
- eventually a leader does get elected.

We looked at three algorithms and implemented the last one, Raft (only the leader election part: no log replication or log-based voting restrictions and no persistent state).

**Ring algorithm (Chang-Roberts)**: The nodes form a logical ring and each one only talks to the neighbour. The `election(id)` message always carries the largest ID seen so far. A node that receives a bigger ID forwards it unchanged. If the received is smaller than its own, it replaces it with its own ID or discards the message if it is already participating in the election. When a node receives its own ID, it has the largest ID and wins. It sends `elected(id)` message around the ring. The algorithm is slow because the messages go one after another, and it breaks if a node crashes during the election.

**Bully algorithm**: Every node can talk to every other node and knows all IDs. The highest living ID wins. A node starting an election sends `election` messages only to the nodes with the higher IDs. An `answer` means "I am alive and my ID is higher". If no answer arrives within a timeout T the node becomes the leader and sends a `coordinator` message to all lower nodes. If a node with a higher ID than the current leader suddenly comes back, it "bullies" the leader takes over. 

**Raft algorithm**: Raft does not pick the highest ID, the first node that times out and collects majority of votes wins.

**States**: Follower -> (timeout) -> Candidate (majority) -> Leader. A node that sees a valid leader or a higher term goes back to Follower.

**Terms** act as a logical clock with at most one leader per term. Every message carries the sender's term:
- Higher term seen -> take it over, `votedFor = None`, become follower 
- Lower term seen -> reject the message 


**Voting**: Each node gives one vote per term, first come first served. A candidate needs a majority of the fixed cluster size. 


**Heartbeats** from the leader keep the followers' timers from running out and suppress new elections.

**Random timeouts** break the symmetry, so spilt votes become rare and don't repeat forever. 


Full Raft algorithm also does log replication and adds a voting rule that a node only votes for a candidate whose log is at least as up to date as its own but that is out of scope of this exercise

## Task 1 - State Machine & Leader Election Implementation

We implemented a Raft-style leader electoin. Our implementation is limited to elections and heartbeaats, there is no log replication. 
Each node runs the same Python script, started with its own name in its own terminal: `python3 node.py --name A/B/C`

For communication we used a Zenoh publish/subscribe: all nodes publish to and subscribe on one shared key (`raft/msg`) and exchange JSON messages with a `type` field. We already used Zenoh in exercise 3 and with a shared key no need peer addresses need to be configred. 


### Program Structure
Each node consists of two concurrent parts:

- **Main loop** checks every 10ms whether the election timer has expired. If it did, it starts an election. If the node is leader it sends a heartbeat every 50ms.
- **Zenoh callback** runs a background thread whenever a message arrives, ignores the node's own messages and dispatches the message to a handler based on its `type`:

```python
def on_message(sample):
    msg = json.loads(sample.payload.to_string())
    if msg["from"] == name: # ignoring on my own message
        return 
    if msg["type"] == "RequestVote":
        on_request_vote(msg)
    elif msg["type"] == "VoteReply":
        on_vote_reply(msg)
    elif msg["type"] == "Heartbeat":
        on_heartbeat(msg)
```

Since both threads read and modify the same state (`current_term`, `voted_for`, `role`, ...), every access is wrapped in a lock.

#### State variables: 
The three variables required by the task keep track of the current term who the node voted for in this term and what the node's role:
```python
current_term = 0
voted_for = None
role = "follower"
```

#### Helper variables: 
```python
leader = None #leader we currently follow (for logging in the terminal:)
votes = set() # nodes that voted for me (used as candidate)
last_heard = time.monotonic() # last time we heard from a valid leader / grandted a vote
timeout = random.uniform(TIMEOUT_MIN, TIMEOUT_MAX) # current randomized election timeout
````
The node state is kept in memory only, so after a restart a node begins again at term 0.


### Messages

| Type | Fields | Purpose |
| :--- | :--- | :--- |
| `RequestVote` | `term`, `from`, `candidate` | A candidate asks all nodes for their vote |
| `VoteReply` | `term`, `from`, `to`, `granted` | Answer to a candidate; ignored by every node except `to` |
| `Heartbeat` | `term`, `from`, `leader` | The leader asserts its leadership and resets followers' timers |


### Randomized timeouts and leader election
```python
CLUSTER_SIZE = 3 # fixed number of nodes in the cluster
MAJORITY = CLUSTER_SIZE // 2 + 1 # votes needed to vin, based on the fixed size
TIMEOUT_MIN = 0.15
TIMEOUT_MAX = 0.30
HEARTBEAT_INTERVAL = 0.05 # have to multiply all by 10 while testing othewise too fast
```

**Election timer** - each follower and candidate draws a random timeout between 150 and 300 ms. The timer is reset (`last_heard` = now, new random `timeout`) whenever the node receives a valid heartbeat, grants a vote, or starts an election.

**Starting an election.** When the timer expires, the node becomes a candidate, increments its term, votes for itself and broadcasts a `RequestVote`:

```python
def start_election():
    # follower / candidate timed out, become candidate in a new term and ask for voted
    global current_term, voted_for, role, votes
    with lock:
        voted_for = name # vote for myself 
        role = "candidate"
        current_term = current_term + 1  # update term
        votes = {name} # freshhhh set 
        msg = {"type": "RequestVote", "term": current_term, "from": name, "candidate": name}
        print(f"[{name}] timeout -> candidate for term {current_term}")
        reset_timer() # if nobody wins, timeout again and retry with term +1 
    send(msg)
```

`votes` is recreated for every new term so votes from an earlier term do not count 

**Voting**: A node that receives a `RequestVote` first applies the higher-term rule, then grants the vote only if the request is for its current term and it has not voted for anyone else in this term.  A vote with a lower term is automatically rejected, and the reply contains the voter's term so an outdated candidate learns about it:

```python
def on_request_vote(msg):
    # a candidat easks for my vote. yes/no and reply
    global current_term, voted_for, role
    with lock:
        # im outdated -> adopt the term, forget old vote, become follower
        if msg["term"] > current_term:
            print(f"[{name}] saw term {msg['term']} > my term {current_term} -> follower")
            current_term = msg["term"]
            voted_for = None
            role = "follower"


        # grant the vote only if:
        # the request is for my current turm
        # i haven't voted yet in this term, or already voter for this same candidate 
        # -> one vote per term, first come first served
        granted = (msg["term"] == current_term) and (voted_for == None or voted_for == msg["candidate"])
        
        if granted: 
            voted_for = msg["candidate"]
            reset_timer() 

        #must reply, my term in the reply lets an outdated candidate learn it's behind
        reply = {"type": "VoteReply", "term": current_term, "from" : name, "to": msg["candidate"], "granted": granted}
        print(f"[{name}] term{reply['term']}: vote for {msg['candidate']}? {granted}") 
    send(reply)
```


**Becoming leader**: a candidate counts only granted votes from its current term, and only while it is still a candidate. As soon as it has a majority (2 of 3), it becomes leader:

```python
 if role == "candidate" and msg["term"] == current_term and msg["granted"]
            votes.add(msg["from"])
            #  majority reacher -> im a "leader" of this term
            if len(votes) >= MAJORITY:
                    role = "leader"
```

The majority is computed from the **fixed** cluster size, not from the nodes that are currently reachable. Otherwise a single isolated node could count itself as a "majority" and elect itself, leading to two leaders.

**Heartbeats.** The leader sends a `Heartbeat` every 50 ms from the main loop. A node receiving a heartbeat ignores it if the term is lower than its own; otherwise it adopts a higher term, becomes (or stays) follower and resets its timer. Since 50 ms is well below the minimum timeout of 150 ms, followers never time out while the leader is alive. This also makes a candidate step down when another node has already won the same term
So in the main loop we check the timer every 10ms, start elections in case the leader is expired and send heartpeats as leader.


## Task 2 - Experiments and Failure Recovery

### 2.1 Initial Leader Election: 
#### Start Nodes A, B, and C. Verify that a single node is elected leader and that all followers receive its periodic heartbeats: 


Node A was started first and timed out before the other nodes were running. It became the candidate for the term 1  and term 2, but since it was alone and only had its own vote, neither election succeeded and it just kept updating the term. This already demonstrates that a node cannot become leader without a majority, even if its the only node running. 

Node B then finally joined during term 3, adopted the higher term, voted for A and A became the leader with 2 of 3 votes. At the time when C joined, the leder was already decided, so C adopted term 3 from A's heartbeat and started following A. 


Both B and C log "following leader A in term 3" which is only printed when a heartbeat is received. Afterwards no node starts a new election. Followers reset hteir 150-300ms election timer on every heartbeat (every 50ms), so the absence of further timeouts shows that the heartbeats keep arriving periodically. 
```bash
(dissy) anna@Annas-MacBook-Air src % python3 node.py --name A
[A] started as follower
[A] timeout -> candidate for term 1
[A] timeout -> candidate for term 2
[A] timeout -> candidate for term 3
[A]: I am a leader of the term 3
```

```bash
(dissy) anna@Annas-MacBook-Air src % python3 node.py --name B
[B] started as follower
[B] saw term 3 > my term 0 -> follower
[B] term3: vote for A? True
[B] following leader A in term 3
```

```bash
(dissy) anna@Annas-MacBook-Air src % python3 node.py --name C
[C] started as follower
[C] saw term 3 > my term 0 -> follower
[C] following leader A in term 3
```


###  2.2 Leader Crash & Re-election
#### Stop the active leader process. Observe and record:

- The outcome of the new election term.

We stopped the leader A with Crtl+C.

- How remaining nodes detect the failure: 

No failure message, the nodes only notice the failure because A's heartbeats stop arriving. So their election timers are no longer reset and eventually expire.

- The transition of a follower to candidate.

B's election times was the first one to expire (random timeout was shorter thabn C's). So, B became candidate for term 4, voted for itself and broadcast a `RequestVote`. 

- The outcome of the new election term.

C received B's `RequestVote` with term 4 > 3 before its own timer expired. It adopted term 4, granted its vote and B became leader of term 4 with 2 of 3 votes. C then follows B.

```bash
[A]: I am a leader of the term 3
^C
bye bye
```

```bash
[B] timeout -> candidate for term 4
[B]: I am a leader of the term 4
```

```bash
saw term 4 > my term 3 -> follower
[C] term4: vote for B? True
[C] following leader B in term 4
```


### 2.3 Node Recovery: 
#### Restart the previously stopped node. Observe how its outdated term is updated and how it reintegrates as a follower.

After estarting A begins again as follower in term 0. The first heartbeat from B carries term 4 > 0, so A adopts term 4 and follows B. Since B's heartbeats (every 50 ms) arrive before A's election timeout (at least 150 ms) can expire, A never becomes a candidate and does not disrupt the running cluster.


```bash
 (dissy) anna@Annas-MacBook-Air src % python3 node.py --name A
[A] started as follower
[A] saw term 4 > my term 0 -> follower
[A] following leader B in term 4
```




## Task 3 - Conceptual Questions
### 3.1 Answer the following questions concise and precisely:

#### 3.1.1 Why are randomized election timeouts critical for preventing perpetual split votes?

If all nodes timeout at the same time, they then become candidates and vote for themselves. No candidate can reach a majorirty, election fails ans since all timers expire at the same time again, the same split vote would repeat forever. With randomized timeouts, one node usually times out clearly before the others, sends its `RequestVote` message first, collects a majority before any other node becomes a candidate.


#### 3.1.2 What happens if two candidates receive an equal number of votes in a cluster, and how does the system recover?
If the votes are split equally, no candidate reaches a majority, so the term ends without a leader. No node "picks" a winner, the candidates simply stay candidates until their election timers expire again. The first one to time out starts a new election in the next term with a newly drawn random timeout. Since the new timeouts differ, one candidate is very likely to start first and win the next election. (In a 3-node cluster an exact tie is only possible if a vote is lost; with an even number of nodes, e.g. 4, a 2:2 split can occur.)


#### 3.1.3 How does comparing currentTerm prevent an isolated or delayed node from disrupting the active cluster with stale messages?
Every message carries the sender's term. Messages with a lower term than the receiver's are rejected or ignored: stale heartbeats from an old leader do not reset any follower's timer, and stale `RequestVote`s receive no votes. At the same time, the replies contain the receiver's higher term, so the outdated node learns that it is behind, adopts the new term and steps down to follower. An isolated node can still become a candidate (like if it's the only one left after the rest disconnected), but it can never win or make other nodes follow it. A limitation of the basic algorithm is that an isolated node keeps increasing its term; when it reconnects, its higher term forces the current leader to step down. Full Raft implementations prevent this with a "PreVote" phase.



#### 3.1.4 Is leader election alone suﬀicient to guarantee linearizable consistency in a distributed database? Explain briefly
No. Linearizability means the system behaves as if there was a single copy of the data: every read returns the result of the most recent completed write. Leader election only guarantees at most one leader per term. Additionally, writes must be replicated through a log and only count as committed once a majority has stored them, and a new leader must already contain all committed writes (Raft's "log at least as up-to-date" voting rule, which we left out). Furthermore, a partitioned old leader that has not yet seen the higher term may still believe it is leader and answer reads with stale data, so a leader must confirm its leadership with a majority before serving reads.