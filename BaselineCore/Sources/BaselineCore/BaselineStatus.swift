import Foundation

public enum BaselineStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case learning
    case clear
    case info
    case warn
    case high

    /// Higher means a stronger pattern break. Learning sits above clear only so
    /// callers can tell "not enough data" from "in range".
    public var rank: Int {
        switch self {
        case .clear: 0
        case .learning: 1
        case .info: 2
        case .warn: 3
        case .high: 4
        }
    }

    public var label: String {
        switch self {
        case .clear: "In range"
        case .learning: "Learning"
        case .info: "Note"
        case .warn: "Outside"
        case .high: "Far outside"
        }
    }
}
