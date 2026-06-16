import SwiftUI

@main
struct StrangewordsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.resume() }
        }
    }
}
