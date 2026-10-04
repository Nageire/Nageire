import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingRepository = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        #if os(macOS)
        // Shown in the system's settings window, which has its own title bar and close button.
        form
            .frame(width: 420)
            .fixedSize(horizontal: false, vertical: true)
        #else
        NavigationStack {
            form
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("Signed in as", value: model.accountLogin ?? "—")
                LabeledContent("Repository", value: model.repository?.fullName ?? "—")
            }
            Section {
                Button("Change repository") { isChoosingRepository = true }
                Button("Sign out", role: .destructive) { isConfirmingSignOut = true }
            }
            // The macOS settings window can be opened from the sign-in screen.
            .disabled(!model.isSignedIn)
        }
        .formStyle(.grouped)
        .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { model.signOut() }
        } message: {
            if model.outbox.pendingCount > 0 {
                Text("The repository choice is removed from this device. Unsent notes and changes stay here and are sent after you sign in again.")
            } else {
                Text("The repository choice is removed from this device.")
            }
        }
        .task { await model.refreshAccount() }
        .sheet(isPresented: $isChoosingRepository) {
            NavigationStack {
                RepositoryPickerView(api: model.api) { isChoosingRepository = false }
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
