# SWIM Gossip Protocol - Justfile

# Default recipe: show available commands
default:
    @just --list

# Build the project
build:
    cargo build

# Build release version
release:
    cargo build --release

# Run a single node (usage: just run 127.0.0.1:9000 [seed_addr])
run addr *seeds:
    RUST_LOG=info cargo run -- {{addr}} {{seeds}}

# Run the seed node on port 9000
node1:
    RUST_LOG=info cargo run -- 127.0.0.1:9000

# Run node 2, joining seed
node2:
    RUST_LOG=info cargo run -- 127.0.0.1:9001 127.0.0.1:9000

# Run node 3, joining seed
node3:
    RUST_LOG=info cargo run -- 127.0.0.1:9002 127.0.0.1:9000

# Run node 4, joining seed
node4:
    RUST_LOG=info cargo run -- 127.0.0.1:9003 127.0.0.1:9000

# Run the interactive cluster test script
cluster:
    ./test_cluster.sh

# Run tests
test:
    cargo test

# Check code without building
check:
    cargo check

# Format code
fmt:
    cargo fmt

# Run clippy linter
lint:
    cargo clippy

# Clean build artifacts
clean:
    cargo clean

# Watch for changes and rebuild
watch:
    cargo watch -x build

# Show demo instructions
demo:
    @echo "=== SWIM Gossip Protocol Demo ==="
    @echo ""
    @echo "Open 4 terminals and run:"
    @echo "  Terminal 1: just node1"
    @echo "  Terminal 2: just node2"
    @echo "  Terminal 3: just node3"
    @echo "  Terminal 4: just node4"
    @echo ""
    @echo "Or run the interactive cluster:"
    @echo "  just cluster"
    @echo ""
    @echo "Then try killing a node with Ctrl+C"
    @echo "and watch the others detect the failure!"

# ============ Benchmarking & Profiling ============

# Run benchmark (30 seconds by default)
bench duration="30":
    cd bench && DURATION={{duration}} ./benchmark.sh

# Trace syscalls with strace (shows epoll_wait, sendto, recvfrom)
trace-syscalls addr seed="":
    cd bench && ./trace_syscalls.sh {{addr}} {{seed}}

# Analyze strace output
analyze-trace file:
    cd bench && python3 analyze_trace.py {{file}}

# Profile with perf (record mode)
perf-record addr seed="":
    cd bench && ./perf_profile.sh record {{addr}} {{seed}}

# Profile with perf (stat mode - real-time stats)
perf-stat addr seed="":
    cd bench && ./perf_profile.sh stat {{addr}} {{seed}}

# Generate flamegraph
flamegraph addr seed="":
    cd bench && ./perf_profile.sh flamegraph {{addr}} {{seed}}

# Visualize latency from log files
visualize *files:
    cd bench && python3 visualize_latency.py {{files}}

# Show benchmarking help
bench-help:
    @echo "=== SWIM Benchmarking & Profiling ==="
    @echo ""
    @echo "Quick benchmark:"
    @echo "  just bench              # Run 30s benchmark with 4 nodes"
    @echo "  just bench 60           # Run 60s benchmark"
    @echo ""
    @echo "Syscall tracing (shows epoll efficiency):"
    @echo "  just trace-syscalls 127.0.0.1:9000"
    @echo "  just trace-syscalls 127.0.0.1:9001 127.0.0.1:9000"
    @echo "  just analyze-trace bench/traces/syscalls_9000_*.log"
    @echo ""
    @echo "CPU profiling:"
    @echo "  just perf-stat 127.0.0.1:9000      # Real-time CPU stats"
    @echo "  just perf-record 127.0.0.1:9000    # Record profile"
    @echo "  just flamegraph 127.0.0.1:9000     # Generate flamegraph"
    @echo ""
    @echo "Latency visualization:"
    @echo "  just visualize bench/results/*.log"
    @echo ""
    @echo "What to look for:"
    @echo "  - epoll_wait with long waits = efficient (no busy polling)"
    @echo "  - Low RTT variance = consistent performance"
    @echo "  - sendto/recvfrom < 10µs = fast syscalls"
