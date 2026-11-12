import SwiftUI
import BaselineCore

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusHeader
                if model.snapshot.isExample {
                    exampleBanner
                }
                if !model.snapshot.hasBeenWritten || needsConnect {
                    connectCard
                }
                if let pattern = model.snapshot.patternChange, pattern.isActive {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pattern.headline)
                            .font(.headline)
                        Text(pattern.explanation)
                            .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                }
                NavigationLink {
                    ReadinessDetailView()
                } label: {
                    ReadinessCard(readiness: model.snapshot.readiness)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    SleepDetailView()
                } label: {
                    SleepScoreCard(sleep: model.snapshot.sleepScore)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    JournalView()
                } label: {
                    Text("Journal and tag effects")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                ForEach(model.snapshot.metrics) { metric in
                    NavigationLink {
                        MetricDetailView(metric: metric.metric)
                    } label: {
                        MetricCardView(snapshot: metric)
                    }
                    .buttonStyle(.plain)
                }
                Text(AlertCopy.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let lastError = model.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Today")
        .refreshable {
            await model.refresh(context: context, source: .health)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink("Alerts") {
                    AlertsView()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Settings") {
                    SettingsView()
                }
            }
            if model.isRefreshing {
                ToolbarItem(placement: .bottomBar) {
                    ProgressView()
                }
            }
        }
    }

    private var needsConnect: Bool {
        !model.didRequestHealthAccess && !model.snapshot.isExample
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.snapshot.overall.label)
                .font(.title2.weight(.semibold))
                .foregroundStyle(model.snapshot.overall.tint)
            Text(AlertCopy.headline(for: model.snapshot))
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exampleBanner: some View {
        Text("Example pattern. These numbers are not your health data.")
            .font(.subheadline)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Health")
                .font(.headline)
            Text("Baseline Ring reads HRV, resting heart rate, sleep, steps, and activity on this iPhone. Wrist temperature is included only when your watch records it. On-device only.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Allow Health Access") {
                Task { await model.refresh(context: context, source: .health) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRefreshing)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
