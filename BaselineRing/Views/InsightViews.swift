import SwiftUI
import SwiftData
import BaselineCore

struct ReadinessCard: View {
    var readiness: ReadinessScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Readiness")
                    .font(.headline)
                Spacer()
                Text(readiness?.confidence.label ?? "Low")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let score = readiness?.score {
                Text("\(score)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
            } else {
                Text("Not enough data")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(readiness?.explanation ?? "Readiness appears after HRV, resting HR, and sleep have enough days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SleepScoreCard: View {
    var sleep: SleepScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep")
                    .font(.headline)
                Spacer()
                if let sleep {
                    Text(sleep.usedStages ? "Stages" : "Duration")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let score = sleep?.score {
                Text("\(score)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
            } else {
                Text("Not enough data")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(sleep?.explanation ?? "Sleep score uses your nights, not a population target.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ReadinessDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let readiness = model.snapshot.readiness {
                Section {
                    if let score = readiness.score {
                        LabeledContent("Score", value: "\(score)")
                    } else {
                        Text("Not enough data")
                    }
                    LabeledContent("Confidence", value: readiness.confidence.label)
                }
                Section("What moved it") {
                    ForEach(readiness.contributions) { part in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(part.detail)
                            if let z = part.zScore {
                                Text(String(format: "z %+.2f", z))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let load = model.snapshot.activityLoad {
                    Section("Latest complete activity load") {
                        Text(load.explanation)
                    }
                }
                if let pattern = model.snapshot.patternChange, pattern.isActive {
                    Section {
                        Text(pattern.headline)
                            .font(.headline)
                        Text(pattern.explanation)
                    }
                }
            } else {
                Text("Refresh after Health access to build a readiness score.")
            }
            Section {
                Text(AlertCopy.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Readiness")
    }
}

struct SleepDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let sleep = model.snapshot.sleepScore {
                Section {
                    if let score = sleep.score {
                        LabeledContent("Score", value: "\(score)")
                    } else {
                        Text("Not enough data")
                    }
                    LabeledContent("Confidence", value: sleep.confidence.label)
                    LabeledContent("Stages", value: sleep.usedStages ? "Included" : "Not used")
                }
                Section("What moved it") {
                    ForEach(sleep.contributions) { part in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(part.detail)
                            if let z = part.zScore {
                                Text(String(format: "z %+.2f", z))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Sleep score appears after a refresh.")
            }
            Section {
                Text(AlertCopy.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sleep")
    }
}

struct JournalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \DayTag.createdAt, order: .reverse) private var tags: [DayTag]
    @Query(sort: \DailyMetric.day) private var daily: [DailyMetric]
    @State private var day = Date()
    @State private var custom = ""

    var body: some View {
        List {
            Section("Add a tag") {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                TextField("Custom label", text: $custom)
                ForEach(DayTagKind.allCases) { kind in
                    Button(kind.displayName) {
                        add(kind)
                    }
                }
            }
            Section("Recent tags") {
                if tags.isEmpty {
                    Text("No tags yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags) { tag in
                        VStack(alignment: .leading) {
                            Text(tag.record().label)
                            Text(tag.day.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            Section("Average next-day difference") {
                if impacts.isEmpty {
                    Text("Tag a few days. Effects show after \(TagEffectCalculator.minimumSamples) tagged nights with a following day of data.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(impacts) { impact in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(impact.label)
                                .font(.headline)
                            Text(impact.explanation)
                                .font(.subheadline)
                        }
                    }
                }
            }
            Section {
                Text("Tags are notes you add. They are not a reading from the watch. \(AlertCopy.footer)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Journal")
    }

    private var impacts: [TagImpact] {
        let aggregates = daily.map {
            DailyAggregate(metric: $0.metricKind, day: $0.day, value: $0.value, sampleCount: $0.sampleCount)
        }
        return TagEffectCalculator.impacts(
            tags: tags.map { $0.record() },
            daily: aggregates,
            activityDays: model.enrichment.activityDays,
            calendar: .current
        )
    }

    private func add(_ kind: DayTagKind) {
        let label = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .custom, label.isEmpty { return }
        let start = Calendar.current.startOfDay(for: day)
        context.insert(DayTag(day: start, kind: kind, customLabel: kind == .custom ? label : nil))
        try? context.save()
        if kind == .custom { custom = "" }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(tags[index])
        }
        try? context.save()
    }
}
