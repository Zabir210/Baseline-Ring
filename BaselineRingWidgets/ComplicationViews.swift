import WidgetKit
import SwiftUI
import BaselineCore

struct BaselineComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.zabir.baselinering.status", provider: ComplicationTimelineProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Baseline")
        .description("Personal baseline status. Not a diagnosis.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

struct ComplicationView: View {
    var entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            Text(entry.snapshot.readinessComplicationText)
                .font(.headline)
                .foregroundStyle(tint)
                .widgetLabel("Readiness")
        case .accessoryInline:
            Text(readinessInline)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(readinessInline)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(entry.snapshot.readiness?.explanation ?? AlertCopy.headline(for: entry.snapshot))
                    .font(.caption2)
                    .lineLimit(3)
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Text(entry.snapshot.readinessComplicationText)
                    .font(.headline)
                    .foregroundStyle(tint)
            }
            .widgetLabel("Readiness")
        }
    }

    private var readinessInline: String {
        if let score = entry.snapshot.readiness?.score {
            return "Readiness \(score)"
        }
        return "Readiness –"
    }

    private var tint: Color {
        guard let score = entry.snapshot.readiness?.score else { return .gray }
        if score >= 70 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
}
