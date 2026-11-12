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
    public var readiness: ReadinessScore?
    public var sleepScore: SleepScore?
    public var activityLoad: ActivityLoad?
    public var patternChange: PatternChangeSignal?

    public init(
        updatedAt: Date,
        isExample: Bool,
        overall: BaselineStatus,
        metrics: [MetricSnapshot],
        topAlertSentence: String?,
        readiness: ReadinessScore? = nil,
        sleepScore: SleepScore? = nil,
        activityLoad: ActivityLoad? = nil,
        patternChange: PatternChangeSignal? = nil
    ) {
        self.updatedAt = updatedAt
        self.isExample = isExample
        self.overall = overall
        self.metrics = metrics
        self.topAlertSentence = topAlertSentence
        self.readiness = readiness
        self.sleepScore = sleepScore
        self.activityLoad = activityLoad
        self.patternChange = patternChange
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt, isExample, overall, metrics, topAlertSentence
        case readiness, sleepScore, activityLoad, patternChange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isExample = try container.decode(Bool.self, forKey: .isExample)
        overall = try container.decode(BaselineStatus.self, forKey: .overall)
        metrics = try container.decode([MetricSnapshot].self, forKey: .metrics)
        topAlertSentence = try container.decodeIfPresent(String.self, forKey: .topAlertSentence)
        readiness = try container.decodeIfPresent(ReadinessScore.self, forKey: .readiness)
        sleepScore = try container.decodeIfPresent(SleepScore.self, forKey: .sleepScore)
        activityLoad = try container.decodeIfPresent(ActivityLoad.self, forKey: .activityLoad)
        patternChange = try container.decodeIfPresent(PatternChangeSignal.self, forKey: .patternChange)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isExample, forKey: .isExample)
        try container.encode(overall, forKey: .overall)
        try container.encode(metrics, forKey: .metrics)
        try container.encodeIfPresent(topAlertSentence, forKey: .topAlertSentence)
        try container.encodeIfPresent(readiness, forKey: .readiness)
        try container.encodeIfPresent(sleepScore, forKey: .sleepScore)
        try container.encodeIfPresent(activityLoad, forKey: .activityLoad)
        try container.encodeIfPresent(patternChange, forKey: .patternChange)
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

    /// Readiness number when we are willing to show one; otherwise the status glyph.
    public var readinessComplicationText: String {
        if let score = readiness?.score {
            return "\(score)"
        }
        return "–"
    }
}
