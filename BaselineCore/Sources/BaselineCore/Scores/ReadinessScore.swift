import Foundation

/// One core signal used by readiness. `zScore` is the signed z from `BaselineEngine`.
public struct ReadinessSignal: Sendable, Equatable {
    public var zScore: Double?
    public var sampleCount: Int
    public var observedDay: Date?

    public init(zScore: Double?, sampleCount: Int, observedDay: Date?) {
        self.zScore = zScore
        self.sampleCount = sampleCount
        self.observedDay = observedDay
    }
}

public struct ReadinessScore: Codable, Sendable, Equatable {
    public var score: Int?
    public var confidence: ScoreConfidence
    public var contributions: [ScoreContribution]
    public var explanation: String
    /// Short line for the Watch, the complication, and the Shortcut.
    public var spokenLine: String

    public init(
        score: Int?,
        confidence: ScoreConfidence,
        contributions: [ScoreContribution],
        explanation: String,
        spokenLine: String
    ) {
        self.score = score
        self.confidence = confidence
        self.contributions = contributions
        self.explanation = explanation
        self.spokenLine = spokenLine
    }
}

/// Weighted, capped z-score readiness. A neutral day is 80.
/// Weights: HRV 0.40, resting HR 0.30, sleep duration 0.20, prior-day activity load 0.10.
/// HRV down, resting HR up, short sleep, and a high prior-day load all subtract points.
/// The number is withheld unless at least two core signals are fresh and past the 10-day minimum.
public enum ReadinessScoreCalculator {
    public static let hrvWeight = 0.40
    public static let rhrWeight = 0.30
    public static let sleepWeight = 0.20
    public static let activityWeight = 0.10
    /// Core samples older than this are left out instead of treated as today's reading.
    public static let maxFreshLagDays = 1
    public static let highConfidenceSamples = 21

    public static func score(
        hrv: ReadinessSignal,
        restingHR: ReadinessSignal,
        sleep: ReadinessSignal,
        priorActivityLoadZ: Double?,
        priorActivitySampleCount: Int,
        asOf: Date,
        calendar: Calendar
    ) -> ReadinessScore {
        let hrvPart = corePart(
            name: "HRV",
            signal: hrv,
            weight: hrvWeight,
            higherIsWorse: false,
            asOf: asOf,
            calendar: calendar
        )
        let rhrPart = corePart(
            name: "Resting HR",
            signal: restingHR,
            weight: rhrWeight,
            higherIsWorse: true,
            asOf: asOf,
            calendar: calendar
        )
        let sleepPart = corePart(
            name: "Sleep",
            signal: sleep,
            weight: sleepWeight,
            higherIsWorse: false,
            asOf: asOf,
            calendar: calendar
        )
        let activityPart = activityPart(
            zScore: priorActivityLoadZ,
            sampleCount: priorActivitySampleCount
        )
        let parts = [hrvPart, rhrPart, sleepPart, activityPart]
        let usableCore = [hrvPart, rhrPart, sleepPart].filter(\.contribution.included).count
        let confidence = confidenceLevel(core: [hrvPart, rhrPart, sleepPart], usableCore: usableCore)
        let raw = ScoreMath.neutral + parts.reduce(0) { $0 + $1.contribution.points }
        let published: Int? = confidence == .low ? nil : ScoreMath.rounded(raw)
        let contributions = parts.map(\.contribution)
        let explanation = explanationText(score: published, contributions: contributions)
        let spoken = published.map { "Readiness is \($0) out of 100." }
            ?? "Not enough data for a readiness number."
        return ReadinessScore(
            score: published,
            confidence: confidence,
            contributions: contributions,
            explanation: explanation,
            spokenLine: spoken
        )
    }

    private struct Part {
        var contribution: ScoreContribution
        var sampleCount: Int
    }

    private static func corePart(
        name: String,
        signal: ReadinessSignal,
        weight: Double,
        higherIsWorse: Bool,
        asOf: Date,
        calendar: Calendar
    ) -> Part {
        let needed = BaselineParameters.defaultMinimumSampleCount
        guard let z = signal.zScore, z.isFinite, signal.sampleCount >= needed, let day = signal.observedDay else {
            let detail = "\(name) isn’t in this number (\(signal.sampleCount) of \(needed) days)."
            return Part(
                contribution: ScoreContribution(name: name, zScore: nil, points: 0, included: false, detail: detail),
                sampleCount: signal.sampleCount
            )
        }
        let lag = ScoreMath.dayLag(from: day, to: asOf, calendar: calendar)
        if lag > maxFreshLagDays {
            let detail = "\(name) is \(lag) days old, so it isn’t in this number."
            return Part(
                contribution: ScoreContribution(name: name, zScore: z, points: 0, included: false, detail: detail),
                sampleCount: signal.sampleCount
            )
        }
        let directional = higherIsWorse ? -z : z
        let points = ScoreMath.points(directionalZ: directional, weight: weight)
        let detail = "\(name) \(ScoreMath.formatSigma(z)) moved this by \(ScoreMath.formatPoints(points)) points."
        return Part(
            contribution: ScoreContribution(name: name, zScore: z, points: points, included: true, detail: detail),
            sampleCount: signal.sampleCount
        )
    }

    private static func activityPart(zScore: Double?, sampleCount: Int) -> Part {
        let needed = BaselineParameters.defaultMinimumSampleCount
        guard let z = zScore, z.isFinite, sampleCount >= needed else {
            let detail = "Yesterday’s activity load isn’t in this number yet (\(sampleCount) of \(needed) days)."
            return Part(
                contribution: ScoreContribution(name: "Activity", zScore: nil, points: 0, included: false, detail: detail),
                sampleCount: sampleCount
            )
        }
        let points = ScoreMath.points(directionalZ: -z, weight: activityWeight)
        let detail = "Activity load \(ScoreMath.formatSigma(z)) moved this by \(ScoreMath.formatPoints(points)) points."
        return Part(
            contribution: ScoreContribution(name: "Activity", zScore: z, points: points, included: true, detail: detail),
            sampleCount: sampleCount
        )
    }

    private static func confidenceLevel(core: [Part], usableCore: Int) -> ScoreConfidence {
        guard usableCore >= 2 else { return .low }
        let included = core.filter(\.contribution.included)
        if included.count == 3, included.allSatisfy({ $0.sampleCount >= highConfidenceSamples }) {
            return .high
        }
        return .medium
    }

    private static func explanationText(score: Int?, contributions: [ScoreContribution]) -> String {
        let body = contributions.map(\.detail).joined(separator: " ")
        if let score {
            return "Readiness \(score). \(body)"
        }
        return "Not enough data for a readiness number. \(body)"
    }
}
