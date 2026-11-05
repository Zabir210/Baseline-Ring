import SwiftUI
import SwiftData
import BaselineCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var windowDays = BaselineParameters.defaultWindowDays
    @State private var zWarn = 2.0
    @State private var zHigh = 3.0
    @State private var notificationsEnabled = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Baseline window") {
                Picker("Days", selection: $windowDays) {
                    Text("14").tag(14)
                    Text("21").tag(21)
                    Text("30").tag(30)
                }
                .pickerStyle(.segmented)
            }
            Section("Sensitivity") {
                Stepper(value: $zWarn, in: 1...4, step: 0.1) {
                    Text("Notable at \(zWarn, specifier: "%.1f")σ")
                }
                Stepper(value: $zHigh, in: 1.5...5, step: 0.1) {
                    Text("Strong break at \(zHigh, specifier: "%.1f")σ")
                }
            }
            Section("Notifications") {
                Toggle("Pattern notifications", isOn: $notificationsEnabled)
            }
            Section {
                Button("Rebuild from Health") {
                    Task { await model.refresh(context: context, source: .health) }
                }
                .disabled(model.isRefreshing)
                Button("Load example pattern") {
                    Task { await model.refresh(context: context, source: .example) }
                }
                .disabled(model.isRefreshing)
            } footer: {
                Text("Example pattern replaces stored days with a fake series so you can read the alert copy. It is not your health data.")
            }
            if let note = model.storageNote {
                Section("Storage") {
                    Text(note)
                        .font(.footnote)
                }
            }
            Section {
                Text("Personal pattern signal — not a diagnosis. Baseline Ring does not give medical advice, and it does not upload your health data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: load)
        .onChange(of: windowDays) { _, _ in persist() }
        .onChange(of: zWarn) { _, _ in persist() }
        .onChange(of: zHigh) { _, _ in persist() }
        .onChange(of: notificationsEnabled) { _, _ in persist() }
    }

    private func load() {
        let settings = BaselineStore.ensureSettings(in: context)
        windowDays = settings.baselineWindowDays
        zWarn = settings.zWarn
        zHigh = settings.zHigh
        notificationsEnabled = settings.notificationsEnabled
        loaded = true
    }

    private func persist() {
        guard loaded else { return }
        if zHigh < zWarn {
            zHigh = zWarn
        }
        let settings = BaselineStore.ensureSettings(in: context)
        let parameters = BaselineParameters(windowDays: windowDays, zWarn: zWarn, zHigh: zHigh)
        let unchanged = settings.baselineWindowDays == parameters.windowDays
            && abs(settings.zWarn - parameters.zWarn) < 0.001
            && abs(settings.zHigh - parameters.zHigh) < 0.001
            && settings.notificationsEnabled == notificationsEnabled
        guard !unchanged else { return }
        Task {
            await model.updateSettings(
                windowDays: windowDays,
                zWarn: zWarn,
                zHigh: zHigh,
                notificationsEnabled: notificationsEnabled,
                context: context
            )
        }
    }
}
