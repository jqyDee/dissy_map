import argparse, zenoh, time

# cmmand line arguments: name, role, traitor flag, numebr of lieutenants, order (used by commander)
parser = argparse.ArgumentParser(description="Byzantine node")
parser.add_argument("--name", required=True, help="name of a node")
parser.add_argument("--role", required=True, choices=["commander", "lieutenant"])
parser.add_argument("--traitor", action="store_true")
parser.add_argument("--lieutenants", type=int, default=2)
parser.add_argument("--order", choices=["attack", "retreat"], default="attack")
args = parser.parse_args()

name = args.name

# a traitor uses this to lie: attack <-> retread
def flip(order):
    if(order == "attack"):
        return "retreat"
    else:
        return"attack"

session = zenoh.open(zenoh.Config());

# lieutenant state: order receive directly from the commander. none for nothing yet
from_commander = None
# lieutenant state: relayed orders form the other lieutenants, sender -> value
relays = {}

# names of all lieutenants that are ready including ourselves if we're lieutenant
ready_lieutenants = set()

# callback for liveliness changes, called by Zenoh in a background thread
def on_liveliness(sample):
    peer_name = str(sample.key_expr).split("/")[-1]
    if sample.kind == zenoh.SampleKind.PUT:
        ready_lieutenants.add(peer_name)
        print(f"Alive token ('{sample.key_expr}') name: '{peer_name}'")
    elif sample.kind == zenoh.SampleKind.DELETE:
        ready_lieutenants.discard(peer_name)
        print(f"Dropped token ('{sample.key_expr}')")

# only watch lieutenats tokens: the commander needs to know when all are ready, lieutenants need to know whom to relay to
liveliness_subscriber = session.liveliness().declare_subscriber("byz/alive/lieutenant/*", on_liveliness, history=True)

# callback for inbox. sender = last part of the key, payload = "order:x" or "relay:x"
def on_message(sample):
    #global because we assign new values to these inside the function 
    global from_commander, start
    sender = str(sample.key_expr).split("/")[-1]
    text = sample.payload.to_string()
    kind, value = text.split(":")
    print(sender, kind, value)

    if kind == "order":
        from_commander = value
        # start the decision timer when the order arrives
        start = time.time()
    elif kind == "relay":
        relays[sender] = value

# our inbox: everyone sends to byz/inbox/<our name>/<their name>
inbox_subscriber = session.declare_subscriber("byz/inbox/" + name + "/*", on_message)
# im ready, declared only after the inbox exists so no order gets lost 
token = session.liveliness().declare_token("byz/alive/" + args.role + "/" + args.name)

#flags so each step happens once
sent = False
relayed = False 
decided = False 
# initial timer value, resets when the order arrives 
start = time.time()
try:
    while(True):
        #round 1: commander sends its order once all lieutenants are ready
        if(args.role == "commander") and not sent and len(ready_lieutenants) == args.lieutenants:
                # sorted to fix order so that a traitor commander sends the opposite order to every second lieutenant
                for i, l in enumerate(sorted(ready_lieutenants)):
                    if args.traitor and i % 2 == 1:
                        value = flip(args.order)
                    else:
                        value = args.order
                    session.put("byz/inbox/" + l + "/" + name, "order:" + value)
                sent = True
        # round 2: each lieutenant forwards what it received to other lieutenants
        if(args.role == "lieutenant") and from_commander is not None and not relayed and len(ready_lieutenants) == args.lieutenants:
            for l in sorted(ready_lieutenants):
                # do not relay to ourselves
                if l == name:
                    continue
                # a traitor lieutenant relays the opposite of what it received
                if args.traitor == True:
                    value = flip(from_commander)
                else:
                    value = from_commander
                session.put("byz/inbox/" + l + "/" + name, "relay:" + value)
            relayed = True
        # decision: majority over the commander's order + all relays (or timeout)
        # give up waiting for relays 15s after receiving the order 
        waited_too_long = time.time() - start > 15 
        if args.role == "lieutenant" and from_commander is not None and not decided and (len(relays) == args.lieutenants - 1 or waited_too_long):
            votes = [from_commander] + list(relays.values())
            attacks = votes.count("attack")
            if attacks * 2 > len(votes):
                decision = "attack"
            elif attacks * 2 < len(votes):
                decision = "retreat"
            else:
                # tie (only possible with 2 lieutenants) -> follow the commander
                decision = from_commander
            print("Decision:" , decision, "votes:", votes)
            decided = True

        
        print(name)
        print("ready lieutenants : ", ready_lieutenants)
        time.sleep(2)
# to close the session cleanely, token disappears and the others know we left
except KeyboardInterrupt:
    print("\nbye bye")
    session.close()