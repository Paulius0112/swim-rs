#!/bin/bash

# Trace syscalls for SWIM node using strace
# Shows epoll_wait, sendto, recvfrom calls with timing

set -e

BINARY="../target/release/swim-rs"
OUTPUT_DIR="./traces"
mkdir -p "$OUTPUT_DIR"

usage() {
    echo "Usage: $0 <node_addr> [seed_addr]"
    echo ""
    echo "Examples:"
    echo "  $0 127.0.0.1:9000              # Start seed node with tracing"
    echo "  $0 127.0.0.1:9001 127.0.0.1:9000  # Start node joining seed"
    echo ""
    echo "Output files:"
    echo "  traces/syscalls_<port>.log     - All syscalls"
    echo "  traces/epoll_<port>.log        - Filtered epoll calls"
    echo "  traces/network_<port>.log      - Filtered network calls"
}

if [ -z "$1" ]; then
    usage
    exit 1
fi

ADDR="$1"
SEED="$2"
PORT=$(echo "$ADDR" | cut -d: -f2)

echo "Building release binary..."
(cd .. && cargo build --release 2>&1 | tail -1)

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRACE_FILE="$OUTPUT_DIR/syscalls_${PORT}_${TIMESTAMP}.log"

echo ""
echo "=== Tracing SWIM node on $ADDR ==="
echo "Output: $TRACE_FILE"
echo ""
echo "Press Ctrl+C to stop tracing"
echo ""

# Trace with timing (-T), relative timestamps (-r), and filter relevant syscalls
if [ -z "$SEED" ]; then
    strace -T -r -f \
        -e trace=epoll_wait,epoll_ctl,sendto,recvfrom,read,write \
        -o "$TRACE_FILE" \
        env RUST_LOG=info "$BINARY" "$ADDR" &
else
    strace -T -r -f \
        -e trace=epoll_wait,epoll_ctl,sendto,recvfrom,read,write \
        -o "$TRACE_FILE" \
        env RUST_LOG=info "$BINARY" "$ADDR" "$SEED" &
fi

STRACE_PID=$!

# Wait for Ctrl+C
trap "kill $STRACE_PID 2>/dev/null; exit 0" INT TERM

wait $STRACE_PID

echo ""
echo "=== Trace Summary ==="
echo "Total syscalls: $(wc -l < "$TRACE_FILE")"
echo "epoll_wait calls: $(grep -c 'epoll_wait' "$TRACE_FILE" || echo 0)"
echo "sendto calls: $(grep -c 'sendto' "$TRACE_FILE" || echo 0)"
echo "recvfrom calls: $(grep -c 'recvfrom' "$TRACE_FILE" || echo 0)"
echo ""
echo "Trace saved to: $TRACE_FILE"
