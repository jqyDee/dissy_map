import argparse, zenoh, time

#read the node's name from the command line
parser = argparse.ArgumentParser(description="choose a name for a node")
parser.add_argument("--name", required=True, help="name of a node")
args = parser.parse_args()

# open a Zenoh session in peer mode -> starts scounting and connects to other peers 
session = zenoh.open(zenoh.Config());
name = args.name

# here we declare a liveliness token with a name passed as command args for as long as the program runs
token = session.liveliness().declare_token("node/" + name)

# set of names of the nodes we see incl. ourselves
peers = set()

# callback for liveliness changes, called by Zenoh in a background thread
def on_liveliness(sample):
    peer_name = str(sample.key_expr).split("/")[-1]
    if sample.kind == zenoh.SampleKind.PUT:
        peers.add(peer_name)
        print(f"Alive token ('{sample.key_expr}') name: '{peer_name}'")
    elif sample.kind == zenoh.SampleKind.DELETE:
        peers.discard(peer_name)
        print(f"Dropped token ('{sample.key_expr}')")

# listen to everyone's liveliness tokens; history=True gives us nodes that were running before we started
liveliness_subscriber = session.liveliness().declare_subscriber("node/*", on_liveliness, history=True)


# main loop print our name and who we see every 2s, callback updates peers in the backgrouns
try :
    while(True):
        print("your name is:", name)
        print("peers: ", peers)
        time.sleep(2)

# to close the session cleanely, token disappears and the others know we left
except KeyboardInterrupt:
    print("\nbye bye")
    session.close()
