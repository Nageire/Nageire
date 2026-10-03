import Foundation
import Testing
@testable import Nageire

@MainActor
struct GitHubAppConfigurationTests {
    @Test func theInstallationURLPointsAtTheAppsInstallPage() {
        let configuration = GitHubAppConfiguration(clientID: "client-id", slug: "nageire")

        #expect(configuration.installationURL.absoluteString == "https://github.com/apps/nageire/installations/new")
    }
}
