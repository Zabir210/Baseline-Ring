import Foundation

public enum DayTagKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case alcohol
    case lateMeal
    case travel
    case stress
    case illness
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .alcohol: "Alcohol"
        case .lateMeal: "Late meal"
        case .travel: "Travel"
        case .stress: "Stress"
        case .illness: "Illness"
        case .custom: "Custom"
        }
    }
}

public struct DayTagRecord: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var day: Date
    public var kind: DayTagKind
    public var customLabel: String?

    public init(id: UUID = UUID(), day: Date, kind: DayTagKind, customLabel: String? = nil) {
        self.id = id
        self.day = day
        self.kind = kind
        self.customLabel = customLabel
    }

    public var label: String {
        if kind == .custom {
            let trimmed = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Custom" : trimmed
        }
        return kind.displayName
    }
}

public struct TagImpact: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var taggedNights: Int
    public var minimumSamples: Int
    public var readinessDelta: Double?
    public var hrvDeltaMilliseconds: Double?
    public var explanation: String

    public init(
        id: String,
        label: String,
        taggedNights: Int,
        minimumSamples: Int,
        readinessDelta: Double?,
        hrvDeltaMilliseconds: Double?,
        explanation: String
    ) {
        self.id = id
        self.label = label
        self.taggedNights = taggedNights
        self.minimumSamples = minimumSamples
        self.readinessDelta = readinessDelta
        self.hrvDeltaMilliseconds = hrvDeltaMilliseconds
        self.explanation = explanation
    }
}

/// Average next-day difference after a tag, versus days that were not followed by that tag.
/// Needs `minimumSamples` tagged nights before it will quote a number.
public enum TagEffectCalculator {
    public static let minimumSamples = 5

    public static func impacts(
        tags: [DayTagRecord],
        daily: [DailyAggregate],
        activityDays: [ActivityDay] = [],
        calendar: Calendar,
        settings: BaselineParameters = .mvp
    ) -> [TagImpact] {
        let outcomes = dayOutcomes(daily: daily, activityDays: activityDays, calendar: calendar, settings: settings)
        let groups = Dictionary(grouping: tags) { tagGroupKey($0) }
        return groups.keys.sorted().compactMap { key in
            guard let group = groups[key], let sample = group.first else { return nil }
            return impact(label: sample.label, id: key, tags: group, outcomes: outcomes, calendar: calendar)
        }
    }

    private static func tagGroupKey(_ tag: DayTagRecord) -> String {
        if tag.kind == .custom {
            return "custom:" + tag.label.lowercased()
        }
        return tag.kind.rawValue
    }

    private struct DayOutcome {
        var day: Date
        var hrv: Double?
        var readiness: Int?
    }

    private static func impact(
        label: String,
        id: String,
        tags: [DayTagRecord],
        outcomes: [DayOutcome],
        calendar: Calendar
    ) -> TagImpact {
        let taggedNext = Set(tags.compactMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0.day)) })
        let nextDays = outcomes.filter { outcome in
            taggedNext.contains(calendar.startOfDay(for: outcome.day))
        }
        let otherDays = outcomes.filter { outcome in
            !taggedNext.contains(calendar.startOfDay(for: outcome.day))
        }
        let taggedHRV = nextDays.compactMap(\.hrv)
        let otherHRV = otherDays.compactMap(\.hrv)
        let taggedReady = nextDays.compactMap(\.readiness).map(Double.init)
        let otherReady = otherDays.compactMap(\.readiness).map(Double.init)

        let hrvDelta: Double?
        let readyDelta: Double?
        if taggedHRV.count >= minimumSamples, !otherHRV.isEmpty {
            hrvDelta = average(taggedHRV) - average(otherHRV)
        } else {
            hrvDelta = nil
        }
        if taggedReady.count >= minimumSamples, !otherReady.isEmpty {
            readyDelta = average(taggedReady) - average(otherReady)
        } else {
            readyDelta = nil
        }

        let nights = max(taggedHRV.count, taggedReady.count)
        let explanation: String
        if hrvDelta == nil && readyDelta == nil {
            explanation = "Not enough days yet (\(min(taggedHRV.count, nights)) of \(minimumSamples)) to estimate \(label)."
        } else {
            var pieces: [String] = []
            if let hrvDelta {
                let direction = hrvDelta < 0 ? "lower" : "higher"
                pieces.append(String(format: "next-day HRV averages %.0f ms %@", abs(hrvDelta), direction))
            }
            if let readyDelta {
                let direction = readyDelta < 0 ? "lower" : "higher"
                pieces.append(String(format: "next-day readiness averages %.0f points %@", abs(readyDelta), direction))
            }
            explanation = "After \(label), \(pieces.joined(separator: " and ")) (\(taggedHRV.count) nights). This is a personal average, not a cause. \(AlertCopy.footer)"
        }
        return TagImpact(
            id: id,
            label: label,
            taggedNights: taggedHRV.count,
            minimumSamples: minimumSamples,
            readinessDelta: readyDelta,
            hrvDeltaMilliseconds: hrvDelta,
            explanation: explanation
        )
    }

    private static func dayOutcomes(
        daily: [DailyAggregate],
        activityDays: [ActivityDay],
        calendar: Calendar,
        settings: BaselineParameters
    ) -> [DayOutcome] {
        let days = Set(daily.map { calendar.startOfDay(for: $0.day) }).sorted()
        return days.map { day in
            let hrv = value(metric: .hrv, on: day, daily: daily, calendar: calendar)
            let readiness = readinessScore(
                on: day,
                daily: daily,
                activityDays: activityDays,
                calendar: calendar,
                settings: settings
            )
            return DayOutcome(day: day, hrv: hrv, readiness: readiness)
        }
    }

    private static func readinessScore(
        on day: Date,
        daily: [DailyAggregate],
        activityDays: [ActivityDay],
        calendar: Calendar,
        settings: BaselineParameters
    ) -> Int? {
        let signal: (MetricKind) -> ReadinessSignal = { metric in
            let series = daily
                .filter { $0.metric == metric }
                .map { (day: calendar.startOfDay(for: $0.day), value: $0.value) }
                .sorted { $0.day < $1.day }
            let history = series.filter { $0.day < day }.map { $0.value }
            let observation = series.last(where: { $0.day == day })?.value
            let evaluation = BaselineEngine.evaluate(
                metric: metric,
                baselineValues: history,
                observation: observation,
                observedDay: observation == nil ? nil : day,
                settings: settings
            )
            return ReadinessSignal(
                zScore: evaluation.zScore,
                sampleCount: evaluation.sampleCount,
                observedDay: evaluation.observedDay
            )
        }
        let prior = ActivityLoadCalculator.priorDayLoadZ(days: activityDays, before: day, settings: settings)
        let score = ReadinessScoreCalculator.score(
            hrv: signal(.hrv),
            restingHR: signal(.rhr),
            sleep: signal(.sleep),
            priorActivityLoadZ: prior?.zScore,
            priorActivitySampleCount: prior?.sampleCount ?? 0,
            asOf: day,
            calendar: calendar
        )
        return score.score
    }

    private static func value(
        metric: MetricKind,
        on day: Date,
        daily: [DailyAggregate],
        calendar: Calendar
    ) -> Double? {
        daily.first {
            $0.metric == metric && calendar.isDate($0.day, inSameDayAs: day)
        }?.value
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
