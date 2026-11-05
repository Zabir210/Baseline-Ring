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
            Text(entry.snapshot.complicationText)
                .font(.headline)
                .foregroundStyle(tint)
                .widgetLabel(entry.snapshot.overall.label)
        case .accessoryInline:
            Text("Baseline \(entry.snapshot.overall.label)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.overall.label)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(AlertCopy.headline(for: entry.snapshot))
                    .font(.caption2)
                    .lineLimit(3)
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Text(entry.snapshot.complicationText)
                    .font(.headline)
                    .foregroundStyle(tint)
            }
            .widgetLabel(entry.snapshot.overall.label)
        }
    }

    private var tint: Color {
        switch entry.snapshot.overall {
        case .clear: .green
        case .learning: .gray
        case .info: .blue
        case .warn: .orange
        case .high: .red
        }
    }
}
