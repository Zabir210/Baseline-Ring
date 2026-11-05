import Foundation

public struct StubHealthReader: HealthReading, Sendable {
    public var fixture: [DailyAggregate]

    public init(fixture: [DailyAggregate] = []) {
        self.fixture = fixture
    }

    public func requestReadAuthorization() async throws {}

    public func dailyAggregates(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> [DailyAggregate] {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        return fixture.filter { $0.day >= lower && $0.day < upper }
    }

    /// Deterministic series so the simulator can show copy without Health data.
    /// HRV today is 3.5σ low (high). Resting HR today is 2.4σ high (warn).
    /// Last night's sleep is about 2.7σ low (warn). Yesterday's steps are 2.8σ low (warn).
    /// Today's sleep and steps are decoys and must be ignored.
    public static func examplePattern(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DailyAggregate] {
        let today = calendar.startOfDay(for: now)
        var rows: [DailyAggregate] = []
        for daysAgo in 0...23 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let hrv = daysAgo == 0 ? 51.5 : 55.0
            let rhr = daysAgo == 0 ? 59.2 : 58.0
            let sleep = daysAgo == 0 ? 1.0 : (daysAgo == 1 ? 7.1 : 7.5)
            let steps = daysAgo == 0 ? 100.0 : (daysAgo == 1 ? 7_600.0 : 9_000.0)
            rows.append(DailyAggregate(metric: .hrv, day: day, value: hrv, sampleCount: 1))
            rows.append(DailyAggregate(metric: .rhr, day: day, value: rhr, sampleCount: 1))
            rows.append(DailyAggregate(metric: .sleep, day: day, value: sleep, sampleCount: 1))
            rows.append(DailyAggregate(metric: .steps, day: day, value: steps, sampleCount: 1))
        }
        return rows
    }
}
