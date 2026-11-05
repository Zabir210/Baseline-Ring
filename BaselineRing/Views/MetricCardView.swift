import SwiftUI
import BaselineCore

struct MetricCardView: View {
    var snapshot: MetricSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.metric.displayName)
                    .font(.headline)
                Spacer()
                Text(snapshot.status.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(snapshot.status.tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(snapshot.status.tint)
            }
            if let observed = snapshot.observed {
                Text(snapshot.metric.formatWithUnit(observed))
                    .font(.title2.weight(.semibold))
            } else {
                Text("No day yet")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let mean = snapshot.mean {
                    Text("Baseline \(snapshot.metric.formatWithUnit(mean))")
                } else {
                    Text("Baseline —")
                }
                Spacer()
                if let z = snapshot.zScore {
                    Text(String(format: "z %+.1f", z))
                } else if snapshot.status == .learning {
                    Text("\(snapshot.sampleCount) of 10 days")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
