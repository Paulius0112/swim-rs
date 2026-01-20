#!/bin/bash

# SWIM Protocol Benchmark Script
# Runs a cluster and measures performance metrics

set -e

BINARY="../target/release/swim-rs"
OUTPUT_DIR="./results"
mkdir -p "$OUTPUT_DIR"

# Configuration
NUM_NODES=${NUM_NODES:-4}
BASE_PORT=${BASE_PORT:-9000}
DURATION=${DURATION:-30}  # seconds

declare -a PIDS

cleanup() {
    echo ""
    echo "Stopping nodes..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null
}

trap cleanup EXIT

echo "=== SWIM Protocol Benchmark ==="
echo ""
echo "Configuration:"
echo "  Nodes: $NUM_NODES"
echo "  Duration: ${DURATION}s"
echo "  Base port: $BASE_PORT"
echo ""

# Build release binary
echo "Building release binary..."
(cd .. && cargo build --release 2>&1 | tail -1)

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$OUTPUT_DIR/benchmark_${TIMESTAMP}.txt"

echo ""
echo "Starting cluster..."

# Start seed node
SEED_ADDR="127.0.0.1:$BASE_PORT"
LOG_FILE="$OUTPUT_DIR/node_${BASE_PORT}_${TIMESTAMP}.log"
RUST_LOG=info "$BINARY" "$SEED_ADDR" > "$LOG_FILE" 2>&1 &
PIDS+=($!)
sleep 0.3

# Start other nodes
for i in $(seq 2 $NUM_NODES); do
    PORT=$((BASE_PORT + i - 1))
    ADDR="127.0.0.1:$PORT"
    LOG_FILE="$OUTPUT_DIR/node_${PORT}_${TIMESTAMP}.log"
    RUST_LOG=info "$BINARY" "$ADDR" "$SEED_ADDR" > "$LOG_FILE" 2>&1 &
    PIDS+=($!)
    sleep 0.3
done

echo "Cluster started with $NUM_NODES nodes"
echo "Running for ${DURATION} seconds..."
echo ""

# Let it run
sleep "$DURATION"

echo "Collecting results..."
echo ""

# Stop nodes
cleanup
trap - EXIT
sleep 1

# Analyze logs
echo "=== Benchmark Results ===" | tee "$RESULT_FILE"
echo "Timestamp: $TIMESTAMP" | tee -a "$RESULT_FILE"
echo "Nodes: $NUM_NODES" | tee -a "$RESULT_FILE"
echo "Duration: ${DURATION}s" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# Extract RTT data from logs
echo "=== RTT Latency (from logs) ===" | tee -a "$RESULT_FILE"

for i in $(seq 1 $NUM_NODES); do
    PORT=$((BASE_PORT + i - 1))
    LOG_FILE="$OUTPUT_DIR/node_${PORT}_${TIMESTAMP}.log"

    if [ -f "$LOG_FILE" ]; then
        # Extract RTT values
        RTT_VALUES=$(grep -oP 'RTT: \K[0-9.]+[µnm]s' "$LOG_FILE" 2>/dev/null | head -100)

        if [ -n "$RTT_VALUES" ]; then
            echo "" | tee -a "$RESULT_FILE"
            echo "Node $i (port $PORT):" | tee -a "$RESULT_FILE"

            # Count samples
            SAMPLE_COUNT=$(echo "$RTT_VALUES" | wc -l)
            echo "  Samples: $SAMPLE_COUNT" | tee -a "$RESULT_FILE"

            # Get last stats line from log
            LAST_STATS=$(grep "RTT:" "$LOG_FILE" | tail -1)
            if [ -n "$LAST_STATS" ]; then
                echo "  $LAST_STATS" | tee -a "$RESULT_FILE"
            fi
        fi
    fi
done

echo "" | tee -a "$RESULT_FILE"
echo "=== Message Counts ===" | tee -a "$RESULT_FILE"

for i in $(seq 1 $NUM_NODES); do
    PORT=$((BASE_PORT + i - 1))
    LOG_FILE="$OUTPUT_DIR/node_${PORT}_${TIMESTAMP}.log"

    if [ -f "$LOG_FILE" ]; then
        PINGS=$(grep -c "Sent PING" "$LOG_FILE" 2>/dev/null || echo 0)
        ACKS=$(grep -c "Received ACK" "$LOG_FILE" 2>/dev/null || echo 0)
        echo "Node $i: $PINGS pings sent, $ACKS acks received" | tee -a "$RESULT_FILE"
    fi
done

echo "" | tee -a "$RESULT_FILE"
echo "Results saved to: $RESULT_FILE"
echo "Log files in: $OUTPUT_DIR/"
