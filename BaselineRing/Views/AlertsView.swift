import SwiftUI
import SwiftData
import BaselineCore

struct AlertsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AnomalyAlert.createdAt, order: .reverse) private var alerts: [AnomalyAlert]

    var body: some View {
        Group {
            if alerts.isEmpty {
                ContentUnavailableView(
                    "No pattern breaks",
                    systemImage: "checkmark.circle",
                    description: Text("When a metric leaves your usual range, it will show up here. \(AlertCopy.footer)")
                )
            } else {
                List {
                    ForEach(alerts) { alert in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(alert.metricKind.displayName)
                                    .font(.headline)
                                Spacer()
                                Text(alert.severity.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(alert.severity.tint)
                            }
                            Text(alert.message)
                                .font(.subheadline)
                            Text(alert.day.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if alert.acknowledged {
                                Text("Acknowledged")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(alert.acknowledged ? "Restore" : "Acknowledge") {
                                alert.acknowledged.toggle()
                                try? context.save()
                            }
                            .tint(alert.acknowledged ? .gray : .blue)
                        }
                    }
                    Section {
                        Text(AlertCopy.footer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Alerts")
    }
}
