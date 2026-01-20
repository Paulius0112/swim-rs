# swim-rs

A Rust implementation of the SWIM (Scalable Weakly-consistent Infection-style Process Group Membership) gossip protocol.

## Overview

SWIM is a protocol for maintaining membership information in large-scale distributed systems. It provides:

- **Failure detection** - Detects when nodes become unreachable
- **Membership dissemination** - Spreads membership updates across the cluster
- **Scalability** - O(1) message load per member per protocol period

## How It Works

1. **Periodic Probing**: Each node periodically selects a random member and sends a `Ping`
2. **Direct Ack**: If the target responds with an `Ack`, it's considered alive
3. **Indirect Probing**: If no `Ack` is received, the node asks other members to probe the target via `PingReq`
4. **Failure Suspicion**: If indirect probes also fail, the target is marked as `Suspect`
5. **Failure Confirmation**: After a timeout, `Suspect` members are marked as `Dead`

## State Transitions

```
Active ──(probe timeout + indirect timeout)──> Suspect ──(suspect timeout)──> Dead
   ^                                              │
   └────────────────(ack received)────────────────┘
```

## Building

```bash
cargo build
```

## Running

### Using `just` (recommended)

```bash
# Show available commands
just

# Run the demo (shows instructions)
just demo

# Run individual nodes in separate terminals
just node1  # Seed node on :9000
just node2  # Joins seed on :9001
just node3  # Joins seed on :9002
just node4  # Joins seed on :9003

# Or run interactive cluster
just cluster
```

### Using cargo directly

```bash
# Start seed node
RUST_LOG=info cargo run -- 127.0.0.1:9000

# Start additional nodes (in separate terminals)
RUST_LOG=info cargo run -- 127.0.0.1:9001 127.0.0.1:9000
RUST_LOG=info cargo run -- 127.0.0.1:9002 127.0.0.1:9000
```

### Using test scripts

```bash
# Interactive cluster manager
./test_cluster.sh

# Or run nodes manually
./run_demo.sh start  # Shows instructions
./run_demo.sh node1  # Run in terminal 1
./run_demo.sh node2  # Run in terminal 2
# etc.
```

## Demo: Failure Detection

1. Start 4 nodes using `just cluster` or in separate terminals
2. Watch the tick logs show membership growing
3. Kill one node with Ctrl+C
4. Watch other nodes detect the failure:
   - First they'll try indirect probing
   - Then mark the node as `SUSPECT`
   - After timeout, mark as `DEAD`

## Protocol Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `TICK_INTERVAL` | 1s | How often to probe members |
| `PROBE_TIMEOUT` | 500ms | Time to wait for Ack before indirect probing |
| `SUSPECT_TIMEOUT` | 3s | Time before Suspect becomes Dead |
| `INDIRECT_PROBE_COUNT` | 3 | Number of members to ask for indirect probes |

## Messages

- **Ping** - Direct probe, expects Ack back
- **Ack** - Response to Ping
- **PingReq** - Request another node to probe a target on your behalf

## Dependencies

- `mio` - Non-blocking I/O
- `postcard` + `serde` - Binary serialization
- `rand` - Random member selection
- `tracing` - Logging
- `clap` - CLI argument parsing
- `anyhow` - Error handling

## References

- [SWIM: Scalable Weakly-consistent Infection-style Process Group Membership Protocol](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf) - Original paper by Abhinandan Das, Indranil Gupta, Ashish Motivala
