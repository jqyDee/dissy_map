# EX0X Report: [Exercise Title]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Task 1 - [Discovering peers]

**1.1**

I chose to implement this task in Rust using Zenoh in its default peer mode. Each node takes a unique name via the command line argument --name. Neither code nor configuration need to contain any addresses.

Since Zenoh is asynchronous, we need a runtime, Tokio for rust.
We open a new zenoh session with the default config. The default config means following things:
- session runs in peer mode
- process listens on a random TCP port
- process sends scouting messages to the UDP multicast group `224.0.0.224:7446` with a TTL of 1, meaning those messages never leave the local network.
- Peers who receive the scouting message answer with a hello message back to the address where the packet came from. They include their own address and tcp port they are listening on and the peer-peer transport session can be established that way

```
let session = zenoh::open(zenoh::Config::default()).await?;
    let own_id = session.info().zid().await;
    println!("[{}] started as {own_id}", args.name);
```

So those three lines using Zenoh do a lot of heavy lifting for us.

Inside this session struct, we can find the processes own ZenohId, via session.info().zid()

```
let _token = session
        .liveliness()
        .declare_token(format!("{NODES_PREFIX}/{}", args.name))
        .await?;
```

Next we create a liveliness token. The _ infront of the variable name is used to supress a compiler warning that states, that this variable is not actually used. But why do we need it then?
The existence of this token is the important part, because again Zenoh does a lot of work in the background. Upon dropping the token, because of a SIGINT that causes main() to return for example, the node undeclares its token to its peers, so they know the connection ends.

We now know all of our peers by their ZenohID, but task 1 asks that each peer should identify itself with a unique name. This code snippet comes into play:

```
let subscriber = session
        .liveliness()
        .declare_subscriber(format!("{NODES_PREFIX}/*"))
        .history(true)
        .await?;
```

`session.liveliness()` contains all peers for whom a liveliness token currently exists and thus a connection is established. 
`.declare_subscriber(format!("{NODES_PREFIX}/*"))` subsribes to join/leave events of all nodes that share the prefix we established at the top of the program with `const NODES_PREFIX: &str = "dissy/ex3/nodes";`
`.history(true)`lets a node see join/leave events that happened before its own connection was established
`.await?;` deals with the async nature of the code.

We use a BTreeSet to store alive connections and a tokio interval `report` to periodically display information about the discovered peers. This interval can be set as an command line argument and otherwise defaults to 2 seconds:

```
let mut alive = BTreeSet::new();
let mut report = tokio::time::interval(Duration::from_secs(args.interval));
```

inside a rust `loop`, that only ends through a sigint, we handle and update the current connections:

```
loop {
        tokio::select! {
            sample = token_subscriber.recv_async() => {
                let token_sample = token_sample?;
                let name = token_sample.key_expr().as_str().rsplit('/').next().unwrap_or_default();
                if name == args.name {
                    continue;
                }
                match token_sample.kind() {
                    SampleKind::Put => {
                        println!("[{}] JOIN  {name}", args.name);
                        alive.insert(name.to_string());
                    }
                    SampleKind::Delete => {
                        println!("[{}] LEAVE {name}", args.name);
                        alive.remove(name);
                    }
                }
            }
            _ = report.tick() => {
                // Two views: names claimed by the application, and the sessions
                // the transport layer is really connected to.
                let sessions: Vec<_> = session.info().peers_zid().await.collect();
                println!(
                    "[{}] peers: {alive:?} | {} transport sessions: {sessions:?}",
                    args.name,
                    sessions.len(),
                );
            }
            _ = tokio::signal::ctrl_c() => break,
        }
    }
```

The `tokio::select!` macro lets us wait for three different events (`subscriber.recv_async()`, `report.tick()`, `tokio::signal::ctrl_c()`) concurrently and executes the code block of which ever one happens first.

If a sample of a peer is received, we split its key to check if its name is our own, if so we just continue. If not we do a pattern matching on wether it is a join or a leave event and print that information together with the peers name.

Every 2 seconds (`report.tick()`) we print the available peers and the corresponding transport session (one per p2p connection, eg A - B and A - C are two transport sessions).

We run the program in three terminals:

- `./target/debug/node --name A`
- `./target/debug/node --name B`
- `./target/debug/node --name C`

**Output in terminal A:**

```
[A] started as 69b96384d60ae1206698082623633653
[A] peers: {} | 0 transport sessions: []
[A] JOIN  B
[A] peers: {"B"} | 1 transport sessions: [755092d569a8b2481b0fd124d5e0cdc3]
[A] JOIN  C
[A] peers: {"B", "C"} | 2 transport sessions: [5e021fba91970cc04f2a2a80a3eb6358, 755092d569a8b2481b0fd124d5e0cdc3]
[A] peers: {"B", "C"} | 2 transport sessions: [5e021fba91970cc04f2a2a80a3eb6358, 755092d569a8b2481b0fd124d5e0cdc3]
```

**Output in terminal B:**
```
[B] started as 755092d569a8b2481b0fd124d5e0cdc3
[B] JOIN  A
[B] peers: {"A"} | 1 transport sessions: [69b96384d60ae1206698082623633653]
[B] JOIN  C
[B] peers: {"A", "C"} | 2 transport sessions: [5e021fba91970cc04f2a2a80a3eb6358, 69b96384d60ae1206698082623633653]
[B] peers: {"A", "C"} | 2 transport sessions: [5e021fba91970cc04f2a2a80a3eb6358, 69b96384d60ae1206698082623633653]
```

**Output in terminal C:**

```
[C] started as 5e021fba91970cc04f2a2a80a3eb6358
[C] JOIN  B
[C] peers: {"B"} | 1 transport sessions: [755092d569a8b2481b0fd124d5e0cdc3]
[C] JOIN  A
[C] peers: {"A", "B"} | 2 transport sessions: [755092d569a8b2481b0fd124d5e0cdc3, 69b96384d60ae1206698082623633653]
[C] peers: {"A", "B"} | 2 transport sessions: [755092d569a8b2481b0fd124d5e0cdc3, 69b96384d60ae1206698082623633653]
```

We can see that even tho we started node C last, it contains the samples `JOIN B` and `JOIN A`. This is because of `.history(true)` that we mentioned.


**1.2**

After having started all nodes, we stop node B, wait a few seconds, and then start it again. This is what A and C observe:

**Output in terminal A:**

```
[A] peers: {"B", "C"} | 2 transport sessions: [2e4ff3bcf79610917b055589f1d90a3d, db2ed97ec527fb2f2d20cbfef0cd0438]
[A] LEAVE B
[A] peers: {"C"} | 1 transport sessions: [2e4ff3bcf79610917b055589f1d90a3d]
[A] peers: {"C"} | 1 transport sessions: [2e4ff3bcf79610917b055589f1d90a3d]
[A] peers: {"C"} | 1 transport sessions: [2e4ff3bcf79610917b055589f1d90a3d]
[A] peers: {"C"} | 1 transport sessions: [2e4ff3bcf79610917b055589f1d90a3d]
[A] JOIN  B
[A] peers: {"B", "C"} | 2 transport sessions: [2e4ff3bcf79610917b055589f1d90a3d, 280354b3a0a14a5377eb49b186bbbc6c]
```

**Output in terminal C:**

```
[C] peers: {"A", "B"} | 2 transport sessions: [db2ed97ec527fb2f2d20cbfef0cd0438, fb3bb3fce5d84ddbe1cfd86c4147f7d4]
[C] LEAVE B
[C] peers: {"A"} | 1 transport sessions: [fb3bb3fce5d84ddbe1cfd86c4147f7d4]
[C] peers: {"A"} | 1 transport sessions: [fb3bb3fce5d84ddbe1cfd86c4147f7d4]
[C] peers: {"A"} | 1 transport sessions: [fb3bb3fce5d84ddbe1cfd86c4147f7d4]
[C] JOIN  B
[C] peers: {"A", "B"} | 2 transport sessions: [280354b3a0a14a5377eb49b186bbbc6c, fb3bb3fce5d84ddbe1cfd86c4147f7d4]
```

In both cases we can see the `LEAVE B` and `JOIN B` samples that are send when B's liveliness token is created/deconstructed. Inbetween A and C only list each other as peers and only have 1 transport session.

> **How does a node learn that another node is available?**

Zenoh finds other nodes through multicast scouting. A new node sends a scouting message to `224.0.0.224:7446` and receiving nodes answer with their address. A TCP connection can now be established and the node can learn about other nodes in the network through gossip.
Only the ZID (ZenohID) and IP/Port are known, learning about the unique names we assigned happens through the liveliness tokens.

> **What happens when Node B leaves, and what happens when it joins again?**

When node B leaves its token ceases to exist and A and C receive the "Leave" event.
When node B rejoins a new token is created and A and C receive the "Join" event

> **Your discovery mechanism tells you a node is reachable. Can you trust that a discovered node is who
it claims to be, or that its messages are truthful?**

No, we cannot trust in that. I started node A, then node B and then another node B. When starting a second node calling itself B A didn't notice anything. Also when now terminating the original node B, node A still doesn't notice anything. No "Leave" event is received, because it is still connected to another node, claiming to be B. Only after also terminating this node, node A will say that B left.
In our programm we just know, that there is some process running and that it is claiming a certain name.

---

## Task 2 - [Exchange messages between peers]

## 2.1

For our publish/subscribe mechanism we use the shared key expression `const HELLO_TOPIC: &str = "dissy/ex3/hello";`
Each node will later publish messages under `"dissy/ex3/hello/{NODE_NAME}"`.
First we use the already established Zenoh-Session and build
- a publisher:
```
//task 2 message publisher
let publisher = session
    .declare_publisher(format!("{HELLO_TOPIC}/{}", args.name))
    .await?;
```

- a subscriber:
```
//task 2 message subscriber
let message_subscriber = session
    .declare_subscriber(format!("{HELLO_TOPIC}/*"))
    .allowed_origin(Locality::Remote) //dont subscribe to your own messages!
    .await?;
```

We can see that the subscriber subscribes to all key expressions of the form "dissy/ex3/hello/{something}", which also includes its own. In order not to subscribe to its own messages we apply the function '.allowed_origin(Locality::Remote)' while building the subscriber.

To periodically publish messages I just reused the interval from task 1, so information about peers and messages will always be published together. If you don't want this to be the case you can create another tokio::time::interval and add another branch in the loop using the new timers .tick().

The hello message contains the nodes name and a counter of how many hellos have been sent so far:

```
//task 2, periodical hello
publisher.put(format!("Hello from Node {} #{}", args.name, seq))
    .await?;
seq += 1;
```

To receive messages we add another branch in our loop:
```
//branch task 2 where messages are received
message_sample = message_subscriber.recv_async() => {
    let message_sample = message_sample?;

    if message_sample.kind() != SampleKind::Put { continue; }

    let name_sender = message_sample.key_expr().as_str().rsplit('/').next().unwrap_or_default();
    let Ok(text) = message_sample.payload().try_to_string() else {
        eprintln!("[{}] non-UTF-8 payload from {name_sender}", args.name);
        continue;
    };
    println!("[{}] {} says: {}", args.name, name_sender, text);
}
```

When our message_subscriber receives a message this branch gets executed. 
`let message_sample = message_sample?;` is Rust syntax for unwrapping an Ok Result or else returning the error from main, ending the program.
We should only receive samples of kind SampleKind::Put, but incase a SampleKind::Delete message comes in we don't want to print anything, hence: `if message_sample.kind() != SampleKind::Put { continue; }`
To get the sender we use the line `let name_sender = message_sample.key_expr().as_str().rsplit('/').next().unwrap_or_default();`
`rsplit()` splits splits at every `/` and then reverses the tokens so we get the last part first, which is the senders node name.

As a demonstration we start nodes A and B, wait for a little bit and then start node C

**Output Node A**
```
/target/debug/node --name A
[A] started as 25127460d1bda2de0dc4c29af266999d
[A] JOIN  B
[A] peers: {"B"} | 1 transport sessions: [20fdef4ebfb8d08b6e18588cf2007bb0]
[A] B says: Hello from Node B #0
[A] peers: {"B"} | 1 transport sessions: [20fdef4ebfb8d08b6e18588cf2007bb0]
[A] B says: Hello from Node B #1
[A] peers: {"B"} | 1 transport sessions: [20fdef4ebfb8d08b6e18588cf2007bb0]
[A] B says: Hello from Node B #2
[A] JOIN  C
[A] C says: Hello from Node C #0
[A] peers: {"B", "C"} | 2 transport sessions: [59d64a3b59a140751c85e762b0c4a402, 20fdef4ebfb8d08b6e18588cf2007bb0]
[A] B says: Hello from Node B #3
[A] C says: Hello from Node C #1
[A] peers: {"B", "C"} | 2 transport sessions: [59d64a3b59a140751c85e762b0c4a402, 20fdef4ebfb8d08b6e18588cf2007bb0]
```

Node A receives 3 Hello's from B before C joins and also starts sending Hellos.

We skip Node B's output since it is very similar to this one.

**Output Node C**
```
./target/debug/node --name C
[C] started as 59d64a3b59a140751c85e762b0c4a402
[C] JOIN  B
[C] JOIN  A
[C] peers: {"A", "B"} | 2 transport sessions: [20fdef4ebfb8d08b6e18588cf2007bb0, 25127460d1bda2de0dc4c29af266999d]
[C] B says: Hello from Node B #3
[C] A says: Hello from Node A #3
[C] peers: {"A", "B"} | 2 transport sessions: [20fdef4ebfb8d08b6e18588cf2007bb0, 25127460d1bda2de0dc4c29af266999d]
[C] A says: Hello from Node A #4
[C] B says: Hello from Node B #4
[C] peers: {"A", "B"} | 2 transport sessions: [20fdef4ebfb8d08b6e18588cf2007bb0, 25127460d1bda2de0dc4c29af266999d]
[C] B says: Hello from Node B #5
[C] A says: Hello from Node A #5
```

Here we see that Node C didn't receive the first few messages from A and B. However it did receive the JOIN messages from A and B. This is because with the token_subsriber we used .history(true) and with the message_subscriber we didn't.

## 2.2

> What is the main difference between static configuration and dynamic discovery?

'static configuration': every node has addresses of the required peers pre configured and listens on a dedicated port. When new nodes are added or addresses change, the configurations of the nodes have to be changed, and the nodes possibly restarted.

'dynamic configuration': nodes find out each others addresses and ports during runtime. In our case using Zenoh, this happens scouting with multicast and gossip. Joining and leaving happens automatically wihtout needing to change configs. But also in our case this only works in the local network for now, within the multicasting range (TTL of 1) and anyone can join in.

> Why is the publish/subscribe pattern useful for communication between distributed processes?

Publishers can publish to a topic wihtout needing to know who will receive it. In the same way subscribers can subscribe to a topic without needing to know who sent it. This also means that to me as a publisher/subscriber it doesnt matter if more nodes join in or leave, since I dont have to change my behaviour.

> Is peer discovery sufficient to make an application fault-tolerant? Explain briefly.

No it is not. Peer discovery allows us to know which nodes are currently reachable, but when a node crashes and rejoins, the messages it missed inbetween are potentially lost, unless this fault-tolerance is explicetly implemented. The same logic applies to the messages the node would have sent during failure.
Also nodes can lie about their identity for example, easily taking someone elses name as we have seen previously in the report.

## Task 3 - [he Byzantine Generals Problem]

## 3.1

We build the program in such a way, that we don't have to change it for later tasks. Lieutenants and Commanders run the same binary, just with different command-line arguments and we can chose how many lieutenants we want to start up.

I will skip explaining parts of the code that were already explained or similar in task 1.

We use three key_expressions to exchange messages via a publish/subscribe mechanism in this task:

- `"dissy/ex3/bgp/nodes/<role>/<name>"`
For liveliness. Everyone subscribes. This was done in the beginning. I later realized that that no one actually needs to subscribe to `"dissy/ex3/bgp/nodes/commander/*"` but everyone subscribes to `"dissy/ex3/bgp/nodes/lieutenant/*"`

- `"dissy/ex3/bgp/order/<to>"`
the commander publishes his order here, the lieutenants subscribe to `"dissy/ex3/bgp/order/<their_own_name>"` each, to get their orders.

- `"dissy/ex3/bgp/relay/<from>/<to>"`
Each lieutenant publishes their order to `"dissy/ex3/bgp/relay/<their_own_name>/<iterate_through_every_peer_l_here>"`
Also each lieutenant subscribes to `"dissy/ex3/bgp/relay/*/<their_own_name>"` to receive relayed orders from either other peer lieutenant

We run the program with following flags (optional):
For lieutenants: `--name <name> --role lieutenant (--traitor) (--lieutenants <number of lieutenants if its not 2>)`
For commanders: `--name <name> --role commander (--traitor) --order <attack/retreat> (--lieutenants <number of lieutenants if its not 2>)`

## 3.2

We start three processes, one commander, two lieutenants, and none of them are traitors.

**Commander in Exp 1**
`./target/debug/byzantine_node --name C --role commander --order attack`

```
[C] role=commander traitor=false
[C] JOIN  L1
[C] JOIN  L2
[C] all lieutenants present: {"L1", "L2"}
[C] sent attack to L1
[C] sent attack to L2
```

Commander correctly waits for two lieutenants and then sends "attack" to both.

**Lieutenant 1 in Exp 1**
`./target/debug/byzantine_node --name L1 --role lieutenant`

```
[L1] role=lieutenant traitor=false
[L1] JOIN  L2
[L1] other lieutenants present: {"L2"}
[L1] received from commander: attack
[L1] forwarded attack to L2
[L1] received from L2: attack
[L1] DECISION: attack   (values: commander=attack, L2=attack)
```

L1 receives the order "attack" from C, forwards it to L2. L1 also receives "attack" from L2 and thus decides on "attack".

**Lieutenant 2 in Exp 1**
`./target/debug/byzantine_node --name L2 --role lieutenant`

```
[L2] role=lieutenant traitor=false
[L2] JOIN  L1
[L2] other lieutenants present: {"L1"}
[L2] received from commander: attack
[L2] forwarded attack to L1
[L2] received from L1: attack
[L2] DECISION: attack   (values: commander=attack, L1=attack)
```

L2 receives "attack" from both C and L1, L2 forwards "attack" to L1 and also decides on "attack"

Now we run the same experiment, but the commander is a traitor, who sends "retreat" to one and "attack" to the other L.

**Commander in Exp 2**
`./target/debug/byzantine_node --name C --role commander --traitor --order attack`

```
[C] role=commander traitor=true
[C] JOIN  L1
[C] JOIN  L2
[C] all lieutenants present: {"L1", "L2"}
[C] sent attack to L1
[C] sent retreat to L2
```

This time we see `traitor=true` for the commander and therefore `[C] sent attack to L1` and `[C] sent retreat to L2`. We will see how the Lieutenants react to that.

**Lieutenant 1 in Exp 2**
`./target/debug/byzantine_node --name L1 --role lieutenant`

```
[L1] role=lieutenant traitor=false
[L1] JOIN  L2
[L1] other lieutenants present: {"L2"}
[L1] received from commander: attack
[L1] forwarded attack to L2
[L1] received from L2: retreat
[L1] DECISION: attack   (values: commander=attack, L2=retreat)
```

We see `[L1] received from commander: attack` but also `[L1] received from L2: retreat`, so conflicting information. Already it is impossible for L1 to satisfy both properties **Agreement** and **Validity**, but lets look at L2 as well

**Lieutenant 2 in Exp 2**
`./target/debug/byzantine_node --name L2 --role lieutenant`

```
[L2] role=lieutenant traitor=false
[L2] JOIN  L1
[L2] other lieutenants present: {"L1"}
[L2] received from commander: retreat
[L2] forwarded retreat to L1
[L2] received from L1: attack
[L2] DECISION: retreat   (values: commander=retreat, L1=attack)
```

Again we see the conflicting information, only flipped this time. To fulfill **Agreement**, one of the two Lietenants would have to change its mind, and therefore either communicate with the other further or follow a different rule set. Otherwise this property will not be satisfied.

## 3.3

Lets run the experiment with 4 nodes, 1 commander, three lieutenants. I will stop pasting the whole output to not make this report unnecessarily long.

- Exp 1: all loyal
- Exp 2: traitor commander
- Exp 3: one traitor lieutenant

**Commander in Exp 1**
`./target/debug/byzantine_node --name L3 --role lieutenant --lieutenants 3`

```
[C] sent attack to L1
[C] sent attack to L2
[C] sent attack to L3
```

Same order to every lieutenant.

**Lieutenant 1 in Exp 1**
`./target/debug/byzantine_node --name L1 --role lieutenant --lieutenants 3`

```
[L1] received from commander: attack
[L1] forwarded attack to L2
[L1] forwarded attack to L3
[L1] received from L2: attack
[L1] received from L3: attack
[L1] DECISION: attack   (values: commander=attack, L2=attack, L3=attack)
```

Received attack from C, forwarded attack to both other L's, received attack from both other L'2, decided on attack.

**Lieutenant 2 in Exp 1**
`./target/debug/byzantine_node --name L2 --role lieutenant --lieutenants 3`

```
[L2] received from commander: attack
[L2] forwarded attack to L1
[L2] forwarded attack to L3
[L2] received from L1: attack
[L2] received from L3: attack
[L2] DECISION: attack   (values: commander=attack, L1=attack, L3=attack)
```

Same for Lieutenant 2, nothing interesting to add.

**Lieutenant 3 in Exp 1**
`./target/debug/byzantine_node --name L3 --role lieutenant --lieutenants 3`

```
[L3] received from commander: attack
[L3] forwarded attack to L1
[L3] forwarded attack to L2
[L3] received from L1: attack
[L3] received from L2: attack
[L3] DECISION: attack   (values: commander=attack, L1=attack, L2=attack)
```

And with Lieutenant 3 also having decided on attack, all three Lieutenants agree in this experiment, as expected.

**Commander in Exp 2**
`./target/debug/byzantine_node --name C --role commander --traitor --order attack --lieutenants 3`

```
[C] sent attack to L1
[C] sent retreat to L2
[C] sent attack to L3
```

The commander now sends conflicting information.

**Lieutenant 1 in Exp 2**
`./target/debug/byzantine_node --name L1 --role lieutenant --lieutenants 3`

```
[L1] received from commander: attack
[L1] forwarded attack to L2
[L1] forwarded attack to L3
[L1] received from L2: retreat
[L1] received from L3: attack
[L1] DECISION: attack   (values: commander=attack, L2=retreat, L3=attack)
```

L1 receives attack from C and forwards that, but L1 receives both attack and receive from its peer lieutenants. majority vote lands on attack.

**Lieutenant 2 in Exp 2**
`./target/debug/byzantine_node --name L2 --role lieutenant --lieutenants 3`

```
[L2] received from commander: retreat
[L2] forwarded retreat to L1
[L2] forwarded retreat to L3
[L2] received from L1: attack
[L2] received from L3: attack
[L2] DECISION: attack   (values: commander=retreat, L1=attack, L3=attack)
```

L2 receives retreat from C and forwards that, but since both its peers forwarded attack, majority vote again lands on attack.

**Lieutenant 2 in Exp 2**
`./target/debug/byzantine_node --name L3 --role lieutenant --lieutenants 3`

```
[L3] received from commander: attack
[L3] forwarded attack to L1
[L3] forwarded attack to L2
[L3] received from L1: attack
[L3] received from L2: retreat
[L3] DECISION: attack   (values: commander=attack, L1=attack, L2=retreat)
```

L3 is the same as L1. We see that this time agreement is satisfied. 


Intersting observation:

```
let order = if args.traitor && i % 2 == 1 {
            base.opposite()
        } else {
            base
        };
```

Because of this snipped in my program, the commander send the actual order twice, and the opposite order just once. I ran the same experiment where I changed `if args.traitor && i % 2 == 1` to `if args.traitor && i % 2 == 0`, and nothing else, this time all lieutenants agree on retreat as opposed to attack. So agreement is still satisfied, even though they agree on the opposite order of what the commander actually got handed as an command-line argument.

**Experiment 3**
For this experiment we will chose L1 as the traitor, everyone else is loyal.

**Commander in Exp 3**
`./target/debug/byzantine_node --name C --role commander --order attack --lieutenants 3`
 Nothing interesting is happening here, C sends attack to L1, L2 and L3

**Lieutenant 1 in Exp 3**
`./target/debug/byzantine_node --name L1 --role lieutenant --traitor --lieutenants 3`

```
[L1] received from commander: attack
[L1] forwarded retreat to L2
[L1] forwarded retreat to L3
[L1] received from L3: attack
[L1] received from L2: attack
[L1] DECISION: attack   (values: commander=attack, L2=attack, L3=attack)   (traitor)
```

This is our traitor. He receives attack from C, but forwards retreat. He still decides on attack.

**Lieutenant 2 in Exp 3**
`./target/debug/byzantine_node --name L2 --role lieutenant --lieutenants 3`

```
[L2] received from commander: attack
[L2] forwarded attack to L1
[L2] forwarded attack to L3
[L2] received from L1: retreat
[L2] received from L3: attack
[L2] DECISION: attack   (values: commander=attack, L1=retreat, L3=attack)
```

L2 receives the incorrect order from the traitor L1, yet still decides on attack.

**Lieutenant 3 in Exp 3**
The same thing as for Lieutenant 2, L3 receives retreat from the traitor yet still decides on attack due to the majority vote.


**Conclusion**

When having 3 lieutenants, they always agree on the same thing, despite there being traitors.

## 3.4

> Why does majority voting succeed with three lieutenants but fail with only two?

When having two lieutentants, each one holds to orders. The commanders, and the relay of the other lieutenant. If they differ, there cannot be a rule or majority voting that leads to both lieutenants chosing the same thing.
When having three lieutenants each one holds three values. Two relays and the order of the commander. A traitor lieutenant can falsify only only one of the relays of the other lieutenants. This will not be enough to because they both still have two correct orders, so everyone agrees.
A traitor commander can send whatever he wants to whomever he wants, but because of the relays all lieutenants end up holding **exactly** the same three values, although from different sources, so again they will agree.

> In your implementation the commander is a designated, central node. Tasks 1–2, by contrast, built
a fully decentralized mesh without a coordinator. What does the commander provide that makes
agreement possible with four nodes, and why does the problem become harder when all nodes are
equal?

Our commander provides a single proposed value and acts as a fixed starting point. Everyone knows they are getting a value each from the same person, and they are then able to cross-check through the relay. 
When all nodes are equal there isn't one natural source, each node may have its own initial value, that they then have to relay but again traitors could lie here. You could try and turn a "all-nodes-are-equal" scenario into a "commander" scenario by electing a leader, but this again is an agreement problem.

> Your four-node implementation guarantees agreement, but can it identify which node is the traitor?
Explain what a loyal node can and cannot observe.

It cannot. It can only detect if a traitor was present or not.
If one node receives conflicting information e.g. L1 receives the following: `Commander says attack`, `L2 says attack`, `L3 says retreat`, there are now multiple possibilities for who the traitor could be. Either the commander is loyal and sent attack to everyone, than L3 would be the traitor. Or the commander is the traitor and sent attack to L1, attack to L2 and retreat to L3, there is no way to know since L1 doesnt actually know what the commander sent, L1 just know what its peers say the commander sent, which could into also be a lie.

> By default, nodes often use automatic multicast scouting to discover each other on a local network. In
restricted networks (or wide-area networks) where multicast is blocked. How could nodes communicate
in such cases in practice? Investigate whether the middleware you selected offers such a feature.

Zenoh offers static endpoints. That means I can configure a node with an addresses and ports of peers and it will be able to establish connections to those initial addresses. (works over TCP, UDP, QUIC among others). Only one node in a pair needs this configuration to establish a connection.

Let's say a node has a static endpoint configured using the address of a node that is already part of a wider peer to peer network, then through gossiping this initial node will learn of the entire network automatically as well.

There are Zenoh routers (zenohd), which can act as a single known entry point, over which peers can discover each other. After initial discovery this router can be bypassed again and traffic flows directly peer to peer.


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
