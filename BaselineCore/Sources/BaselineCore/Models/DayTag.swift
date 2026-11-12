import Foundation
import SwiftData

/// A note the user attaches to a local day. The app does not infer these.
@Model
public final class DayTag {
    public var id: UUID
    public var day: Date
    public var kindRaw: String
    public var customLabel: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        day: Date,
        kind: DayTagKind,
        customLabel: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.day = day
        self.kindRaw = kind.rawValue
        self.customLabel = customLabel
        self.createdAt = createdAt
    }

    public var kind: DayTagKind {
        get { DayTagKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    public func record() -> DayTagRecord {
        DayTagRecord(id: id, day: day, kind: kind, customLabel: customLabel)
    }
}
