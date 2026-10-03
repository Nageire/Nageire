import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isChoosingRepository = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Signed in as", value: model.accountLogin ?? "—")
                    LabeledContent("Repository", value: model.repository?.fullName ?? "—")
                }
                Section {
                    Button("Change repository") { isChoosingRepository = true }
                    Button("Sign out", role: .destructive) { model.signOut() }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(verbatim: "Nageire"))
        }
        .task { await model.refreshAccount() }
        .sheet(isPresented: $isChoosingRepository) {
            NavigationStack {
                RepositoryPickerView(api: model.api)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", role: .cancel) { isChoosingRepository = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 360)
            #endif
        }
    }
}
