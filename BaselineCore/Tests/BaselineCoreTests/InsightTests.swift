import XCTest
import BaselineCore

final class InsightTests: XCTestCase {
    private var calendar: Calendar!
    private var today: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        today = Date(timeIntervalSince1970: 1_700_000_000)
    }

    func testReadinessDropsByCappedHRVAndWithholdsSparseData() {
        let ready = ReadinessScoreCalculator.score(
            hrv: ReadinessSignal(zScore: -3, sampleCount: 21, observedDay: today),
            restingHR: ReadinessSignal(zScore: 0, sampleCount: 21, observedDay: today),
            sleep: ReadinessSignal(zScore: 0, sampleCount: 21, observedDay: today),
            priorActivityLoadZ: nil,
            priorActivitySampleCount: 0,
            asOf: today,
            calendar: calendar
        )
        XCTAssertEqual(ready.confidence, .high)
        XCTAssertEqual(ready.score, 60)
        let hrv = ready.contributions.first { $0.name == "HRV" }
        XCTAssertEqual(hrv?.points ?? 0, -20, accuracy: 0.001)
        XCTAssertEqual(hrv?.zScore ?? 0, -3, accuracy: 0.001)
        XCTAssertTrue(ready.explanation.contains("-3.0σ"))

        let sparse = ReadinessScoreCalculator.score(
            hrv: ReadinessSignal(zScore: nil, sampleCount: 4, observedDay: today),
            restingHR: ReadinessSignal(zScore: 0, sampleCount: 21, observedDay: today),
            sleep: ReadinessSignal(zScore: nil, sampleCount: 3, observedDay: nil),
            priorActivityLoadZ: nil,
            priorActivitySampleCount: 0,
            asOf: today,
            calendar: calendar
        )
        XCTAssertEqual(sparse.confidence, .low)
        XCTAssertNil(sparse.score)
        XCTAssertTrue(sparse.explanation.contains("Not enough data"))
        XCTAssertTrue(sparse.spokenLine.contains("Not enough data"))
    }

    func testReadinessIgnoresStaleHRVAndUsesActivityLoad() {
        let staleDay = calendar.date(byAdding: .day, value: -4, to: today)!
        let stale = ReadinessScoreCalculator.score(
            hrv: ReadinessSignal(zScore: -3, sampleCount: 21, observedDay: staleDay),
            restingHR: ReadinessSignal(zScore: 0, sampleCount: 21, observedDay: today),
            sleep: ReadinessSignal(zScore: 0, sampleCount: 12, observedDay: today),
            priorActivityLoadZ: 3,
            priorActivitySampleCount: 21,
            asOf: today,
            calendar: calendar
        )
        XCTAssertEqual(stale.confidence, .medium)
        XCTAssertEqual(stale.score, 75)
        XCTAssertFalse(stale.contributions.first { $0.name == "HRV" }?.included ?? true)
        XCTAssertEqual(stale.contributions.first { $0.name == "Activity" }?.points ?? 0, -5, accuracy: 0.001)
    }

    func testActivityLoadReferencesAndPriorDayZ() {
        let typical = ActivityLoadCalculator.load(steps: 10_000, activeEnergyKilocalories: 500, zoneMinutes: 30)
        XCTAssertEqual(typical.value, 100 / 1.5, accuracy: 0.001)
        XCTAssertTrue(typical.explanation.contains("10000 steps"))

        let stepsOnly = ActivityLoadCalculator.load(steps: 10_000, activeEnergyKilocalories: nil, zoneMinutes: nil)
        XCTAssertEqual(stepsOnly.value, 30, accuracy: 0.001)

        let anchor = today!
        var days: [ActivityDay] = []
        for offset in 1...12 {
            let day = calendar.date(byAdding: .day, value: -offset, to: anchor)!
            let steps = offset == 1 ? 20_000.0 : 10_000.0
            days.append(ActivityDay(day: day, steps: steps))
        }
        let prior = ActivityLoadCalculator.priorDayLoadZ(days: days, before: anchor)
        XCTAssertEqual(prior?.sampleCount, 11)
        XCTAssertNotNil(prior?.zScore)
        XCTAssertGreaterThan(prior?.zScore ?? 0, 0)
    }

    func testSleepFallbackAndStagePaths() {
        var nights: [SleepNight] = []
        for offset in 0...14 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            if offset == 0 {
                nights.append(SleepNight(day: day, asleepHours: 6, inBedHours: 8, bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60))
            } else {
                nights.append(SleepNight(day: day, asleepHours: 7.5, inBedHours: 8.5, bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60))
            }
        }
        let fallback = SleepScoreCalculator.score(nights: nights)
        XCTAssertFalse(fallback.usedStages)
        XCTAssertEqual(fallback.confidence, .medium)
        XCTAssertEqual(fallback.score, 50)
        XCTAssertEqual(fallback.contributions.first { $0.name == "Time asleep" }?.points ?? 0, -25, accuracy: 0.001)
        XCTAssertEqual(fallback.contributions.first { $0.name == "Time in bed" }?.points ?? 0, -15, accuracy: 0.001)
        XCTAssertEqual(fallback.contributions.first { $0.name == "Schedule" }?.points ?? 0, 10, accuracy: 0.001)
        XCTAssertTrue(fallback.explanation.contains("no core/deep/REM"))

        var staged: [SleepNight] = []
        for offset in 0...21 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let deep = offset == 0 ? 1.2 : 1.5
            staged.append(
                SleepNight(
                    day: day,
                    asleepHours: 7.5,
                    inBedHours: 8.5,
                    coreHours: 4,
                    deepHours: deep,
                    remHours: 1.5,
                    bedtimeMinutes: 23 * 60,
                    wakeMinutes: 7 * 60
                )
            )
        }
        let stages = SleepScoreCalculator.score(nights: staged)
        XCTAssertTrue(stages.usedStages)
        XCTAssertEqual(stages.confidence, .high)
        XCTAssertEqual(stages.score, 68)
        XCTAssertEqual(stages.contributions.first { $0.name == "Deep sleep" }?.zScore ?? 0, -3, accuracy: 0.001)
        XCTAssertEqual(stages.contributions.first { $0.name == "Deep sleep" }?.points ?? 0, -12.5, accuracy: 0.001)
    }

    func testPatternChangeNeedsTwoDaysAndStaysNonDiagnostic() {
        let quiet = PatternChangeDetector.detect(days: [
            PatternDay(day: today, hrvZ: -2, restingHRZ: 2)
        ])
        XCTAssertFalse(quiet.isActive)

        let second = calendar.date(byAdding: .day, value: -1, to: today)!
        let active = PatternChangeDetector.detect(days: [
            PatternDay(day: second, hrvZ: -1.2, restingHRZ: 1.1),
            PatternDay(day: today, hrvZ: -1.5, restingHRZ: 1.4, wristTemperatureZ: 1.2)
        ])
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.dayCount, 2)
        XCTAssertTrue(active.usedWristTemperature)
        XCTAssertTrue(active.explanation.contains("Your pattern changed"))
        XCTAssertTrue(active.explanation.contains("Wrist temperature"))
        XCTAssertFalse(active.explanation.localizedCaseInsensitiveContains("sick"))
        XCTAssertFalse(active.explanation.localizedCaseInsensitiveContains("fever"))
        XCTAssertTrue(active.explanation.contains(AlertCopy.footer))

        let temperatureAlone = PatternChangeDetector.detect(days: [
            PatternDay(day: second, hrvZ: 0, restingHRZ: 0, wristTemperatureZ: 2),
            PatternDay(day: today, hrvZ: 0.2, restingHRZ: -0.4, wristTemperatureZ: 2)
        ])
        XCTAssertFalse(temperatureAlone.isActive)
    }

    func testTagEffectNeedsFiveNights() throws {
        var daily: [DailyAggregate] = []
        var tags: [DayTagRecord] = []
        let taggedOffsets = [6, 8, 10, 12, 14]
        let nextOffsets = [5, 7, 9, 11, 13]
        for offset in 0..<30 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            daily.append(DailyAggregate(metric: .hrv, day: day, value: nextOffsets.contains(offset) ? 49 : 55, sampleCount: 1))
            if taggedOffsets.contains(offset) {
                tags.append(DayTagRecord(day: day, kind: .alcohol))
            }
        }
        let tooFew = TagEffectCalculator.impacts(
            tags: Array(tags.prefix(2)),
            daily: daily,
            calendar: calendar
        )
        XCTAssertNil(tooFew.first?.hrvDeltaMilliseconds)
        XCTAssertTrue(tooFew.first?.explanation.contains("Not enough") ?? false)

        let impact = try XCTUnwrap(TagEffectCalculator.impacts(tags: tags, daily: daily, calendar: calendar).first)
        XCTAssertEqual(impact.hrvDeltaMilliseconds ?? 0, -6, accuracy: 0.001)
        XCTAssertTrue(impact.explanation.contains("6 ms lower"))
        XCTAssertFalse(impact.explanation.localizedCaseInsensitiveContains("causes"))
    }
}
