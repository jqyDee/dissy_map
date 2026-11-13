import argparse, zenoh, time, threading, json, random


# parsing the command line argument:
parser = argparse.ArgumentParser(description="choose a name for the node")
parser.add_argument("--name", required=True, help="name of a node")
args = parser.parse_args()
name = args.name


# configuration
CLUSTER_SIZE = 3 # fixed number of nodes in the cluster
MAJORITY = CLUSTER_SIZE // 2 + 1 # votes needed to vin, based on the fixed size
TIMEOUT_MIN = 0.15
TIMEOUT_MAX = 0.30
HEARTBEAT_INTERVAL = 0.05 # have to multiply all by 10 while testing othewise too fast

# opening zenoh session:
session = zenoh.open(zenoh.Config());
publisher = session.declare_publisher("raft/msg")

def send(msg):
    # broadcast a message (dict) to all nodes as JSON text
    publisher.put(json.dumps(msg))

# node state 
# sjared between the mein loop and the Zenoh callback thread -> every read and write with lock.
lock = threading.Lock()

role = "follower"
current_term = 0
voted_for = None

leader = None # leader i currently follow, used for logging :)
votes = set() # who voted for me, only to use by a candidate
last_heard = time.monotonic() # last time i heard from a leader / granted a vote
timeout = random.uniform(TIMEOUT_MIN, TIMEOUT_MAX) # my current random election timeout

def reset_timer():
    # restart the election timer with a new random timeout
    # called when a valid heartbeat arrives, i grant a vote, i start anelection
    global last_heard, timeout
    last_heard = time.monotonic()
    timeout = random.uniform(TIMEOUT_MIN, TIMEOUT_MAX)


# all the message handlers that zenoh calls from background thread 
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

def on_vote_reply(msg):
    global current_term, voted_for, role
    with lock:
        #  ignore replies not addressed to me
        if msg["to"] != name:
            return

         #  higher-term rule (as in on_request_vote)
        if msg["term"] > current_term:
                print(f"[{name}] saw term {msg['term']} > my term {current_term} -> follower")
                current_term = msg["term"]
                voted_for = None
                role = "follower"

        # only counts if im still a candidate, its for this term and its a yes
        if role == "candidate" and msg["term"] == current_term and msg["granted"]:
            votes.add(msg["from"])
            #  majority reacher -> im a "leader" of this term
            if len(votes) >= MAJORITY:
                    role = "leader"
                    print(f"[{name}]: I am a leader of the term {current_term}")

        
    

def on_heartbeat(msg):
    # hello im the leader of this term do not start an election
    global current_term, voted_for, role, leader
    with lock:
        # heartbeat form an old leader -> ignore
        if msg["term"] < current_term:
            return
        # higher term -> take over, forget voted for, role is follower and reset timer 
        if msg["term"] > current_term:
                print(f"[{name}] saw term {msg['term']} > my term {current_term} -> follower")
                current_term = msg["term"]
                voted_for = None

        # same or higher term - a valid leader exists -> 
        # become or stay follower and reset the timer
        role = "follower"
        reset_timer()

        # log only when the leader changes
        if msg["leader"] != leader:
            leader = msg["leader"]
            print(f"[{name}] following leader {leader} in term {current_term}")
            



def on_message(sample):
    # zenoh callback for every message on raft/msg. decode and dispatch by type
    msg = json.loads(sample.payload.to_string()) # JSON text -> dict 
    if msg["from"] == name: # ignoring on my own message
        return 
    if msg["type"] == "RequestVote":
        on_request_vote(msg)
    elif msg["type"] == "VoteReply":
        on_vote_reply(msg)
    elif msg["type"] == "Heartbeat":
        on_heartbeat(msg)

# subscribe to the shared key 
subscriber = session.declare_subscriber("raft/msg", on_message)


# starting an election

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



# main loop
last_heartbeat_sent = 0 
print(f"[{name}] started as follower")

try: 
    while True:
        now = time.monotonic()

        # read the shared state once under the lock, then act on the copies
        with lock:
            r = role
            term = current_term
            expired = now - last_heard > timeout

        # follower / candidate: no heartbeat (or vote) for too long -> start an election
        if r != "leader" and expired:
            start_election()


        # leader:send a heartbeat every HEARTBEAT_INTERVAL to keep followers from timing out
        if r == "leader" and now - last_heartbeat_sent >= HEARTBEAT_INTERVAL:
            send({"type": "Heartbeat", "term": term, "from": name, "leader": name})
            last_heartbeat_sent = now 
        time.sleep(0.01) #check again in 10ms

# and to remove yourself :)
except KeyboardInterrupt:
    print("\nbye bye")
    session.close()

