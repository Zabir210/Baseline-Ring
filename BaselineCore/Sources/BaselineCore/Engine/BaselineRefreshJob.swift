import Foundation

public struct BaselineStateDraft: Sendable, Equatable {
    public var metric: MetricKind
    public var windowDays: Int
    public var mean: Double
    public var stddev: Double
    public var sampleCount: Int
    public var cusumPos: Double
    public var cusumNeg: Double
}

public struct AlertDraft: Sendable, Equatable {
    public var metric: MetricKind
    public var day: Date
    public var observed: Double
    public var baselineMean: Double
    public var zScore: Double
    public var severity: BaselineStatus
    public var message: String
}

public struct RefreshResult: Sendable, Equatable {
    public var evaluations: [MetricEvaluation]
    public var states: [BaselineStateDraft]
    public var alerts: [AlertDraft]
    public var snapshot: BaselineSnapshot
}

/// Pure recompute: daily aggregates in, evaluations and copy out. No SwiftData, no HealthKit.
public enum BaselineRefreshJob {
    public static func run(
        daily: [DailyAggregate],
        asOf now: Date,
        calendar: Calendar,
        settings: BaselineParameters,
        previousCUSUM: [MetricKind: CUSUMState] = [:],
        isExample: Bool = false
    ) -> RefreshResult {
        let today = calendar.startOfDay(for: now)
        var evaluations: [MetricEvaluation] = []
        var states: [BaselineStateDraft] = []
        var alerts: [AlertDraft] = []
        var snapshots: [MetricSnapshot] = []

        for metric in MetricKind.allCases {
            let series = merged(daily, metric: metric, calendar: calendar)
            let usable: [DailyAggregate]
            if metric.excludesTodayUntilFinal {
                usable = series.filter { $0.day < today }
            } else {
                usable = series
            }

            let observationPoint = usable.last
            let history = observationPoint == nil ? usable : Array(usable.dropLast())
            var evaluation = BaselineEngine.evaluate(
                metric: metric,
                baselineValues: history.map(\.value),
                observation: observationPoint?.value,
                observedDay: observationPoint?.day,
                settings: settings
            )

            let previous = previousCUSUM[metric] ?? .zero
            let cusum: CUSUMUpdate
            if settings.cusumEnabled, let z = evaluation.zScore, !evaluation.isLearning {
                cusum = CUSUM.updateBadDirection(previous: previous, zScore: z, metric: metric)
                if cusum.exceedsLimit, evaluation.status.rank < BaselineStatus.warn.rank {
                    evaluation.status = .warn
                }
            } else {
                cusum = CUSUMUpdate(state: previous, exceedsLimit: false)
            }

            let sentence: String?
            if let observed = evaluation.observed,
               let mean = evaluation.mean,
               let z = evaluation.zScore,
               let day = evaluation.observedDay,
               evaluation.status == .info || evaluation.status == .warn || evaluation.status == .high {
                let message = AlertCopy.message(
                    metric: metric,
                    value: observed,
                    mean: mean,
                    zScore: z,
                    windowDays: settings.windowDays
                )
                sentence = message
                alerts.append(
                    AlertDraft(
                        metric: metric,
                        day: day,
                        observed: observed,
                        baselineMean: mean,
                        zScore: z,
                        severity: evaluation.status,
                        message: message
                    )
                )
            } else {
                sentence = nil
            }

            if let mean = evaluation.mean, let stddev = evaluation.stddev {
                states.append(
                    BaselineStateDraft(
                        metric: metric,
                        windowDays: settings.windowDays,
                        mean: mean,
                        stddev: stddev,
                        sampleCount: evaluation.sampleCount,
                        cusumPos: cusum.state.positive,
                        cusumNeg: cusum.state.negative
                    )
                )
            }

            snapshots.append(
                MetricSnapshot(
                    metric: metric,
                    status: evaluation.status,
                    observed: evaluation.observed,
                    observedDay: evaluation.observedDay,
                    mean: evaluation.mean,
                    stddev: evaluation.stddev,
                    zScore: evaluation.zScore,
                    sampleCount: evaluation.sampleCount,
                    sentence: sentence
                )
            )
            evaluations.append(evaluation)
        }

        let overall = overallStatus(snapshots.map(\.status))
        let top = alerts.max { lhs, rhs in
            if lhs.severity.rank != rhs.severity.rank {
                return lhs.severity.rank < rhs.severity.rank
            }
            return lhs.metric.sortOrder > rhs.metric.sortOrder
        }

        let snapshot = BaselineSnapshot(
            updatedAt: now,
            isExample: isExample,
            overall: overall,
            metrics: snapshots,
            topAlertSentence: top?.message
        )
        return RefreshResult(
            evaluations: evaluations,
            states: states,
            alerts: alerts,
            snapshot: snapshot
        )
    }

    static func overallStatus(_ statuses: [BaselineStatus]) -> BaselineStatus {
        if statuses.contains(.high) { return .high }
        if statuses.contains(.warn) { return .warn }
        if statuses.contains(.info) { return .info }
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == .clear }) { return .clear }
        return .learning
    }

    private static func merged(
        _ rows: [DailyAggregate],
        metric: MetricKind,
        calendar: Calendar
    ) -> [DailyAggregate] {
        let matching = rows.filter { $0.metric == metric }
        let grouped = Dictionary(grouping: matching) { calendar.startOfDay(for: $0.day) }
        return grouped.map { day, items in
            let value: Double
            if metric == .steps {
                value = items.reduce(0) { $0 + $1.value }
            } else {
                let weight = items.reduce(0) { $0 + Double(max($1.sampleCount, 1)) }
                let weighted = items.reduce(0) { $0 + $1.value * Double(max($1.sampleCount, 1)) }
                value = weight > 0 ? weighted / weight : 0
            }
            let count = items.reduce(0) { $0 + max($1.sampleCount, 1) }
            return DailyAggregate(metric: metric, day: day, value: value, sampleCount: count)
        }
        .sorted { $0.day < $1.day }
    }
}
