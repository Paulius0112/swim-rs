use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// Tracks latency statistics for the protocol
pub struct LatencyMetrics {
    /// Recent RTT samples (ping -> ack)
    samples: VecDeque<Duration>,
    /// Maximum samples to keep
    max_samples: usize,
    /// Start time for uptime calculation
    start_time: Instant,
    /// Total pings sent
    pub pings_sent: u64,
    /// Total acks received
    pub acks_received: u64,
    /// Total timeouts
    pub timeouts: u64,
}

impl LatencyMetrics {
    pub fn new(max_samples: usize) -> Self {
        Self {
            samples: VecDeque::with_capacity(max_samples),
            max_samples,
            start_time: Instant::now(),
            pings_sent: 0,
            acks_received: 0,
            timeouts: 0,
        }
    }

    pub fn record_rtt(&mut self, rtt: Duration) {
        if self.samples.len() >= self.max_samples {
            self.samples.pop_front();
        }
        self.samples.push_back(rtt);
        self.acks_received += 1;
    }

    pub fn record_ping_sent(&mut self) {
        self.pings_sent += 1;
    }

    pub fn record_timeout(&mut self) {
        self.timeouts += 1;
    }

    pub fn uptime(&self) -> Duration {
        self.start_time.elapsed()
    }

    pub fn sample_count(&self) -> usize {
        self.samples.len()
    }

    /// Calculate statistics from recent samples
    pub fn stats(&self) -> Option<LatencyStats> {
        if self.samples.is_empty() {
            return None;
        }

        let mut sorted: Vec<Duration> = self.samples.iter().copied().collect();
        sorted.sort();

        let sum: Duration = sorted.iter().sum();
        let count = sorted.len();
        let mean = sum / count as u32;

        let min = sorted[0];
        let max = sorted[count - 1];
        let p50 = sorted[count / 2];
        let p95 = sorted[(count as f64 * 0.95) as usize];
        let p99_idx = ((count as f64 * 0.99) as usize).min(count - 1);
        let p99 = sorted[p99_idx];

        // Calculate jitter (standard deviation)
        let mean_nanos = mean.as_nanos() as f64;
        let variance: f64 = sorted
            .iter()
            .map(|d| {
                let diff = d.as_nanos() as f64 - mean_nanos;
                diff * diff
            })
            .sum::<f64>()
            / count as f64;
        let jitter = Duration::from_nanos(variance.sqrt() as u64);

        Some(LatencyStats {
            min,
            max,
            mean,
            p50,
            p95,
            p99,
            jitter,
            sample_count: count,
        })
    }

    /// Get raw samples for export
    pub fn raw_samples(&self) -> Vec<Duration> {
        self.samples.iter().copied().collect()
    }
}

#[derive(Debug, Clone)]
pub struct LatencyStats {
    pub min: Duration,
    pub max: Duration,
    pub mean: Duration,
    pub p50: Duration,
    pub p95: Duration,
    pub p99: Duration,
    pub jitter: Duration,
    pub sample_count: usize,
}

impl std::fmt::Display for LatencyStats {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "RTT: min={:?} max={:?} mean={:?} p50={:?} p95={:?} p99={:?} jitter={:?} (n={})",
            self.min,
            self.max,
            self.mean,
            self.p50,
            self.p95,
            self.p99,
            self.jitter,
            self.sample_count
        )
    }
}
