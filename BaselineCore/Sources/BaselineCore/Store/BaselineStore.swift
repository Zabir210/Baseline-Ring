import Foundation
import SwiftData

public struct PreviousAlert: Sendable {
    public var severity: BaselineStatus
    public var acknowledged: Bool
    public var createdAt: Date
}

public struct ApplyOutcome: Sendable {
    public var snapshot: BaselineSnapshot
    public var notifications: [AlertDraft]
}

@MainActor
public enum BaselineStore {
    public static func ensureSettings(in context: ModelContext) -> AppSettings {
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        return created
    }

    public static func currentParameters(in context: ModelContext) -> BaselineParameters {
        ensureSettings(in: context).parameters()
    }

    /// Replaces daily rows with `daily`, refreshes baselines and alerts, and saves.
    public static func recompute(
        daily: [DailyAggregate],
        asOf now: Date = .now,
        calendar: Calendar = .current,
        settings: BaselineParameters? = nil,
        isExample: Bool,
        notify: Bool,
        in context: ModelContext
    ) throws -> ApplyOutcome {
        let settingsRow = ensureSettings(in: context)
        let resolved = settings ?? settingsRow.parameters()
        let previousCUSUM = try cusumByMetric(in: context)
        let previousAlerts = try previousAlertsByKey(in: context, calendar: calendar)
        let result = BaselineRefreshJob.run(
            daily: daily,
            asOf: now,
            calendar: calendar,
            settings: resolved,
            previousCUSUM: previousCUSUM,
            isExample: isExample
        )

        for row in try context.fetch(FetchDescriptor<DailyMetric>()) {
            context.delete(row)
        }
        for row in try context.fetch(FetchDescriptor<AnomalyAlert>()) {
            context.delete(row)
        }

        for aggregate in mergedForStorage(daily, calendar: calendar) {
            context.insert(
                DailyMetric(
                    day: aggregate.day,
                    metric: aggregate.metric,
                    value: aggregate.value,
                    sampleCount: aggregate.sampleCount
                )
            )
        }

        let existingStates = try context.fetch(FetchDescriptor<BaselineState>())
        var stateByMetric: [String: BaselineState] = [:]
        for state in existingStates {
            stateByMetric[state.metricRaw] = state
        }
        for draft in result.states {
            if let state = stateByMetric[draft.metric.rawValue] {
                state.windowDays = draft.windowDays
                state.mean = draft.mean
                state.stddev = draft.stddev
                state.sampleCount = draft.sampleCount
                state.updatedAt = now
                state.cusumPos = draft.cusumPos
                state.cusumNeg = draft.cusumNeg
            } else {
                context.insert(
                    BaselineState(
                        metric: draft.metric,
                        windowDays: draft.windowDays,
                        mean: draft.mean,
                        stddev: draft.stddev,
                        sampleCount: draft.sampleCount,
                        updatedAt: now,
                        cusumPos: draft.cusumPos,
                        cusumNeg: draft.cusumNeg
                    )
                )
            }
        }

        var notifications: [AlertDraft] = []
        for alert in result.alerts {
            let key = alertKey(metric: alert.metric, day: alert.day, calendar: calendar)
            let previous = previousAlerts[key]
            let acknowledged: Bool
            let createdAt: Date
            if let previous {
                acknowledged = alert.severity.rank > previous.severity.rank ? false : previous.acknowledged
                createdAt = previous.createdAt
            } else {
                acknowledged = false
                createdAt = now
            }
            context.insert(
                AnomalyAlert(
                    metric: alert.metric,
                    day: alert.day,
                    observed: alert.observed,
                    baselineMean: alert.baselineMean,
                    zScore: alert.zScore,
                    severity: alert.severity,
                    message: alert.message,
                    acknowledged: acknowledged,
                    createdAt: createdAt
                )
            )
            if notify, !isExample, AlertPolicy.shouldNotify(previous: previous?.severity, new: alert.severity) {
                notifications.append(alert)
            }
        }

        settingsRow.lastRefreshAt = now
        settingsRow.usingExamplePattern = isExample
        try context.save()
        return ApplyOutcome(snapshot: result.snapshot, notifications: notifications)
    }

    private static func cusumByMetric(in context: ModelContext) throws -> [MetricKind: CUSUMState] {
        let rows = try context.fetch(FetchDescriptor<BaselineState>())
        var map: [MetricKind: CUSUMState] = [:]
        for row in rows {
            guard let metric = MetricKind(rawValue: row.metricRaw) else { continue }
            map[metric] = CUSUMState(positive: row.cusumPos, negative: row.cusumNeg)
        }
        return map
    }

    private static func previousAlertsByKey(
        in context: ModelContext,
        calendar: Calendar
    ) throws -> [String: PreviousAlert] {
        let rows = try context.fetch(FetchDescriptor<AnomalyAlert>())
        var map: [String: PreviousAlert] = [:]
        for row in rows {
            guard let metric = MetricKind(rawValue: row.metricRaw) else { continue }
            let key = alertKey(metric: metric, day: row.day, calendar: calendar)
            map[key] = PreviousAlert(
                severity: row.severity,
                acknowledged: row.acknowledged,
                createdAt: row.createdAt
            )
        }
        return map
    }

    private static func mergedForStorage(_ rows: [DailyAggregate], calendar: Calendar) -> [DailyAggregate] {
        var merged: [DailyAggregate] = []
        for metric in MetricKind.allCases {
            let matching = rows.filter { $0.metric == metric }
            let grouped = Dictionary(grouping: matching) { calendar.startOfDay(for: $0.day) }
            for (day, items) in grouped {
                let value: Double
                if metric == .steps {
                    value = items.reduce(0) { $0 + $1.value }
                } else {
                    let weight = Double(items.reduce(0) { $0 + max($1.sampleCount, 1) })
                    let weighted = items.reduce(0) { $0 + $1.value * Double(max($1.sampleCount, 1)) }
                    value = weight > 0 ? weighted / weight : 0
                }
                let count = items.reduce(0) { $0 + max($1.sampleCount, 1) }
                merged.append(DailyAggregate(metric: metric, day: day, value: value, sampleCount: count))
            }
        }
        return merged
    }

    private static func alertKey(metric: MetricKind, day: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: day)
        return "\(metric.rawValue)|\(start.timeIntervalSinceReferenceDate)"
    }
}
