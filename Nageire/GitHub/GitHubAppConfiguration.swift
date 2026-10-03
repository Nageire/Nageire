import Foundation

struct GitHubAppConfiguration: Equatable {
    let clientID: String
    let slug: String

    var installationURL: URL {
        URL(string: "https://github.com/apps/\(slug)/installations/new")!
    }
}

extension GitHubAppConfiguration {
    init(bundle: Bundle) {
        guard
            let clientID = bundle.object(forInfoDictionaryKey: "GitHubAppClientID") as? String, !clientID.isEmpty,
            let slug = bundle.object(forInfoDictionaryKey: "GitHubAppSlug") as? String, !slug.isEmpty
        else {
            fatalError("GitHubAppClientID and GitHubAppSlug must be set in Info.plist through Config/GitHubApp.xcconfig.")
        }
        self.init(clientID: clientID, slug: slug)
    }
}
