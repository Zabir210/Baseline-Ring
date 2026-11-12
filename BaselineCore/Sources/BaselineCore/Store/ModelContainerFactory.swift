import Foundation
import SwiftData

@MainActor
public enum ModelContainerFactory {
    public struct AppContainer {
        public var container: ModelContainer
        public var note: String?
    }

    public static var schema: Schema {
        Schema([
            MetricSample.self,
            DailyMetric.self,
            BaselineState.self,
            AnomalyAlert.self,
            AppSettings.self,
            DayTag.self
        ])
    }

    public static func makeMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "BaselineRing-memory",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Opens the App Group store with CloudKit explicitly off. Falls back to a memory
    /// store so a cold launch without the entitlement does not crash.
    public static func makeAppContainer() -> AppContainer {
        let url = AppGroup.storeURL()
        let configuration = ModelConfiguration(
            "BaselineRing",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            let note = AppGroup.containerURL() == nil
                ? "App Group \(AppGroup.identifier) is not active for this build, so the store is in Application Support. Turn the capability on before expecting the Watch to see data."
                : nil
            return AppContainer(container: container, note: note)
        }
        if let memory = try? makeMemoryContainer() {
            return AppContainer(
                container: memory,
                note: "Couldn’t open the saved store. This launch is temporary and resets when you quit."
            )
        }
        fatalError("Baseline Ring could not create a SwiftData store.")
    }
}
