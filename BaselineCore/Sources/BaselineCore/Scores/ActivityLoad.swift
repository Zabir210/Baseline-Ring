import Foundation

public struct ActivityDay: Sendable, Equatable, Identifiable {
    public var day: Date
    public var steps: Double?
    public var activeEnergyKilocalories: Double?
    public var zoneMinutes: Double?

    public var id: String { "activity-\(day.timeIntervalSinceReferenceDate)" }

    public init(
        day: Date,
        steps: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        zoneMinutes: Double? = nil
    ) {
        self.day = day
        self.steps = steps
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.zoneMinutes = zoneMinutes
    }
}

public struct ActivityLoad: Codable, Sendable, Equatable {
    /// 0...100. About 67 is a day that matches the reference (or your own baseline).
    public var value: Double
    public var stepsComponent: Double?
    public var energyComponent: Double?
    public var zoneComponent: Double?
    public var explanation: String

    public init(
        value: Double,
        stepsComponent: Double?,
        energyComponent: Double?,
        zoneComponent: Double?,
        explanation: String
    ) {
        self.value = value
        self.stepsComponent = stepsComponent
        self.energyComponent = energyComponent
        self.zoneComponent = zoneComponent
        self.explanation = explanation
    }
}

/// Daily load from steps, active energy, and workout heart-rate zone minutes.
/// Each present input is `min(2, value / denominator)`. The denominator is your baseline
/// when it is above the epsilon, otherwise a wide reference cap (10_000 steps, 500 kcal, 30 min).
/// Load = 100 × weighted components / 1.5, so a typical day lands near 67 and a very heavy day caps at 100.
public enum ActivityLoadCalculator {
    public static let stepsWeight = 0.45
    public static let energyWeight = 0.35
    public static let zoneWeight = 0.20
    public static let stepsReference = 10_000.0
    public static let energyReference = 500.0
    public static let zoneReference = 30.0
    public static let stepsFloor = 500.0
    public static let energyFloor = 20.0
    public static let zoneFloor = 5.0
    /// σ floor when a load series is turned into a z-score for readiness.
    public static let loadEpsilon = 5.0

    public static func load(
        steps: Double?,
        activeEnergyKilocalories: Double?,
        zoneMinutes: Double?,
        stepsBaseline: Double? = nil,
        energyBaseline: Double? = nil,
        zoneBaseline: Double? = nil
    ) -> ActivityLoad {
        let stepsPart = component(
            value: steps,
            baseline: stepsBaseline,
            reference: stepsReference,
            floor: stepsFloor
        )
        let energyPart = component(
            value: activeEnergyKilocalories,
            baseline: energyBaseline,
            reference: energyReference,
            floor: energyFloor
        )
        let zonePart = component(
            value: zoneMinutes,
            baseline: zoneBaseline,
            reference: zoneReference,
            floor: zoneFloor
        )
        let weighted = (stepsPart ?? 0) * stepsWeight
            + (energyPart ?? 0) * energyWeight
            + (zonePart ?? 0) * zoneWeight
        let value = min(100, max(0, 100 * weighted / 1.5))
        return ActivityLoad(
            value: value,
            stepsComponent: stepsPart,
            energyComponent: energyPart,
            zoneComponent: zonePart,
            explanation: explanation(
                value: value,
                steps: steps,
                energy: activeEnergyKilocalories,
                zoneMinutes: zoneMinutes
            )
        )
    }

    public static func dailyLoads(_ days: [ActivityDay]) -> [(day: Date, load: Double)] {
        days.map { day in
            (
                day.day,
                load(
                    steps: day.steps,
                    activeEnergyKilocalories: day.activeEnergyKilocalories,
                    zoneMinutes: day.zoneMinutes
                ).value
            )
        }
        .sorted { $0.day < $1.day }
    }

    /// Z-score of the latest load strictly before `readinessDay`, against earlier loads.
    public static func priorDayLoadZ(
        days: [ActivityDay],
        before readinessDay: Date,
        settings: BaselineParameters = .mvp
    ) -> (load: ActivityLoad, zScore: Double?, sampleCount: Int)? {
        let ordered = days.sorted { $0.day < $1.day }.filter { $0.day < readinessDay }
        guard let latest = ordered.last else { return nil }
        let historyLoads = dailyLoads(Array(ordered.dropLast())).suffix(settings.windowDays).map(\.load)
        // Load lives on a 0...100 scale. Use loadEpsilon, not the steps epsilon.
        let stats = BaselineEngine.statistics(values: Array(historyLoads), epsilon: loadEpsilon)
        let z: Double?
        if let stats, historyLoads.count >= settings.minimumSampleCount {
            z = BaselineEngine.zScore(observation: dailyLoads([latest])[0].load, mean: stats.mean, stddev: stats.stddev)
        } else {
            z = nil
        }
        let built = load(
            steps: latest.steps,
            activeEnergyKilocalories: latest.activeEnergyKilocalories,
            zoneMinutes: latest.zoneMinutes
        )
        return (built, z, historyLoads.count)
    }

    private static func component(
        value: Double?,
        baseline: Double?,
        reference: Double,
        floor: Double
    ) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let personal = (baseline ?? 0) > floor ? baseline! : nil
        let denominator = personal ?? reference
        guard denominator > 0 else { return nil }
        return min(2, value / denominator)
    }

    private static func explanation(
        value: Double,
        steps: Double?,
        energy: Double?,
        zoneMinutes: Double?
    ) -> String {
        var bits: [String] = []
        if let steps {
            bits.append("\(Int(steps.rounded())) steps")
        }
        if let energy {
            bits.append("\(Int(energy.rounded())) kcal active")
        }
        if let zoneMinutes {
            bits.append("\(Int(zoneMinutes.rounded())) min with heart rate in a working range")
        }
        if bits.isEmpty {
            return "No activity inputs for this day."
        }
        return "Activity load \(Int(value.rounded())) from \(bits.joined(separator: ", "))."
    }
}
