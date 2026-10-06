import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.isSignedIn {
            SignInView(oauth: model.oauth, onAuthorized: model.completeSignIn)
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
