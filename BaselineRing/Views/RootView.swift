import SwiftUI
import BaselineCore

struct RootView: View {
    var storageNote: String?
    @State private var model = AppModel()
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            TodayView()
        }
        .environment(model)
        .task {
            model.storageNote = storageNote
            await model.bootstrap(context: context)
        }
    }
}
