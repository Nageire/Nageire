import SwiftUI

struct RepositoryPickerView: View {
    @State private var picker: RepositoryPickerModel
    @State private var reloadCount = 0
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let onSelect: () -> Void

    // The presenter closes the picker. On macOS the dismiss action of a view that nothing
    // presented closes its window, and closing the only window quits the app.
    init(api: GitHubAPI, onSelect: @escaping () -> Void = {}) {
        _picker = State(initialValue: RepositoryPickerModel(api: api))
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            switch picker.state {
            case .loading:
                ProgressView()
            case .loaded(let repositories) where repositories.isEmpty:
                ContentUnavailableView {
                    Label("Install Nageire on a repository", systemImage: "tray")
                } description: {
                    Text("On GitHub, choose “Only select repositories” and pick the one where your notes will live. Nageire can read and write nothing else.")
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
                                onSelect()
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
        // Installing happens in the browser, so the list is read again when the app comes back to the front.
        .task(id: scenePhase) {
            if scenePhase == .active {
                await picker.refresh()
            }
        }
    }
}
