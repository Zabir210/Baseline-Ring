import Foundation

public struct EnrichedHealthDays: Sendable, Equatable {
    public var aggregates: [DailyAggregate]
    public var sleepNights: [SleepNight]
    public var activityDays: [ActivityDay]
    public var temperatures: [TemperatureDay]

    public init(
        aggregates: [DailyAggregate],
        sleepNights: [SleepNight] = [],
        activityDays: [ActivityDay] = [],
        temperatures: [TemperatureDay] = []
    ) {
        self.aggregates = aggregates
        self.sleepNights = sleepNights
        self.activityDays = activityDays
        self.temperatures = temperatures
    }
}

/// One aggregated local day. `day` is the start of that day in the calendar used to build it.
public struct DailyAggregate: Sendable, Equatable, Identifiable {
    public var metric: MetricKind
    public var day: Date
    public var value: Double
    public var sampleCount: Int

    public var id: String {
        "\(metric.rawValue)|\(day.timeIntervalSinceReferenceDate)"
    }

    public init(metric: MetricKind, day: Date, value: Double, sampleCount: Int) {
        self.metric = metric
        self.day = day
        self.value = value
        self.sampleCount = sampleCount
    }
}

/// Read-only HealthKit surface. Core does not import HealthKit so widgets and tests stay portable.
/// The iOS app supplies `HealthKitReader`.
public protocol HealthReading: Sendable {
    func requestReadAuthorization() async throws
    func dailyAggregates(from start: Date, through end: Date, calendar: Calendar) async throws -> [DailyAggregate]
    func enrichedDays(from start: Date, through end: Date, calendar: Calendar) async throws -> EnrichedHealthDays
}

extension HealthReading {
    public func enrichedDays(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> EnrichedHealthDays {
        let aggregates = try await dailyAggregates(from: start, through: end, calendar: calendar)
        let stepsByDay = Dictionary(grouping: aggregates.filter { $0.metric == .steps }) { $0.day }
        let activity = stepsByDay.map { day, rows in
            ActivityDay(day: day, steps: rows.reduce(0) { $0 + $1.value })
        }
        return EnrichedHealthDays(
            aggregates: aggregates,
            sleepNights: SleepScoreCalculator.nights(from: aggregates),
            activityDays: activity,
            temperatures: []
        )
    }
}

/// Identifier strings the iOS reader maps onto HealthKit types. Read-only; this app does not write Health data.
public enum HealthMetricCatalog {
    public static func identifier(for metric: MetricKind) -> String {
        switch metric {
        case .hrv:
            "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        case .rhr:
            "HKQuantityTypeIdentifierRestingHeartRate"
        case .sleep:
            "HKCategoryTypeIdentifierSleepAnalysis"
        case .steps:
            "HKQuantityTypeIdentifierStepCount"
        }
    }

    public static let readOnlyNote = "Read HRV, resting heart rate, sleep, steps, active energy, heart rate during workouts, and wrist temperature when the watch has it. Do not request write access."
}
