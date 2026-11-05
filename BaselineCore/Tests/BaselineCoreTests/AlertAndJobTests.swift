import XCTest
import BaselineCore

final class AlertAndJobTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    func testAlertCopyTemplates() {
        let hrv = AlertCopy.message(metric: .hrv, value: 42, mean: 58, zScore: -2.4, windowDays: 21)
        XCTAssertEqual(
            hrv,
            "Your HRV is 42 ms, about 2.4σ below your 21-day average of 58 ms. That breaks your usual range."
        )
        let rhr = AlertCopy.message(metric: .rhr, value: 72, mean: 58, zScore: 2.2, windowDays: 21)
        XCTAssertTrue(rhr.contains("72 bpm"))
        XCTAssertTrue(rhr.contains("above"))
        XCTAssertTrue(rhr.contains("58 bpm"))

        let sleep = AlertCopy.message(metric: .sleep, value: 5.2, mean: 7.5, zScore: -2.1, windowDays: 21)
        XCTAssertTrue(sleep.contains("5.2 h"))
        XCTAssertTrue(sleep.contains("7.5 h"))

        let steps = AlertCopy.message(metric: .steps, value: 3200, mean: 8000, zScore: -2.6, windowDays: 21)
        XCTAssertTrue(steps.contains("3200"))
        XCTAssertTrue(steps.contains("8000"))
        XCTAssertFalse(steps.localizedCaseInsensitiveContains("diagnosis"))
        XCTAssertFalse(hrv.localizedCaseInsensitiveContains("doctor"))
    }

    func testSummaryIncludesFooterOnce() {
        let learning = AlertCopy.summary(for: .empty)
        XCTAssertTrue(learning.contains("10 days"))
        XCTAssertEqual(learning.components(separatedBy: AlertCopy.footer).count - 1, 1)

        let clear = BaselineSnapshot(
            updatedAt: now,
            isExample: false,
            overall: .clear,
            metrics: MetricKind.allCases.map { MetricSnapshot.learning($0) },
            topAlertSentence: nil
        )
        XCTAssertTrue(AlertCopy.summary(for: clear).contains("All clear"))
    }

    func testNotificationPolicy() {
        XCTAssertTrue(AlertPolicy.shouldNotify(previous: nil, new: .warn))
        XCTAssertTrue(AlertPolicy.shouldNotify(previous: nil, new: .high))
        XCTAssertFalse(AlertPolicy.shouldNotify(previous: nil, new: .info))
        XCTAssertFalse(AlertPolicy.shouldNotify(previous: .warn, new: .warn))
        XCTAssertTrue(AlertPolicy.shouldNotify(previous: .warn, new: .high))
        XCTAssertFalse(AlertPolicy.shouldNotify(previous: .high, new: .warn))
        XCTAssertTrue(AlertPolicy.shouldNotify(previous: .info, new: .warn))
    }

    func testExamplePatternDirections() throws {
        let daily = StubHealthReader.examplePattern(now: now, calendar: calendar)
        let result = BaselineRefreshJob.run(
            daily: daily,
            asOf: now,
            calendar: calendar,
            settings: .mvp,
            isExample: true
        )
        let byMetric = Dictionary(uniqueKeysWithValues: result.evaluations.map { ($0.metric, $0) })

        let hrv = try XCTUnwrap(byMetric[.hrv])
        XCTAssertEqual(hrv.mean ?? 0, 55, accuracy: 1e-12)
        XCTAssertEqual(hrv.observed ?? 0, 51.5, accuracy: 1e-12)
        XCTAssertEqual(hrv.zScore ?? 0, -3.5, accuracy: 1e-12)
        XCTAssertEqual(hrv.status, .high)
        XCTAssertEqual(hrv.observedDay, calendar.startOfDay(for: now))

        let rhr = try XCTUnwrap(byMetric[.rhr])
        XCTAssertEqual(rhr.zScore ?? 0, 2.4, accuracy: 1e-12)
        XCTAssertEqual(rhr.status, .warn)

        let sleep = try XCTUnwrap(byMetric[.sleep])
        XCTAssertEqual(sleep.observed ?? 0, 7.1, accuracy: 1e-12)
        XCTAssertEqual(sleep.status, .warn)
        XCTAssertNotEqual(sleep.observedDay, calendar.startOfDay(for: now))

        let steps = try XCTUnwrap(byMetric[.steps])
        XCTAssertEqual(steps.observed ?? 0, 7_600, accuracy: 1e-12)
        XCTAssertEqual(steps.zScore ?? 0, -2.8, accuracy: 1e-12)
        XCTAssertEqual(steps.status, .warn)
        XCTAssertNotEqual(steps.observedDay, calendar.startOfDay(for: now))

        XCTAssertEqual(result.snapshot.overall, .high)
        XCTAssertEqual(result.snapshot.drivingMetric?.metric, .hrv)
        XCTAssertEqual(result.snapshot.complicationText, "H")
        XCTAssertTrue(result.snapshot.topAlertSentence?.contains("HRV") ?? false)
        XCTAssertEqual(result.alerts.count, 4)
        XCTAssertTrue(result.snapshot.isExample)
    }

    func testCUSUMUpgradesASmallSustainedShift() {
        let baseline = Array(repeating: 55.0, count: 21)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let mild = DailyAggregate(metric: .hrv, day: day, value: 54, sampleCount: 1)
        let history = (1...21).map { offset in
            DailyAggregate(
                metric: .hrv,
                day: day.addingTimeInterval(Double(-offset) * 86_400),
                value: baseline[0],
                sampleCount: 1
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let settings = BaselineParameters(cusumEnabled: true)
        let result = BaselineRefreshJob.run(
            daily: history + [mild],
            asOf: day,
            calendar: calendar,
            settings: settings,
            previousCUSUM: [.hrv: CUSUMState(positive: 3.6, negative: 0)]
        )
        let hrv = result.evaluations.first { $0.metric == .hrv }
        // z = (54 - 55) / 1 = -1, which is inside the z band, but CUSUM crosses 4.
        XCTAssertEqual(hrv?.zScore ?? 0, -1, accuracy: 1e-12)
        XCTAssertEqual(hrv?.status, .warn)
        XCTAssertEqual(result.states.first { $0.metric == .hrv }?.cusumPos ?? 0, 4.1, accuracy: 1e-12)
    }

    func testCUSUMStaysOffByDefault() {
        let update = CUSUM.update(
            previous: CUSUMState(positive: 3.6, negative: 0),
            zScore: 1
        )
        XCTAssertEqual(update.state.positive, 4.1, accuracy: 1e-12)
        XCTAssertTrue(update.exceedsLimit)

        let favorable = CUSUM.updateBadDirection(
            previous: CUSUMState(positive: 3, negative: 0),
            zScore: 5,
            metric: .hrv
        )
        XCTAssertFalse(favorable.exceedsLimit)
        XCTAssertEqual(favorable.state.positive, 0, accuracy: 1e-12)
    }
}
