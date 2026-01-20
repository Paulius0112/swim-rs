#!/bin/bash

# SWIM Gossip Protocol Test Script
# This script starts multiple nodes and demonstrates failure detection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BINARY="./target/debug/swim-rs"
BASE_PORT=9000
NUM_NODES=4

# Arrays to track PIDs
declare -a PIDS

cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    wait 2>/dev/null
    echo -e "${GREEN}All nodes stopped.${NC}"
}

trap cleanup EXIT

# Build the project
echo -e "${BLUE}Building project...${NC}"
cargo build 2>&1 | tail -1

echo -e "${GREEN}Build complete!${NC}\n"

# Start the first node (seed node)
SEED_ADDR="127.0.0.1:$BASE_PORT"
echo -e "${GREEN}Starting Node 1 (seed) on $SEED_ADDR${NC}"
RUST_LOG=info $BINARY "$SEED_ADDR" &
PIDS+=($!)
sleep 0.5

# Start remaining nodes, each joining via the seed
for i in $(seq 2 $NUM_NODES); do
    PORT=$((BASE_PORT + i - 1))
    ADDR="127.0.0.1:$PORT"
    echo -e "${GREEN}Starting Node $i on $ADDR (joining via $SEED_ADDR)${NC}"
    RUST_LOG=info $BINARY "$ADDR" "$SEED_ADDR" &
    PIDS+=($!)
    sleep 0.5
done

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Cluster started with $NUM_NODES nodes${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "\nNode addresses:"
for i in $(seq 1 $NUM_NODES); do
    PORT=$((BASE_PORT + i - 1))
    echo -e "  Node $i: 127.0.0.1:$PORT (PID: ${PIDS[$((i-1))]})"
done

echo -e "\n${YELLOW}Commands:${NC}"
echo -e "  ${GREEN}kill <N>${NC}  - Kill node N (e.g., 'kill 2')"
echo -e "  ${GREEN}status${NC}    - Show running nodes"
echo -e "  ${GREEN}quit${NC}      - Stop all nodes and exit"
echo -e "\n${BLUE}Watch the logs to see failure detection in action!${NC}"
echo -e "${BLUE}When you kill a node, others will detect it as SUSPECT then DEAD.${NC}\n"

# Interactive loop
while true; do
    read -r -p "> " cmd arg

    case "$cmd" in
        kill)
            if [[ -z "$arg" ]]; then
                echo -e "${RED}Usage: kill <node_number>${NC}"
                continue
            fi
            idx=$((arg - 1))
            if [[ $idx -lt 0 || $idx -ge ${#PIDS[@]} ]]; then
                echo -e "${RED}Invalid node number. Valid: 1-$NUM_NODES${NC}"
                continue
            fi
            pid=${PIDS[$idx]}
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                echo -e "${YELLOW}Killed Node $arg (PID: $pid)${NC}"
                echo -e "${BLUE}Other nodes should detect this failure soon...${NC}"
            else
                echo -e "${RED}Node $arg is already dead${NC}"
            fi
            ;;
        status)
            echo -e "\n${BLUE}Node Status:${NC}"
            for i in $(seq 1 $NUM_NODES); do
                idx=$((i - 1))
                pid=${PIDS[$idx]}
                PORT=$((BASE_PORT + i - 1))
                if kill -0 "$pid" 2>/dev/null; then
                    echo -e "  Node $i (127.0.0.1:$PORT): ${GREEN}RUNNING${NC} (PID: $pid)"
                else
                    echo -e "  Node $i (127.0.0.1:$PORT): ${RED}STOPPED${NC}"
                fi
            done
            echo ""
            ;;
        quit|exit|q)
            echo -e "${YELLOW}Shutting down cluster...${NC}"
            exit 0
            ;;
        "")
            continue
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${NC}"
            echo -e "Commands: kill <N>, status, quit"
            ;;
    esac
done
