import SwiftUI

/// A composite "feels like" assessment of how the network actually performs
/// right now, blending upstream signals (latency, jitter, packet loss) with a
/// hint of local WiFi health for cause attribution. Inspired by weather
/// "feels like" temperature: a single number that captures the lived experience
/// better than any one raw metric.
struct FeelsLikeScore {
    let score: Int          // 0–100
    let rating: Rating
    let cause: Cause

    enum Rating: String {
        case smooth = "Smooth"
        case usable = "Usable"
        case rough = "Rough"
        case down = "Down"

        var color: Color {
            switch self {
            case .smooth: return .green
            case .usable: return .yellow
            case .rough: return .orange
            case .down: return .red
            }
        }

        /// Weather-report iconography, matching the "feels like" metaphor:
        /// clear skies down through a thunderstorm.
        var symbol: String {
            switch self {
            case .smooth: return "sun.max.fill"
            case .usable: return "cloud.sun.fill"
            case .rough: return "cloud.rain.fill"
            case .down: return "cloud.bolt.rain.fill"
            }
        }
    }

    /// Why the connection feels the way it does. Separates upstream (ISP /
    /// internet) problems from local (WiFi) ones so the user can tell whether
    /// it's their network or their provider.
    enum Cause {
        case none
        case upstream(String)
        case local(String)
        case bufferbloat
        case internetDown

        var description: String? {
            switch self {
            case .none: return nil
            case .upstream(let reason): return "Upstream: \(reason)"
            case .local(let reason): return "Local: \(reason)"
            case .bufferbloat: return "Bufferbloat (link saturated)"
            case .internetDown: return "Internet down"
            }
        }
    }

    /// Compute the score from the most recent ping window plus optional WiFi
    /// and router context. `recentPings` should be in chronological order; the
    /// caller is expected to pass a short window (e.g. the last ~10 pings).
    ///
    /// `throughputBytesPerSec` and `peakThroughputBytesPerSec` (combined rx+tx,
    /// from the router) let the model spot bufferbloat: latency/jitter that
    /// spikes specifically because the link is saturated by the user's own
    /// traffic. Pass `nil` when router monitoring is unavailable.
    static func compute(
        recentPings: [PingRecord],
        wifi: WiFiSnapshot?,
        wanConnected: Bool?,
        throughputBytesPerSec: Double? = nil,
        peakThroughputBytesPerSec: Double? = nil
    ) -> FeelsLikeScore {
        // Router explicitly reports the WAN link as down — nothing else matters.
        if wanConnected == false {
            return FeelsLikeScore(score: 0, rating: .down, cause: .internetDown)
        }

        // No data yet: assume all is well rather than alarming the user.
        guard !recentPings.isEmpty else {
            return FeelsLikeScore(score: 100, rating: .smooth, cause: .none)
        }

        let failures = recentPings.filter { !$0.success }.count
        let lossRate = Double(failures) / Double(recentPings.count)
        let latencies = recentPings.compactMap(\.latencyMs)

        // Every ping in the window timed out — the internet is effectively gone.
        guard !latencies.isEmpty else {
            return FeelsLikeScore(score: 0, rating: .down, cause: .internetDown)
        }

        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let jitter = standardDeviation(latencies)

        let latencyPenalty = penaltyForLatency(avgLatency)
        let jitterPenalty = penaltyForJitter(jitter)
        let lossPenalty = penaltyForLoss(lossRate)

        let score = max(0, 100 - latencyPenalty - jitterPenalty - lossPenalty)
        let rating = ratingFor(score)
        let cause = attributeCause(
            score: score,
            latencyPenalty: latencyPenalty,
            jitterPenalty: jitterPenalty,
            lossPenalty: lossPenalty,
            wifi: wifi,
            linkSaturated: isLinkSaturated(throughputBytesPerSec, peak: peakThroughputBytesPerSec)
        )

        return FeelsLikeScore(score: Int(score.rounded()), rating: rating, cause: cause)
    }

    // MARK: - Penalty curves

    /// Latency is fine up to 50ms, then ramps in. Capped so it can't dominate
    /// loss/jitter, which hurt the experience more.
    private static func penaltyForLatency(_ ms: Double) -> Double {
        if ms <= 50 { return 0 }
        if ms <= 200 { return (ms - 50) / 150 * 30 }
        return min(50, 30 + (ms - 200) / 200 * 20)
    }

    /// Jitter (latency variability) is what makes calls and video stutter even
    /// when average latency looks acceptable.
    private static func penaltyForJitter(_ stddev: Double) -> Double {
        if stddev <= 10 { return 0 }
        return min(35, (stddev - 10) / 70 * 30)
    }

    /// Packet loss is weighted heaviest — a single timeout in the window is
    /// immediately noticeable.
    private static func penaltyForLoss(_ rate: Double) -> Double {
        min(70, rate * 150)
    }

    private static func ratingFor(_ score: Double) -> Rating {
        if score >= 85 { return .smooth }
        if score >= 65 { return .usable }
        if score >= 35 { return .rough }
        return .down
    }

    /// Pick the dominant degradation and decide what's behind it.
    ///
    /// Priority: when latency/jitter spikes *and* the link is saturated, it's
    /// almost certainly bufferbloat (the user's own traffic congesting the
    /// upstream queue) — the most specific, actionable call. Otherwise a weak
    /// WiFi signal is the next best explanation, since it itself drives loss
    /// and jitter to 1.1.1.1. Failing both, it's an upstream problem.
    private static func attributeCause(
        score: Double,
        latencyPenalty: Double,
        jitterPenalty: Double,
        lossPenalty: Double,
        wifi: WiFiSnapshot?,
        linkSaturated: Bool
    ) -> Cause {
        // Connection feels fine — don't manufacture a problem.
        guard score < 85 else { return .none }

        // Bufferbloat: a latency/jitter-driven dip while the link is maxed out.
        // Pure packet loss isn't classic bufferbloat, so require latency or
        // jitter to be the dominant penalty.
        let latencyOrJitterDominant = max(latencyPenalty, jitterPenalty) >= lossPenalty
        if linkSaturated && latencyOrJitterDominant {
            return .bufferbloat
        }

        if let wifi, wifi.rssi <= -75 {
            return .local("weak WiFi signal (\(wifi.rssi) dBm)")
        }

        let reason: String
        if lossPenalty >= jitterPenalty && lossPenalty >= latencyPenalty {
            reason = "packet loss"
        } else if jitterPenalty >= latencyPenalty {
            reason = "high jitter"
        } else {
            reason = "high latency"
        }
        return .upstream(reason)
    }

    /// Treat the link as saturated when current throughput is both meaningful
    /// in absolute terms and a large fraction of the day's observed peak. The
    /// relative test adapts to the actual link speed (which we never know
    /// directly), while the floor keeps a quiet day from registering as busy.
    private static func isLinkSaturated(_ throughput: Double?, peak: Double?) -> Bool {
        guard let throughput, let peak, peak > 0 else { return false }
        let floor = 500_000.0  // 0.5 MB/s
        return throughput >= floor && throughput >= peak * 0.6
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
