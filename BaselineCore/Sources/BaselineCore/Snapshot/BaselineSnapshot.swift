import Foundation

public struct MetricSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var metric: MetricKind
    public var status: BaselineStatus
    public var observed: Double?
    public var observedDay: Date?
    public var mean: Double?
    public var stddev: Double?
    public var zScore: Double?
    public var sampleCount: Int
    public var sentence: String?

    public var id: String { metric.rawValue }

    public init(
        metric: MetricKind,
        status: BaselineStatus,
        observed: Double?,
        observedDay: Date?,
        mean: Double?,
        stddev: Double?,
        zScore: Double?,
        sampleCount: Int,
        sentence: String?
    ) {
        self.metric = metric
        self.status = status
        self.observed = observed
        self.observedDay = observedDay
        self.mean = mean
        self.stddev = stddev
        self.zScore = zScore
        self.sampleCount = sampleCount
        self.sentence = sentence
    }

    public static func learning(_ metric: MetricKind) -> MetricSnapshot {
        MetricSnapshot(
            metric: metric,
            status: .learning,
            observed: nil,
            observedDay: nil,
            mean: nil,
            stddev: nil,
            zScore: nil,
            sampleCount: 0,
            sentence: nil
        )
    }
}

/// Small JSON document the Watch complication can read without opening SwiftData.
public struct BaselineSnapshot: Codable, Sendable, Equatable {
    public var updatedAt: Date
    public var isExample: Bool
    public var overall: BaselineStatus
    public var metrics: [MetricSnapshot]
    public var topAlertSentence: String?

    public init(
        updatedAt: Date,
        isExample: Bool,
        overall: BaselineStatus,
        metrics: [MetricSnapshot],
        topAlertSentence: String?
    ) {
        self.updatedAt = updatedAt
        self.isExample = isExample
        self.overall = overall
        self.metrics = metrics
        self.topAlertSentence = topAlertSentence
    }

    public static let empty = BaselineSnapshot(
        updatedAt: .distantPast,
        isExample: false,
        overall: .learning,
        metrics: MetricKind.allCases.map { MetricSnapshot.learning($0) },
        topAlertSentence: nil
    )

    public var hasBeenWritten: Bool {
        updatedAt != .distantPast
    }

    /// Metric that should drive the complication letter, if any pattern break is showing.
    public var drivingMetric: MetricSnapshot? {
        let flagged = metrics.filter { $0.status == .info || $0.status == .warn || $0.status == .high }
        return flagged.max { lhs, rhs in
            if lhs.status.rank != rhs.status.rank {
                return lhs.status.rank < rhs.status.rank
            }
            return lhs.metric.sortOrder > rhs.metric.sortOrder
        }
    }

    public var complicationText: String {
        switch overall {
        case .clear:
            return "OK"
        case .learning:
            return "–"
        case .info, .warn, .high:
            return drivingMetric?.metric.letter ?? "!"
        }
    }
}
