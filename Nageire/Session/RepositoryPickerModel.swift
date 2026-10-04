import Foundation
import Observation

@Observable
final class RepositoryPickerModel {
    enum State: Equatable {
        case loading
        case loaded([Repository])
        case failed
    }

    private(set) var state: State = .loading
    private let api: GitHubAPI

    init(api: GitHubAPI) {
        self.api = api
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await api.installedRepositories())
        } catch {
            if !Task.isCancelled {
                state = .failed
            }
        }
    }

    /// Reloads a list that is already shown, keeping it in place until the new one arrives and when the reload fails.
    func refresh() async {
        guard case .loaded = state else { return }
        if let repositories = try? await api.installedRepositories(), !Task.isCancelled {
            state = .loaded(repositories)
        }
    }
}
