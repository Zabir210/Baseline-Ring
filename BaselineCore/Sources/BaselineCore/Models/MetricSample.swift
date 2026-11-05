import Foundation
import SwiftData

/// One HealthKit sample in canonical units. The MVP dashboard reads `DailyMetric`;
/// raw samples are kept for provenance and later debugging.
@Model
public final class MetricSample {
    public var id: UUID
    public var metricRaw: String
    public var startDate: Date
    public var endDate: Date
    public var value: Double
    public var sourceBundleId: String?
    public var importedAt: Date

    public init(
        id: UUID = UUID(),
        metric: MetricKind,
        startDate: Date,
        endDate: Date,
        value: Double,
        sourceBundleId: String? = nil,
        importedAt: Date = .now
    ) {
        self.id = id
        self.metricRaw = metric.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.sourceBundleId = sourceBundleId
        self.importedAt = importedAt
    }

    public var metricKind: MetricKind {
        get { MetricKind(rawValue: metricRaw) ?? .hrv }
        set { metricRaw = newValue.rawValue }
    }
}
