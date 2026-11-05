import SwiftUI
import BaselineCore

struct WatchStatusView: View {
    @State private var snapshot = SnapshotStore.load() ?? .empty

    var body: some View {
        List {
            Section {
                Text(snapshot.overall.label)
                    .font(.headline)
                Text(AlertCopy.headline(for: snapshot))
                    .font(.caption2)
            }
            ForEach(snapshot.metrics) { metric in
                HStack {
                    Text(metric.metric.letter)
                        .font(.headline)
                        .frame(width: 24)
                    VStack(alignment: .leading) {
                        Text(metric.metric.displayName)
                        if let observed = metric.observed {
                            Text(metric.metric.formatWithUnit(observed))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(metric.status.label)
                        .font(.caption2)
                }
            }
            Section {
                Text(AlertCopy.footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Baseline")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Refresh") {
                    WatchSessionClient.shared.requestLatest()
                    if let stored = SnapshotStore.load() {
                        snapshot = stored
                    }
                }
            }
        }
        .onAppear {
            WatchSessionClient.shared.activate()
            WatchSessionClient.shared.onSnapshot = { updated in
                snapshot = updated
            }
            if let stored = SnapshotStore.load() {
                snapshot = stored
            }
        }
    }
}
