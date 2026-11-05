import Foundation
import SwiftData

/// Single settings row. `BaselineStore.ensureSettings` creates it.
@Model
public final class AppSettings {
    public var id: UUID
    public var baselineWindowDays: Int
    public var zWarn: Double
    public var zHigh: Double
    public var cusumEnabled: Bool
    public var notificationsEnabled: Bool
    public var lastRefreshAt: Date?
    public var didRequestHealthAccess: Bool
    public var usingExamplePattern: Bool

    public init(
        id: UUID = UUID(),
        baselineWindowDays: Int = BaselineParameters.defaultWindowDays,
        zWarn: Double = 2,
        zHigh: Double = 3,
        cusumEnabled: Bool = false,
        notificationsEnabled: Bool = false,
        lastRefreshAt: Date? = nil,
        didRequestHealthAccess: Bool = false,
        usingExamplePattern: Bool = false
    ) {
        self.id = id
        self.baselineWindowDays = baselineWindowDays
        self.zWarn = zWarn
        self.zHigh = zHigh
        self.cusumEnabled = cusumEnabled
        self.notificationsEnabled = notificationsEnabled
        self.lastRefreshAt = lastRefreshAt
        self.didRequestHealthAccess = didRequestHealthAccess
        self.usingExamplePattern = usingExamplePattern
    }

    public func parameters() -> BaselineParameters {
        BaselineParameters(
            windowDays: baselineWindowDays,
            minimumSampleCount: BaselineParameters.defaultMinimumSampleCount,
            zWarn: zWarn,
            zHigh: zHigh,
            cusumEnabled: cusumEnabled
        )
    }
}
