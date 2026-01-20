use anyhow::Result;
use clap::Parser;
use swim_rs::protocol::node::Node;


// TODO: Include verification of the string to socket type
#[derive(Parser)]
struct Cli {
    socket: String,
    seeds: Option<Vec<String>>
}

fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let args = Cli::parse();

    let mut node = Node::new(args.socket)?;

    if let Some(peers) = args.seeds {
        for peer in peers {
            node.join(peer)?;
        }
    }

    node.event_loop()?;

    Ok(())
}

