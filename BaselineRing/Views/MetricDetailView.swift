import SwiftUI
import SwiftData
import Charts
import BaselineCore

struct MetricDetailView: View {
    var metric: MetricKind
    @Environment(AppModel.self) private var model
    @Query(sort: \DailyMetric.day) private var daily: [DailyMetric]
    @Query(sort: \AnomalyAlert.day, order: .reverse) private var alerts: [AnomalyAlert]

    private var snapshot: MetricSnapshot {
        model.snapshot.metrics.first { $0.metric == metric } ?? .learning(metric)
    }

    private var points: [DailyMetric] {
        daily.filter { $0.metricKind == metric }
    }

    private var metricAlerts: [AnomalyAlert] {
        alerts.filter { $0.metricKind == metric }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: snapshot.status.label)
                if let observed = snapshot.observed {
                    LabeledContent("Latest", value: metric.formatWithUnit(observed))
                }
                if let mean = snapshot.mean {
                    LabeledContent("Baseline mean", value: metric.formatWithUnit(mean))
                }
                if let stddev = snapshot.stddev {
                    LabeledContent("Baseline σ", value: metric.formatWithUnit(stddev))
                }
                if let z = snapshot.zScore {
                    LabeledContent("z-score", value: String(format: "%+.2f", z))
                }
                LabeledContent("Days in window", value: "\(snapshot.sampleCount)")
                if let sentence = snapshot.sentence {
                    Text(sentence)
                }
            }
            Section("Recent days") {
                if points.isEmpty {
                    Text("No days stored yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Day", point.day, unit: .day),
                            y: .value(metric.displayName, point.value)
                        )
                        if let mean = snapshot.mean {
                            RuleMark(y: .value("Baseline", mean))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 180)
                }
            }
            if !metricAlerts.isEmpty {
                Section("Alerts") {
                    ForEach(metricAlerts) { alert in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.severity.label)
                                .font(.caption.weight(.semibold))
                            Text(alert.message)
                                .font(.subheadline)
                        }
                    }
                }
            }
            Section {
                Text(AlertCopy.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(metric.displayName)
    }
}
