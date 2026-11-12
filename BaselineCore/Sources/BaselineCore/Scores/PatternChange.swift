import Foundation

public struct TemperatureDay: Sendable, Equatable {
    public var day: Date
    public var celsius: Double

    public init(day: Date, celsius: Double) {
        self.day = day
        self.celsius = celsius
    }
}

public struct PatternDay: Sendable, Equatable {
    public var day: Date
    public var hrvZ: Double?
    public var restingHRZ: Double?
    public var wristTemperatureZ: Double?

    public init(day: Date, hrvZ: Double?, restingHRZ: Double?, wristTemperatureZ: Double? = nil) {
        self.day = day
        self.hrvZ = hrvZ
        self.restingHRZ = restingHRZ
        self.wristTemperatureZ = wristTemperatureZ
    }
}

/// Multi-day HRV drop plus resting-HR rise. Wrist temperature, when a watch has it,
/// is mentioned if it is also high. It never creates the flag on its own.
/// User-facing copy says the pattern changed. It does not name an illness.
public struct PatternChangeSignal: Codable, Sendable, Equatable {
    public var isActive: Bool
    public var dayCount: Int
    public var headline: String
    public var explanation: String
    public var usedWristTemperature: Bool

    public init(
        isActive: Bool,
        dayCount: Int,
        headline: String,
        explanation: String,
        usedWristTemperature: Bool
    ) {
        self.isActive = isActive
        self.dayCount = dayCount
        self.headline = headline
        self.explanation = explanation
        self.usedWristTemperature = usedWristTemperature
    }

    public static let quiet = PatternChangeSignal(
        isActive: false,
        dayCount: 0,
        headline: "No multi-day pattern change",
        explanation: "Resting HR and HRV have not both been off your usual range together for two days in a row.",
        usedWristTemperature: false
    )
}

public enum PatternChangeDetector {
    public static let hrvDropZ = -1.0
    public static let restingRiseZ = 1.0
    public static let temperatureRiseZ = 1.0
    public static let temperatureEpsilon = 0.1

    public static func detect(days: [PatternDay]) -> PatternChangeSignal {
        let ordered = days.sorted { $0.day < $1.day }
        var streak: [PatternDay] = []
        for day in ordered.reversed() {
            if qualifies(day) {
                streak.append(day)
            } else {
                break
            }
        }
        streak.reverse()
        guard streak.count >= 2 else { return .quiet }

        let tempDays = streak.filter { ($0.wristTemperatureZ ?? 0) >= temperatureRiseZ }
        let usedTemp = !tempDays.isEmpty
        var sentences = streak.map { day -> String in
            let hrv = String(format: "%.1f", abs(day.hrvZ ?? 0))
            let rhr = String(format: "%.1f", day.restingHRZ ?? 0)
            return "One of those days, HRV was \(hrv)σ below your usual and resting HR was \(rhr)σ above it."
        }
        if let latestTemp = tempDays.last?.wristTemperatureZ {
            let formatted = String(format: "%.1f", latestTemp)
            sentences.append("Wrist temperature was \(formatted)σ above your recent nights on the latest of those days.")
        }
        let explanation = "Your pattern changed across \(streak.count) days. \(sentences.joined(separator: " ")) \(AlertCopy.footer)"
        return PatternChangeSignal(
            isActive: true,
            dayCount: streak.count,
            headline: "Your pattern changed",
            explanation: explanation,
            usedWristTemperature: usedTemp
        )
    }

    public static func days(
        daily: [DailyAggregate],
        temperatures: [TemperatureDay] = [],
        settings: BaselineParameters = .mvp
    ) -> [PatternDay] {
        let hrv = rollingZ(daily: daily, metric: .hrv, epsilon: MetricKind.hrv.epsilon, settings: settings)
        let rhr = rollingZ(daily: daily, metric: .rhr, epsilon: MetricKind.rhr.epsilon, settings: settings)
        let tempValues = temperatures.map { (day: $0.day, value: $0.celsius) }
        let temp = rollingZ(values: tempValues, epsilon: temperatureEpsilon, settings: settings)
        let allDays = Set(hrv.map(\.day) + rhr.map(\.day) + temp.map(\.day))
        return allDays.sorted().map { day in
            PatternDay(
                day: day,
                hrvZ: hrv.first { $0.day == day }?.z,
                restingHRZ: rhr.first { $0.day == day }?.z,
                wristTemperatureZ: temp.first { $0.day == day }?.z
            )
        }
    }

    private static func qualifies(_ day: PatternDay) -> Bool {
        guard let hrv = day.hrvZ, let rhr = day.restingHRZ else { return false }
        return hrv <= hrvDropZ && rhr >= restingRiseZ
    }

    private static func rollingZ(
        daily: [DailyAggregate],
        metric: MetricKind,
        epsilon: Double,
        settings: BaselineParameters
    ) -> [(day: Date, z: Double?)] {
        let values = daily
            .filter { $0.metric == metric }
            .map { (day: $0.day, value: $0.value) }
            .sorted { $0.day < $1.day }
        return rollingZ(values: values, epsilon: epsilon, settings: settings)
    }

    private static func rollingZ(
        values: [(day: Date, value: Double)],
        epsilon: Double,
        settings: BaselineParameters
    ) -> [(day: Date, z: Double?)] {
        values.enumerated().map { index, point in
            let history = values.prefix(index).suffix(settings.windowDays).map(\.value)
            guard history.count >= settings.minimumSampleCount,
                  let stats = BaselineEngine.statistics(values: Array(history), epsilon: epsilon) else {
                return (point.day, nil)
            }
            let z = BaselineEngine.zScore(observation: point.value, mean: stats.mean, stddev: stats.stddev)
            return (point.day, z)
        }
    }
}
