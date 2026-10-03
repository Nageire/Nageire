import SwiftUI

@main
struct NageireApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
