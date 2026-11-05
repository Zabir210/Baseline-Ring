import Foundation
import SwiftData

/// One explainable pattern break. At most one row per metric per local day;
/// the store updates it in place when the z-score gets stronger.
@Model
public final class AnomalyAlert {
    public var id: UUID
    public var metricRaw: String
    public var day: Date
    public var observed: Double
    public var baselineMean: Double
    public var zScore: Double
    public var severityRaw: String
    public var message: String
    public var acknowledged: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        metric: MetricKind,
        day: Date,
        observed: Double,
        baselineMean: Double,
        zScore: Double,
        severity: BaselineStatus,
        message: String,
        acknowledged: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.metricRaw = metric.rawValue
        self.day = day
        self.observed = observed
        self.baselineMean = baselineMean
        self.zScore = zScore
        self.severityRaw = severity.rawValue
        self.message = message
        self.acknowledged = acknowledged
        self.createdAt = createdAt
    }

    public var metricKind: MetricKind {
        get { MetricKind(rawValue: metricRaw) ?? .hrv }
        set { metricRaw = newValue.rawValue }
    }

    public var severity: BaselineStatus {
        get { BaselineStatus(rawValue: severityRaw) ?? .info }
        set { severityRaw = newValue.rawValue }
    }
}
