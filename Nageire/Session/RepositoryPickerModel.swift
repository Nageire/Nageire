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
}
