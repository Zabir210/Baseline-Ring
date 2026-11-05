import Foundation

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

    public static let readOnlyNote = "Authorize only HRV, resting heart rate, sleep analysis, and step count. Do not request write access."
}
