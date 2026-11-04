use std::collections::{BTreeMap, BTreeSet};
use std::time::Duration;

use clap::{Parser, ValueEnum};
use zenoh::Session;
use zenoh::handlers::FifoChannelHandler;
use zenoh::pubsub::Subscriber;
use zenoh::sample::{Sample, SampleKind};

#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
enum Role {
    Commander,
    Lieutenant,
}

impl Role {
    // Spelling used in key expressions, e.g. "dissy/ex3/bgp/nodes/lieutenant/L1"
    fn as_str(self) -> &'static str {
        match self {
            Role::Commander => "commander",
            Role::Lieutenant => "lieutenant",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
enum Order {
    Attack,
    Retreat,
}

impl Order {
    fn as_str(self) -> &'static str {
        match self {
            Order::Attack => "attack",
            Order::Retreat => "retreat",
        }
    }

    fn from_string(order: &str) -> Option<Self> {
        match order {
            "attack" => Some(Order::Attack),
            "retreat" => Some(Order::Retreat),
            _ => None,
        }
    }

    fn opposite(self) -> Order {
        match self {
            Order::Attack => Order::Retreat,
            Order::Retreat => Order::Attack,
        }
    }
}

#[derive(Parser)]
struct Args {
    /// Unique node name, e.g. A
    #[arg(long)]
    name: String,

    /// Nodes role
    #[arg(long, value_enum)]
    role: Role,

    /// Behave as a traitor
    #[arg(long)]
    traitor: bool,

    /// Order a loyal commander sends (required for --role commander)
    #[arg(long, value_enum, required_if_eq("role", "commander"))]
    order: Option<Order>,

    /// Number of lieutenants to expect (2 or 3)
    #[arg(long, default_value_t = 2)]
    lieutenants: usize,
}

// for liveliness, everyone subscribes
// "dissy/ex3/bgp/nodes/<role>/<name>"
const PRESENCE_PREFIX: &str = "dissy/ex3/bgp/nodes";

// to receive orders, lieutenant <to> subscribes
// "dissy/ex3/bgp/order/<to>"
const ORDER_PREFIX: &str = "dissy/ex3/bgp/order";

// for forwarding between lieutenants, <from> publishes, <to> subscribes
// "dissy/ex3/bgp/relay/<from>/<to>"
const RELAY_PREFIX: &str = "dissy/ex3/bgp/relay";

type SampleSubscriber = Subscriber<FifoChannelHandler<Sample>>;

#[tokio::main]
async fn main() -> zenoh::Result<()> {
    let args = Args::parse();

    let session = zenoh::open(zenoh::Config::default()).await?;
    println!(
        "[{}] role={} traitor={}",
        args.name,
        args.role.as_str(),
        args.traitor
    );

    match args.role {
        Role::Lieutenant => run_lieutenant(&session, &args).await?,
        Role::Commander => run_commander(&session, &args).await?,
    }

    session.close().await?;
    Ok(())
}

async fn run_commander(session: &Session, args: &Args) -> zenoh::Result<()> {
    // The commander only sends, so it needs no data subscribers.
    let token_subscription = session
        .liveliness()
        .declare_subscriber(format!("{PRESENCE_PREFIX}/lieutenant/*"))
        .history(true)
        .await?;

    // lets others see it in the presence list.
    let _token = declare_presence(session, args).await?;

    // The token keys are the only place the commander learns the lieutenants' names,
    // which it needs to address "order/<L>". BTreeSet keeps them sorted.
    let lieutenants =
        wait_for_lieutenants(&token_subscription, &args.name, args.lieutenants).await?;
    println!("[{}] all lieutenants present: {lieutenants:?}", args.name);

    // Grace delay: lieutenants' subscriber declarations need a moment to reach every peer.
    tokio::time::sleep(Duration::from_secs(1)).await;

    let base = args.order.expect("clap enforces --order for the commander");

    for (i, l) in lieutenants.iter().enumerate() {
        // Loyal: same order for everyone. Traitor: flip it for every second lieutenant,
        // so different lieutenants receive conflicting orders.
        let order = if args.traitor && i % 2 == 1 {
            base.opposite()
        } else {
            base
        };
        session
            .put(format!("{ORDER_PREFIX}/{l}"), order.as_str())
            .await?;
        println!("[{}] sent {} to {l}", args.name, order.as_str());
    }

    // Stay alive briefly so the puts are delivered and the token doesn't vanish mid-round.
    tokio::time::sleep(Duration::from_secs(5)).await;

    Ok(())
}

async fn run_lieutenant(session: &Session, args: &Args) -> zenoh::Result<()> {
    // Data subscribers FIRST, so that our token later means "ready to receive".
    // They must stay alive for the whole function: dropping them undeclares them.
    let order_subscription = session
        .declare_subscriber(format!("{ORDER_PREFIX}/{}", args.name))
        .await?;
    let relay_subscription = session
        .declare_subscriber(format!("{RELAY_PREFIX}/*/{}", args.name))
        .await?;

    let token_subscription = session
        .liveliness()
        .declare_subscriber(format!("{PRESENCE_PREFIX}/lieutenant/*"))
        .history(true)
        .await?;

    let _token = declare_presence(session, args).await?;

    // Wait for the other lieutenants before receiving, so that we know whom to forward to.
    let others =
        wait_for_lieutenants(&token_subscription, &args.name, args.lieutenants - 1).await?;
    println!("[{}] other lieutenants present: {others:?}", args.name);

    let mut from_commander: Option<Order> = None;
    let mut relays: BTreeMap<String, Order> = BTreeMap::new();

    // Created ONCE: a traitor may send nothing, and we must still decide.
    // pin! lets select! poll the same timer in every iteration via &mut.
    let timeout = tokio::time::sleep(Duration::from_secs(10));
    tokio::pin!(timeout);

    loop {
        if from_commander.is_some() && relays.len() == others.len() {
            // when we get here, the commander sent an Order and we received messages from the other lieutenants
            break;
        }

        tokio::select! {
            //branch 1: order is received by commander and forwarded to other lieutenants
            sample = order_subscription.recv_async() => {
                let sample = sample?;

                // is the payload some text?
                let Ok(text) = sample.payload().try_to_string() else {
                    eprintln!("[{}] non-UTF-8 payload", args.name);
                    continue;
                };

                // is the string a valid order?
                let Some(order) = Order::from_string(&text) else {
                    eprintln!("[{}] invalid order from commander: {text}", args.name);
                    continue;
                };
                if from_commander.is_some() {
                    // Oral messages: one order per round. Ignore repeats (a traitor commander could send several).
                    eprintln!("[{}] ignoring second order from commander: {text}", args.name);
                    continue;
                }
                println!("[{}] received from commander: {}", args.name, order.as_str());
                from_commander = Some(order);

                // for now traitors just relay the opposite of their command
                let forwarded = if args.traitor { order.opposite() } else { order };
                for other in &others {
                    session
                        .put(format!("{RELAY_PREFIX}/{}/{other}", args.name), forwarded.as_str())
                        .await?;
                    println!("[{}] forwarded {} to {other}", args.name, forwarded.as_str());
                }
            }

            //branch 2: a relay from another lieutenant arrives, key "relay/<from>/<me>"
            sample = relay_subscription.recv_async() => {
                let sample = sample?;
                // last segment is our own name, the one before it is the sender
                let sender = sample.key_expr().as_str().rsplit('/').nth(1).unwrap_or_default().to_string();
                if !others.contains(&sender) || relays.contains_key(&sender) {
                    eprintln!("[{}] ignoring relay from unknown or repeated sender {sender}", args.name);
                    continue;
                }

                // is payload a string?
                let Ok(text) = sample.payload().try_to_string() else {
                    eprintln!("[{}] non-UTF-8 relay from {sender}", args.name);
                    continue;
                };

                // is string a valid order
                let Some(order) = Order::from_string(&text) else {
                    eprintln!("[{}] invalid relay from {sender}: {text}", args.name);
                    continue;
                };
                println!("[{}] received from {sender}: {}", args.name, order.as_str());
                relays.insert(sender, order);
            }

            //branch 3: give up waiting, decide with what we have
            _ = &mut timeout => {
                println!("[{}] timeout, deciding with what I have", args.name);
                break;
            }
        }
    }

    // Missing values (traitor stayed silent, garbage, timeout) count as the default: retreat.
    let commander_value = from_commander.unwrap_or(Order::Retreat);
    let mut values = vec![commander_value];
    let mut view = format!("commander={}", commander_value.as_str());
    for other in &others {
        let v = relays.get(other).copied().unwrap_or(Order::Retreat);
        values.push(v);
        view.push_str(&format!(", {other}={}", v.as_str()));
    }

    let decision = decide(&values, commander_value);
    let suffix = if args.traitor { "   (traitor)" } else { "" };
    println!(
        "[{}] DECISION: {}   (values: {view}){suffix}",
        args.name,
        decision.as_str()
    );

    // Stay alive briefly so our relays reach slower lieutenants before the session closes.
    tokio::time::sleep(Duration::from_secs(2)).await;

    Ok(())
}

/// Majority vote. A tie (only possible with 2 values, i.e. 3 nodes) falls back to the
/// commander's value: with a traitor commander, the loyal lieutenants then disagree,
/// which is the 3-node impossibility the task asks to observe.
fn decide(values: &[Order], tie_break: Order) -> Order {
    let attacks = values.iter().filter(|&&v| v == Order::Attack).count();
    let retreats = values.len() - attacks;
    if attacks > retreats {
        Order::Attack
    } else if retreats > attacks {
        Order::Retreat
    } else {
        tie_break
    }
}

async fn declare_presence(
    session: &Session,
    args: &Args,
) -> zenoh::Result<zenoh::liveliness::LivelinessToken> {
    session
        .liveliness()
        .declare_token(format!(
            "{PRESENCE_PREFIX}/{}/{}",
            args.role.as_str(),
            args.name
        ))
        .await
}

/// Collects lieutenant names from liveliness tokens until `expected` names
/// (excluding `own_name`) are alive at the same time.
async fn wait_for_lieutenants(
    token_subscription: &SampleSubscriber,
    own_name: &str,
    expected: usize,
) -> zenoh::Result<BTreeSet<String>> {
    let mut names = BTreeSet::new();
    while names.len() < expected {
        let sample = token_subscription.recv_async().await?;
        let name = sample
            .key_expr()
            .as_str()
            .rsplit('/')
            .next()
            .unwrap_or_default();
        if name == own_name {
            continue;
        }
        match sample.kind() {
            SampleKind::Put => {
                println!("[{own_name}] JOIN  {name}");
                names.insert(name.to_string());
            }
            SampleKind::Delete => {
                println!("[{own_name}] LEAVE {name}");
                names.remove(name);
            }
        }
    }
    Ok(names)
}
