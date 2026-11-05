import Foundation

public struct CUSUMState: Sendable, Equatable {
    public var positive: Double
    public var negative: Double

    public static let zero = CUSUMState(positive: 0, negative: 0)

    public init(positive: Double, negative: Double) {
        self.positive = positive
        self.negative = negative
    }
}

public struct CUSUMUpdate: Sendable, Equatable {
    public var state: CUSUMState
    public var exceedsLimit: Bool
}

/// Tabular CUSUM on the z-score. Allowance k = 0.5 and decision interval h = 4,
/// both in z units (k = 0.5σ, h = 4σ before dividing by σ).
/// Off by default. The job only raises an alert when `BaselineParameters.cusumEnabled` is true.
public enum CUSUM {
    public static let allowanceK = 0.5
    public static let decisionH = 4.0

    public static func update(
        previous: CUSUMState,
        zScore: Double,
        allowanceK: Double = CUSUM.allowanceK,
        decisionH: Double = CUSUM.decisionH
    ) -> CUSUMUpdate {
        guard zScore.isFinite else {
            return CUSUMUpdate(state: previous, exceedsLimit: false)
        }
        let positive = max(0, previous.positive + zScore - allowanceK)
        let negative = min(0, previous.negative + zScore + allowanceK)
        let state = CUSUMState(positive: positive, negative: negative)
        let exceeds = positive >= decisionH || negative <= -decisionH
        return CUSUMUpdate(state: state, exceedsLimit: exceeds)
    }

    /// One-sided CUSUM on the bad direction. Favorable runs decay the sum; they do not alert.
    public static func updateBadDirection(
        previous: CUSUMState,
        zScore: Double,
        metric: MetricKind
    ) -> CUSUMUpdate {
        guard zScore.isFinite else {
            return CUSUMUpdate(state: previous, exceedsLimit: false)
        }
        let zBad = metric.badDirection == .higher ? zScore : -zScore
        let positive = max(0, previous.positive + zBad - allowanceK)
        let state = CUSUMState(positive: positive, negative: 0)
        return CUSUMUpdate(state: state, exceedsLimit: positive >= decisionH)
    }
}
