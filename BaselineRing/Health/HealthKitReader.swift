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
        async let sleepFetched = sleepContext(from: start, through: end, calendar: calendar)
        let (hrv, rhr, steps, sleep) = try await (hrvDays, rhrDays, stepDays, sleepFetched)
        return hrv + rhr + steps + sleep.aggregates
    }

    func enrichedDays(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> EnrichedHealthDays {
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
        async let energyDays = ignoringErrors(
            { try await self.dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: start, through: end, calendar: calendar) },
            fallback: [:]
        )
        async let sleep = sleepContext(from: start, through: end, calendar: calendar)
        async let zones = ignoringErrors(
            { try await self.zoneMinutesByDay(from: start, through: end, calendar: calendar) },
            fallback: [:]
        )
        async let temps = ignoringErrors(
            { try await self.wristTemperature(from: start, through: end, calendar: calendar) },
            fallback: []
        )
        let (hrv, rhr, steps, energy, sleepResult, zoneMap, temperatures) = try await (
            hrvDays, rhrDays, stepDays, energyDays, sleep, zones, temps
        )
        var activity: [Date: ActivityDay] = [:]
        for row in steps {
            activity[row.day] = ActivityDay(day: row.day, steps: row.value)
        }
        for (day, kcal) in energy {
            var dayLoad = activity[day] ?? ActivityDay(day: day)
            dayLoad.activeEnergyKilocalories = kcal
            activity[day] = dayLoad
        }
        for (day, minutes) in zoneMap {
            var dayLoad = activity[day] ?? ActivityDay(day: day)
            dayLoad.zoneMinutes = minutes
            activity[day] = dayLoad
        }
        return EnrichedHealthDays(
            aggregates: hrv + rhr + steps + sleepResult.aggregates,
            sleepNights: sleepResult.nights,
            activityDays: activity.values.sorted { $0.day < $1.day },
            temperatures: temperatures
        )
    }

    private func ignoringErrors<T>(_ body: () async throws -> T, fallback: T) async -> T {
        do {
            return try await body()
        } catch {
            return fallback
        }
    }

    private func readTypes() throws -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for identifier in [
            HKQuantityTypeIdentifier.heartRateVariabilitySDNN,
            .restingHeartRate,
            .stepCount,
            .activeEnergyBurned,
            .heartRate
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
        types.insert(HKWorkoutType.workoutType())
        if #available(iOS 16.0, *) {
            if let temperature = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                types.insert(temperature)
            }
        }
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

    /// Asleep stages are summed when the sample uses the watchOS 9+ stage values.
    /// Older recordings that are only asleep or in bed still produce a night.
    /// A sample is attributed to the calendar day it ends on, or the next day when it ends at 6pm or later.
    private func sleepContext(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> (aggregates: [DailyAggregate], nights: [SleepNight]) {
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

        var buckets: [Date: NightBucket] = [:]
        for sample in samples {
            let night = wakeDay(for: sample.endDate, calendar: calendar)
            guard night >= rangeStart, night < rangeEnd else { continue }
            let span = SleepInterval(start: sample.startDate, end: sample.endDate)
            var bucket = buckets[night] ?? NightBucket()
            switch sleepClass(sample) {
            case .asleep:
                bucket.asleep.append(span)
            case .core:
                bucket.core.append(span)
                bucket.asleep.append(span)
            case .deep:
                bucket.deep.append(span)
                bucket.asleep.append(span)
            case .rem:
                bucket.rem.append(span)
                bucket.asleep.append(span)
            case .inBed:
                bucket.inBed.append(span)
            case .awake, .other:
                break
            }
            bucket.starts.append(sample.startDate)
            bucket.ends.append(sample.endDate)
            buckets[night] = bucket
        }

        let aggregates = buckets.map { day, bucket in
            DailyAggregate(
                metric: .sleep,
                day: day,
                value: mergedHours(bucket.asleep),
                sampleCount: bucket.asleep.count
            )
        }
        let nights = buckets.map { day, bucket in
            SleepNight(
                day: day,
                asleepHours: mergedHours(bucket.asleep),
                inBedHours: bucket.inBed.isEmpty ? nil : mergedHours(bucket.inBed),
                coreHours: bucket.core.isEmpty ? nil : mergedHours(bucket.core),
                deepHours: bucket.deep.isEmpty ? nil : mergedHours(bucket.deep),
                remHours: bucket.rem.isEmpty ? nil : mergedHours(bucket.rem),
                bedtimeMinutes: bucket.starts.min().map { minutesFromMidnight($0, calendar: calendar) },
                wakeMinutes: bucket.ends.max().map { minutesFromMidnight($0, calendar: calendar) }
            )
        }
        return (aggregates, nights)
    }

    /// Stage values exist on iOS 16 / watchOS 9 and later. Older asleep/in-bed samples stay on the fallback path.
    private func sleepClass(_ sample: HKCategorySample) -> SleepClass {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return .other }
        if #available(iOS 16.0, *) {
            switch value {
            case .asleepCore: return .core
            case .asleepDeep: return .deep
            case .asleepREM: return .rem
            case .asleepUnspecified: return .asleep
            case .inBed: return .inBed
            case .awake: return .awake
            default: return .other
            }
        }
        switch value {
        case .inBed: return .inBed
        case .awake: return .awake
        default: return .asleep
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

    private func minutesFromMidnight(_ date: Date, calendar: Calendar) -> Double {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return Double(hour * 60 + minute)
    }

    private func dailySums(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd, options: .strictStartDate)
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: rangeStart,
            intervalComponents: DateComponents(day: 1)
        )
        let statistics: HKStatisticsCollection? = try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            query.initialResultsHandler = { _, collection, error in
                gate.resume {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: collection)
                    }
                }
            }
            store.execute(query)
        }
        guard let statistics else { return [:] }
        var sums: [Date: Double] = [:]
        statistics.enumerateStatistics(from: rangeStart, to: rangeEnd) { stats, _ in
            guard let quantity = stats.sumQuantity() else { return }
            sums[calendar.startOfDay(for: stats.startDate)] = quantity.doubleValue(for: unit)
        }
        return sums
    }

    /// Wrist temperature is Series 8 / Ultra and later. Other watches return an empty list.
    private func wristTemperature(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> [TemperatureDay] {
        guard #available(iOS 16.0, *) else { return [] }
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else {
            return []
        }
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd, options: .strictStartDate)
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .discreteAverage,
            anchorDate: rangeStart,
            intervalComponents: DateComponents(day: 1)
        )
        let statistics: HKStatisticsCollection? = try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            query.initialResultsHandler = { _, collection, error in
                gate.resume {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: collection)
                    }
                }
            }
            store.execute(query)
        }
        guard let statistics else { return [] }
        var days: [TemperatureDay] = []
        statistics.enumerateStatistics(from: rangeStart, to: rangeEnd) { stats, _ in
            guard let quantity = stats.averageQuantity() else { return }
            days.append(
                TemperatureDay(
                    day: calendar.startOfDay(for: stats.startDate),
                    celsius: quantity.doubleValue(for: .degreeCelsius())
                )
            )
        }
        return days
    }

    /// Rough working-range minutes: average workout heart rate at or above 120 bpm counts fully,
    /// 100–119 bpm counts half. This is an estimate for load, not a clinical zone model.
    /// Unverified against a paired watch on this branch.
    private func zoneMinutesByDay(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) async throws -> [Date: Double] {
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                gate.resume {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKWorkout]) ?? [])
                    }
                }
            }
            store.execute(query)
        }
        var minutes: [Date: Double] = [:]
        for workout in workouts {
            let average = try await averageHeartRate(during: workout)
            let length = workout.duration / 60
            let credit: Double
            if let average, average >= 120 {
                credit = length
            } else if let average, average >= 100 {
                credit = length * 0.5
            } else {
                credit = 0
            }
            guard credit > 0 else { continue }
            let day = calendar.startOfDay(for: workout.startDate)
            minutes[day, default: 0] += credit
        }
        return minutes
    }

    private func averageHeartRate(during workout: HKWorkout) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                gate.resume {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
                    }
                }
            }
            store.execute(query)
        }
    }
}

private struct NightBucket {
    var asleep: [SleepInterval] = []
    var inBed: [SleepInterval] = []
    var core: [SleepInterval] = []
    var deep: [SleepInterval] = []
    var rem: [SleepInterval] = []
    var starts: [Date] = []
    var ends: [Date] = []
}

private enum SleepClass {
    case asleep
    case core
    case deep
    case rem
    case inBed
    case awake
    case other
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
