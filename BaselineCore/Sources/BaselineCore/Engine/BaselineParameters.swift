import Foundation

public struct BaselineParameters: Sendable, Equatable {
    public static let defaultWindowDays = 21
    public static let defaultMinimumSampleCount = 10

    public var windowDays: Int
    public var minimumSampleCount: Int
    public var zWarn: Double
    public var zHigh: Double
    public var cusumEnabled: Bool

    public static let mvp = BaselineParameters()

    public init(
        windowDays: Int = defaultWindowDays,
        minimumSampleCount: Int = defaultMinimumSampleCount,
        zWarn: Double = 2,
        zHigh: Double = 3,
        cusumEnabled: Bool = false
    ) {
        let window = min(30, max(14, windowDays))
        let minimum = max(2, minimumSampleCount)
        let warn = min(6, max(0.5, zWarn))
        var high = min(8, max(0.5, zHigh))
        if high < warn {
            high = warn
        }
        self.windowDays = window
        self.minimumSampleCount = minimum
        self.zWarn = warn
        self.zHigh = high
        self.cusumEnabled = cusumEnabled
    }
}
