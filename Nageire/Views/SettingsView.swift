import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingRepository = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Signed in as", value: model.accountLogin ?? "—")
                    LabeledContent("Repository", value: model.repository?.fullName ?? "—")
                }
                Section {
                    Button("Change repository") { isChoosingRepository = true }
                    Button("Sign out", role: .destructive) { isConfirmingSignOut = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
            } message: {
                if model.outbox.pendingCount > 0 {
                    Text("The repository choice is removed from this device. Unsent notes stay here and are sent after you sign in again.")
                } else {
                    Text("The repository choice is removed from this device.")
                }
            }
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
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
    }
}
