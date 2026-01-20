#!/bin/bash

# Simple SWIM demo - runs nodes with clear output
# Usage: ./run_demo.sh [start|node1|node2|node3|node4]

set -e

BINARY="./target/debug/swim-rs"
export RUST_LOG=info

case "$1" in
    start)
        echo "Building..."
        cargo build 2>&1 | tail -1
        echo ""
        echo "=== SWIM Gossip Protocol Demo ==="
        echo ""
        echo "Open 4 terminal windows and run:"
        echo "  Terminal 1: ./run_demo.sh node1"
        echo "  Terminal 2: ./run_demo.sh node2"
        echo "  Terminal 3: ./run_demo.sh node3"
        echo "  Terminal 4: ./run_demo.sh node4"
        echo ""
        echo "Then try killing node2 or node3 with Ctrl+C"
        echo "and watch the others detect the failure!"
        echo ""
        ;;
    node1)
        echo "=== Node 1 (Seed) - 127.0.0.1:9000 ==="
        $BINARY "127.0.0.1:9000"
        ;;
    node2)
        echo "=== Node 2 - 127.0.0.1:9001 (joining via seed) ==="
        $BINARY "127.0.0.1:9001" "127.0.0.1:9000"
        ;;
    node3)
        echo "=== Node 3 - 127.0.0.1:9002 (joining via seed) ==="
        $BINARY "127.0.0.1:9002" "127.0.0.1:9000"
        ;;
    node4)
        echo "=== Node 4 - 127.0.0.1:9003 (joining via seed) ==="
        $BINARY "127.0.0.1:9003" "127.0.0.1:9000"
        ;;
    *)
        echo "Usage: $0 [start|node1|node2|node3|node4]"
        echo ""
        echo "  start - Build and show instructions"
        echo "  node1 - Run seed node on port 9000"
        echo "  node2 - Run node on port 9001, join seed"
        echo "  node3 - Run node on port 9002, join seed"
        echo "  node4 - Run node on port 9003, join seed"
        ;;
esac
