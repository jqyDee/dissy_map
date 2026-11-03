import argparse, zenoh, time

parser = argparse.ArgumentParser(description="choose a name for a node")
parser.add_argument("--name", required=True, help="name of a node")
args = parser.parse_args()


session = zenoh.open(zenoh.Config());
name = args.name

# here we declare a liveliness token with a name passed as command args
token = session.liveliness().declare_token("node/" + name)
peers = set()
def on_change(sample):
    peer_name = str(sample.key_expr).split("/")[-1]
    if sample.kind == zenoh.SampleKind.PUT:
        peers.add(peer_name)
        print(f"Alive token ('{sample.key_expr}') name: '{peer_name}'")
    elif sample.kind == zenoh.SampleKind.DELETE:
        peers.discard(peer_name)
        print(f"Dropped token ('{sample.key_expr}')")

#then we check if a liveliness token is present and subscribe to changes
subscriber = session.liveliness().declare_subscriber("node/*", on_change, history=True)



try :
    while(True):
        print("your name is:", name)
        print("peers: ", peers)
        time.sleep(2)
except KeyboardInterrupt:
    print("\nbye bye")
    session.close()
