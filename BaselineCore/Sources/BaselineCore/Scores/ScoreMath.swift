import Foundation

public enum ScoreConfidence: String, Codable, Sendable, Equatable {
    case low
    case medium
    case high

    public var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

public struct ScoreContribution: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var zScore: Double?
    /// Signed points added to the neutral score. Zero when the metric is left out.
    public var points: Double
    public var included: Bool
    public var detail: String

    public var id: String { name }

    public init(name: String, zScore: Double?, points: Double, included: Bool, detail: String) {
        self.name = name
        self.zScore = zScore
        self.points = points
        self.included = included
        self.detail = detail
    }
}

enum ScoreMath {
    static let neutral = 80.0
    /// Full ±3σ swing, split across weights. A weight of 1.0 can move the score by 50 points.
    static let fullSwing = 50.0

    static func points(directionalZ: Double, weight: Double) -> Double {
        guard directionalZ.isFinite else { return 0 }
        let capped = min(3, max(-3, directionalZ))
        return weight * fullSwing * (capped / 3)
    }

    static func rounded(_ raw: Double) -> Int {
        Int(min(100, max(0, raw)).rounded())
    }

    static func dayLag(from day: Date, to asOf: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: asOf)
        return calendar.dateComponents([.day], from: start, to: today).day ?? 0
    }

    static func formatSigma(_ z: Double) -> String {
        String(format: "%+.1fσ", z)
    }

    static func formatPoints(_ points: Double) -> String {
        String(format: "%+.0f", points.rounded())
    }
}
