import SwiftUI

struct RepositoryPickerView: View {
    @State private var picker: RepositoryPickerModel
    @State private var reloadCount = 0
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(api: GitHubAPI) {
        _picker = State(initialValue: RepositoryPickerModel(api: api))
    }

    var body: some View {
        Group {
            switch picker.state {
            case .loading:
                ProgressView()
            case .loaded(let repositories) where repositories.isEmpty:
                ContentUnavailableView {
                    Label("No repositories available", systemImage: "tray")
                } description: {
                    Text("Install the Nageire GitHub App on the repository where your notes will live, then reload.")
                } actions: {
                    Button("Install on GitHub") { openURL(model.configuration.installationURL) }
                        .buttonStyle(.borderedProminent)
                }
            case .loaded(let repositories):
                List {
                    Section {
                        ForEach(repositories) { repository in
                            Button {
                                model.select(repository)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(verbatim: repository.fullName)
                                    Spacer()
                                    if repository == model.repository {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Button("Add or remove repositories on GitHub") { openURL(model.configuration.installationURL) }
                            .font(.footnote)
                    }
                }
            case .failed:
                ContentUnavailableView {
                    Label("Could not load repositories", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Try again") { reloadCount += 1 }
                }
            }
        }
        .navigationTitle("Choose a repository")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reload", systemImage: "arrow.clockwise") { reloadCount += 1 }
            }
        }
        // Keyed on the counter so that a reload cancels the load still in flight instead of racing it.
        .task(id: reloadCount) { await picker.load() }
    }
}
