import WidgetKit
import BaselineCore

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: BaselineSnapshot
}

struct ComplicationTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = currentEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: SnapshotStore.load() ?? .empty)
    }
}
