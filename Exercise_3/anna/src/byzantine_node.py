import argparse, zenoh, time

parser = argparse.ArgumentParser(description="choose a name for a node")
parser.add_argument("--name", required=True, help="name of a node")
parser.add_argument("--role", required=True, choices=["commander", "lieutenant"])
parser.add_argument("--traitor", action="store_true")
parser.add_argument("--lieutenants", type=int, default=2)
parser.add_argument("--order", choices=["attack", "retreat"], default="attack")
args = parser.parse_args()

name = args.name


session = zenoh.open(zenoh.Config());
token = session.liveliness().declare_token("byz/alive/" + args.role + "/" + args.name)

ready_lieutenants = set()
def on_change(sample):
    peer_name = str(sample.key_expr).split("/")[-1]
    if sample.kind == zenoh.SampleKind.PUT:
        ready_lieutenants.add(peer_name)
        print(f"Alive token ('{sample.key_expr}') name: '{peer_name}'")
    elif sample.kind == zenoh.SampleKind.DELETE:
        ready_lieutenants.discard(peer_name)
        print(f"Dropped token ('{sample.key_expr}')")

subscriber = session.liveliness().declare_subscriber("byz/alive/lieutenant/*", on_change, history=True)


try:
    while(True):
        print(name)
        print("ready lieutenants : ", ready_lieutenants)
        time.sleep(5)
except KeyboardInterrupt:
    print("\nbye bye")
    session.close()