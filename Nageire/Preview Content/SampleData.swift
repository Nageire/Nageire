#if DEBUG
import Foundation

/// The sample of the design prototype, so that a preview or a run of the app can be set beside the renders in `docs/design`.
enum SampleData {
    static let accountLogin = "hanako"
    static let repository = Repository(owner: "hanako", name: "notes")
    static let deviceCode = DeviceCode(
        deviceCode: "sample",
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://github.com/login/device")!,
        interval: 5
    )

    /// The text waiting in the toss sheet.
    static let draft = """
        # 今週の買い出し

        - [x] 花ばさみの研ぎ
        - [ ] 剣山（小）
        - [ ] 水切り用の新聞

        ![ito.jpg](ito.jpg)
        """

    /// The notes of the stream, newest first. Their times are counted back from `now`, so that
    /// the first two days are today and yesterday whenever the sample is shown. The first note is unsent.
    static func notes(asOf now: Date = .now, calendar: Calendar = .current) -> [NoteEntry] {
        func time(daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func entry(_ text: (_ folder: String) -> String, at createdAt: Date, editedAt: Date? = nil, suffix: String, isPending: Bool = false) -> NoteEntry {
            // A note's files are in the folder named like the note, beside it.
            let folder = "\(createdAt.formatted(Note.stampStyle))-\(suffix)"
            let note = Note(body: text(folder), createdAt: createdAt, timeZone: calendar.timeZone, suffix: suffix)
            let entry = NoteEntry(path: note.repositoryPath, contents: note.contents, isPending: isPending)
            guard let editedAt else { return entry }
            let edited = entry.contents(withText: entry.editableText, updatedAt: editedAt, timeZone: calendar.timeZone)
            return NoteEntry(path: entry.path, contents: edited, isPending: isPending)
        }
        return [
            entry({ _ in
                """
                来週の火曜は稽古と重なる。木曜の午後に電話する。

                - [ ] 受付に電話
                - [ ] カレンダーを直す
                """
            }, at: time(daysAgo: 0, 14, 32), suffix: "0a01", isPending: true),
            entry({ _ in "雨の前のあの灰色に近い。冬の服の色にしたい。" }, at: time(daysAgo: 0, 7, 40), suffix: "0a02"),
            entry({ _ in
                """
                # 読みかけの本のメモ

                三章まで。器は空いているところに意味がある、という一文。
                """
            }, at: time(daysAgo: 1, 22, 5), suffix: "0a03"),
            entry({ _ in
                """
                # 夕飯の買い物

                - [x] 大根
                - [x] 油揚げ
                - [ ] 柚子
                """
            }, at: time(daysAgo: 1, 17, 20), suffix: "0a04"),
            entry({ folder in
                """
                # 稽古の記録 — 投げ入れ

                今日は**枝を二本**だけ。器の口を見てから枝の向きを決めると、先生に言われた。

                - 枝は水際で決まる
                - 花は低く、ひとつ
                - *余白を恐れない*

                - [x] 剣山を洗う
                - [ ] 来週までに枝を探す

                ![kuwa.jpg](\(folder)/kuwa.jpg)

                次の稽古は[教室の予定](https://example.com/schedule)を見てから決める。
                """
            }, at: time(daysAgo: 1, 9, 12), editedAt: time(daysAgo: 1, 18, 40), suffix: "0a05"),
            entry({ folder in
                """
                # 引っ越しの見積もり

                二社に頼んだ。箱の数を先に数えておくと早い。

                ![IMG_0412.jpeg](\(folder)/IMG_0412.jpeg)

                ![IMG_0413.jpeg](\(folder)/IMG_0413.jpeg)
                """
            }, at: time(daysAgo: 4, 20, 15), suffix: "0a06"),
            entry({ _ in
                """
                # 庭の金木犀が咲いた

                去年より五日早い。窓を開けて書いている。
                """
            }, at: time(daysAgo: 4, 8, 30), suffix: "0a07"),
        ]
    }
}

/// A state of the app the design renders, which the sample can start in.
enum SampleScene: String {
    /// The sample account with its notes.
    case stream
    /// The sample account before its first note.
    case empty
    /// The sample account with GitHub refusing what it sends, as after the app was removed from the repository.
    case refused
    /// The app before sign-in, holding nothing.
    case signedOut
}

extension AppModel {
    /// A model that keeps to itself: its notes are in memory, its defaults are a suite of its own,
    /// it reads no Keychain, and it reaches no network. GitHub answers as it would while the
    /// device is offline, which keeps the unsent note unsent and leaves an edit or a deletion waiting.
    static func sample(_ scene: SampleScene = .stream) -> AppModel {
        let notes = scene == .empty || scene == .signedOut ? [] : SampleData.notes()
        let signedIn = scene != .signedOut
        let store = InMemoryNoteStore(pending: notes.filter(\.isPending).map {
            Note(fileName: String($0.path[fileNameStart(of: $0.path)...]), contents: $0.contents)
        })
        let api = SampleAPI(
            files: notes.filter { !$0.isPending }.map { StoredFile(path: $0.path, contents: Data($0.contents.utf8)) },
            refusesWrites: scene == .refused
        )
        let oauth = SampleOAuth()
        // The standard defaults hold the account, the repository, and the draft of the person's own sign-in.
        let suite = "com.yamat47.Nageire.sample"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("The suite name is not one the system reserves.")
        }
        // What an earlier run left there would make this one start differently.
        defaults.removePersistentDomain(forName: suite)
        let model = AppModel(
            configuration: GitHubAppConfiguration(clientID: "sample", slug: "nageire"),
            oauth: oauth,
            api: api,
            outbox: NoteOutbox(store: store, api: api),
            library: NoteLibrary(store: store, api: api),
            session: GitHubSession(store: SampleTokenStore(isSignedIn: signedIn), oauth: oauth),
            defaults: defaults
        )
        if signedIn {
            // Choosing the repository fetches its notes, which is how the sent ones reach the list.
            model.select(SampleData.repository)
        }
        return model
    }
}

private struct SampleAPI: GitHubAPI {
    /// What the repository holds.
    private let files: [RemoteFile]
    private let blobs: [String: Data]
    /// Answers a write with 404, as GitHub does for a repository the app can no longer reach. Otherwise the device is offline.
    private let refusesWrites: Bool

    init(files: [StoredFile], refusesWrites: Bool) {
        self.files = files.map { RemoteFile(path: $0.path, sha: RemoteFile.sha(of: $0.contents)) }
        blobs = Dictionary(zip(self.files.map(\.sha), files.map(\.contents))) { first, _ in first }
        self.refusesWrites = refusesWrites
    }

    private var writeFailure: any Error {
        refusesWrites ? GitHubAPIError.unexpectedStatus(404) : URLError(.notConnectedToInternet)
    }

    func currentUserLogin() async throws -> String { SampleData.accountLogin }
    func installedRepositories() async throws -> [Repository] { [SampleData.repository] }
    func noteFiles(in repository: Repository) async throws -> [RemoteFile] { files }

    func blob(_ sha: String, in repository: Repository) async throws -> Data {
        guard let contents = blobs[sha] else {
            throw GitHubAPIError.invalidResponse
        }
        return contents
    }

    func createFile(at path: String, in repository: Repository, content: Data, message: String) async throws {
        throw writeFailure
    }

    func writeFile(at path: String, in repository: Repository, content: Data, message: String) async throws {
        throw writeFailure
    }

    func deleteFile(at path: String, in repository: Repository, message: String) async throws {
        throw writeFailure
    }
}

private struct SampleOAuth: GitHubOAuth {
    func requestDeviceCode() async throws -> DeviceCode { SampleData.deviceCode }
    func pollToken(deviceCode: String) async throws -> DeviceTokenPoll { .pending }
    func refresh(refreshToken: String) async throws -> TokenGrant { throw URLError(.notConnectedToInternet) }
}

/// Tokens that never expire and are kept nowhere.
private struct SampleTokenStore: TokenStore {
    let isSignedIn: Bool

    func load() throws -> TokenSet? {
        isSignedIn ? TokenSet(accessToken: "sample", accessTokenExpiresAt: .distantFuture, refreshToken: "sample") : nil
    }

    func save(_ tokens: TokenSet) throws {}
    func delete() throws {}
}
#endif
