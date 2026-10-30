use core::fmt;
use std::{
    cmp::Ordering,
    collections::HashMap,
    time::{Duration, Instant},
};

use clap::ValueEnum;
use libp2p::{
    PeerId,
    gossipsub::{self, IdentTopic},
};
use serde::{Deserialize, Serialize};

use crate::node::{App, Node};

const DECIDE_TIMEOUT: Duration = Duration::from_secs(10);

/// role of the node
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ValueEnum)]
pub enum Role {
    Commander,
    Lieutenant,
}

/// order from the commander, or a "fake" order
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ValueEnum)]
pub enum Order {
    Attack,
    Retreat,
}

/// no sender field: the sender is the signed gossipsub source
#[derive(Debug, Serialize, Deserialize)]
pub enum ByzMsg {
    /// Round 1: commander -> Lieutenant
    Order(Order),
    /// Round 2: "the commander told me"
    Relay(Order),
}

impl Order {
    /// what a traitor sends
    pub fn flip(self) -> Self {
        match self {
            Order::Attack => Order::Retreat,
            Order::Retreat => Order::Attack,
        }
    }
}

impl fmt::Display for Order {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Order::Attack => write!(f, "attack"),
            Order::Retreat => write!(f, "retreat"),
        }
    }
}

/// state of one general
pub struct Byzantine {
    pub role: Role,
    pub traitor: bool,
    /// number of lieutenants in the run (2 or 3)
    pub lieutenants: usize,
    /// order a commander gives (ignored for lieutenants)
    pub order: Order,
    /// commander: orders have been sent
    sent: bool,
    /// lieutenant: order received directly from the commander
    pub from_commander: Option<Order>,
    /// lieutenant: own relay has been sent
    relayed: bool,
    /// lieutenant: values relayed by the other lieutenants
    pub relays: HashMap<PeerId, Order>,
    /// messages from peers whose role we do not know yet
    pending: Vec<(PeerId, ByzMsg)>,
    /// lieutenant: decide at the latest at this point
    deadline: Option<Instant>,
    pub decision: Option<Order>,
}

impl Byzantine {
    pub fn new(role: Role, traitor: bool, lieutenants: usize, order: Order) -> Self {
        Self {
            role,
            traitor,
            lieutenants,
            order,
            sent: false,
            from_commander: None,
            relayed: false,
            relays: HashMap::new(),
            pending: Vec::new(),
            deadline: None,
            decision: None,
        }
    }
}

impl Node {
    /// init the byzantine publish/subscribe protocol. this is basically
    /// subscribing to the protocol.
    pub(crate) fn byz_init(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        self.swarm
            .behaviour_mut()
            .gossipsub
            .subscribe(&inbox(&self.name))?;
        Ok(())
    }

    /// get the `Byzantine` state (machine)
    fn byz(&self) -> &Byzantine {
        match &self.app {
            App::Byzantine(b) => b,
            _ => unreachable!("byzantine handler called in another app"),
        }
    }

    /// get the `Byzantine` state (machine) as mutable
    fn byz_mut(&mut self) -> &mut Byzantine {
        match &mut self.app {
            App::Byzantine(b) => b,
            _ => unreachable!("byzantine handler called in another app"),
        }
    }

    ///
    pub(crate) fn byz_tick(&mut self) {
        self.byz_retry_pending();
        match self.byz().role {
            Role::Commander => self.commander_try_send(),
            Role::Lieutenant => {
                self.lieutenant_try_relay();
                self.lieutenant_try_decide();
            }
        }
    }

    /// get a list of all the names of the already ready/subscribed to the topic
    /// lieutenants.
    fn ready_lieutenants(&self) -> Vec<String> {
        let gossipsub = &self.swarm.behaviour().gossipsub;
        let mut ready: Vec<String> = self
            .roles
            .iter()
            .filter(|(_, role)| **role == Role::Lieutenant)
            .filter_map(|(peer, _)| {
                let name = self.names.get(peer)?;
                let topic = inbox(name).hash();
                let subscribed = gossipsub
                    .all_peers()
                    .any(|(p, topics)| p == peer && topics.contains(&&topic));
                subscribed.then(|| name.clone())
            })
            .collect();
        ready.sort();
        ready
    }

    /// send a message to a node
    fn byz_send(&mut self, to: &str, msg: ByzMsg) {
        let data = serde_json::to_vec(&msg).expect("ByzMsg always serializes");
        match self
            .swarm
            .behaviour_mut()
            .gossipsub
            .publish(inbox(to), data)
        {
            Ok(_) => self.log(format!("-> {to}: {msg:?}")),
            Err(e) => self.log(format!("send to {to} failed: {e}")),
        }
    }

    /// round 1: once all lieutenants are ready, send each one an order. A
    /// traitor sends the opposite order to every second lieutenant.
    fn commander_try_send(&mut self) {
        let b = self.byz();
        if b.sent {
            return;
        }

        // only send command from out from the commander when all needed
        // lieutenants are connected
        let (n, order, traitor) = (b.lieutenants, b.order, b.traitor);
        let targets = self.ready_lieutenants();
        if targets.len() < n {
            return;
        }

        // send to the lieutenants
        for (i, name) in targets.iter().enumerate() {
            // flip every second one
            let value = if traitor && i % 2 == 1 {
                order.flip()
            } else {
                order
            };
            self.byz_send(name, ByzMsg::Order(value));
        }
        self.byz_mut().sent = true;
    }

    /// round 2: forward the commander's order to all other lieutenants, as
    /// our own claim. A traitor forwards the opposite.
    fn lieutenant_try_relay(&mut self) {
        let b = self.byz();
        // nothing received from the commander
        let Some(received) = b.from_commander else {
            return;
        };
        // if relayed already, nothing todo
        if b.relayed {
            return;
        }

        let (n, traitor) = (b.lieutenants, b.traitor);
        let targets = self.ready_lieutenants();
        // check if all lieutenants are connected (specified as arg)
        if targets.len() < n - 1 {
            return;
        }

        // flip the order if a traitor
        let value = if traitor { received.flip() } else { received };
        // round 2 only sends to lieutenants, so only send to them
        for name in &targets {
            self.byz_send(name, ByzMsg::Relay(value));
        }
        self.byz_mut().relayed = true;
    }

    /// decide once all values are there, or when the deadline has passed
    fn lieutenant_try_decide(&mut self) {
        let b = self.byz();
        if b.decision.is_some() {
            return;
        }

        // previous step complete (got cmd from commander and relay phase is
        // through), also checking timeout here
        let complete = b.from_commander.is_some() && b.relays.len() >= b.lieutenants - 1;
        let timed_out = b.deadline.is_some_and(|d| Instant::now() >= d);
        if !complete && !timed_out {
            return;
        }

        let relays: Vec<Order> = b.relays.values().copied().collect();
        let decision = decide(b.from_commander, &relays);
        let relay_list: Vec<String> = b
            .relays
            .iter()
            .map(|(p, o)| {
                let name = self.names.get(p).map(String::as_str).unwrap_or("?");
                format!("{name}={o}")
            })
            .collect();
        let line = format!(
            "DECIDE {decision} (commander={}, relays=[{}]{})",
            b.from_commander.map_or("none".into(), |o| o.to_string()),
            relay_list.join(", "),
            if timed_out && !complete {
                ", timeout"
            } else {
                ""
            },
        );
        self.byz_mut().decision = Some(decision);
        self.log(line);
    }

    /// a byzantine message arrived on our inbox
    pub(crate) fn byz_receive(&mut self, message: gossipsub::Message) {
        let Some(source) = message.source else {
            return;
        };
        // deserialize the msg
        let msg = match serde_json::from_slice::<ByzMsg>(&message.data) {
            Ok(msg) => msg,
            Err(e) => {
                self.log(format!("invalid message from {source}: {e}"));
                return;
            }
        };
        // handle the message
        self.byz_handle(source, msg);
        // if lieutenant then try relay and decide
        if self.byz().role == Role::Lieutenant {
            self.lieutenant_try_relay();
            self.lieutenant_try_decide();
        }
    }

    /// accept a message only if it fits the sender's role: orders only from
    /// the commander, relays only from lieutenants
    fn byz_handle(&mut self, source: PeerId, msg: ByzMsg) {
        let Some(role) = self.roles.get(&source).copied() else {
            // name exchange with this peer not finished yet, retry on tick
            self.byz_mut().pending.push((source, msg));
            return;
        };
        // the name of the node of the incoming msg
        let from = self
            .names
            .get(&source)
            .cloned()
            .unwrap_or_else(|| "?".into());

        // self the message into the log
        self.log(format!("<- {from}: {msg:?}"));

        // check if the message is from the correct node
        //
        // from the commander has to be of type Order
        // from the lieutenant has to be of type Relay
        let b = self.byz_mut();
        match (msg, role) {
            (ByzMsg::Order(o), Role::Commander) if b.from_commander.is_none() => {
                b.from_commander = Some(o);
            }
            (ByzMsg::Relay(o), Role::Lieutenant) => {
                b.relays.entry(source).or_insert(o);
            }
            (msg, role) => {
                self.log(format!("ignored {msg:?} from {from} ({role:?})"));
                return;
            }
        }

        // check if the deadline is already set (first one sets it). If not, set
        // it yourself.
        let b = self.byz_mut();
        if b.deadline.is_none() {
            b.deadline = Some(Instant::now() + DECIDE_TIMEOUT);
        }
    }

    /// retry any pending messages (pending == not in the names yet)
    fn byz_retry_pending(&mut self) {
        let pending = std::mem::take(&mut self.byz_mut().pending);
        for (source, msg) in pending {
            self.byz_handle(source, msg);
        }
    }
}

/// majority over the commander's value and all relays; on a tie (only with
/// two lieutenants) the commander's value wins. missing commander = retreat
pub fn decide(from_commander: Option<Order>, relays: &[Order]) -> Order {
    // decision from the commander
    let own = from_commander.unwrap_or(Order::Retreat);
    let total = relays.len() + 1;
    // count the attacks (relays and own)
    let attacks =
        relays.iter().filter(|o| **o == Order::Attack).count() + usize::from(own == Order::Attack);
    match (2 * attacks).cmp(&total) {
        Ordering::Greater => Order::Attack,
        Ordering::Less => Order::Retreat,
        Ordering::Equal => own,
    }
}

fn inbox(name: &str) -> IdentTopic {
    IdentTopic::new(format!("/dissy/byz/1.0.0/{name}"))
}
