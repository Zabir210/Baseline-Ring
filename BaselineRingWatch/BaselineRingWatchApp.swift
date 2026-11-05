import SwiftUI
import BaselineCore

@main
struct BaselineRingWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchStatusView()
            }
        }
    }
}
