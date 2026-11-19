import json, argparse, time
from kazoo.client import KazooClient
from kazoo.exceptions import NodeExistsError, BadVersionError, ConnectionLoss, SessionExpiredError



def bid(bidder_id, amount):
    if not zk.connected:
        print("rejected: not connected to ZooKeeper")
        return
    try: 
        while True: 
            data, stat = zk.get("/auction")
            state = json.loads(data.decode())

            if state["open"] == False:
                print("rejected: the auction is not open")
                return
            if state["highest_bid"] >= amount:
                print("rejected: already accepted higher bid")
                return

            new_bytes = {
                "open": True,
                "highest_bid": amount,
                "bidder_id": bidder_id
            }
            time.sleep(args.delay)
            try:
                zk.set("/auction", json.dumps(new_bytes).encode(), version=stat.version)
                print("bid accepted")
                return
            except BadVersionError:
                print("conflict, retrying")
    except (ConnectionLoss, SessionExpiredError):
        print("rejected: lost connection to Zookeeper")

def query():
    try: 
        data, stat = zk.get("/auction")
        state = json.loads(data.decode())

        if state["bidder_id"] is not None: 
            print(f"highest bid: {state['highest_bid']} by {state['bidder_id']}")
        else:
            print("no bids yet")
    except (ConnectionLoss, SessionExpiredError):
        print("rejected: lost connection to Zookeeper")

def close():
    if not zk.connected:
        print("rejected: not connected to ZooKeeper")
        return
    try: 
        while True: 
            data, stat = zk.get("/auction")
            state = json.loads(data.decode())
        
            if state["open"] == False:
                print("rejected: the auction is already closed")
                return
        
            new_bytes = {
                "open": False,
                "highest_bid": state["highest_bid"],
                "bidder_id": state["bidder_id"]
                }
            time.sleep(args.delay)
            try: 
                zk.set("/auction", json.dumps(new_bytes).encode(), version=stat.version)
                if state["bidder_id"] is not None:
                    print(f"bidder {state['bidder_id']} won with the bid of {state['highest_bid']}")
                else: 
                    print("no winner, nobody bid")
                return

            except BadVersionError:
                print("conflict, retrying")
    except(ConnectionLoss, SessionExpiredError):
        print("rejected: lost connection to Zookeeper")
    

        

if __name__ == "__main__":
    # parsing the command line argument:
    parser = argparse.ArgumentParser(description="choose a name for the node")
    parser.add_argument("--name", required=True, help="name of a node")
    parser.add_argument("--zk", default="127.0.0.1:2181", help="ZooKeeper address host:port")
    parser.add_argument("--delay", type=float, default=0)
    args = parser.parse_args()
    name = args.name

    zk = KazooClient(hosts=args.zk)
    zk.start()
    state = {
        "open": True,
        "highest_bid": 0,
        "bidder_id": None
    }

    try: 
        zk.create("/auction", json.dumps(state).encode())
    except NodeExistsError:
        pass # auction already exists do not reset
    try: 
        zk.create(f"/nodes/{name}", ephemeral=True, makepath=True)
    except NodeExistsError:
        print(f"a node named {name} is already registered (old session not expired yet?)")

    @zk.DataWatch("/auction")
    def on_change(data, stat):
        if data == None:
            print("auction deleted")
            return 
        
        state = json.loads(data.decode())
        print(f"[update v{stat.version}] highest bid: {state['highest_bid']} by {state['bidder_id']}")
        if state["open"] == False:
            print("auction closed")

    
    while True:
        try:
            cmd = input(f"[{name}]> ").split()
        except (EOFError, KeyboardInterrupt):
            break
        if not cmd: 
            continue  
        elif cmd[0] == "query":
            query()
        elif cmd[0] == "bid":
            try:
                bid(cmd[1], int(cmd[2]))
            except (IndexError, ValueError):
                print("usage: bid <name> <amount>")
        elif cmd[0] == "close":
            close()
        elif cmd[0] == "exit":
            break
        elif cmd[0] == "reset":
            if not zk.connected:
                print("rejected: not connected to ZooKeeper")
                continue
            try: 
                zk.delete("/auction")
                zk.create("/auction", json.dumps(state).encode()) 
            except(ConnectionLoss, SessionExpiredError):
                print("rejected: lost connection to Zookeeper")

        elif cmd[0] == "nodes":
            print(zk.get_children("/nodes"))
        else:
            print("unknown command")

    zk.stop()