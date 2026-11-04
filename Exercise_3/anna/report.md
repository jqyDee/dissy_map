# EX03 Report: Network Topologies, Peer Discovery & Byzantine Agreement

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Setup
All programs are written in Python using Zenoh (`eclipse-zenoh`) in peer mode. All nodes run as separate processes on one laptop and find each other via Zenoh's multicast scouting. No addresses are configured anywhere 

## Task 1 - Discovering peers

### 1.1 Implementation

Each node reads its name from the command line (`--name`) and opens a Zenoh session: 

```python
session = zenoh.open(zenoh.Config());
```
It then declares a liveliness token with its name: 

```python
token = session.liveliness().declare_token("node/" + name)
```
A liveliness token is a way fro a node to say "hello i exist" for as long as it's running. Unline a normal message, it carries no data and is not sent once, but stays visible as long as the node lives.

Zenoh removes it automatically when the node stops, for any reason (clean exit, crash or network loss). The other nodes are then notified with `DELETE`. 

To see the other nodes, each node declares a liveliness subscriber on `node/*`. With `history=True` it also receives the tokens of nodes that were already running before it started. The callback adds the name on `PUT` and removes it on `DELETE`, kept the names in a set:

```python
peers = set()
def on_liveliness(sample):
    peer_name = str(sample.key_expr).split("/")[-1]
    if sample.kind == zenoh.SampleKind.PUT:
        peers.add(peer_name)
        print(f"Alive token ('{sample.key_expr}') name: '{peer_name}'")
    elif sample.kind == zenoh.SampleKind.DELETE:
        peers.discard(peer_name)
        print(f"Dropped token ('{sample.key_expr}')")

liveliness_subscriber = session.liveliness().declare_subscriber("node/*", on_liveliness, history=True)
```


The main loop prints the set of nodes every 2 seconds. Every node also lists itselv because `node/*` matches it's own token as well:

```python
try :
    while(True):
        print("your name is:", name)
        print("peers: ", peers)
        time.sleep(2)
except KeyboardInterrupt:
    print("\nbye bye")
    session.close()
```


###  1.2 Dynamic Behavior:

We started three nodes in separate terminals: 
```bash
python node.py --name A
python node.py --name B
python node.py --name C
```

Node A discivered B and C automatically as soon as they start, the same is true for B and C.
```bash
your name is: A
peers:  {'A', 'C', 'B'}
```

Pressed Ctrl+C in B's terminal:
```bash
Dropped token ('node/B')
your name is: A
peers:  {'A', 'C'}
```
Started the program in B's terminal again and see that A and C print that it's alive again:

```bash
Alive token ('node/B') name: 'B'
your name is: A
peers:  {'A', 'C', 'B'}
```

```bash
Alive token ('node/B') name: 'B'
your name is: C
peers:  {'C', 'A', 'B'}
```

####  How does a node learn that another node is available?
It happens on two layers:

First, Zenoh's scounting: at start up a session sends multicast "hello" messages and peers answer, then they open a direct connection. At this point only their Zenoh IDs are known.

Second, the liveliness tokens: B's token declaration is sent over that connection to every matching liveliness subscriber so A's `on_liveliness` runs with PUT. Thanks to `history=True`, a newly started node also receives the tokens that already exist. 

#### What happens when Node B leaves, and what happens when it joins again?
After `Ctrl+C` B's session closes and the connection breaks. Zenoh on A and C removes B's token by itseld and devivers a `DELETE`. B sends no goodbye messages. When B starts again, it is a new session with a new Zenoh ID. Scouting runs again and the token arrives as a `PUT`. Rejoined B sees A's and C's existing tokens.

#### Your discovery mechanism tells you a node is reachable. Can you trust that a discovered node is who it claims to be, or that its messages are truthful?
No, the name is just a claim in the key and any process could declare `node/B`. The restarted B has a different ID but the same name and we only recognize it by the name it claims. By default Zenoh does not authenticate peers or sign messages. It does support TLS, authentication and access control but it is not configured here. Even with authentication, you would know who sent a message, but not whether its content is true. 



## Task 2 - Exchange Message Between Peers
We extended the Task 1 program (`hello.py`). Each node declares a publisher on its own key `hello/<name>` and a normal (non-liveliness) subscriber on the shared key expression `hello/*`:

```python
publisher = session.declare_publisher("hello/" + name)

def on_hello(sample):
    sender = str(sample.key_expr).split("/")[-1]
    message = sample.payload.to_string()
    print("received " + message + " from node " + sender)

hello_subscriber = session.declare_subscriber("hello/*", on_hello)
```

In the main loop, every node publishes a message every 2 seconds: 

```python
 publisher.put("hello from node " + name)
```
The dender is taken from the last part of the key, and the message text form the payload. Since `hello/*` also matches the node's own key, each node receives its own messages as well. Peer discovery works as in the Task 1, with a liveliness token `node/<name>` and a liveliness subscribler (`on_liveliness`) on `node/*`.

Ouout of node C (trimmed). It receivess the messages of all three nodes and stios receiving from A and B when they leave: 

```bash
peers:  {'A', 'B', 'C'}
received hello from node B from node B
received hello from node A from node A
your name is: C
peers:  {'A', 'B', 'C'}
received hello from node C from node C
Dropped token ('node/A')
received hello from node B from node B
your name is: C
received hello from node C from node C
peers:  {'B', 'C'}
Dropped token ('node/B')
your name is: C
received hello from node C from node C
```

### 2.2 Discussion Questions

#### What is the main difference between static configuration and dynamic discovery?
With static configuration the target addresses, names and routes of all nodes are specified manually in advance. This gives a lot of direct control, because the exact communication parths are known but it is challenging to maintain and update as every new node or changed address requires editing the configuration. This works well on small networks, fixed-size clusters and settings with strict security requirements.

With dynamic discovery, nodes find available endpoints automatically at runtime, by querying a registry or control plane, or, as in our case, through a discovery protocol (Zenoh's multicast scouting). This provides less control, but better scalability. Nodes can join, leave, change location and the system will keep working. This suits cloud-native microservices, data centers and large routing domains. 

#### Why is the publish/subscribe pattern useful for communication between distributed processes?
Publish/subscribe decouples message producers from message consumers. A publisher does not know who receives its messages and a subscriber does not know who sends them. They're connected only through the key expressions. This allows systems to communicate asynchronously and to scale independently. 

#### Is peer discovery suﬀicient to make an application fault-tolerant? Explain briefly.
No, discovery only tells us which nodes are reachable right now. It does not prevent message loss: Zenoh does not store messages by default, so anything published while a node is not yet subscribed is simply lost. It also does not handle failures during communicatino, such as node crashing halfway through a protocol and it does not protect against nodes that behave maliciously. Any process can join the network and claim any name, which is a security problem. Fault tolerance requires additional mechanisms such as readiness checks, timeouts and agreement protocols.



## Task 3 - The Byzantine Generals Problem

### 3.1 implementation
All roles are implemented in one program `byzantine_node.py`. The role, traitor flag, numebr of lieutenants and the commander's order are command line arguments:

```bash
python byzantine_node.py --name L1 --role lieutenant --lieutenants 3
python byzantine_node.py --name CMD --role commander --order attack --lieutenants 3 --traitor
```

- **Readiness** - each lieutenant first subscribes to its inbox and only then declares a liveliness token `"byz/alive/lieutenant/<name>"`. The commander waits until it sees as many lieutenant tokens as given by `--lieutenants` before sending. Since Zenoh does not store messages, this ensures no order is lost.

- **Inboxes:** every node subscribes to `byz/inbox/<own name>/*`. A message to L1 from CMD is sent on `byz/inbox/L1/CMD`, so the sender is the last part of the key. The payload is `order:<value>` (from the commander) or `relay:<value>` (from a lieutenant). Per-recipient keys allow a traitor commander to send different orders to different lieutenants.
- **Round 1:** the commander sends its order to every lieutenant. A traitor commander sends the opposite order to every second lieutenant (sorted by name, so the behaviour is deterministic).
- **Round 2:** each lieutenant forwards the order it received to all other lieutenants. A traitor lieutenant forwards the opposite.
- **Decision:** each lieutenant takes the majority over the commander's order and all relays. On a tie (only possible with two lieutenants), it follows the commander's order. If relays are missing, it decides after a 15 s timeout.

```python
votes = [from_commander] + list(relays.values())
attacks = votes.count("attack")
if attacks * 2 > len(votes):
  decision = "attack"
elif attacks * 2 < len(votes):
  decision = "retreat"
else:
  # tie (only possible with 2 lieutenants) -> follow the commander
  decision = from_commander
```

### 3.2 three nodes:

| Run | Traitor | L1 votes → decision | L2 votes → decision | Agreement |
| :--- | :--- | :--- | :--- | :--- |
| 1 | none | `[attack, attack]` → attack | `[attack, attack]` → attack | yes |
| 2 | commander (L1: attack, L2: retreat) | `[attack, retreat]` → attack | `[retreat, attack]` → retreat | **no** |

In run 2 both lieutenants are loyal and relay honestly, but each ends up with a tie, follows the commander, and they disagree.

#### Why can a lieutenant not tell the two situations apart?
From a lieutenant's point of view, both situations look exactly the same. In run 2, L1 receives "attack" from the commander and "retreat" from L2. This happens if the commander is a traitor and told L2 something different, but it would look identical if the commander were loyal and L2 were the traitor lying in its relay. Since L1 receives the same input in both cases, it must make the same decision. To keep validity when the commander is loyal, it has to follow the commander, and by symmetry L2 does the same, so with a traitor commander the loyal lieutenants disagree. With only two values there is no majority to break the tie.


### 3.3 Four nodes

| Run | Traitor | L1 | L2 | L3 | Agreement |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 3 | none | `[attack, attack, attack]` → attack | `[attack, attack, attack]` → attack | `[attack, attack, attack]` → attack | yes |
| 4 | commander (L2: retreat, others: attack) | `[attack, retreat, attack]` → attack | `[retreat, attack, attack]` → attack | `[attack, attack, retreat]` → attack | yes |
| 5 | L3 (relays retreat) | `[attack, retreat, attack]` → attack | `[attack, retreat, attack]` → attack | (traitor) | yes |

In run 4, L2 was told "retreat" by the commmander but decides "attack" because the two relays outvote the order it received itself. In all runs the loyal lieutenants agree.

### 3.4 Questions

#### Why does majority voting succeed with three lieutenants but fail with only two?
With two lieutenants, each one holds only two values, so if they differ there is nom majority, only a 50:50 tie, and the lieutenant cannot know which source lied. With three lieutenants, each one holds three vlues and a single traitor can falsify at most one of them. If the commander is the traitor, all lieutenants are loyal and relay honestly, so every lieutenant voles over the same set of values and reaches the same majority (run 4). If a lieutenantis the traitor, each loyal lieutenant holds two correct values and one false one, so the correct order wins (run 5). 

#### What does the commander provide that makes agreement possible with four nodes, and why does the problem become harder when all nodes are equal?
The commander acts as a central coordinator: it provides one single proposed value, and every node knows in advance who proposes and who has to agree. The lieutenants only need to agree on what the commander said. In a fully decentralised mesh like in Task 1 and 2, every node is equal and has its own value, so the nodes would first have to agree on whose value counts, for example by electing a leader. But leader election is itself an agreement problem, and a traitor can take part in it. In our implementation, the role is also only a claim in the key `byz/alive/<role>/<name>`, so a traitor could even pretend to be the commander.

#### Your four-node implementation guarantees agreement, but can it identify which node is the traitor?
Not in general. A loyal lieutenant can observe the order it received from the commanderand the values other lieutenants claim to have received. It can't observe what the commander actually sent to others. In run 4, L1 sees "L2 says retreat": either L2 is lying or the commnder told L2 to retread. Both look the same to L1. Only L2 could conclude osmething in that run: both other lieutenants contradict its order, and since there is at most one traitor, the commander must be lying. Agreement does not require identifying the traitor because the majority simply outvotes it. 

#### How could nodes communicate in such cases in practice? Investigate whether the middleware you selected offers such a feature.
Without multicast, nodes need at least one known entry point. In Zenoh, a node can be configured with `connect` endpoints (e.g. `tcp/<ip>:7447`) to connect directly to a known peer or to a Zenoh router (`zenohd`), which forwards traffic between nodes. Once connected, Zenoh's gossip scouting lets peers share the peers they know, so not every node needs to know every address. 