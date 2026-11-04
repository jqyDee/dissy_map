use std::collections::BTreeSet;
use std::time::Duration;

use clap::Parser;
use zenoh::sample::{Locality, SampleKind};

// Every node holds one liveliness token below this prefix, named after itself.
const NODES_PREFIX: &str = "dissy/ex3/nodes";
const HELLO_TOPIC: &str = "dissy/ex3/hello";

#[derive(Parser)]
struct Args {
    /// Unique node name, e.g. A
    #[arg(long)]
    name: String,

    /// Seconds between two peer reports
    #[arg(long, default_value_t = 2)]
    interval: u64,
}

#[tokio::main]
async fn main() -> zenoh::Result<()> {
    let args = Args::parse();

    // The default config is peer mode with multicast scouting: no addresses anywhere.
    let session = zenoh::open(zenoh::Config::default()).await?;
    let own_id = session.info().zid().await;
    println!("[{}] started as {own_id}", args.name);

    // The token stays alive as long as this session does, so peers see us leave
    // without us having to send anything.
    let _token = session
        .liveliness()
        .declare_token(format!("{NODES_PREFIX}/{}", args.name))
        .await?;

    // history(true) also replays the tokens that existed before we subscribed.
    let token_subscriber = session
        .liveliness()
        .declare_subscriber(format!("{NODES_PREFIX}/*"))
        .history(true)
        .await?;

    //task 2 message publisher
    let publisher = session
        .declare_publisher(format!("{HELLO_TOPIC}/{}", args.name))
        .await?;

    //task 2 message subscriber
    let message_subscriber = session
        .declare_subscriber(format!("{HELLO_TOPIC}/*"))
        .allowed_origin(Locality::Remote) //dont subscribe to your own messages!
        .await?;

    let mut alive = BTreeSet::new();
    let mut report = tokio::time::interval(Duration::from_secs(args.interval));

    //for counting up the number of hello's sent
    let mut seq: u64 = 0;

    loop {
        tokio::select! {

            //branch where JOIN/LEAVE tokens are received
            token_sample = token_subscriber.recv_async() => {
                let token_sample = token_sample?;
                let name = token_sample.key_expr().as_str().rsplit('/').next().unwrap_or_default();
                if name == args.name {
                    continue;
                }
                match token_sample.kind() {
                    SampleKind::Put => {
                        println!("[{}] JOIN  {name}", args.name);
                        alive.insert(name.to_string());
                    }
                    SampleKind::Delete => {
                        println!("[{}] LEAVE {name}", args.name);
                        alive.remove(name);
                    }
                }
            }

            //branch task 2 where messages are received
            message_sample = message_subscriber.recv_async() => {
                let message_sample = message_sample?;

                if message_sample.kind() != SampleKind::Put { continue; }

                let name_sender = message_sample.key_expr().as_str().rsplit('/').next().unwrap_or_default();
                let Ok(text) = message_sample.payload().try_to_string() else {
                    eprintln!("[{}] non-UTF-8 payload from {name_sender}", args.name);
                    continue;
                };
                println!("[{}] {} says: {}", args.name, name_sender, text);
            }

            _ = report.tick() => {
                // Two views: names claimed by the application, and the sessions
                // the transport layer is really connected to.
                let sessions: Vec<_> = session.info().peers_zid().await.collect();
                println!(
                    "[{}] peers: {alive:?} | {} transport sessions: {sessions:?}",
                    args.name,
                    sessions.len(),
                );

                //task 2, periodical hello
                publisher.put(format!("Hello from Node {} #{}", args.name, seq))
                    .await?;
                seq += 1;
            }
            _ = tokio::signal::ctrl_c() => break,
        }
    }

    println!("[{}] shutting down", args.name);
    session.close().await?;
    Ok(())
}
