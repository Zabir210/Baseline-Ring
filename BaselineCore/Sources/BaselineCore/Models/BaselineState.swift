import Foundation
import SwiftData

/// Latest rolling baseline for one metric. One row per metric.
@Model
public final class BaselineState {
    public var metricRaw: String
    public var windowDays: Int
    public var mean: Double
    public var stddev: Double
    public var sampleCount: Int
    public var updatedAt: Date
    public var cusumPos: Double
    public var cusumNeg: Double

    public init(
        metric: MetricKind,
        windowDays: Int,
        mean: Double,
        stddev: Double,
        sampleCount: Int,
        updatedAt: Date = .now,
        cusumPos: Double = 0,
        cusumNeg: Double = 0
    ) {
        self.metricRaw = metric.rawValue
        self.windowDays = windowDays
        self.mean = mean
        self.stddev = stddev
        self.sampleCount = sampleCount
        self.updatedAt = updatedAt
        self.cusumPos = cusumPos
        self.cusumNeg = cusumNeg
    }

    public var metricKind: MetricKind {
        get { MetricKind(rawValue: metricRaw) ?? .hrv }
        set { metricRaw = newValue.rawValue }
    }
}
