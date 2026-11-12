import Foundation

public struct SleepNight: Sendable, Equatable, Identifiable {
    public var day: Date
    public var asleepHours: Double
    public var inBedHours: Double?
    public var coreHours: Double?
    public var deepHours: Double?
    public var remHours: Double?
    /// Minutes from local midnight. Times after midnight and before noon are treated as the next morning.
    public var bedtimeMinutes: Double?
    public var wakeMinutes: Double?

    public var id: String { "sleep-\(day.timeIntervalSinceReferenceDate)" }

    public init(
        day: Date,
        asleepHours: Double,
        inBedHours: Double? = nil,
        coreHours: Double? = nil,
        deepHours: Double? = nil,
        remHours: Double? = nil,
        bedtimeMinutes: Double? = nil,
        wakeMinutes: Double? = nil
    ) {
        self.day = day
        self.asleepHours = asleepHours
        self.inBedHours = inBedHours
        self.coreHours = coreHours
        self.deepHours = deepHours
        self.remHours = remHours
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
    }

    public var hasStageBreakdown: Bool {
        let staged = (coreHours ?? 0) + (deepHours ?? 0) + (remHours ?? 0)
        return staged >= 0.25
    }

    public var efficiency: Double? {
        guard let inBedHours, inBedHours > 0.2, asleepHours >= 0 else { return nil }
        return min(1, asleepHours / inBedHours)
    }
}

public struct SleepScore: Codable, Sendable, Equatable {
    public var score: Int?
    public var confidence: ScoreConfidence
    public var usedStages: Bool
    public var contributions: [ScoreContribution]
    public var explanation: String

    public init(
        score: Int?,
        confidence: ScoreConfidence,
        usedStages: Bool,
        contributions: [ScoreContribution],
        explanation: String
    ) {
        self.score = score
        self.confidence = confidence
        self.usedStages = usedStages
        self.contributions = contributions
        self.explanation = explanation
    }
}

/// Sleep score from personal z-scores.
/// Stage path (watchOS 9+ nights that include core, deep, and REM, once 7 prior staged nights exist):
/// duration 0.40, deep 0.25, REM 0.25, efficiency 0.10.
/// Fallback (asleep vs in-bed, no stage history): duration 0.50, efficiency 0.30, bedtime/wake consistency 0.20.
/// Missing pieces contribute 0 and say so. The number is withheld under 10 duration nights.
public enum SleepScoreCalculator {
    public static let minimumStageNights = 7
    public static let durationWeightStages = 0.40
    public static let deepWeight = 0.25
    public static let remWeight = 0.25
    public static let efficiencyWeightStages = 0.10
    public static let durationWeightFallback = 0.50
    public static let efficiencyWeightFallback = 0.30
    public static let consistencyWeight = 0.20
    public static let stageEpsilonHours = 0.10
    public static let efficiencyEpsilon = 0.02

    public static func nights(from aggregates: [DailyAggregate]) -> [SleepNight] {
        aggregates
            .filter { $0.metric == .sleep }
            .map { SleepNight(day: $0.day, asleepHours: $0.value) }
            .sorted { $0.day < $1.day }
    }

    public static func score(
        nights: [SleepNight],
        settings: BaselineParameters = .mvp
    ) -> SleepScore {
        let ordered = nights.sorted { $0.day < $1.day }
        guard let night = ordered.last else {
            return withheld(usedStages: false, contributions: [], note: "No sleep nights stored yet.")
        }
        let history = Array(ordered.dropLast())
        let duration = zContribution(
            name: "Time asleep",
            history: history.map(\.asleepHours),
            observation: night.asleepHours,
            epsilon: MetricKind.sleep.epsilon,
            weight: 0,
            settings: settings
        )
        let stagedHistory = history.filter(\.hasStageBreakdown)
        let useStages = night.hasStageBreakdown && stagedHistory.count >= minimumStageNights
        if useStages {
            return stageScore(night: night, history: stagedHistory, durationZ: duration, settings: settings)
        }
        return fallbackScore(night: night, history: history, durationZ: duration, settings: settings)
    }

    private static func stageScore(
        night: SleepNight,
        history: [SleepNight],
        durationZ: (z: Double?, count: Int),
        settings: BaselineParameters
    ) -> SleepScore {
        let duration = contribution(
            name: "Time asleep",
            z: durationZ.z,
            count: durationZ.count,
            weight: durationWeightStages,
            missing: "Time asleep isn’t in this number yet."
        )
        let deep = zContribution(
            name: "Deep sleep",
            history: history.compactMap(\.deepHours),
            observation: night.deepHours,
            epsilon: stageEpsilonHours,
            weight: deepWeight,
            minimumCount: minimumStageNights,
            settings: settings
        )
        let rem = zContribution(
            name: "REM sleep",
            history: history.compactMap(\.remHours),
            observation: night.remHours,
            epsilon: stageEpsilonHours,
            weight: remWeight,
            minimumCount: minimumStageNights,
            settings: settings
        )
        let efficiency = efficiencyContribution(
            night: night,
            history: history,
            weight: efficiencyWeightStages,
            minimumCount: minimumStageNights,
            settings: settings
        )
        let parts = [
            duration,
            contribution(name: "Deep sleep", z: deep.z, count: deep.count, weight: deepWeight, missing: "Deep sleep isn’t in this number yet."),
            contribution(name: "REM sleep", z: rem.z, count: rem.count, weight: remWeight, missing: "REM sleep isn’t in this number yet."),
            efficiency
        ]
        return assemble(parts: parts, usedStages: true, durationCount: durationZ.count, staged: true)
    }

    private static func fallbackScore(
        night: SleepNight,
        history: [SleepNight],
        durationZ: (z: Double?, count: Int),
        settings: BaselineParameters
    ) -> SleepScore {
        let duration = contribution(
            name: "Time asleep",
            z: durationZ.z,
            count: durationZ.count,
            weight: durationWeightFallback,
            missing: "Time asleep isn’t in this number yet."
        )
        let efficiency = efficiencyContribution(
            night: night,
            history: history,
            weight: efficiencyWeightFallback,
            settings: settings
        )
        let consistency = consistencyContribution(night: night, history: history + [night])
        let stageNote = ScoreContribution(
            name: "Sleep stages",
            zScore: nil,
            points: 0,
            included: false,
            detail: night.hasStageBreakdown
                ? "Stages were recorded, but there aren’t \(minimumStageNights) earlier staged nights yet, so they aren’t in this number."
                : "This night has no core/deep/REM split, so the score uses time asleep, time in bed, and schedule consistency."
        )
        return assemble(
            parts: [duration, efficiency, consistency, stageNote],
            usedStages: false,
            durationCount: durationZ.count,
            staged: false
        )
    }

    private static func assemble(
        parts: [ScoreContribution],
        usedStages: Bool,
        durationCount: Int,
        staged: Bool
    ) -> SleepScore {
        let confidence: ScoreConfidence
        if durationCount < BaselineParameters.defaultMinimumSampleCount {
            confidence = .low
        } else if staged && durationCount >= ReadinessScoreCalculator.highConfidenceSamples {
            confidence = .high
        } else {
            confidence = .medium
        }
        let raw = ScoreMath.neutral + parts.reduce(0) { $0 + $1.points }
        let published: Int? = confidence == .low ? nil : ScoreMath.rounded(raw)
        let body = parts.map(\.detail).joined(separator: " ")
        let explanation: String
        if let published {
            explanation = "Sleep score \(published). \(body)"
        } else {
            explanation = "Not enough data for a sleep score. \(body)"
        }
        return SleepScore(
            score: published,
            confidence: confidence,
            usedStages: usedStages,
            contributions: parts,
            explanation: explanation
        )
    }

    private static func withheld(usedStages: Bool, contributions: [ScoreContribution], note: String) -> SleepScore {
        SleepScore(
            score: nil,
            confidence: .low,
            usedStages: usedStages,
            contributions: contributions,
            explanation: "Not enough data for a sleep score. \(note)"
        )
    }

    private static func contribution(
        name: String,
        z: Double?,
        count: Int,
        weight: Double,
        missing: String
    ) -> ScoreContribution {
        guard let z, z.isFinite else {
            _ = count
            return ScoreContribution(name: name, zScore: nil, points: 0, included: false, detail: missing)
        }
        let points = ScoreMath.points(directionalZ: z, weight: weight)
        let detail = "\(name) \(ScoreMath.formatSigma(z)) moved this by \(ScoreMath.formatPoints(points)) points."
        return ScoreContribution(name: name, zScore: z, points: points, included: true, detail: detail)
    }

    private static func zContribution(
        name: String,
        history: [Double],
        observation: Double?,
        epsilon: Double,
        weight: Double,
        minimumCount: Int = BaselineParameters.defaultMinimumSampleCount,
        settings: BaselineParameters
    ) -> (z: Double?, count: Int) {
        _ = name
        _ = weight
        guard let observation, observation.isFinite else { return (nil, history.count) }
        let window = Array(history.suffix(settings.windowDays))
        guard window.count >= minimumCount else { return (nil, window.count) }
        guard let stats = BaselineEngine.statistics(values: window, epsilon: epsilon) else {
            return (nil, window.count)
        }
        let z = BaselineEngine.zScore(observation: observation, mean: stats.mean, stddev: stats.stddev)
        return (z, window.count)
    }

    private static func efficiencyContribution(
        night: SleepNight,
        history: [SleepNight],
        weight: Double,
        minimumCount: Int = BaselineParameters.defaultMinimumSampleCount,
        settings: BaselineParameters
    ) -> ScoreContribution {
        guard night.efficiency != nil else {
            return ScoreContribution(
                name: "Time in bed",
                zScore: nil,
                points: 0,
                included: false,
                detail: "Time in bed wasn’t recorded, so efficiency isn’t in this number."
            )
        }
        let past = history.compactMap(\.efficiency)
        let zipped = zContribution(
            name: "Efficiency",
            history: past,
            observation: night.efficiency,
            epsilon: efficiencyEpsilon,
            weight: weight,
            minimumCount: minimumCount,
            settings: settings
        )
        return contribution(
            name: "Time in bed",
            z: zipped.z,
            count: zipped.count,
            weight: weight,
            missing: "Not enough nights with both asleep and in-bed time for efficiency."
        )
    }

    private static func consistencyContribution(night: SleepNight, history: [SleepNight]) -> ScoreContribution {
        let bedtimes = history.compactMap { $0.bedtimeMinutes.map(linearMinutes) }
        let wakes = history.compactMap { $0.wakeMinutes.map(linearWake) }
        guard bedtimes.count >= minimumStageNights || wakes.count >= minimumStageNights else {
            return ScoreContribution(
                name: "Schedule",
                zScore: nil,
                points: 0,
                included: false,
                detail: "Not enough bedtimes or wake times yet for a consistency term."
            )
        }
        let bedtimeSpread = standardDeviationMinutes(bedtimes)
        let wakeSpread = standardDeviationMinutes(wakes)
        let spreads = [bedtimeSpread, wakeSpread].compactMap { $0 }
        guard let spread = spreads.isEmpty ? nil : spreads.reduce(0, +) / Double(spreads.count) else {
            return ScoreContribution(
                name: "Schedule",
                zScore: nil,
                points: 0,
                included: false,
                detail: "Schedule consistency isn’t in this number."
            )
        }
        // 60 minutes of spread is neutral. Tighter schedules add points, wider ones subtract.
        let directional = min(1, max(-1, (60 - spread) / 60))
        let points = consistencyWeight * ScoreMath.fullSwing * directional
        _ = night
        let detail = "Bedtime and wake times vary by about \(Int(spread.rounded())) min (\(ScoreMath.formatPoints(points)) points)."
        return ScoreContribution(name: "Schedule", zScore: nil, points: points, included: true, detail: detail)
    }

    /// Evening bedtimes stay continuous: 23:00 → 1380, 01:00 → 1500.
    static func linearMinutes(_ minutesFromMidnight: Double) -> Double {
        minutesFromMidnight < 12 * 60 ? minutesFromMidnight + 24 * 60 : minutesFromMidnight
    }

    static func linearWake(_ minutesFromMidnight: Double) -> Double {
        minutesFromMidnight
    }

    private static func standardDeviationMinutes(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let sum = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sum / Double(values.count - 1)).squareRoot()
    }
}
