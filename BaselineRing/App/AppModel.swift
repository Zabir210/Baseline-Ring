import Foundation
import SwiftData
import BaselineCore

enum RefreshSource {
    /// Ask HealthKit for the last 60 days and recompute.
    case health
    /// Replace stored days with the built-in example series.
    case example
    /// Recompute from days already stored. Used when settings change.
    case storedSeries
}

@MainActor
@Observable
final class AppModel {
    var snapshot: BaselineSnapshot = SnapshotStore.load() ?? .empty
    var isRefreshing = false
    var lastError: String?
    var storageNote: String?
    var didRequestHealthAccess = false
    private var didAutoRefresh = false
    private let reader: any HealthReading = HealthKitReader()

    func bootstrap(context: ModelContext) async {
        let settings = BaselineStore.ensureSettings(in: context)
        didRequestHealthAccess = settings.didRequestHealthAccess
        if let stored = SnapshotStore.load() {
            snapshot = stored
        }
        guard settings.didRequestHealthAccess, !settings.usingExamplePattern, !didAutoRefresh else { return }
        didAutoRefresh = true
        await refresh(context: context, source: .health)
    }

    func refresh(context: ModelContext, source: RefreshSource) async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            let settings = BaselineStore.ensureSettings(in: context)
            let daily = try await loadDaily(source: source, settings: settings, context: context)
            let example = source == .example || (source == .storedSeries && settings.usingExamplePattern)
            let notify = source == .health && settings.notificationsEnabled
            let outcome = try BaselineStore.recompute(
                daily: daily,
                settings: settings.parameters(),
                isExample: example,
                notify: notify,
                in: context
            )
            snapshot = outcome.snapshot
            try SnapshotStore.save(outcome.snapshot)
            PhoneWatchLink.shared.send(outcome.snapshot)
            if notify {
                await LocalAlertNotifier.post(outcome.notifications)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateSettings(
        windowDays: Int,
        zWarn: Double,
        zHigh: Double,
        notificationsEnabled: Bool,
        context: ModelContext
    ) async {
        let settings = BaselineStore.ensureSettings(in: context)
        let parameters = BaselineParameters(windowDays: windowDays, zWarn: zWarn, zHigh: zHigh)
        let turnedOn = notificationsEnabled && !settings.notificationsEnabled
        settings.baselineWindowDays = parameters.windowDays
        settings.zWarn = parameters.zWarn
        settings.zHigh = parameters.zHigh
        settings.notificationsEnabled = notificationsEnabled
        try? context.save()
        if turnedOn {
            await LocalAlertNotifier.requestAuthorization()
        }
        let rows = (try? context.fetch(FetchDescriptor<DailyMetric>())) ?? []
        guard !rows.isEmpty else { return }
        await refresh(context: context, source: .storedSeries)
    }

    private func loadDaily(
        source: RefreshSource,
        settings: AppSettings,
        context: ModelContext
    ) async throws -> [DailyAggregate] {
        switch source {
        case .health:
            try await reader.requestReadAuthorization()
            settings.didRequestHealthAccess = true
            didRequestHealthAccess = true
            try context.save()
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -60, to: .now) ?? .now
            return try await reader.dailyAggregates(from: start, through: .now, calendar: calendar)
        case .example:
            return StubHealthReader.examplePattern()
        case .storedSeries:
            let rows = try context.fetch(FetchDescriptor<DailyMetric>())
            return rows.map {
                DailyAggregate(
                    metric: $0.metricKind,
                    day: $0.day,
                    value: $0.value,
                    sampleCount: $0.sampleCount
                )
            }
        }
    }
}
