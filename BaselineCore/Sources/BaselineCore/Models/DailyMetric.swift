import Foundation
import SwiftData

/// One local calendar day, already aggregated.
/// HRV: mean ms. RHR: mean bpm. Sleep: asleep hours. Steps: sum.
@Model
public final class DailyMetric {
    public var id: UUID
    public var day: Date
    public var metricRaw: String
    public var value: Double
    public var sampleCount: Int

    public init(
        id: UUID = UUID(),
        day: Date,
        metric: MetricKind,
        value: Double,
        sampleCount: Int
    ) {
        self.id = id
        self.day = day
        self.metricRaw = metric.rawValue
        self.value = value
        self.sampleCount = sampleCount
    }

    public var metricKind: MetricKind {
        get { MetricKind(rawValue: metricRaw) ?? .hrv }
        set { metricRaw = newValue.rawValue }
    }
}
