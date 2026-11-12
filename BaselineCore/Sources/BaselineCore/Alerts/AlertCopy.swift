import Foundation

public enum AlertCopy {
    public static let footer = "Personal pattern signal — not a diagnosis."

    public static func message(
        metric: MetricKind,
        value: Double,
        mean: Double,
        zScore: Double,
        windowDays: Int
    ) -> String {
        let absZ = String(format: "%.1f", abs(zScore))
        switch metric {
        case .hrv:
            return "Your HRV is \(metric.format(value)) ms, about \(absZ)σ below your \(windowDays)-day average of \(metric.format(mean)) ms. That breaks your usual range."
        case .rhr:
            return "Resting HR is \(metric.format(value)) bpm, \(absZ)σ above your baseline \(metric.format(mean)) bpm."
        case .sleep:
            return "Last night you slept \(metric.format(value)) h vs baseline \(metric.format(mean)) h (\(absZ)σ low)."
        case .steps:
            return "Steps are light today: \(metric.format(value)) vs usual \(metric.format(mean)) (\(absZ)σ below)."
        }
    }

    public static func headline(for snapshot: BaselineSnapshot) -> String {
        switch snapshot.overall {
        case .clear:
            return "All clear. Your recent HRV, resting heart rate, sleep, and steps are inside your usual range."
        case .learning:
            return "Still learning your baselines. Each metric needs at least 10 days."
        case .info, .warn, .high:
            return snapshot.topAlertSentence ?? "A metric is outside your usual range."
        }
    }

    public static func summary(for snapshot: BaselineSnapshot) -> String {
        var text = headline(for: snapshot)
        if let spoken = snapshot.readiness?.spokenLine {
            text += " \(spoken)"
        }
        if let pattern = snapshot.patternChange, pattern.isActive {
            text += " \(pattern.headline)."
        }
        return "\(text) \(footer)"
    }
}
