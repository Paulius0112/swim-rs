use std::net::SocketAddr;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Message {
    /// Direct probe - expects Ack back
    Ping { seq: u32, from: SocketAddr },
    /// Response to Ping or PingReq
    Ack { seq: u32, from: SocketAddr },
    /// Indirect probe request - asks a node to ping target on our behalf
    PingReq {
        seq: u32,
        from: SocketAddr,
        target: SocketAddr,
    },
}

impl Message {
    pub fn to_bytes(&self) -> Result<Vec<u8>, postcard::Error> {
        postcard::to_allocvec(self)
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, postcard::Error> {
        postcard::from_bytes(bytes)
    }
}
