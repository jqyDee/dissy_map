use ratatui::{
    Frame,
    layout::{Constraint, Layout},
    style::{Style, Stylize},
    text::Line,
    widgets::{Block, List, Paragraph},
};

use crate::node::Node;

/// two panes: status (own id + connected peers) on top, event log below
pub fn draw(frame: &mut Frame, node: &Node) {
    let status = status_lines(node);
    // +2 for the block borders
    let [status_area, log_area] = Layout::vertical([
        Constraint::Length(status.len() as u16 + 2),
        Constraint::Fill(1),
    ])
    .areas(frame.area());

    // render the status pane
    frame.render_widget(
        Paragraph::new(status).block(Block::bordered().title(format!(" Node {} ", node.name))),
        status_area,
    );

    // only the newest lines that fit, so the log scrolls with new messages
    let visible = log_area.height.saturating_sub(2) as usize;
    let skip = node.log.len().saturating_sub(visible);
    let items = node.log.iter().skip(skip).map(String::as_str);
    
    // render the log pane
    frame.render_widget(
        List::new(items).block(Block::bordered().title(" Messages (q to quit) ")),
        log_area,
    );
}

// compile the status lines for the tui
fn status_lines(node: &Node) -> Vec<Line<'_>> {
    let mut lines = vec![
        Line::from(format!("peer id: {}", node.swarm.local_peer_id())),
        Line::from("connected peers:".bold()),
    ];
    for p in node.swarm.connected_peers() {
        let name = node.names.get(p).map(String::as_str).unwrap_or("?");
        lines.push(Line::from(format!("  {name:<8} {p}")));
    }
    if lines.len() == 2 {
        lines.push(Line::styled("  (none yet)", Style::new().dim()));
    }
    lines
}
