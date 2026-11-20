import json
import time
import uuid

from kazoo.exceptions import (
    BadVersionError,
    ConnectionLoss,
    NodeExistsError,
    RolledBackError,
    SessionExpiredError,
)

ROOT = "/auctions"


def state_path(aid: str):
    return f"{ROOT}/{aid}"


def log_path(aid: str):
    return f"{ROOT}/{aid}/log"


class NotConnected(Exception):
    """Raised instead of acting on stale local knowledge"""


def _enc(obj):
    return json.dumps(obj, sort_keys=True).encode()


def _commit(txn):
    results = txn.commit()
    for r in results:
        if isinstance(r, Exception) and not isinstance(r, RolledBackError):
            raise r
    return results


class Auction:
    def __init__(self, zk, aid, connected, node, delay=0.0, log=print):
        self.zk = zk
        self.aid = aid
        self.connected = connected
        self.node = node
        self.delay = delay
        self.log = log
        self.retries = 0

    def _require_connection(self):
        if not self.connected.is_set():
            raise NotConnected("no ZooKeeper session, refusing operation")

    def _pause(self, ver):
        if self.delay:
            self.log(f"[debug] read v{ver}, sleeping {self.delay}s before write")
            time.sleep(self.delay)

    def _append_log(self, txn, entry):
        entry = {**entry, "node": self.node, "t": time.time()}
        txn.create(log_path(self.aid) + "/op-", _enc(entry), sequence=True)

    def read(self):
        self._require_connection()
        data, stat = self.zk.get(state_path(self.aid))
        return json.loads(data), stat.version

    def history(self):
        p = log_path(self.aid)
        out = []
        for child in sorted(self.zk.get_children(p)):
            data, _ = self.zk.get(f"{p}/{child}")
            out.append(json.loads(data))
        return out

    def open(self, item):
        self._require_connection()
        state = {
            "auction_id": self.aid,
            "item": item,
            "status": "OPEN",
            "bidder": None,
            "amount": None,
            "bid_id": None,
            "winner": None,
        }
        txn = self.zk.transaction()
        txn.create(state_path(self.aid), _enc(state))
        txn.create(log_path(self.aid), b"")
        self._append_log(txn, {"op": "open", "item": item})
        try:
            _commit(txn)
            return True
        except NodeExistsError:
            return False

    def bid(self, bidder, amount, op_id=None):
        op_id = op_id or uuid.uuid4().hex
        while True:
            state, ver = self.read()

            if state["status"] != "OPEN":
                return False, f"rejected: auction closed, winner {state['winner']}"
            if state["amount"] is not None and amount <= state["amount"]:
                return (
                    False,
                    f"rejected: must exceed {state['amount']} ({state['bidder']})",
                )

            self._pause(ver)
            new = {**state, "bidder": bidder, "amount": amount, "bid_id": op_id}
            txn = self.zk.transaction()
            txn.set_data(state_path(self.aid), _enc(new), version=ver)
            self._append_log(
                txn,
                {
                    "op": "bid",
                    "op_id": op_id,
                    "bidder": bidder,
                    "amount": amount,
                },
            )

            try:
                self._require_connection()
                _commit(txn)
                return True, f"accepted (v{ver} -> v{ver + 1})"
            except BadVersionError:
                self.retries += 1
                self.log(
                    f"[cas] BadVersion on v{ver}: state changed concurrently, re-reading"
                )
            except (ConnectionLoss, SessionExpiredError) as e:
                return self._resolve_uncertain(op_id, e)

    def _resolve_uncertain(self, op_id, err):
        """The write may or may not have been applied. Find out from ZK, never guess."""
        self.log(f"[conn] {type(err).__name__} during write, outcome unknown")
        if not self.connected.wait(timeout=15):
            return None, "UNKNOWN: still disconnected, NOT claiming success"
        if any(e.get("op_id") == op_id for e in self.history()):
            return True, "accepted (confirmed from log after reconnect)"
        return False, "not applied (confirmed after reconnect), bid again if you want"

    def close(self):
        """Returns (winner_or_None, message). Idempotent: always returns THE result."""
        while True:
            state, ver = self.read()
            if state["status"] == "CLOSED":
                return state["winner"], "already closed, reporting existing result"

            self._pause(ver)
            winner = (
                {"bidder": state["bidder"], "amount": state["amount"]}
                if state["amount"] is not None
                else None
            )
            new = {**state, "status": "CLOSED", "winner": winner}
            txn = self.zk.transaction()
            txn.set_data(state_path(self.aid), _enc(new), version=ver)
            self._append_log(txn, {"op": "close", "winner": winner})
            try:
                self._require_connection()
                _commit(txn)
                return winner, "closed by this node"
            except BadVersionError:
                self.retries += 1
                self.log(f"[cas] BadVersion on v{ver} while closing, re-reading")
            except (ConnectionLoss, SessionExpiredError) as e:
                # Close is idempotent: after reconnecting, the loop re-reads and
                # either sees CLOSED (whoever did it) or tries again.
                self.log(
                    f"[conn] {type(e).__name__} during close, re-checking after reconnect"
                )
                if not self.connected.wait(timeout=15):
                    raise NotConnected("still disconnected, close outcome unknown")
