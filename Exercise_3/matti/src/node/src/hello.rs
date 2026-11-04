use libp2p::gossipsub::{self, IdentTopic};

use crate::{behaviours::VERSION, node::Node};

impl Node {
    /// subscribe to the topic in gossipsip
    pub(crate) fn hello_init(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        self.swarm.behaviour_mut().gossipsub.subscribe(&topic())?;
        Ok(())
    }

    /// tick/publish a new message
    pub(crate) fn hello_tick(&mut self) {
        let msg = format!("Hello from Node {}", self.name);
        if let Err(e) = self.swarm.behaviour_mut().gossipsub.publish(topic(), msg) {
            self.log(format!("publish failed: {e}"));
        }
    }

    /// receive a published message on the topic you subscribed to
    pub(crate) fn hello_receive(&mut self, message: gossipsub::Message) {
        // sender = signed source PeerId, mapped to the name from name exchange
        let from = message
            .source
            .and_then(|p| self.names.get(&p).cloned())
            .unwrap_or_else(|| "?".into());
        self.log(format!(
            "<- {from}: {}",
            String::from_utf8_lossy(&message.data)
        ));
    }
}

/// topic/protocol name
fn topic() -> IdentTopic {
    IdentTopic::new(format!("/dissy/hello/{}", VERSION))
}
