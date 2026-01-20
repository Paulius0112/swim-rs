# swim-rs

A high-performance Rust implementation of the [SWIM gossip protocol](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf) using `mio` and Linux `epoll`.

<!-- Add a GIF here: ![Demo](demo.gif) -->

## Demo

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Node 1 (seed)                    Node 2                    Node 3          │
│  127.0.0.1:9000                   127.0.0.1:9001            127.0.0.1:9002  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [12:35:05] Node started          [12:35:05] Joining...                     │
│  [12:35:05] ← PING from :9001     [12:35:05] PING → :9000                   │
│  [12:35:05] ACK → :9001           [12:35:05] ← ACK (RTT: 144µs) ✓           │
│                                                                             │
│  === TICK ===                     === TICK ===              === TICK ===   │
│  Members: 2 active                Members: 1 active         Members: 1     │
│  RTT: 64µs mean, 7µs jitter       RTT: 57µs mean                            │
│                                                                             │
│  [12:35:15] Kill Node 2 (Ctrl+C)  [TERMINATED]                              │
│                                                                             │
│  [12:35:16] PING → :9001 ...                                                │
│  [12:35:16] timeout! trying indirect probe                                  │
│  [12:35:17] ⚠ Member :9001 is now SUSPECT                                   │
│  [12:35:20] ✗ Member :9001 is now DEAD                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Try it yourself:**
```bash
just cluster    # Start 4-node cluster, then type: kill 2
```

## Performance

Measured on localhost with `strace` and protocol-level metrics:

| Metric | Value |
|--------|-------|
| **RTT (ping → ack)** | 46-144 µs |
| **Mean latency** | ~60-90 µs |
| **P99 latency** | ~144 µs |
| **Jitter** | 7-33 µs |
| **Idle CPU** | 0% (epoll blocks efficiently) |

```
epoll_wait(...) = 1     <0.000010s>   ← event ready
sendto(9 bytes)         <0.000052s>   ← send ping
recvfrom(9 bytes)       <0.000014s>   ← receive ack
epoll_wait(...) = 0     <1.001033s>   ← sleep 1s (zero CPU!)
```

## Why epoll?

| poll() / select() | epoll() |
|-------------------|---------|
| O(n) - scan ALL fds | O(1) - only ready fds |
| Copy fd set every call | Register once, reuse |
| 10k connections = 10k checks | 10k connections = check only active |

## Quick Start

```bash
# Install
git clone https://github.com/Paulius0112/swim-rs
cd swim-rs
cargo build --release

# Run 4-node cluster
just cluster

# Or manually in separate terminals:
just node1   # Seed node on :9000
just node2   # Joins via :9000
just node3
just node4
```

## How SWIM Works

```
        ┌──────────┐         PING          ┌──────────┐
        │  Node A  │ ───────────────────►  │  Node B  │
        │          │ ◄───────────────────  │          │
        └──────────┘         ACK           └──────────┘
              │
              │ timeout?
              ▼
        ┌──────────┐       PING-REQ        ┌──────────┐
        │  Node A  │ ───────────────────►  │  Node C  │
        │          │    "ping B for me"    │          │
        └──────────┘                       └──────────┘
                                                │
                                                │ PING
                                                ▼
                                          ┌──────────┐
                                          │  Node B  │
                                          │  (dead?) │
                                          └──────────┘
```

**State Machine:**
```
Active ──(probe timeout)──► Suspect ──(suspect timeout)──► Dead
   ▲                            │
   └────────(ack received)──────┘
```

## Protocol Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `TICK_INTERVAL` | 1s | How often to probe members |
| `PROBE_TIMEOUT` | 500ms | Time to wait for Ack |
| `SUSPECT_TIMEOUT` | 3s | Time before Suspect → Dead |
| `INDIRECT_PROBE_COUNT` | 3 | Nodes to ask for indirect probe |

## Benchmarking

```bash
just bench              # Run 30s benchmark
just trace-syscalls 127.0.0.1:9000   # strace epoll/sendto/recvfrom
just perf-stat 127.0.0.1:9000        # CPU performance counters
just flamegraph 127.0.0.1:9000       # Generate flamegraph
just visualize results/*.log          # Plot latency charts
```

## Project Structure

```
src/
├── main.rs              # CLI entry point
├── lib.rs               # Library exports
└── protocol/
    ├── node.rs          # Core Node implementation + event loop
    ├── messages.rs      # Ping, Ack, PingReq
    └── metrics.rs       # RTT tracking, jitter calculation

bench/
├── benchmark.sh         # Run cluster and collect stats
├── trace_syscalls.sh    # strace wrapper
├── analyze_trace.py     # Parse strace output
└── visualize_latency.py # Plot RTT distribution
```

## References

- [SWIM Paper](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf) - Original protocol by Das, Gupta, Motivala
- [mio](https://github.com/tokio-rs/mio) - Metal I/O library for Rust
- [epoll(7)](https://man7.org/linux/man-pages/man7/epoll.7.html) - Linux I/O event notification

## License

MIT
