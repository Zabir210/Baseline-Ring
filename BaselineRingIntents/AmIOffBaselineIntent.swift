import AppIntents
import BaselineCore

struct AmIOffBaselineIntent: AppIntent {
    static let title: LocalizedStringResource = "Am I Off Baseline?"
    static let description = IntentDescription(
        "Checks on-device baselines and reads your readiness score when there is enough data."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = SnapshotStore.load() ?? .empty
        return .result(dialog: IntentDialog(stringLiteral: AlertCopy.summary(for: snapshot)))
    }
}

struct BaselineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AmIOffBaselineIntent(),
            phrases: [
                "Am I off baseline in \(.applicationName)",
                "Check my baseline with \(.applicationName)"
            ],
            shortTitle: "Am I Off Baseline?",
            systemImageName: "waveform.path.ecg"
        )
    }
}
