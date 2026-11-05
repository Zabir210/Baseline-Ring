import XCTest
import SwiftData
import BaselineCore

@MainActor
final class StoreTests: XCTestCase {
    func testInMemoryModelsRoundTrip() throws {
        let container = try ModelContainerFactory.makeMemoryContainer()
        let context = container.mainContext
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        context.insert(
            MetricSample(
                metric: .hrv,
                startDate: day,
                endDate: day.addingTimeInterval(60),
                value: 48,
                sourceBundleId: "com.apple.health"
            )
        )
        context.insert(DailyMetric(day: day, metric: .hrv, value: 48, sampleCount: 3))
        context.insert(
            BaselineState(metric: .hrv, windowDays: 21, mean: 55, stddev: 4, sampleCount: 12)
        )
        context.insert(
            AnomalyAlert(
                metric: .hrv,
                day: day,
                observed: 48,
                baselineMean: 55,
                zScore: -1.75,
                severity: .info,
                message: "example"
            )
        )
        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let metrics = try context.fetch(FetchDescriptor<DailyMetric>())
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.value, 48)
        XCTAssertEqual(metrics.first?.metricKind, .hrv)

        let states = try context.fetch(FetchDescriptor<BaselineState>())
        XCTAssertEqual(states.first?.mean, 55)
        XCTAssertEqual(states.first?.windowDays, 21)

        let samples = try context.fetch(FetchDescriptor<MetricSample>())
        XCTAssertEqual(samples.first?.sourceBundleId, "com.apple.health")

        let alerts = try context.fetch(FetchDescriptor<AnomalyAlert>())
        XCTAssertEqual(alerts.first?.severity, .info)
        XCTAssertFalse(alerts.first?.acknowledged ?? true)

        XCTAssertEqual(BaselineStore.ensureSettings(in: context).id, settings.id)
        XCTAssertEqual(BaselineStore.currentParameters(in: context).windowDays, 21)
    }

    func testRecomputePersistsSeriesAndSnapshotCopy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let daily = StubHealthReader.examplePattern(now: now, calendar: calendar)

        let container = try ModelContainerFactory.makeMemoryContainer()
        let context = container.mainContext
        let outcome = try BaselineStore.recompute(
            daily: daily,
            asOf: now,
            calendar: calendar,
            isExample: true,
            notify: true,
            in: context
        )

        XCTAssertEqual(outcome.snapshot.overall, .high)
        XCTAssertTrue(outcome.notifications.isEmpty)

        let stored = try context.fetch(FetchDescriptor<DailyMetric>())
        XCTAssertGreaterThan(stored.count, 40)
        let alerts = try context.fetch(FetchDescriptor<AnomalyAlert>())
        XCTAssertEqual(alerts.count, 4)
        XCTAssertTrue(alerts.contains { $0.metricKind == .hrv && $0.severity == .high })

        let settings = BaselineStore.ensureSettings(in: context)
        XCTAssertTrue(settings.usingExamplePattern)
        XCTAssertNotNil(settings.lastRefreshAt)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try SnapshotStore.save(outcome.snapshot, to: directory)
        let loaded = try XCTUnwrap(SnapshotStore.load(from: directory))
        XCTAssertEqual(loaded.overall, .high)
        XCTAssertEqual(loaded.complicationText, "H")
        XCTAssertEqual(AppGroup.identifier, "group.com.zabir.baselinering")
    }

    func testAcknowledgeSurvivesSameSeverityRefresh() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let daily = StubHealthReader.examplePattern(now: now, calendar: calendar)
        let container = try ModelContainerFactory.makeMemoryContainer()
        let context = container.mainContext

        _ = try BaselineStore.recompute(
            daily: daily,
            asOf: now,
            calendar: calendar,
            isExample: false,
            notify: false,
            in: context
        )
        let first = try context.fetch(FetchDescriptor<AnomalyAlert>()).first { $0.metricKind == .rhr }
        first?.acknowledged = true
        try context.save()

        _ = try BaselineStore.recompute(
            daily: daily,
            asOf: now,
            calendar: calendar,
            isExample: false,
            notify: true,
            in: context
        )
        let second = try context.fetch(FetchDescriptor<AnomalyAlert>()).first { $0.metricKind == .rhr }
        XCTAssertEqual(second?.acknowledged, true)
        XCTAssertEqual(second?.severity, .warn)
    }
}
