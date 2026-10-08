# Nageire

A notes app for iOS and macOS in SwiftUI. A note is a Markdown file in the user's own GitHub repository; there is no server. The idea and every settled decision are in `docs/concept.md`; read it first in any session.

## Documents

- `docs/concept.md`: the principles and the decisions in force. A decision goes here once it is made.
- `docs/ux-redesign.md`, `docs/on-device-model.md`: the decisions of the redesign, with their reasons.
- `docs/design-reference.md` and `docs/design/`: the design to match, its tokens, and its renders.
- `docs/ui-guide.md`: how the UI is built in SwiftUI: the shape of the code, the state, each component, the previews, and the editor.
- `docs/workplan.md`: the order of work for the redesign, phase by phase, and how a phase is verified and merged.

Documents under `docs/`, commit messages, and pull requests are written in English. The app's strings are in English and Japanese in `Nageire/Localizable.xcstrings`.

## Building and testing

Xcode 27 on macOS, which needs macOS 26.6 or later on Apple silicon. The scheme is `Nageire`; the tests run from it on macOS and on an iOS simulator:

```
xcodebuild test -scheme Nageire -destination 'platform=macOS'
xcodebuild test -scheme Nageire -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI runs both on every pull request. A Linux session cannot build the app and is used for documents only.

The tests run inside the app. Started for them, or by Xcode for a preview, the app builds a model that keeps to itself (`AppModel.sample(.signedOut)`): signed out, in memory, with no Keychain and no network. Otherwise it would start as the app of whoever runs the tests, read their tokens, and send and fetch their notes.

## Conventions

- Load the `writing-conventions` skill before writing a comment, a test name, a commit message, a pull request, or a document. Its rules on what goes where and on prose apply here.
- The `swift-idioms` and `swift-concurrency` skills under `.claude/skills` apply while writing Swift, `test-audit` while writing tests, and `github-actions-workflows` while touching `.github`. The two Swift skills were checked against Swift 6.4, which Xcode 27 carries. The app target is in language mode 6 with the main actor as the default isolation and approachable concurrency, the configuration they prefer for an app. The test target is in mode 6 with approachable concurrency and no default isolation, so a suite or a test double is marked `@MainActor`.
- Structural and behavioral changes go in separate commits. No trailer or footer in a commit or pull request says a model took part.
- A pull request body has three sections, Background, Not done, and Where to look, and nothing else. The `create-pr` skill produces it.
- A decision recorded in `docs/concept.md` or `docs/ux-redesign.md` is built, not reopened. A new decision is proposed in the document first and built after.

## State of the redesign

Steps 1 to 6 of the roadmap in `docs/concept.md` are built and merged. The design of the redesign is settled and recorded. The project builds with Xcode 27 in Swift language mode 6 against the iOS 27 and macOS 27 deployment targets, and CI runs on the `xcode-27` runner image, so the step before phase 1 in `docs/workplan.md` is done. Phase 1, the look, is built and merged, and the decisions it settled are in `docs/concept.md` under The screens. Its verification over the whole phase, item 12 of its checklist, was not run by the session that closed it, which had no Xcode; run it in an environment with Xcode before phase 2 changes the screens, and fix what it finds as a pull request of its own. Phase 2, the editor, follows as the pull requests named in `docs/workplan.md`; the merges on `main` show how far it has come. Do not begin a pull request before the one before it is merged.
