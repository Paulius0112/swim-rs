#!/usr/bin/env python3
"""
Visualize SWIM protocol latency data.

Parses log files and generates charts showing:
- RTT distribution
- Latency over time
- Jitter analysis

Usage:
    ./visualize_latency.py results/node_9000_*.log
    ./visualize_latency.py results/*.log --output latency_report.png
"""

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple

# Try to import matplotlib, provide helpful message if not available
try:
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False


@dataclass
class RTTSample:
    timestamp: datetime
    rtt_us: float  # microseconds
    target: str


def parse_duration(s: str) -> float:
    """Parse duration string like '123.45µs' or '1.23ms' to microseconds."""
    s = s.strip()
    if s.endswith('µs'):
        return float(s[:-2])
    elif s.endswith('us'):
        return float(s[:-2])
    elif s.endswith('ns'):
        return float(s[:-2]) / 1000
    elif s.endswith('ms'):
        return float(s[:-2]) * 1000
    elif s.endswith('s'):
        return float(s[:-1]) * 1_000_000
    else:
        return float(s)


def parse_log_file(filename: str) -> List[RTTSample]:
    """Parse a SWIM node log file and extract RTT samples."""
    samples = []

    # Pattern for log lines with RTT
    # Example: 2024-01-15T10:30:45.123456Z  INFO swim_rs::protocol::node: Received ACK seq=5 from 127.0.0.1:9001 (RTT: 234.56µs)
    rtt_pattern = re.compile(
        r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?)\s+\w+\s+.*?'
        r'Received ACK.*?from\s+([\d.:]+)\s+\(RTT:\s*([^\)]+)\)'
    )

    # Also try simpler pattern without timestamp
    simple_pattern = re.compile(
        r'Received ACK.*?from\s+([\d.:]+)\s+\(RTT:\s*([^\)]+)\)'
    )

    with open(filename, 'r') as f:
        line_num = 0
        for line in f:
            line_num += 1

            match = rtt_pattern.search(line)
            if match:
                try:
                    ts_str = match.group(1)
                    # Handle various timestamp formats
                    if ts_str.endswith('Z'):
                        ts_str = ts_str[:-1]
                    if '.' in ts_str:
                        ts = datetime.fromisoformat(ts_str)
                    else:
                        ts = datetime.fromisoformat(ts_str)

                    target = match.group(2)
                    rtt_str = match.group(3)
                    rtt_us = parse_duration(rtt_str)

                    samples.append(RTTSample(
                        timestamp=ts,
                        rtt_us=rtt_us,
                        target=target
                    ))
                except (ValueError, IndexError) as e:
                    pass  # Skip malformed lines
            else:
                # Try simple pattern
                match = simple_pattern.search(line)
                if match:
                    try:
                        target = match.group(1)
                        rtt_str = match.group(2)
                        rtt_us = parse_duration(rtt_str)

                        samples.append(RTTSample(
                            timestamp=datetime.now(),  # Use current time if no timestamp
                            rtt_us=rtt_us,
                            target=target
                        ))
                    except (ValueError, IndexError):
                        pass

    return samples


def print_statistics(samples: List[RTTSample], filename: str):
    """Print statistics to console."""
    if not samples:
        print(f"No RTT samples found in {filename}")
        return

    rtts = [s.rtt_us for s in samples]
    rtts_sorted = sorted(rtts)
    n = len(rtts)

    mean = sum(rtts) / n
    p50 = rtts_sorted[n // 2]
    p95 = rtts_sorted[int(n * 0.95)]
    p99 = rtts_sorted[min(int(n * 0.99), n - 1)]
    min_rtt = rtts_sorted[0]
    max_rtt = rtts_sorted[-1]

    # Jitter (standard deviation)
    variance = sum((x - mean) ** 2 for x in rtts) / n
    jitter = variance ** 0.5

    print(f"\n{'=' * 60}")
    print(f"RTT Statistics: {filename}")
    print(f"{'=' * 60}")
    print(f"Samples:    {n}")
    print(f"Min:        {min_rtt:.2f} µs")
    print(f"Max:        {max_rtt:.2f} µs")
    print(f"Mean:       {mean:.2f} µs")
    print(f"P50:        {p50:.2f} µs")
    print(f"P95:        {p95:.2f} µs")
    print(f"P99:        {p99:.2f} µs")
    print(f"Jitter:     {jitter:.2f} µs")
    print()

    # ASCII histogram
    print("RTT Distribution:")
    buckets = [0, 50, 100, 200, 500, 1000, 2000, 5000, float('inf')]
    bucket_names = ['0-50µs', '50-100µs', '100-200µs', '200-500µs',
                   '500µs-1ms', '1-2ms', '2-5ms', '>5ms']
    counts = [0] * (len(buckets) - 1)

    for rtt in rtts:
        for i in range(len(buckets) - 1):
            if buckets[i] <= rtt < buckets[i + 1]:
                counts[i] += 1
                break

    max_count = max(counts) if counts else 1
    bar_width = 40

    for name, count in zip(bucket_names, counts):
        bar_len = int(bar_width * count / max_count) if max_count > 0 else 0
        bar = '█' * bar_len
        pct = 100 * count / n if n > 0 else 0
        print(f"  {name:>12}: {bar:<40} {count:>5} ({pct:>5.1f}%)")


def plot_latency(all_samples: dict, output_file: Optional[str] = None):
    """Generate matplotlib visualization."""
    if not HAS_MATPLOTLIB:
        print("\nMatplotlib not installed. Install with:")
        print("  pip install matplotlib")
        print("\nSkipping graphical visualization.")
        return

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle('SWIM Protocol Latency Analysis', fontsize=14, fontweight='bold')

    colors = plt.cm.tab10.colors

    # 1. RTT over time
    ax1 = axes[0, 0]
    for idx, (name, samples) in enumerate(all_samples.items()):
        if samples:
            times = range(len(samples))
            rtts = [s.rtt_us for s in samples]
            ax1.plot(times, rtts, 'o-', markersize=2, alpha=0.7,
                    color=colors[idx % len(colors)], label=name)
    ax1.set_xlabel('Sample #')
    ax1.set_ylabel('RTT (µs)')
    ax1.set_title('RTT Over Time')
    ax1.legend(loc='upper right', fontsize=8)
    ax1.grid(True, alpha=0.3)

    # 2. RTT distribution (histogram)
    ax2 = axes[0, 1]
    for idx, (name, samples) in enumerate(all_samples.items()):
        if samples:
            rtts = [s.rtt_us for s in samples]
            ax2.hist(rtts, bins=50, alpha=0.5, label=name, color=colors[idx % len(colors)])
    ax2.set_xlabel('RTT (µs)')
    ax2.set_ylabel('Frequency')
    ax2.set_title('RTT Distribution')
    ax2.legend(loc='upper right', fontsize=8)
    ax2.grid(True, alpha=0.3)

    # 3. CDF
    ax3 = axes[1, 0]
    for idx, (name, samples) in enumerate(all_samples.items()):
        if samples:
            rtts = sorted([s.rtt_us for s in samples])
            cdf = [i / len(rtts) for i in range(1, len(rtts) + 1)]
            ax3.plot(rtts, cdf, '-', linewidth=2,
                    color=colors[idx % len(colors)], label=name)
    ax3.set_xlabel('RTT (µs)')
    ax3.set_ylabel('CDF')
    ax3.set_title('Cumulative Distribution')
    ax3.axhline(y=0.5, color='gray', linestyle='--', alpha=0.5, label='P50')
    ax3.axhline(y=0.95, color='gray', linestyle=':', alpha=0.5, label='P95')
    ax3.axhline(y=0.99, color='gray', linestyle='-.', alpha=0.5, label='P99')
    ax3.legend(loc='lower right', fontsize=8)
    ax3.grid(True, alpha=0.3)

    # 4. Jitter (rolling standard deviation)
    ax4 = axes[1, 1]
    window = 20
    for idx, (name, samples) in enumerate(all_samples.items()):
        if len(samples) > window:
            rtts = [s.rtt_us for s in samples]
            jitters = []
            for i in range(window, len(rtts)):
                window_data = rtts[i-window:i]
                mean = sum(window_data) / window
                variance = sum((x - mean) ** 2 for x in window_data) / window
                jitters.append(variance ** 0.5)
            ax4.plot(range(window, len(rtts)), jitters, '-', linewidth=1,
                    color=colors[idx % len(colors)], label=name, alpha=0.7)
    ax4.set_xlabel('Sample #')
    ax4.set_ylabel('Jitter (µs)')
    ax4.set_title(f'Rolling Jitter (window={window})')
    ax4.legend(loc='upper right', fontsize=8)
    ax4.grid(True, alpha=0.3)

    plt.tight_layout()

    if output_file:
        plt.savefig(output_file, dpi=150, bbox_inches='tight')
        print(f"\nChart saved to: {output_file}")
    else:
        plt.show()


def main():
    parser = argparse.ArgumentParser(description='Visualize SWIM protocol latency')
    parser.add_argument('files', nargs='+', help='Log files to analyze')
    parser.add_argument('--output', '-o', help='Output file for chart (PNG)')
    parser.add_argument('--no-plot', action='store_true', help='Skip plotting, only print stats')

    args = parser.parse_args()

    all_samples = {}

    for filename in args.files:
        path = Path(filename)
        if not path.exists():
            print(f"Warning: {filename} not found, skipping")
            continue

        samples = parse_log_file(filename)
        print_statistics(samples, path.name)

        if samples:
            # Use just the filename as the label
            all_samples[path.stem] = samples

    if not args.no_plot and all_samples:
        plot_latency(all_samples, args.output)


if __name__ == '__main__':
    main()
