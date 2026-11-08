import argparse, zenoh, time, threading, json, random


# parsing the argument
parser = argparse.ArgumentParser(description="choose a name for the node")
parser.add_argument("--name", required=True, help="name of a node")
args = parser.parse_args()
name = args.name


CLUSTER_SIZE = 3
MAJORITY = CLUSTER_SIZE // 2 + 1
TIMEOUT_MIN = 0.15
TIMEOUT_MAX = 0.30
HEARTBEAT_INTERVAL = 0.05 # have to multiply all by 10 while testing othewist too fast
# opening zenoh session:
session = zenoh.open(zenoh.Config());
publisher = session.declare_publisher("raft/msg")

def send(msg):
    publisher.put(json.dumps(msg))

# lock and state variables
lock = threading.Lock()

role = "follower"
current_term = 0
voted_for = None
votes = set() # who voted for me, only to use by a candidate
last_heard = time.monotonic()
timeout = random.uniform(TIMEOUT_MIN, TIMEOUT_MAX)

def reset_timer():
    global last_heard, timeout
    last_heard = time.monotonic()
    timeout = random.uniform(TIMEOUT_MIN, TIMEOUT_MAX)


def on_request_vote(msg):
    global current_term, voted_for, role
    with lock:
        if msg["term"] > current_term:
            current_term = msg["term"]
            voted_for = None
            role = "follower"
        

        granted = (msg["term"] == current_term) and (voted_for == None or voted_for == msg["candidate"])
        
        if granted: 
            voted_for = msg["candidate"]
            reset_timer()
    
        reply = {"type": "VoteReply", "term": current_term, "from" : name, "to": msg["candidate"], "granted": granted}
        print(f"[{name}] term{reply['term']}: vote for {msg['candidate']}? {granted}") 
    send(reply)

def on_vote_reply(msg):
    global current_term, voted_for, role
    with lock:
        # TODO 1. reply not addressed to me? -> return 
        # TODO 2. higher-term rule (as in on_request_vote)
        # TODO 3. only ocunts if im still a candidate and msg["term"] is current_term and is granded -> votes.add(msg["from"])
        # TODO 4. length of votes >= majority -> role = "leader" blah blah
        pass 

def on_heartbeat(msg):
    global current_term, voted_for, role
    with lock:
        # TODO 5. message term < current term -> bad bad, return 
        #TODO 6. higher term -> take over, voted for is none, role is follower and reset timer 
        pass

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

subscriber = session.declare_subscriber("raft/msg", on_message)

# starting an election

def start_election():
    global current_term, voted_for, role, votes
    with lock:
        # TODO become candidate, current term + 1 vote for myself reset times
        msg = {"type": "RequestVote", "term": current_term, "from": name, "candidate": name}
    send(msg)


last_heartbeat_sent = 0 
print(f"[{name}] started as follower")

try: 
    while True:
        now = time.monotonic()
        with lock:
            r = role
            term = current_term
            expired = now - last_heard > timeout
        if r != "leader" and expired:
            start_election()

        if r == "leader" and now - last_heartbeat_sent >= HEARTBEAT_INTERVAL:
            send({"type": "Heartbeat", "term": term, "from": name, "leader": name})
            last_heartbeat_sent = now 
        time.sleep(0.01)
except KeyboardInterrupt:
    print("\nbye bye")
    session.close()

