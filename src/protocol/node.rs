use std::{
    collections::{HashMap, VecDeque},
    io,
    net::{SocketAddr, ToSocketAddrs},
    time::{Duration, Instant},
};

use anyhow::Result;
use mio::{Events, Interest, Poll, Token, net::UdpSocket};
use rand::RngCore;
use tracing::{info, warn};

use crate::protocol::messages::Message;
use crate::protocol::metrics::LatencyMetrics;

// Protocol timing constants
const TICK_INTERVAL: Duration = Duration::from_secs(1);
const PROBE_TIMEOUT: Duration = Duration::from_millis(500);
const SUSPECT_TIMEOUT: Duration = Duration::from_secs(3);
const INDIRECT_PROBE_COUNT: usize = 3;

/// Tracks an outgoing probe that's awaiting an Ack
pub struct PendingProbe {
    pub seq: u32,
    pub target: SocketAddr,
    pub sent_at: Instant,
    /// Whether we've already tried indirect probing for this target
    pub indirect_sent: bool,
}

/// Queued outgoing message
struct OutgoingMessage {
    data: Vec<u8>,
    target: SocketAddr,
}

pub struct Membership {
    pub self_seq: u32,
    pub members: HashMap<SocketAddr, Member>,
}

impl Membership {
    pub fn new() -> Self {
        Self {
            self_seq: 0,
            members: HashMap::new(),
        }
    }

    pub fn next_seq(&mut self) -> u32 {
        let seq = self.self_seq;
        self.self_seq = self.self_seq.wrapping_add(1);
        seq
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PeerState {
    Active,
    Suspect,
    Dead,
}

pub struct Member {
    pub state: PeerState,
    pub incarnation: u32,
    pub last_state_change: Instant,
}

pub struct Node {
    pub socket: UdpSocket,
    pub local_addr: SocketAddr,
    pub members: Membership,
    pub probes: Vec<PendingProbe>,
    send_queue: VecDeque<OutgoingMessage>,
    last_tick: Instant,
    pub metrics: LatencyMetrics,
}

// Single token for our UDP socket
const UDP_SOCKET: Token = Token(0);

impl Node {
    pub fn new(addr: String) -> Result<Self> {
        let socket_addr = addr.to_socket_addrs()?.last().unwrap();
        let socket = UdpSocket::bind(socket_addr)?;
        let local_addr = socket.local_addr()?;

        info!("Node started on {}", local_addr);

        Ok(Self {
            socket,
            local_addr,
            members: Membership::new(),
            probes: Vec::new(),
            send_queue: VecDeque::new(),
            last_tick: Instant::now(),
            metrics: LatencyMetrics::new(1000), // Keep last 1000 samples
        })
    }

    /// Queue a join request to the specified peer address.
    pub fn join(&mut self, addr: String) -> Result<()> {
        info!("Joining cluster via {}", addr);
        let target: SocketAddr = addr.parse()?;

        self.send_ping(target)?;
        Ok(())
    }

    /// Send a ping to a target and track it as a pending probe
    fn send_ping(&mut self, target: SocketAddr) -> Result<()> {
        let seq = self.members.next_seq();

        let probe = PendingProbe {
            seq,
            target,
            sent_at: Instant::now(),
            indirect_sent: false,
        };
        self.probes.push(probe);

        let msg = Message::Ping {
            seq,
            from: self.local_addr,
        };

        let bytes = msg.to_bytes()?;
        self.queue_send(bytes, target);
        self.metrics.record_ping_sent();
        info!("Sent PING seq={} to {}", seq, target);

        Ok(())
    }

    /// Request indirect probes through other members
    fn send_indirect_probes(&mut self, target: SocketAddr, seq: u32) -> Result<()> {
        let others: Vec<SocketAddr> = self
            .members
            .members
            .iter()
            .filter(|(&addr, m)| addr != target && m.state == PeerState::Active)
            .map(|(&addr, _)| addr)
            .collect();

        if others.is_empty() {
            info!("No other members available for indirect probe of {}", target);
            return Ok(());
        }

        // Pick up to INDIRECT_PROBE_COUNT random members
        let count = others.len().min(INDIRECT_PROBE_COUNT);
        let mut selected = Vec::with_capacity(count);
        let mut indices: Vec<usize> = (0..others.len()).collect();

        for _ in 0..count {
            let idx = rand::rng().next_u32() as usize % indices.len();
            selected.push(others[indices[idx]]);
            indices.swap_remove(idx);
        }

        for intermediary in selected {
            let msg = Message::PingReq {
                seq,
                from: self.local_addr,
                target,
            };
            let bytes = msg.to_bytes()?;
            self.queue_send(bytes, intermediary);
            info!(
                "Sent PING-REQ seq={} to {} for target {}",
                seq, intermediary, target
            );
        }

        Ok(())
    }

    fn queue_send(&mut self, data: Vec<u8>, target: SocketAddr) {
        self.send_queue.push_back(OutgoingMessage { data, target });
    }

    fn flush_send_queue(&mut self) -> io::Result<bool> {
        while let Some(msg) = self.send_queue.front() {
            match self.socket.send_to(&msg.data, msg.target) {
                Ok(bytes) => {
                    info!("Sent {} bytes to {}", bytes, msg.target);
                    self.send_queue.pop_front();
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                    return Ok(false);
                }
                Err(e) => return Err(e),
            }
        }
        Ok(true)
    }

    fn handle_message(&mut self, msg: Message) -> Result<()> {
        match msg {
            Message::Ping { seq, from } => {
                info!("Received PING seq={} from {}", seq, from);

                // Ensure sender is in our membership list
                self.ensure_member(from);

                // Send Ack back
                let ack = Message::Ack {
                    seq,
                    from: self.local_addr,
                };
                let bytes = ack.to_bytes()?;
                self.queue_send(bytes, from);
            }

            Message::Ack { seq, from } => {
                // Calculate RTT if we have a matching probe
                if let Some(probe) = self.probes.iter().find(|p| p.seq == seq && p.target == from) {
                    let rtt = probe.sent_at.elapsed();
                    self.metrics.record_rtt(rtt);
                    info!("Received ACK seq={} from {} (RTT: {:?})", seq, from, rtt);
                } else {
                    info!("Received ACK seq={} from {} (no matching probe)", seq, from);
                }

                // Remove matching probe
                self.probes.retain(|p| !(p.seq == seq && p.target == from));

                // Mark member as active
                self.mark_active(from);
            }

            Message::PingReq { seq, from, target } => {
                info!(
                    "Received PING-REQ seq={} from {} for target {}",
                    seq, from, target
                );

                // Ensure requester is in our membership
                self.ensure_member(from);

                // Send a ping to target, but when we get an ack, forward it to `from`
                // For simplicity, we'll directly ping and let the ack handling work
                // We need to track that this is on behalf of someone else

                // Send ping to target
                let ping = Message::Ping {
                    seq,
                    from: self.local_addr,
                };
                let bytes = ping.to_bytes()?;
                self.queue_send(bytes, target);

                // We'll also need to forward any ack we receive back to the original requester
                // For now, simplified: we just ping the target
                // A full implementation would track indirect probe requests
            }
        }

        Ok(())
    }

    /// Ensure a member exists in our list, add if not present
    fn ensure_member(&mut self, addr: SocketAddr) {
        if addr != self.local_addr && !self.members.members.contains_key(&addr) {
            info!("Adding new member: {}", addr);
            self.members.members.insert(
                addr,
                Member {
                    state: PeerState::Active,
                    incarnation: 0,
                    last_state_change: Instant::now(),
                },
            );
        }
    }

    /// Mark a member as active
    fn mark_active(&mut self, addr: SocketAddr) {
        if let Some(member) = self.members.members.get_mut(&addr) {
            if member.state != PeerState::Active {
                info!("Member {} is now ACTIVE", addr);
                member.state = PeerState::Active;
                member.last_state_change = Instant::now();
            }
        } else {
            self.ensure_member(addr);
        }
    }

    /// Mark a member as suspect
    fn mark_suspect(&mut self, addr: SocketAddr) {
        if let Some(member) = self.members.members.get_mut(&addr) {
            if member.state == PeerState::Active {
                warn!("Member {} is now SUSPECT", addr);
                member.state = PeerState::Suspect;
                member.last_state_change = Instant::now();
            }
        }
    }

    /// Mark a member as dead
    fn mark_dead(&mut self, addr: SocketAddr) {
        if let Some(member) = self.members.members.get_mut(&addr) {
            if member.state != PeerState::Dead {
                warn!("Member {} is now DEAD", addr);
                member.state = PeerState::Dead;
                member.last_state_change = Instant::now();
            }
        }
    }

    /// Called every tick interval
    fn tick(&mut self) -> Result<()> {
        // Print membership status
        info!(
            "=== TICK === Members: {} active, {} suspect, {} dead | Pings: {} sent, {} acked, {} timeouts",
            self.count_by_state(PeerState::Active),
            self.count_by_state(PeerState::Suspect),
            self.count_by_state(PeerState::Dead),
            self.metrics.pings_sent,
            self.metrics.acks_received,
            self.metrics.timeouts,
        );

        // Print latency stats if we have samples
        if let Some(stats) = self.metrics.stats() {
            info!("{}", stats);
        }

        // 1. Check for timed-out probes
        self.check_probe_timeouts()?;

        // 2. Check for suspects that should become dead
        self.check_suspect_timeouts();

        // 3. Probe a random active member
        self.probe_random_member()?;

        Ok(())
    }

    fn count_by_state(&self, state: PeerState) -> usize {
        self.members
            .members
            .values()
            .filter(|m| m.state == state)
            .count()
    }

    fn check_probe_timeouts(&mut self) -> Result<()> {
        let now = Instant::now();
        let mut timed_out = Vec::new();
        let mut need_indirect = Vec::new();

        for probe in &self.probes {
            if now.duration_since(probe.sent_at) > PROBE_TIMEOUT {
                if !probe.indirect_sent {
                    need_indirect.push((probe.target, probe.seq));
                } else {
                    timed_out.push(probe.target);
                }
            }
        }

        // Request indirect probes for those that haven't had them yet
        for (target, seq) in need_indirect {
            info!("Direct probe to {} timed out, trying indirect", target);
            self.send_indirect_probes(target, seq)?;

            // Mark the probe as having indirect sent
            for probe in &mut self.probes {
                if probe.target == target {
                    probe.indirect_sent = true;
                    probe.sent_at = Instant::now(); // Reset timer for indirect probe
                }
            }
        }

        // Mark as suspect those that timed out even with indirect probes
        for target in timed_out {
            info!("Indirect probe to {} also timed out, marking suspect", target);
            self.mark_suspect(target);
            self.metrics.record_timeout();
        }

        // Remove timed out probes
        self.probes
            .retain(|p| now.duration_since(p.sent_at) <= PROBE_TIMEOUT || !p.indirect_sent);

        Ok(())
    }

    fn check_suspect_timeouts(&mut self) {
        let now = Instant::now();
        let mut to_mark_dead = Vec::new();

        for (&addr, member) in &self.members.members {
            if member.state == PeerState::Suspect
                && now.duration_since(member.last_state_change) > SUSPECT_TIMEOUT
            {
                to_mark_dead.push(addr);
            }
        }

        for addr in to_mark_dead {
            self.mark_dead(addr);
        }
    }

    fn probe_random_member(&mut self) -> Result<()> {
        let active: Vec<SocketAddr> = self
            .members
            .members
            .iter()
            .filter(|(_, m)| m.state == PeerState::Active)
            .map(|(&addr, _)| addr)
            .collect();

        if active.is_empty() {
            return Ok(());
        }

        let rnd_index = rand::rng().next_u32() as usize % active.len();
        let target = active[rnd_index];

        // Don't probe if we already have a pending probe for this target
        if self.probes.iter().any(|p| p.target == target) {
            return Ok(());
        }

        self.send_ping(target)?;
        Ok(())
    }

    pub fn event_loop(&mut self) -> Result<()> {
        let mut poll = Poll::new()?;
        let mut events = Events::with_capacity(128);

        poll.registry()
            .register(&mut self.socket, UDP_SOCKET, Interest::READABLE | Interest::WRITABLE)?;

        info!("Event loop started");
        let mut buf = [0; 1 << 16];

        loop {
            // Calculate timeout until next tick
            let elapsed = self.last_tick.elapsed();
            let timeout = if elapsed >= TICK_INTERVAL {
                Some(Duration::ZERO)
            } else {
                Some(TICK_INTERVAL - elapsed)
            };

            if let Err(e) = poll.poll(&mut events, timeout) {
                if e.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(e.into());
            }

            // Check if tick is due
            if self.last_tick.elapsed() >= TICK_INTERVAL {
                self.tick()?;
                self.last_tick = Instant::now();
            }

            // Always try to flush send queue (edge-triggered epoll won't re-notify)
            let _ = self.flush_send_queue();

            // Process socket events
            for event in events.iter() {
                match event.token() {
                    UDP_SOCKET => {
                        // Handle readable
                        if event.is_readable() {
                            loop {
                                match self.socket.recv_from(&mut buf) {
                                    Ok((packet_size, _source)) => {
                                        match Message::from_bytes(&buf[..packet_size]) {
                                            Ok(msg) => {
                                                if let Err(e) = self.handle_message(msg) {
                                                    warn!("Error handling message: {}", e);
                                                }
                                            }
                                            Err(e) => {
                                                warn!("Failed to parse message: {}", e);
                                            }
                                        }
                                    }
                                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                                        break;
                                    }
                                    Err(e) => {
                                        return Err(e.into());
                                    }
                                }
                            }
                        }

                        // Handle writable
                        if event.is_writable() {
                            self.flush_send_queue()?;
                        }
                    }
                    _ => {
                        warn!("Unexpected event token");
                    }
                }
            }
        }
    }
}
