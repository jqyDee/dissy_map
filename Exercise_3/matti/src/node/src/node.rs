use std::{collections::HashMap, time::Duration};

use crossterm::event::{Event, EventStream, KeyCode, KeyEventKind, KeyModifiers};
use futures::StreamExt;
use libp2p::{PeerId, Swarm, gossipsub, mdns, ping, request_response, swarm::SwarmEvent};
use tokio::time::Instant;

use crate::{
    behaviours::{
        NameRequest, NameRespone, NetwBehaviour, NetwBehaviourEvent, build_swarm_default,
    },
    byzantine::{Byzantine, Role},
};

/// what the app is doing on top of discovery
pub enum App {
    Discover,
    Hello,
    Byzantine(Byzantine),
}

/// a running peer: the libp2p swarm plus our application state
pub struct Node {
    /// which kind of the app is run (simple `Discover`, `Hello` or `Byzantine`)
    pub(crate) app: App,
    /// event log shown in the messages pane (or printed in plain mode)
    pub(crate) log: Vec<String>,
    /// print to stdout instead of draeing the tui (e.g. scripts)
    pub(crate) plain: bool,
    /// our own name, given on the command line
    pub(crate) name: String,
    /// the libp2p swarm driving all connections and protocols
    pub(crate) swarm: Swarm<NetwBehaviour>,
    /// names of connected peers, learned through the name exchange protocol
    pub(crate) names: HashMap<PeerId, String>,
    /// roles of connected peers, learned through the name exchange protocol
    pub(crate) roles: HashMap<PeerId, Role>,
    /// start time, log lines are stamped relative to it
    start: Instant,
}

impl Node {
    /// create a new node with a fresh identity; does not listen yet
    pub fn new(app: App, plain: bool, name: String) -> Result<Self, Box<dyn std::error::Error>> {
        let swarm = build_swarm_default()?;
        let mut node = Self {
            app,
            log: Vec::new(),
            plain,
            name,
            swarm,
            names: HashMap::new(),
            roles: HashMap::new(),
            start: Instant::now(),
        };
        match node.app {
            App::Discover => {}
            App::Hello => node.hello_init()?,
            App::Byzantine(_) => node.byz_init()?,
        }
        Ok(node)
    }

    /// listen on all local interfaces, the OS picks a free tcp port. mdns
    /// announces these listen addresses, so without listening we cannot be
    /// discovered.
    pub fn listen(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        self.swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse()?)?;
        Ok(())
    }

    /// event loop: the swarm only makes progress while it is polled here
    pub async fn run(&mut self) {
        if self.plain {
            self.run_plain().await;
        } else {
            self.run_tui().await;
        }
    }

    /// run the peer log on std stdout
    async fn run_plain(&mut self) {
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        loop {
            // whichever is ready first: periodic status output or the next
            // swarm event
            tokio::select! {
                _ = tick.tick() => {
                    self.print_status();
                    self.on_tick();
                },
                ev = self.swarm.select_next_some() => self.handle_event(ev),
            }
        }
    }

    /// run the peer log in TUI
    async fn run_tui(&mut self) {
        let mut terminal = ratatui::init();
        let mut keys = EventStream::new();
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        let mut redraw = tokio::time::interval(Duration::from_millis(100));
        loop {
            tokio::select! {
                _ = tick.tick() => self.on_tick(),
                ev = self.swarm.select_next_some() => self.handle_event(ev),
                Some(Ok(key)) = keys.next() => {
                    if is_quit(&key) {
                        break;
                    }
                }
                _ = redraw.tick() => {
                    if terminal.draw(|frame| crate::ui::draw(frame, self)).is_err() {
                        break;
                    }
                }
            }
        }
        ratatui::restore();
    }

    /// what to do on tick (always print the status, and then do ...)
    fn on_tick(&mut self) {
        match self.app {
            App::Discover => {}
            App::Hello => self.hello_tick(),
            App::Byzantine(_) => self.byz_tick(),
        }
    }

    /// print our own peer id and all connected peers with their names
    fn print_status(&self) {
        println!("[{}] self={} peers:", self.name, self.swarm.local_peer_id());
        for p in self.swarm.connected_peers() {
            let n = self.names.get(p).map(String::as_str).unwrap_or("?");
            println!("    {n:<8} {p}");
        }
    }

    /// dispatch swarm events: behaviour events go to their protocol handler,
    /// connection events are handled here
    fn handle_event(&mut self, event: SwarmEvent<NetwBehaviourEvent>) {
        match event {
            SwarmEvent::Behaviour(NetwBehaviourEvent::Mdns(ev)) => self.on_mdns(ev),
            SwarmEvent::Behaviour(NetwBehaviourEvent::NameExchange(ev)) => {
                self.on_name_exchange(ev)
            }
            SwarmEvent::Behaviour(NetwBehaviourEvent::Ping(ev)) => self.on_ping(ev),
            SwarmEvent::Behaviour(NetwBehaviourEvent::Gossipsub(ev)) => self.on_gossipsub(ev),
            SwarmEvent::Behaviour(NetwBehaviourEvent::Identify(_)) => {}
            SwarmEvent::NewListenAddr { address, .. } => {
                self.log(format!("listening on {address}"));
            }
            SwarmEvent::ConnectionEstablished {
                peer_id,
                num_established,
                ..
            } => {
                // only on the first connection; both sides may dial each other
                // at once
                if num_established.get() == 1 {
                    self.swarm
                        .behaviour_mut()
                        .name_exchange
                        .send_request(&peer_id, NameRequest);
                }
            }
            // num_established == 0: the last connection to this peer is gone.
            // cause is None for a clean close, Some(error) e.g. on a crash
            SwarmEvent::ConnectionClosed {
                peer_id,
                num_established: 0,
                cause,
                ..
            } => {
                let who = self.names.remove(&peer_id).unwrap_or_else(|| "?".into());
                self.roles.remove(&peer_id);
                self.log(format!("- LEAVE {who} ({peer_id}), cause: {cause:?}"));
            }
            _ => {}
        }
    }

    /// mdns only reports peers, it does not connect to them; we dial ourselves
    fn on_mdns(&mut self, ev: mdns::Event) {
        match ev {
            mdns::Event::Discovered(list) => {
                // one entry per (peer, address); a peer may show up with
                // several addresses
                for (peer, addr) in list {
                    if !self.swarm.is_connected(&peer)
                        && let Err(e) = self.swarm.dial(addr)
                    {
                        self.log(format!("dial {peer} failed: {e}"));
                    }
                }
            }
            // only logged: discovery and connections are separate layers, a
            // peer may still be connected after its mdns record expired
            mdns::Event::Expired(list) => {
                for (peer, _) in list {
                    self.log(format!("mdns record expired for {peer}"));
                }
            }
        }
    }

    /// answer name requests with our own name, store names from responses
    fn on_name_exchange(&mut self, ev: request_response::Event<NameRequest, NameRespone>) {
        match ev {
            // `peer` is the noise-verified peer id of the connection, while
            // the name in a response is only claimed by that peer
            request_response::Event::Message { peer, message, .. } => match message {
                // `channel` is a one-time handle to answer this request
                request_response::Message::Request { channel, .. } => {
                    let role = match &self.app {
                        App::Byzantine(b) => Some(b.role),
                        _ => None,
                    };
                    let resp = NameRespone {
                        name: self.name.clone(),
                        role,
                    };
                    // Err only if the connection already closed; nothing to
                    // do then
                    let _ = self
                        .swarm
                        .behaviour_mut()
                        .name_exchange
                        .send_response(channel, resp);
                }
                request_response::Message::Response { response, .. } => {
                    if self
                        .names
                        .iter()
                        .any(|(p, n)| *p != peer && *n == response.name)
                    {
                        self.log(format!("WARNING duplicate name {} ({peer})", response.name));
                    }
                    // insert returns None for a new peer, so JOIN prints once
                    if self.names.insert(peer, response.name.clone()).is_none() {
                        self.log(format!("+ JOIN {} ({peer})", response.name));
                    }
                    if let Some(role) = response.role {
                        self.roles.insert(peer, role);
                    }
                }
            },
            // our request failed: timeout, unsupported protocol, connection
            // closed, ...
            request_response::Event::OutboundFailure { peer, error, .. } => {
                self.log(format!("name request to {peer} failed: {error}"));
                // tretry while still connected; a peer that doesn't speak our protocol never will
                let retry = self.swarm.is_connected(&peer)
                    && !matches!(
                        error,
                        request_response::OutboundFailure::UnsupportedProtocols
                    );
                if retry {
                    self.swarm
                        .behaviour_mut()
                        .name_exchange
                        .send_request(&peer, NameRequest);
                }
            }
            // receiving a request or sending our response failed
            request_response::Event::InboundFailure { peer, error, .. } => {
                self.log(format!("name request from {peer} failed: {error}"));
            }
            request_response::Event::ResponseSent { .. } => {}
        }
    }

    /// close connection on ping error, so dead peers are detected
    fn on_ping(&mut self, ev: ping::Event) {
        if let Err(e) = ev.result {
            self.log(format!("ping {} failed: {e}, closing connection", ev.peer));
            self.swarm.close_connection(ev.connection);
        }
    }

    /// handle the gossipsub publisher/subscriber protocol.
    fn on_gossipsub(&mut self, ev: gossipsub::Event) {
        match ev {
            gossipsub::Event::Message { message, .. } => match self.app {
                App::Discover => {}
                App::Hello => self.hello_receive(message),
                App::Byzantine(_) => self.byz_receive(message),
            },
            gossipsub::Event::Subscribed { peer_id, topic } => {
                self.log(format!("{peer_id} subscribed to {topic}"));
            }
            _ => {}
        }
    }

    /// add a line to the event log; printed immediately in plain mode
    pub(crate) fn log(&mut self, msg: impl Into<String>) {
        let line = format!(
            "{:>7.1}s  {}",
            self.start.elapsed().as_secs_f64(),
            msg.into()
        );
        if self.plain {
            println!("[{}] {line}", self.name);
        }
        self.log.push(line);
    }
}

/// q, Esc or Ctrl+C quit the tui (raw mode: Ctrl+C is a key, not a signal)
fn is_quit(ev: &Event) -> bool {
    let Event::Key(k) = ev else { return false };
    k.kind == KeyEventKind::Press
        && (matches!(k.code, KeyCode::Char('q') | KeyCode::Esc)
            || (k.code == KeyCode::Char('c') && k.modifiers.contains(KeyModifiers::CONTROL)))
}
