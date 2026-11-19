use std::time::Duration;

use anyhow::{Result, bail};
use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, BufReader};
use zookeeper_client as zk;

const AUCTION: &str = "/auction";
const NODES: &str = "/auction/nodes";

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
struct AuctionState {
    closed: bool,
    highest: u64,
    bidder: Option<String>,
    winner: Option<String>,
}

#[derive(Parser)]
struct Args {
    #[arg(long)]
    zk: String, // "<zk-ip>:2181"
    #[arg(long)]
    id: String, // e.g. "node1"
    #[command(subcommand)]
    cmd: Option<Cmd>, // none → interactive REPL
}

#[derive(Subcommand)]
enum Cmd {
    Bid { participant: String, amount: u64 },
    Query,
    Close,
}

async fn connect(addr: &str) -> Result<zk::Client> {
    let client = zk::Client::connector()
        .with_session_timeout(Duration::from_secs(5))
        .connect(addr)
        .await?;
    Ok(client)
}

async fn create_ignore_exists(
    c: &zk::Client,
    path: &str,
    data: &[u8],
    mode: zk::CreateMode,
) -> Result<()> {
    match c
        .create(path, data, &mode.with_acls(zk::Acls::anyone_all()))
        .await
    {
        Ok(_) | Err(zk::Error::NodeExists) => Ok(()),
        Err(e) => Err(e.into()),
    }
}

async fn init(c: &zk::Client, id: &str) -> Result<()> {
    let initial = serde_json::to_vec(&AuctionState::default())?;
    create_ignore_exists(c, AUCTION, &initial, zk::CreateMode::Persistent).await?;
    create_ignore_exists(c, NODES, b"", zk::CreateMode::Persistent).await?;
    c.create(
        &format!("{NODES}/{id}"),
        b"",
        &zk::CreateMode::Ephemeral.with_acls(zk::Acls::anyone_all()),
    )
    .await?;
    Ok(())
}

async fn read_state(c: &zk::Client) -> Result<(AuctionState, i32)> {
    let (data, stat) = c.get_data(AUCTION).await?;
    Ok((serde_json::from_slice(&data)?, stat.version))
}

async fn bid(c: &zk::Client, who: &str, amount: u64) -> Result<AuctionState> {
    loop {
        let (mut s, version) = read_state(c).await?;
        if s.closed {
            bail!("rejected: auction closed");
        }
        if amount <= s.highest {
            bail!("rejected: {amount} <= current highest {}", s.highest);
        }
        s.highest = amount;
        s.bidder = Some(who.to_string());
        match c
            .set_data(AUCTION, &serde_json::to_vec(&s)?, Some(version))
            .await
        {
            Ok(_) => return Ok(s),
            Err(zk::Error::BadVersion) => continue,
            Err(e) => return Err(e.into()),
        }
    }
}

async fn close(c: &zk::Client) -> Result<AuctionState> {
    loop {
        let (mut s, version) = read_state(c).await?;
        if s.closed {
            return Ok(s);
        }
        s.closed = true;
        s.winner = s.bidder.clone();
        match c
            .set_data(AUCTION, &serde_json::to_vec(&s)?, Some(version))
            .await
        {
            Ok(_) => return Ok(s),
            Err(zk::Error::BadVersion) => continue,
            Err(e) => return Err(e.into()),
        }
    }
}

fn spawn_watch(c: zk::Client) {
    tokio::spawn(async move {
        loop {
            let Ok((data, stat, watcher)) = c.get_and_watch_data(AUCTION).await else {
                tokio::time::sleep(Duration::from_secs(1)).await;
                continue;
            };
            if let Ok(s) = serde_json::from_slice::<AuctionState>(&data) {
                println!("[watch v{}] {s:?}", stat.version);
            }
            watcher.changed().await;
        }
    });
}

fn spawn_state_log(c: &zk::Client) {
    let mut w = c.state_watcher();
    tokio::spawn(async move {
        loop {
            let st = w.changed().await;
            println!("[session] {st:?}");
            if st.is_terminated() {
                break;
            }
        }
    });
}

async fn run(c: &zk::Client, cmd: Cmd) -> Result<()> {
    match cmd {
        Cmd::Bid {
            participant,
            amount,
        } => println!("accepted: {:?}", bid(c, &participant, amount).await?),
        Cmd::Query => println!("{:?}", read_state(c).await?.0),
        Cmd::Close => println!("closed: {:?}", close(c).await?),
    }
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    let c = connect(&args.zk).await?;
    init(&c, &args.id).await?;

    if let Some(cmd) = args.cmd {
        return run(&c, cmd).await;
    }

    spawn_state_log(&c);
    spawn_watch(c.clone());
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    while let Some(line) = lines.next_line().await? {
        let words: Vec<&str> = line.split_whitespace().collect();
        let cmd = match words.as_slice() {
            ["bid", who, amount] => Cmd::Bid {
                participant: who.to_string(),
                amount: amount.parse()?,
            },
            ["query"] => Cmd::Query,
            ["close"] => Cmd::Close,
            ["exit"] => break,
            _ => {
                println!("usage: bid <who> <amount> | query | close | exit");
                continue;
            }
        };
        if let Err(e) = run(&c, cmd).await {
            println!("error: {e}");
        }
    }
    Ok(())
}
