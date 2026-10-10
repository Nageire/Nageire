import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppModel.Keys.serifBody) private var serifBody = false
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
        @Bindable var model = model
        return Form {
            Group {
                Section("Account") {
                    Button {
                        if let profileURL { openURL(profileURL) }
                    } label: {
                        row("GitHub", value: model.accountLogin.map { "@\($0)" } ?? "—")
                    }
                    .disabled(profileURL == nil)
                    Button("Sign out", role: .destructive) { isConfirmingSignOut = true }
                        .foregroundStyle(.accentText)
                }
                Section("Repository") {
                    Button {
                        isChoosingRepository = true
                    } label: {
                        row("Repository", value: model.repository?.fullName ?? "—")
                    }
                }
                Section("Sync") {
                    LabeledContent("Unsent") {
                        HStack(spacing: 12) {
                            Text("^[\(model.outbox.pendingCount) item](inflect: true)")
                            Button("Send now") { Task { await model.syncNotes() } }
                                .buttonStyle(.text(compact: true))
                                .disabled(model.outbox.pendingCount == 0)
                        }
                    }
                    LabeledContent("Last sent") {
                        if let lastSentAt = model.lastSentAt {
                            Text(dayAndTime: lastSentAt)
                        } else {
                            Text(verbatim: "—")
                        }
                    }
                    Toggle("Send photos on Wi-Fi only", isOn: $model.sendsPhotosOnWiFiOnly)
                    Picker("Photo size", selection: $model.photoSize) {
                        Text("Standard").tag(PhotoSize.standard)
                        Text("Large").tag(PhotoSize.large)
                        Text("Original").tag(PhotoSize.original)
                    }
                }
            }
            // The macOS settings window can be opened from the sign-in screen, where only the look applies.
            .disabled(!model.isSignedIn)
            Section("Writing") {
                // The form shows a segmented picker across the row with no label on iPhone, and the design puts the label beside the control.
                LabeledContent("Body typeface") {
                    Picker("Body typeface", selection: $serifBody) {
                        Text("Sans").tag(false)
                        Text("Serif").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            // The on-device model is not wired until phase 5, so the section reads as on a device without it.
            Section {
            } footer: {
                Text("Not available on this device. Apple Intelligence is required.")
            }
            Section("Look back") {
                LabeledContent("Look back") { Text("Coming soon") }
                    .disabled(true)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.paperRaised)
        .scrollContentBackground(.hidden)
        .background(.paper)
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

    private var profileURL: URL? {
        model.accountLogin.flatMap { URL(string: "https://github.com/")?.appending(path: $0) }
    }

    /// A row that opens something: the label, the value, and the chevron of the design.
    private func row(_ title: LocalizedStringKey, value: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Text(verbatim: value)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.ink2)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }
}

#Preview {
    SettingsView()
        .sample(AppModel.sample())
}
