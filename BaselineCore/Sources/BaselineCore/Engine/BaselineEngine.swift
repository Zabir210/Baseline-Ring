import Foundation

public struct BaselineStatistics: Sendable, Equatable {
    public var mean: Double
    public var stddev: Double
    /// σ before the epsilon floor. Zero when the window is flat or has one point.
    public var rawStddev: Double
    public var sampleCount: Int
}

public struct MetricEvaluation: Sendable, Equatable {
    public var metric: MetricKind
    public var windowDays: Int
    public var sampleCount: Int
    public var isLearning: Bool
    public var mean: Double?
    public var stddev: Double?
    public var observed: Double?
    public var observedDay: Date?
    public var zScore: Double?
    public var status: BaselineStatus
}

/// Rolling z-score baseline. Sample standard deviation (Bessel, n−1), then
/// σ is floored at the metric epsilon so a quiet week cannot explode z.
public enum BaselineEngine {
    /// Steps downward of at least 2σ stay informational until this line.
    public static let stepsLifestyleZ = -2.5

    public static func statistics(values: [Double], epsilon: Double) -> BaselineStatistics? {
        let finite = values.filter(\.isFinite)
        guard !finite.isEmpty else { return nil }

        let count = finite.count
        let mean = finite.reduce(0, +) / Double(count)
        let raw: Double
        if count < 2 {
            raw = 0
        } else {
            let sumOfSquares = finite.reduce(0) { partial, value in
                let delta = value - mean
                return partial + delta * delta
            }
            raw = (sumOfSquares / Double(count - 1)).squareRoot()
        }
        let floor = epsilon > 0 ? epsilon : 1e-9
        return BaselineStatistics(
            mean: mean,
            stddev: max(raw, floor),
            rawStddev: raw,
            sampleCount: count
        )
    }

    public static func zScore(observation: Double, mean: Double, stddev: Double) -> Double {
        let denominator = stddev > 0 ? stddev : 1e-9
        return (observation - mean) / denominator
    }

    /// Direction-aware status. Favorable breaks (HRV up, resting HR down, more sleep, more steps)
    /// stay `.clear`. Steps only become warn/high at or below `stepsLifestyleZ` / zHigh.
    public static func status(
        metric: MetricKind,
        zScore: Double,
        settings: BaselineParameters
    ) -> BaselineStatus {
        guard zScore.isFinite else { return .clear }
        let isBad: Bool
        switch metric.badDirection {
        case .higher:
            isBad = zScore > 0
        case .lower:
            isBad = zScore < 0
        }
        guard isBad else { return .clear }

        if metric == .steps {
            if zScore <= -settings.zHigh { return .high }
            if zScore <= stepsLifestyleZ { return .warn }
            if abs(zScore) >= settings.zWarn { return .info }
            return .clear
        }

        let magnitude = abs(zScore)
        if magnitude >= settings.zHigh { return .high }
        if magnitude >= settings.zWarn { return .warn }
        return .clear
    }

    /// `baselineValues` are complete days before the observation, oldest first.
    /// Extra days beyond the window are dropped from the front.
    public static func evaluate(
        metric: MetricKind,
        baselineValues: [Double],
        observation: Double?,
        observedDay: Date? = nil,
        settings: BaselineParameters = .mvp
    ) -> MetricEvaluation {
        let window = Array(baselineValues.suffix(settings.windowDays))
        let stats = statistics(values: window, epsilon: metric.epsilon)
        let learning = window.count < settings.minimumSampleCount || observation == nil || observation?.isFinite != true
        let z: Double?
        if let stats, let observation, observation.isFinite, !learning {
            z = zScore(observation: observation, mean: stats.mean, stddev: stats.stddev)
        } else {
            z = nil
        }
        let status: BaselineStatus
        if learning {
            status = .learning
        } else if let z {
            status = self.status(metric: metric, zScore: z, settings: settings)
        } else {
            status = .learning
        }
        return MetricEvaluation(
            metric: metric,
            windowDays: settings.windowDays,
            sampleCount: window.count,
            isLearning: learning,
            mean: stats?.mean,
            stddev: stats?.stddev,
            observed: observation,
            observedDay: observedDay,
            zScore: z,
            status: status
        )
    }
}
