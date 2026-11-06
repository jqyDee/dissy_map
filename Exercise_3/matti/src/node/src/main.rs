use clap::{Parser, Subcommand};

use crate::{
    byzantine::{Byzantine, Order, Role},
    node::{App, Node},
};

mod behaviours;
mod byzantine;
mod hello;
mod node;
mod ui;

/// Program Arguments
#[derive(Parser)]
struct Args {
    /// tasks application version
    #[command(subcommand)]
    command: Option<Command>,
    /// unique name of this node, sent to peers via the name exchange protocol
    #[arg(long)]
    name: String,
    #[arg(long)]
    plain: bool,
}

#[derive(Subcommand)]
enum Command {
    /// TASK 1: discover peers and print them (default)
    Discover,
    /// TASK 2: periodically publish a hello message
    Hello,
    /// TASK 3: byzantine generals, oral messages OM(1)
    Byzantine {
        #[arg(long, value_enum)]
        role: Role,
        #[arg(long)]
        traitor: bool,
        /// 2 = three nodes, 3 = four nodes
        #[arg(long, default_value_t = 2)]
        lieutenants: usize,
        #[arg(long, value_enum, default_value_t = Order::Attack)]
        order: Order,
    },
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let app = match args.command.unwrap_or(Command::Discover) {
        Command::Discover => App::Discover,
        Command::Hello => App::Hello,
        Command::Byzantine {
            role,
            traitor,
            lieutenants,
            order,
        } => App::Byzantine(Byzantine::new(role, traitor, lieutenants, order)),
    };

    let mut node = Node::new(app, args.plain, args.name)?;
    // setup errors are fatal, network errors in run() are only logged
    node.listen()?;
    node.run().await;
    Ok(())
}
