import Foundation

/// The four HealthKit series this MVP learns. Same detector family for each.
public enum MetricKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case hrv
    case rhr
    case sleep
    case steps

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hrv: "HRV"
        case .rhr: "Resting HR"
        case .sleep: "Sleep"
        case .steps: "Steps"
        }
    }

    /// One-letter complication token from the weekend plan: H / R / S / T.
    public var letter: String {
        switch self {
        case .hrv: "H"
        case .rhr: "R"
        case .sleep: "S"
        case .steps: "T"
        }
    }

    public var unitSuffix: String {
        switch self {
        case .hrv: "ms"
        case .rhr: "bpm"
        case .sleep: "h"
        case .steps: ""
        }
    }

    /// Tie-break order when two metrics share a severity. Lower wins.
    public var sortOrder: Int {
        switch self {
        case .hrv: 0
        case .rhr: 1
        case .sleep: 2
        case .steps: 3
        }
    }

    /// Floor for σ so a flat week cannot divide by zero.
    /// HRV 1 ms, RHR 0.5 bpm, sleep 0.15 h, steps 500.
    public var epsilon: Double {
        switch self {
        case .hrv: 1
        case .rhr: 0.5
        case .sleep: 0.15
        case .steps: 500
        }
    }

    public var badDirection: BadDirection {
        switch self {
        case .hrv, .sleep, .steps: .lower
        case .rhr: .higher
        }
    }

    /// Steps and sleep stay incomplete until the day (or night) is over.
    public var excludesTodayUntilFinal: Bool {
        switch self {
        case .sleep, .steps: true
        case .hrv, .rhr: false
        }
    }

    public func format(_ value: Double) -> String {
        switch self {
        case .hrv, .rhr, .steps:
            String(Int(value.rounded()))
        case .sleep:
            String(format: "%.1f", value)
        }
    }

    public func formatWithUnit(_ value: Double) -> String {
        let number = format(value)
        if unitSuffix.isEmpty { return number }
        return "\(number) \(unitSuffix)"
    }
}

public enum BadDirection: String, Codable, Sendable {
    /// Large negative z is the notable direction (HRV, sleep, steps).
    case lower
    /// Large positive z is the notable direction (resting HR).
    case higher
}
