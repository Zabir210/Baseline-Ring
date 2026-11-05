import SwiftUI
import SwiftData
import BaselineCore

@main
struct BaselineRingApp: App {
    private let container: ModelContainer
    private let storageNote: String?

    init() {
        let prepared = ModelContainerFactory.makeAppContainer()
        container = prepared.container
        storageNote = prepared.note
        PhoneWatchLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView(storageNote: storageNote)
        }
        .modelContainer(container)
    }
}
