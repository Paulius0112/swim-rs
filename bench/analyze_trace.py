#!/usr/bin/env python3
"""
Analyze strace output to visualize epoll performance and latency.

Usage:
    ./analyze_trace.py traces/syscalls_9000.log
"""

import sys
import re
from collections import defaultdict
from dataclasses import dataclass
from typing import List, Optional
import statistics


@dataclass
class SyscallEvent:
    timestamp: float  # relative timestamp in seconds
    syscall: str
    duration: float  # in seconds
    result: str


def parse_strace_line(line: str) -> Optional[SyscallEvent]:
    """Parse a strace line with -T -r flags."""
    # Format: "     0.000123 syscall(args) = result <duration>"
    # or:     "     0.000123 syscall(args) = result"

    pattern = r'^\s*([\d.]+)\s+(\w+)\([^)]*\)\s*=\s*([^\s<]+)(?:\s+<([\d.]+)>)?'
    match = re.match(pattern, line)

    if not match:
        return None

    rel_time = float(match.group(1))
    syscall = match.group(2)
    result = match.group(3)
    duration = float(match.group(4)) if match.group(4) else 0.0

    return SyscallEvent(
        timestamp=rel_time,
        syscall=syscall,
        duration=duration,
        result=result
    )


def analyze_trace(filename: str):
    """Analyze a strace log file."""
    events: List[SyscallEvent] = []

    with open(filename, 'r') as f:
        for line in f:
            event = parse_strace_line(line)
            if event:
                events.append(event)

    if not events:
        print("No syscalls found in trace file")
        return

    # Group by syscall type
    by_syscall = defaultdict(list)
    for event in events:
        by_syscall[event.syscall].append(event)

    print("=" * 60)
    print(f"SWIM Protocol Syscall Analysis")
    print(f"Trace file: {filename}")
    print(f"Total syscalls: {len(events)}")
    print("=" * 60)
    print()

    # Summary table
    print(f"{'Syscall':<15} {'Count':>10} {'Mean (µs)':>12} {'P50 (µs)':>12} {'P99 (µs)':>12} {'Max (µs)':>12}")
    print("-" * 75)

    for syscall in sorted(by_syscall.keys()):
        calls = by_syscall[syscall]
        durations = [e.duration * 1_000_000 for e in calls]  # Convert to microseconds

        if len(durations) > 0:
            mean = statistics.mean(durations)
            p50 = statistics.median(durations)
            p99 = sorted(durations)[int(len(durations) * 0.99)] if len(durations) > 1 else durations[0]
            max_d = max(durations)

            print(f"{syscall:<15} {len(calls):>10} {mean:>12.2f} {p50:>12.2f} {p99:>12.2f} {max_d:>12.2f}")

    print()

    # epoll_wait specific analysis
    if 'epoll_wait' in by_syscall:
        epoll_events = by_syscall['epoll_wait']
        durations = [e.duration * 1000 for e in epoll_events]  # Convert to ms

        print("=" * 60)
        print("epoll_wait Analysis (event loop efficiency)")
        print("=" * 60)
        print()

        # Categorize wait times
        immediate = sum(1 for d in durations if d < 1)  # < 1ms
        short = sum(1 for d in durations if 1 <= d < 100)  # 1-100ms
        medium = sum(1 for d in durations if 100 <= d < 1000)  # 100ms-1s
        long = sum(1 for d in durations if d >= 1000)  # >= 1s

        total = len(durations)
        print(f"Wait time distribution:")
        print(f"  Immediate (<1ms):    {immediate:>6} ({100*immediate/total:>5.1f}%) - processing events")
        print(f"  Short (1-100ms):     {short:>6} ({100*short/total:>5.1f}%) - active communication")
        print(f"  Medium (100ms-1s):   {medium:>6} ({100*medium/total:>5.1f}%) - waiting for tick")
        print(f"  Long (>=1s):         {long:>6} ({100*long/total:>5.1f}%) - idle waiting")
        print()

        # This shows epoll efficiency - low CPU usage when idle
        print("Key insight: epoll_wait blocks efficiently when there's no work,")
        print("using zero CPU while waiting for network events or tick timeout.")
        print()

    # Network I/O analysis
    if 'sendto' in by_syscall or 'recvfrom' in by_syscall:
        print("=" * 60)
        print("Network I/O Analysis")
        print("=" * 60)
        print()

        if 'sendto' in by_syscall:
            sends = by_syscall['sendto']
            send_times = [e.duration * 1_000_000 for e in sends]
            print(f"sendto: {len(sends)} calls")
            print(f"  Mean: {statistics.mean(send_times):.2f} µs")
            print(f"  Max:  {max(send_times):.2f} µs")
            print()

        if 'recvfrom' in by_syscall:
            recvs = by_syscall['recvfrom']
            recv_times = [e.duration * 1_000_000 for e in recvs]
            print(f"recvfrom: {len(recvs)} calls")
            print(f"  Mean: {statistics.mean(recv_times):.2f} µs")
            print(f"  Max:  {max(recv_times):.2f} µs")
            print()

    # Generate histogram data for visualization
    print("=" * 60)
    print("epoll_wait Duration Histogram (ASCII)")
    print("=" * 60)
    print()

    if 'epoll_wait' in by_syscall:
        durations_ms = [e.duration * 1000 for e in by_syscall['epoll_wait']]

        # Create buckets: 0-1ms, 1-10ms, 10-100ms, 100-500ms, 500-1000ms, >1000ms
        buckets = [0, 1, 10, 100, 500, 1000, float('inf')]
        bucket_names = ['0-1ms', '1-10ms', '10-100ms', '100-500ms', '500ms-1s', '>1s']
        counts = [0] * (len(buckets) - 1)

        for d in durations_ms:
            for i in range(len(buckets) - 1):
                if buckets[i] <= d < buckets[i + 1]:
                    counts[i] += 1
                    break

        max_count = max(counts) if counts else 1
        bar_width = 40

        for name, count in zip(bucket_names, counts):
            bar_len = int(bar_width * count / max_count)
            bar = '█' * bar_len
            print(f"{name:>12}: {bar:<40} {count}")

        print()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    analyze_trace(sys.argv[1])


if __name__ == '__main__':
    main()
