#!/bin/bash

# Profile SWIM node with perf to show CPU usage and hotspots
# Requires: linux-tools-generic (perf)

set -e

BINARY="../target/release/swim-rs"
OUTPUT_DIR="./profiles"
mkdir -p "$OUTPUT_DIR"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  record <addr> [seed]  - Record perf data for a node"
    echo "  stat <addr> [seed]    - Show real-time perf stats"
    echo "  flamegraph <addr> [seed] - Generate flamegraph (requires flamegraph tool)"
    echo ""
    echo "Examples:"
    echo "  $0 record 127.0.0.1:9000"
    echo "  $0 stat 127.0.0.1:9001 127.0.0.1:9000"
    echo "  $0 flamegraph 127.0.0.1:9000"
}

check_perf() {
    if ! command -v perf &> /dev/null; then
        echo "Error: perf not found. Install with:"
        echo "  sudo apt install linux-tools-generic linux-tools-\$(uname -r)"
        exit 1
    fi
}

build_release() {
    echo "Building release binary with debug info..."
    (cd .. && RUSTFLAGS="-C debuginfo=2" cargo build --release 2>&1 | tail -1)
}

case "$1" in
    record)
        check_perf
        build_release

        ADDR="$2"
        SEED="$3"
        PORT=$(echo "$ADDR" | cut -d: -f2)
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        PERF_FILE="$OUTPUT_DIR/perf_${PORT}_${TIMESTAMP}.data"

        echo ""
        echo "=== Recording perf data for node on $ADDR ==="
        echo "Output: $PERF_FILE"
        echo "Press Ctrl+C to stop (after ~10-30 seconds of data)"
        echo ""

        if [ -z "$SEED" ]; then
            sudo perf record -g -o "$PERF_FILE" -- \
                env RUST_LOG=info "$BINARY" "$ADDR"
        else
            sudo perf record -g -o "$PERF_FILE" -- \
                env RUST_LOG=info "$BINARY" "$ADDR" "$SEED"
        fi

        echo ""
        echo "Generating report..."
        sudo perf report -i "$PERF_FILE" --stdio > "${PERF_FILE%.data}.txt"
        echo "Report saved to: ${PERF_FILE%.data}.txt"
        echo ""
        echo "View interactively with: sudo perf report -i $PERF_FILE"
        ;;

    stat)
        check_perf
        build_release

        ADDR="$2"
        SEED="$3"

        echo ""
        echo "=== Real-time perf stats for node on $ADDR ==="
        echo "Shows CPU cycles, instructions, cache misses, etc."
        echo "Press Ctrl+C to stop"
        echo ""

        if [ -z "$SEED" ]; then
            sudo perf stat -d -- env RUST_LOG=warn "$BINARY" "$ADDR"
        else
            sudo perf stat -d -- env RUST_LOG=warn "$BINARY" "$ADDR" "$SEED"
        fi
        ;;

    flamegraph)
        check_perf

        if ! command -v flamegraph &> /dev/null; then
            echo "Installing flamegraph tool..."
            cargo install flamegraph
        fi

        build_release

        ADDR="$2"
        SEED="$3"
        PORT=$(echo "$ADDR" | cut -d: -f2)
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        SVG_FILE="$OUTPUT_DIR/flamegraph_${PORT}_${TIMESTAMP}.svg"

        echo ""
        echo "=== Generating flamegraph for node on $ADDR ==="
        echo "Output: $SVG_FILE"
        echo "Let it run for 10-30 seconds, then press Ctrl+C"
        echo ""

        if [ -z "$SEED" ]; then
            sudo -E flamegraph -o "$SVG_FILE" -- \
                env RUST_LOG=warn "$BINARY" "$ADDR"
        else
            sudo -E flamegraph -o "$SVG_FILE" -- \
                env RUST_LOG=warn "$BINARY" "$ADDR" "$SEED"
        fi

        echo ""
        echo "Flamegraph saved to: $SVG_FILE"
        echo "Open in browser to view interactively"
        ;;

    *)
        usage
        exit 1
        ;;
esac
