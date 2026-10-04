import Foundation
import Testing
@testable import Nageire

@MainActor
struct RepositoryPickerModelTests {
    private let api = FakeAPI()

    @Test func loadingListsTheInstalledRepositories() async {
        let repositories = [Repository(owner: "octocat", name: "notes")]
        api.repositories = .success(repositories)
        let model = RepositoryPickerModel(api: api)

        await model.load()

        #expect(model.state == .loaded(repositories))
    }

    @Test func aFailedLoadCanBeRetried() async {
        api.repositories = .failure(URLError(.timedOut))
        let model = RepositoryPickerModel(api: api)
        await model.load()
        #expect(model.state == .failed)

        api.repositories = .success([])
        await model.load()

        #expect(model.state == .loaded([]))
    }

    @Test func refreshingReplacesTheListThatIsShown() async {
        api.repositories = .success([])
        let model = RepositoryPickerModel(api: api)
        await model.load()
        let repositories = [Repository(owner: "octocat", name: "notes")]
        api.repositories = .success(repositories)

        await model.refresh()

        #expect(model.state == .loaded(repositories))
    }

    @Test func aFailedRefreshKeepsTheListThatIsShown() async {
        let repositories = [Repository(owner: "octocat", name: "notes")]
        api.repositories = .success(repositories)
        let model = RepositoryPickerModel(api: api)
        await model.load()
        api.repositories = .failure(URLError(.timedOut))

        await model.refresh()

        #expect(model.state == .loaded(repositories))
    }

    @Test func refreshingBeforeAListIsShownDoesNothing() async {
        api.repositories = .success([])
        let model = RepositoryPickerModel(api: api)

        await model.refresh()

        #expect(model.state == .loading)
    }
}
