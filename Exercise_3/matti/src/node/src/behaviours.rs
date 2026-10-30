use std::time::Duration;

use const_format::concatcp;
use libp2p::{
    StreamProtocol,
    gossipsub::{self, ValidationMode},
    identify, mdns, noise, ping,
    request_response::{self, ProtocolSupport},
    swarm::NetworkBehaviour,
    tcp, yamux,
};
use serde::{Deserialize, Serialize};

use crate::byzantine::Role;

/// protocol version
const VERSION: &str = "1.0.0";
/// the protocol name
const PROTOCOL: &str = concatcp!("/dissy/", VERSION);
/// the name protocol name
const NAME_PROTOCOL: StreamProtocol = StreamProtocol::new(concatcp!("/dissy/name/", VERSION));

/// Send a request to get the name of another peer.
#[derive(Debug, Serialize, Deserialize)]
pub struct NameRequest;

/// Send a response to the `NameRequest` back to anothe peer.
#[derive(Debug, Serialize, Deserialize)]
pub struct NameRespone {
    /// Name of the node giving the response.
    pub name: String,
    /// role in the byzantine run, None for discover/hello
    pub role: Option<Role>,
}

/// Behaviour of the peer network, specifying builtin and custom protocols
#[derive(NetworkBehaviour)]
pub struct NetwBehaviour {
    /// mdns discovery protocol
    pub mdns: mdns::tokio::Behaviour,
    /// identify protocol
    pub identify: identify::Behaviour,
    /// ping protocol
    pub ping: ping::Behaviour,
    /// name exchange protocol: on the first connection to a peer we request its
    /// name; incoming requests are answered with our own name.
    pub name_exchange: request_response::json::Behaviour<NameRequest, NameRespone>,
    /// gossipsub for Task 2 and 3. Publisher/Subscriber implementation for p2p.
    pub gossipsub: gossipsub::Behaviour,
}

impl NetwBehaviour {
    /// create a new (default) NetwBehaviour for our custom peer network
    /// protocol
    pub fn new(
        key: &libp2p::identity::Keypair,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let mdns_cfg = mdns::Config {
            // how long a discovered peer counts as valid without being heard
            // from again; afterwards mdns emits `Expired` (default: 6 min)
            ttl: Duration::from_secs(10),
            // how often we multicast "who is there?"; replies discover new
            // peers and refresh known ones. must be < ttl, otherwise known
            // peers expire between queries
            query_interval: Duration::from_secs(5),
            // no Ipv6 for our application
            enable_ipv6: false,
        };
        // identify config; announces our protocol family "/dissy/1.0.0" to peers
        let ident_cfg = identify::Config::new(PROTOCOL.into(), key.public());
        // strictly check messages to be signed
        let gossipsub_cfg = gossipsub::ConfigBuilder::default()
            .validation_mode(ValidationMode::Strict)
            .build()?;
        Ok(Self {
            mdns: mdns::tokio::Behaviour::new(mdns_cfg, key.public().to_peer_id())?,
            identify: identify::Behaviour::new(ident_cfg),
            ping: ping::Behaviour::default(),
            name_exchange: request_response::json::Behaviour::new(
                [(NAME_PROTOCOL, ProtocolSupport::Full)],
                request_response::Config::default(),
            ),
            gossipsub: gossipsub::Behaviour::new(
                gossipsub::MessageAuthenticity::Signed(key.clone()), // sign messages with the senders key
                gossipsub_cfg,
            )?,
        })
    }
}

pub fn build_swarm_default()
-> Result<libp2p::swarm::Swarm<NetwBehaviour>, Box<dyn std::error::Error>> {
    // new swarm builder that will generate a swarm with new identity (public,
    // private key) pair
    let swarm_build_pipe = libp2p::SwarmBuilder::with_new_identity();

    // run the swarm on the tokio runtime (async sockets and timers)
    let swarm_build_pipe = swarm_build_pipe.with_tokio();

    // build a libp2p stack ontop of the tcp protocol
    //
    // TCP:   one byte pipe between two machines.
    // NOISE: runs handshake where both sides prove they hold the private key,
    //        associated with their peer_id. This makes the connection encrypted
    //        afterwards.
    // YAMUX: split the single connection, into many lightweight streams. In our
    //        case each of, identify, ping, and name exchange get their own stream.
    //        (This is basically a connection multiplexing addition.)
    let swarm_build_pipe = swarm_build_pipe.with_tcp(
        tcp::Config::default(), // default libp2p tcp config
        noise::Config::new,     // default libp2p noise handshake config
        yamux::Config::default, // default libp2p yamux config
    )?;

    // configure the peer network behaviour.
    let swarm_build_pipe = swarm_build_pipe.with_behaviour(NetwBehaviour::new)?;

    // keep connections open even when no protocol stream is active; otherwise
    // the swarm closes idle connections and peers would appear to leave
    let swarm_build_pipe = swarm_build_pipe
        .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(u64::MAX)));

    // build the swarm from the builder
    Ok(swarm_build_pipe.build())
}
