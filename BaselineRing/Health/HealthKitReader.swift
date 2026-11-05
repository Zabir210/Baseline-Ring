import Foundation
import HealthKit
import BaselineCore

enum HealthReadError: LocalizedError {
    case unavailable
    case missingType(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Health data isn’t available on this device."
        case .missingType(let name):
            "Couldn’t read \(name) from Health."
        }
    }
}

/// Read-only HealthKit adapter. Write authorization is never requested.
final class HealthKitReader: HealthReading, @unchecked Sendable {
    private let store = HKHealthStore()

    func requestReadAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthReadError.unavailable
        }
        try await store.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes())
    }

    /// Sunday U6 placeholder. Call `enableBackgroundDelivery` from here once the
    /// HealthKit background-delivery entitlement is on the App ID. Not invoked yet.
    func enableBackgroundUpdates() async {}

    func dailyAggregates(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> [DailyAggregate] {
        async let hrvDays = quantityDays(
            .heartRateVariabilitySDNN,
            metric: .hrv,
            unit: HKUnit.secondUnit(with: .milli),
            cumulative: false,
            from: start,
            through: end,
            calendar: calendar
        )
        async let rhrDays = quantityDays(
            .restingHeartRate,
            metric: .rhr,
            unit: HKUnit.count().unitDivided(by: .minute()),
            cumulative: false,
            from: start,
            through: end,
            calendar: calendar
        )
        async let stepDays = quantityDays(
            .stepCount,
            metric: .steps,
            unit: HKUnit.count(),
            cumulative: true,
            from: start,
            through: end,
            calendar: calendar
        )
        async let sleepRows = sleepDays(from: start, through: end, calendar: calendar)
        let (hrv, rhr, steps, sleep) = try await (hrvDays, rhrDays, stepDays, sleepRows)
        return hrv + rhr + steps + sleep
    }

    private func readTypes() throws -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for identifier in [
            HKQuantityTypeIdentifier.heartRateVariabilitySDNN,
            .restingHeartRate,
            .stepCount
        ] {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
                throw HealthReadError.missingType(identifier.rawValue)
            }
            types.insert(type)
        }
        guard let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthReadError.missingType(HealthMetricCatalog.identifier(for: .sleep))
        }
        types.insert(sleep)
        return types
    }

    private func quantityDays(
        _ identifier: HKQuantityTypeIdentifier,
        metric: MetricKind,
        unit: HKUnit,
        cumulative: Bool,
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> [DailyAggregate] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthReadError.missingType(metric.displayName)
        }
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd, options: .strictStartDate)
        let options: HKStatisticsOptions = cumulative ? .cumulativeSum : .discreteAverage
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: options,
            anchorDate: rangeStart,
            intervalComponents: DateComponents(day: 1)
        )

        let statistics: HKStatisticsCollection = try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            query.initialResultsHandler = { _, collection, error in
                gate.resume {
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let collection {
                        continuation.resume(returning: collection)
                    } else {
                        continuation.resume(throwing: HealthReadError.missingType(metric.displayName))
                    }
                }
            }
            store.execute(query)
        }

        var rows: [DailyAggregate] = []
        statistics.enumerateStatistics(from: rangeStart, to: rangeEnd) { stats, _ in
            let quantity = cumulative ? stats.sumQuantity() : stats.averageQuantity()
            guard let quantity else { return }
            rows.append(
                DailyAggregate(
                    metric: metric,
                    day: calendar.startOfDay(for: stats.startDate),
                    value: quantity.doubleValue(for: unit),
                    sampleCount: 1
                )
            )
        }
        return rows
    }

    /// Asleep stages only (in-bed time is ignored). A sample is attributed to the
    /// calendar day it ends on, or the next day when it ends at 6pm or later.
    private func sleepDays(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> [DailyAggregate] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthReadError.missingType(MetricKind.sleep.displayName)
        }
        let rangeStart = calendar.startOfDay(for: start)
        let expanded = calendar.date(byAdding: .hour, value: -36, to: rangeStart) ?? rangeStart
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: expanded, end: rangeEnd, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                gate.resume {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                    }
                }
            }
            store.execute(query)
        }

        var intervals: [Date: [SleepInterval]] = [:]
        var counts: [Date: Int] = [:]
        for sample in samples where isAsleep(sample) {
            let wakeDay = wakeDay(for: sample.endDate, calendar: calendar)
            guard wakeDay >= rangeStart, wakeDay < rangeEnd else { continue }
            intervals[wakeDay, default: []].append(SleepInterval(start: sample.startDate, end: sample.endDate))
            counts[wakeDay, default: 0] += 1
        }

        return intervals.map { day, spans in
            DailyAggregate(
                metric: .sleep,
                day: day,
                value: mergedHours(spans),
                sampleCount: counts[day] ?? spans.count
            )
        }
    }

    private func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        default:
            return false
        }
    }

    private func wakeDay(for end: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: end)
        if hour >= 18 {
            let next = calendar.date(byAdding: .day, value: 1, to: end) ?? end
            return calendar.startOfDay(for: next)
        }
        return calendar.startOfDay(for: end)
    }

    private func mergedHours(_ intervals: [SleepInterval]) -> Double {
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var cursor: SleepInterval?
        for interval in sorted {
            guard let current = cursor else {
                cursor = interval
                continue
            }
            if interval.start <= current.end {
                cursor = SleepInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += current.end.timeIntervalSince(current.start)
                cursor = interval
            }
        }
        if let current = cursor {
            total += current.end.timeIntervalSince(current.start)
        }
        return total / 3600
    }
}

private struct SleepInterval {
    var start: Date
    var end: Date
}

/// HK query callbacks are documented to arrive once. This keeps a second call from
/// resuming the continuation twice if a future SDK changes that.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !resumed
        if shouldRun {
            resumed = true
        }
        lock.unlock()
        if shouldRun {
            body()
        }
    }
}
