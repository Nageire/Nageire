import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        screen
            .onChange(of: scenePhase, initial: true) { model.isInFront = scenePhase == .active }
    }

    @ViewBuilder
    private var screen: some View {
        if !model.isSignedIn {
            NavigationStack {
                SignInView(model: model.makeSignInModel())
            }
        } else if model.repository == nil {
            NavigationStack {
                RepositoryPickerView(api: model.api)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Sign out", role: .destructive) { model.signOut() }
                        }
                    }
            }
        } else {
            StreamView()
        }
    }
}
