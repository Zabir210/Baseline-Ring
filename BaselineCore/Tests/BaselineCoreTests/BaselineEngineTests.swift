import XCTest
import BaselineCore

final class BaselineEngineTests: XCTestCase {
    func testBesselZScoreMatchesHandCalculation() {
        // n = 10, mean = 11, sum of squares = 14, sample σ = sqrt(14/9).
        let values = [10.0, 12, 11, 13, 9, 10, 12, 11, 10, 12]
        let stats = BaselineEngine.statistics(values: values, epsilon: 1)
        XCTAssertEqual(stats?.mean ?? 0, 11, accuracy: 1e-12)
        XCTAssertEqual(stats?.rawStddev ?? 0, 1.247219128924647, accuracy: 1e-12)
        XCTAssertEqual(stats?.stddev ?? 0, 1.247219128924647, accuracy: 1e-12)

        let z = BaselineEngine.zScore(observation: 8, mean: 11, stddev: stats?.stddev ?? 1)
        XCTAssertEqual(z, -2.4053511772118193, accuracy: 1e-12)

        let evaluation = BaselineEngine.evaluate(
            metric: .hrv,
            baselineValues: values,
            observation: 8,
            settings: .mvp
        )
        XCTAssertFalse(evaluation.isLearning)
        XCTAssertEqual(evaluation.zScore ?? 0, -2.4053511772118193, accuracy: 1e-12)
        XCTAssertEqual(evaluation.status, .warn)
    }

    func testEpsilonFloorOnFlatSeries() {
        let flat = Array(repeating: 55.0, count: 10)
        let stats = BaselineEngine.statistics(values: flat, epsilon: MetricKind.hrv.epsilon)
        XCTAssertEqual(stats?.rawStddev, 0)
        XCTAssertEqual(stats?.stddev, 1)

        let evaluation = BaselineEngine.evaluate(
            metric: .hrv,
            baselineValues: flat,
            observation: 52,
            settings: .mvp
        )
        XCTAssertEqual(evaluation.zScore ?? 0, -3, accuracy: 1e-12)
        XCTAssertEqual(evaluation.status, .high)
    }

    func testLearningBelowTenDays() {
        let values = Array(repeating: 50.0, count: 9)
        let evaluation = BaselineEngine.evaluate(
            metric: .hrv,
            baselineValues: values,
            observation: 20,
            settings: .mvp
        )
        XCTAssertTrue(evaluation.isLearning)
        XCTAssertEqual(evaluation.status, .learning)
        XCTAssertNil(evaluation.zScore)
        XCTAssertEqual(evaluation.mean ?? 0, 50, accuracy: 1e-12)
        XCTAssertEqual(evaluation.sampleCount, 9)
    }

    func testTenDaysIsEnough() {
        let values = Array(repeating: 50.0, count: 10)
        let evaluation = BaselineEngine.evaluate(
            metric: .hrv,
            baselineValues: values,
            observation: 50,
            settings: .mvp
        )
        XCTAssertFalse(evaluation.isLearning)
        XCTAssertEqual(evaluation.status, .clear)
        XCTAssertEqual(evaluation.zScore ?? -1, 0, accuracy: 1e-12)
    }

    func testWindowKeepsTheMostRecentDays() {
        let old = Array(repeating: 1_000.0, count: 4)
        let recent = Array(repeating: 10.0, count: 21)
        let evaluation = BaselineEngine.evaluate(
            metric: .hrv,
            baselineValues: old + recent,
            observation: 10,
            settings: .mvp
        )
        XCTAssertEqual(evaluation.sampleCount, 21)
        XCTAssertEqual(evaluation.mean ?? 0, 10, accuracy: 1e-12)
        XCTAssertEqual(evaluation.status, .clear)
    }

    func testHRVDownAlertsAndHRVUpDoesNot() {
        let baseline = Array(repeating: 55.0, count: 12)
        let down = BaselineEngine.evaluate(metric: .hrv, baselineValues: baseline, observation: 52, settings: .mvp)
        XCTAssertEqual(down.status, .high)
        XCTAssertEqual(down.zScore ?? 0, -3, accuracy: 1e-12)

        let up = BaselineEngine.evaluate(metric: .hrv, baselineValues: baseline, observation: 58, settings: .mvp)
        XCTAssertEqual(up.status, .clear)
        XCTAssertEqual(up.zScore ?? 0, 3, accuracy: 1e-12)
    }

    func testRHRUpAlertsAndRHRDownDoesNot() {
        let baseline = Array(repeating: 60.0, count: 12)
        let up = BaselineEngine.evaluate(metric: .rhr, baselineValues: baseline, observation: 61.5, settings: .mvp)
        XCTAssertEqual(up.zScore ?? 0, 3, accuracy: 1e-12)
        XCTAssertEqual(up.status, .high)

        let down = BaselineEngine.evaluate(metric: .rhr, baselineValues: baseline, observation: 58.5, settings: .mvp)
        XCTAssertEqual(down.status, .clear)
    }

    func testSleepDownAlerts() {
        let baseline = Array(repeating: 7.5, count: 12)
        let evaluation = BaselineEngine.evaluate(
            metric: .sleep,
            baselineValues: baseline,
            observation: 7.05,
            settings: .mvp
        )
        // (7.05 - 7.5) / 0.15 = -3
        XCTAssertEqual(evaluation.zScore ?? 0, -3, accuracy: 1e-9)
        XCTAssertEqual(evaluation.status, .high)
    }

    func testStepsBands() {
        let baseline = Array(repeating: 10_000.0, count: 12)
        let info = BaselineEngine.evaluate(metric: .steps, baselineValues: baseline, observation: 8_800, settings: .mvp)
        XCTAssertEqual(info.zScore ?? 0, -2.4, accuracy: 1e-12)
        XCTAssertEqual(info.status, .info)

        let warn = BaselineEngine.evaluate(metric: .steps, baselineValues: baseline, observation: 8_750, settings: .mvp)
        XCTAssertEqual(warn.zScore ?? 0, -2.5, accuracy: 1e-12)
        XCTAssertEqual(warn.status, .warn)

        let high = BaselineEngine.evaluate(metric: .steps, baselineValues: baseline, observation: 8_500, settings: .mvp)
        XCTAssertEqual(high.zScore ?? 0, -3, accuracy: 1e-12)
        XCTAssertEqual(high.status, .high)

        let moreSteps = BaselineEngine.evaluate(metric: .steps, baselineValues: baseline, observation: 11_500, settings: .mvp)
        XCTAssertEqual(moreSteps.status, .clear)
    }

    func testSensitivitySettings() {
        let baseline = Array(repeating: 55.0, count: 12)
        let loose = BaselineParameters(windowDays: 21, zWarn: 2.5, zHigh: 3)
        let mild = BaselineEngine.evaluate(metric: .hrv, baselineValues: baseline, observation: 52.8, settings: loose)
        XCTAssertEqual(mild.zScore ?? 0, -2.2, accuracy: 1e-12)
        XCTAssertEqual(mild.status, .clear)

        let tight = BaselineParameters(windowDays: 21, zWarn: 2, zHigh: 2.5)
        let stronger = BaselineEngine.evaluate(metric: .hrv, baselineValues: baseline, observation: 52.4, settings: tight)
        XCTAssertEqual(stronger.zScore ?? 0, -2.6, accuracy: 1e-12)
        XCTAssertEqual(stronger.status, .high)
    }

    func testParametersClamp() {
        let clamped = BaselineParameters(windowDays: 7, minimumSampleCount: 1, zWarn: 4, zHigh: 2)
        XCTAssertEqual(clamped.windowDays, 14)
        XCTAssertEqual(clamped.minimumSampleCount, 2)
        XCTAssertEqual(clamped.zWarn, 4)
        XCTAssertEqual(clamped.zHigh, 4)
    }
}
