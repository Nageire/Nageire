---
description: Background knowledge (not a command) on framework-neutral Swift for Swift 6 and later, loaded automatically while writing or reviewing Swift. Covers compiler configuration (language mode, ExistentialAny, MemberImportVisibility, warnings and @diagnose, availability), optionals (force unwrap, try!, as!, guard, sentinels), modelling with value types and enums (struct versus class, final, associated values, exhaustive switch and @unknown default, wrapper types for identifiers), protocols and generics (some versus any, primary associated types), errors (throws, typed throws, try?, Result), the standard library and Foundation (collection queries, safe indexing, string comparison, FormatStyle, Codable, Duration), closures and memory (weak self, unowned), access control and modules (private, package, imports), API Design Guidelines naming, and swift-format and SwiftLint policy. Use when implementing or reviewing .swift files, Package.swift, a .swift-format or .swiftlint.yml file, or Swift compiler settings.
license: MIT
metadata:
    github-path: skills/swift-idioms
    github-ref: refs/tags/v1.9.0
    github-repo: https://github.com/yamat47/github-toolkit
    github-tree-sha: a9b51911938fb018ef71072481aa10b6c7b48c35
name: swift-idioms
---
# Swift idioms

Background knowledge consulted while implementing or reviewing Swift code. Each rule is written so a reviewer can check it against a diff. Rules marked as a preference are house style, not language rules. The rules target Swift 6 and later; version-specific syntax names the release that introduced it and was checked against Swift 6.4 (Xcode 27). Isolation, `Sendable`, tasks, and actors belong to `swift-concurrency`. SwiftUI, App Intents, and test migration belong to the skills Apple ships inside Xcode 27 (`swiftui-specialist`, `app-intents-specialist`, `modernize-tests`), exported with `xcrun agent skills export <dir>`; this skill covers the language, the compiler, the standard library, and naming.

## 1. Compiler configuration

- Use language mode 6 (`SWIFT_VERSION = 6.0`, or `swiftLanguageModes: [.v6]` in `Package.swift`). The concurrency settings that go with it are in `swift-concurrency`; read them before touching asynchronous code.
- Turn on `ExistentialAny`, which requires `any` in front of every existential type, and `MemberImportVisibility`, which requires a file to import the module of each member it uses instead of relying on another file's import. Xcode's app template enables the second (`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`).
- Keep the build free of warnings. A warning that is always there hides the new one. Preference: `SWIFT_TREAT_WARNINGS_AS_ERRORS` in CI, not in local debug builds.
- Silence one diagnostic at one declaration with `@diagnose` (Swift 6.4), for example `@diagnose(DeprecatedDeclaration, as: ignored)` on the function that must still call a deprecated API, with a comment saying when the call goes away. Do not turn the warning group off for the target.
- Guard newer APIs with `if #available` or `@available`, and set the deployment target deliberately; the compiler then lists every call that needs a check. `anyAppleOS` (Swift 6.4) covers all Apple platforms in one clause: `@available(anyAppleOS 27, *)`.
- Do not write an availability check for a version below the deployment target, and delete the ones that fall below it when the target is raised.

## 2. Optionals

- No `!` on an optional, no `try!`, and no `as!` in application code. Each one is a crash with no message at the place where an assumption turned out false. Unwrap with `guard let`, `if let`, or `??`, and cast with `as?`.
- When absence really is a programming error, say so: `guard let url = URL(string: endpoint) else { preconditionFailure("Invalid endpoint: \(endpoint)") }`. The crash then names what was expected. A force unwrap of a literal that cannot fail (`URL(string: "https://example.com")!`) is the one tolerated form, as a preference; `fatalError` in a required but unused `init(coder:)` is another.
- Do not declare implicitly unwrapped optionals (`var name: String!`). The remaining legitimate uses are `@IBOutlet` and values a framework sets before first use.
- Unwrap early and leave the function's main path unindented: `guard let user else { return }`. Use the shorthand `if let user` rather than `if let user = user`.
- A lookup that finds nothing returns `nil`, never a sentinel in the valid range (`0`, `""`, `-1`, `.distantPast`). Supply a default with `??` at the place that knows what the default means, not inside the lookup.
- Avoid `Bool?`. Three states are an `enum` with three named cases.

```swift
// BAD
let user = users.first { $0.id == id }!
let age = Int(text) ?? 0                      // 0 is a real age

// GOOD
guard let user = users.first(where: { $0.id == id }) else { throw LookupError.userNotFound(id) }
guard let age = Int(text) else { return .invalid(field: .age) }
```

## 3. Modelling with types

- Start with a `struct`. Use a `class` when instances have identity (two references must see the same mutations), when a framework requires one, or when the type owns a resource released in `deinit`. An `@Observable` model is a class for the first reason.
- Mark every class `final` unless it is designed for subclassing. Share behaviour through a protocol extension or composition before inheritance.
- Prefer `let`. A `var` property on a struct is fine when mutation is part of the type's meaning; a `var` that is assigned once in `init` is a `let`.
- Model state as an `enum` with associated values, not as a set of optionals and flags. `isLoading`, `items?`, and `error?` together admit combinations that never happen, and every reader has to rule them out again.
- Switch over the project's own enums without `default`, so adding a case produces a compile error at every place that must decide. For an enum from the SDK or another resilient module, end with `@unknown default`, which keeps the warning for cases added later.
- `if` and `switch` are expressions (Swift 5.9). Use them to initialise a `let` instead of declaring a `var` and assigning in each branch.
- Wrap an identifier or a unit in its own type when two values of the same primitive type must not be interchangeable: `struct UserID: Hashable, Sendable { let rawValue: String }`. A function taking `(UserID, TeamID)` cannot be called with the arguments swapped.
- A fixed set of wire values is an `enum` with `String` raw values; decode at the boundary and pass the enum inward. Decide what an unknown value means (a failing decode, or an `unknown` case) once per enum.
- Group constants and static helpers in a caseless `enum`, which cannot be instantiated: `enum Layout { static let spacing = 8.0 }`.
- Rely on synthesised `Equatable`, `Hashable`, and `Codable`. A hand-written `==` that skips a property is a bug waiting for the next property to be added.

```swift
// BAD
struct FeedState {
    var isLoading = false
    var posts: [Post]?
    var error: (any Error)?
}

// GOOD
enum FeedState {
    case idle
    case loading
    case loaded([Post])
    case failed(any Error)
}

func title(for state: FeedState) -> String {
    switch state {
    case .idle, .loading: "Loading"
    case .loaded(let posts): "\(posts.count) posts"
    case .failed: "Could not load"
    }
}
```

## 4. Protocols and generics

- Do not start with a protocol. Write the concrete type, and introduce a protocol when a second conformer exists or a test needs to replace the type at a boundary (network, clock, storage). A protocol with one conformer and no test double is indirection with no reader.
- For a parameter or return type, write `some P` first. It keeps the concrete type, so the compiler specialises the call and associated types stay usable. Write `any P` when values of different concrete types are stored together or the type is chosen at run time.
- Always spell the existential with `any`. `ExistentialAny` (section 1) makes the compiler require it.
- Use primary associated types to keep information: `some Collection<Post>`, `any Sequence<Int>`. Returning `[Post]` is still the right choice when callers index or store the result.
- Swift 6.4 accepts `some P?` and `any P?` for an optional opaque or existential type without parentheses.
- Add one conformance per extension (`extension Post: Codable { }`), with the members that conformance needs. The type's declaration then lists stored properties and nothing else.
- Constrain an extension rather than checking a type at run time: `extension Collection where Element: Identifiable` instead of `if let x = value as? any Identifiable`.

```swift
// BAD: boxes each argument and loses the element type
func total(of prices: any Collection) -> Decimal { ... }

// GOOD
func total(of prices: some Collection<Decimal>) -> Decimal { prices.reduce(0, +) }
```

## 5. Errors

- A function that can fail `throws`. Do not return an optional or a `Bool` to mean "something went wrong"; the caller cannot tell absence from failure and the cause is lost. `Result` is for storing an outcome or passing it through a callback, not for return types of new functions.
- Define errors as an `enum` conforming to `Error`, with associated values that carry what a handler or a log needs. Conform to `LocalizedError` only for errors whose message reaches the user.
- Typed throws (`throws(ParseError)`, Swift 6) fit code whose error set is closed and handled exhaustively in the same module, and generic code that forwards a closure's error type. Public and application-level functions stay with untyped `throws`: a typed signature turns every new failure into a source-breaking change.
- `try?` discards the reason. Use it only where "it failed" and "there is nothing" mean the same to the caller, and never to make a compile error about an unhandled throw go away. An empty `catch { }` is the same defect with more characters.
- Catch the errors the code can act on and let the rest propagate. A `catch` that wraps every error in a generic one erases what the caller needed. Never report `CancellationError` as a failure (see `swift-concurrency`).
- Release resources with `defer` next to the acquisition, so every exit path is covered.
- `precondition` and `fatalError` are for broken invariants, with a message. `assert` is removed in release builds, so it must not guard anything a release build depends on.

```swift
// BAD
func loadProfile() -> Profile? {
    guard let data = try? Data(contentsOf: profileURL) else { return nil }
    return try? JSONDecoder().decode(Profile.self, from: data)
}

// GOOD
func loadProfile() throws -> Profile {
    let data = try Data(contentsOf: profileURL)
    return try JSONDecoder().decode(Profile.self, from: data)
}
```

## 6. Standard library and Foundation

- Ask the collection the question directly: `isEmpty` instead of `count == 0`, `contains(where:)` instead of `filter { }.isEmpty == false`, `first(where:)` instead of `filter { }.first`, `count(where:)` (Swift 6) instead of `filter { }.count`, `allSatisfy` instead of a negated `contains`.
- Indexing an array out of bounds traps. Use `first`, `last`, `indices.contains(i)`, or a `for` loop over the elements when the index is not known to be valid, and `dictionary[key, default: 0]` instead of unwrapping and writing back.
- Do not use `enumerated()` to get indices: its offsets start at zero even for a slice. Use `indices`, or `zip(collection.indices, collection)`.
- A `String` is a collection of `Character`s (grapheme clusters), not bytes, and has no integer subscript. Avoid index arithmetic; use `prefix`, `split`, `firstRange(of:)`, or a regex literal (`/(\d+)-(\d+)/`).
- Match text the user typed with `localizedStandardContains`, which ignores case and diacritics the way the system search does, and sort text the user reads with `localizedStandardCompare`, which orders the way Finder does. `==`, `<`, and `contains` are for identifiers and keys.
- Format values with `FormatStyle`: `date.formatted(date: .abbreviated, time: .shortened)`, `price.formatted(.currency(code: "JPY"))`, `ratio.formatted(.percent)`, `names.formatted(.list(type: .and))`. Do not create `DateFormatter` or `NumberFormatter` for display, and never build display text with `String(format:)`. A fixed-format string for a machine (an API timestamp) uses `Date.ISO8601FormatStyle`, not a locale-dependent style.
- User-facing strings are localisable: a string literal passed to a SwiftUI view already is, and `String(localized:)` covers the rest. Do not concatenate translated fragments; interpolate into one string so translators can reorder it.
- Use `Duration` and `ContinuousClock` for elapsed time and timeouts, and `Date` only for points on the calendar. Take the clock or `now` as a parameter in logic that depends on time.
- Sort with `sorted(using: KeyPathComparator(\.name))` when ordering by properties; pass several comparators for tie-breaks.
- In `Codable` types, map names with `CodingKeys` or a decoder strategy, set `dateDecodingStrategy` explicitly, and keep the wire type separate from the domain type when their shapes differ. A domain type full of optionals because the server may omit fields has let the wire format leak inward.

## 7. Closures and memory

- A retain cycle needs a closure that is stored by an object it captures strongly. Write `[weak self]` for closures that are stored or long-lived (a callback property, an observer, a never-ending task), then `guard let self else { return }`.
- Do not add `[weak self]` by reflex. A non-escaping closure (`map`, `forEach`, `withLock`) cannot create a cycle, and a short task that finishes keeps `self` alive only until it does, which is usually what the code wants.
- Avoid `unowned`. It is a crash when the lifetime assumption breaks, in exchange for skipping one `guard`.
- Delegates and parent references are `weak var`. Swift 6.4 adds `weak let` for a weak reference that is never reassigned, which also lets a `Sendable` class hold one.
- Do not capture a value the closure will read later and expect the current one: a capture list (`[count]`) copies at creation, a plain capture reads at call time. Choose deliberately in callbacks that outlive the surrounding scope.

## 8. Access control and modules

- Default to `private`. Widen to the implicit `internal` when another file needs the member, and to `public` only for a deliberate API of a module. `private(set)` exposes a value while keeping mutation inside the type.
- `package` (Swift 5.9) is visible to every target of one Swift package and invisible outside it. Use it instead of `public` for helpers shared between a package's own modules.
- `fileprivate` is for the rare case of two types in one file sharing a member. Reaching for it often means the file holds two things.
- A file imports the modules it uses, each once, with no unused imports. When two modules export the same name, disambiguate with a module selector (`ModuleA::Item`, Swift 6.3) instead of renaming a local type.
- Preference: one primary type per file, named after it; extensions that add conformances may live in the same file, and `Type+Feature.swift` holds an extension that would otherwise double the file.
- Delete dead code instead of commenting it out; version control has it.

## 9. Naming

These follow the Swift API Design Guidelines on swift.org.

- Judge a name at the call site, not at the declaration. `friends.remove(at: index)` reads as a sentence; `friends.remove(index)` does not say whether it removes a value or a position.
- Omit words that repeat the type (`allViews.remove(cancelButton)`, not `removeElement`), and add a role word when the type alone says too little (`addObserver(_:forKeyPath:)`).
- A method with side effects is an imperative verb (`sort()`, `append(_:)`); its non-mutating counterpart is a participle or a noun (`sorted()`, `appending(_:)`, `union(_:)` beside `formUnion(_:)`).
- A Boolean reads as an assertion about the receiver: `isEmpty`, `hasUnreadMessages`, `canEdit`. Avoid negated names (`isNotHidden`), which turn conditions into double negatives.
- No `get` prefix; a factory method begins with `make`; a conversion initialiser omits the first label (`Int(text)`).
- Protocols that describe what something is are nouns (`Collection`); those that describe a capability end in `able`, `ible`, or `ing` (`Equatable`, `ProgressReporting`).
- Types and protocols are `UpperCamelCase`; everything else, including constants and enum cases, is `lowerCamelCase`. Constants are not `SCREAMING_SNAKE_CASE` and carry no `k` prefix. Acronyms are cased as a unit: `userID`, `urlString`, `HTTPClient`.
- Label closure parameters and tuple members that appear in an API. Default arguments go at the end of the parameter list.

## 10. Format and lint

- Formatting belongs to a tool. `swift-format` ships with the toolchain (`swift format`); run it in CI in lint mode with a committed `.swift-format`. Formatting never appears in a review comment.
- Preference: add SwiftLint only for rules the formatter and compiler do not cover, keeping its default `force_try` and `force_cast` and opting in to `force_unwrapping` and `implicitly_unwrapped_optional`, which together check section 2 on every build. Do not run two tools that both rewrite whitespace.
- Every disabled rule, in the config or inline, has a comment saying why. An inline `// swiftlint:disable:next` names the rule and never disables all rules.

## Checklist

- [ ] Are language mode 6, `ExistentialAny`, and `MemberImportVisibility` on, and is the build free of warnings without a target-wide suppression?
- [ ] Does any `!`, `try!`, `as!`, or implicitly unwrapped optional appear where a `guard`, a thrown error, or `as?` would do?
- [ ] Does any function return a sentinel (`0`, `""`, `-1`) or a `Bool?` for absence or a third state?
- [ ] Is state an `enum` with associated values, and does every `switch` over a project enum avoid `default`?
- [ ] Is a class used where a struct would do, and is every class `final` unless designed for subclassing?
- [ ] Are identifiers of different kinds distinct types where swapping them would compile?
- [ ] Does a protocol exist with a single conformer and no test double, or an `any` where `some` would do?
- [ ] Does any function signal failure with `nil` or `false`, discard a cause with `try?` or an empty `catch`, or use typed throws in a public API?
- [ ] Is a collection queried with `filter` plus `count`, `first`, or `isEmpty`, indexed without a bounds guarantee, or enumerated for indices?
- [ ] Is user-visible text compared with `==`, formatted with `String(format:)` or a formatter object, or concatenated from translated fragments?
- [ ] Is every stored or long-lived closure free of a strong `self` cycle, and is `unowned` absent?
- [ ] Is every declaration as private as its uses allow, with `package` instead of `public` for package-internal sharing?
- [ ] Do names read correctly at the call site, with verb and participle pairs for mutating and non-mutating forms and `lowerCamelCase` constants?
- [ ] Does every disabled lint rule carry a reason, and is exactly one tool responsible for formatting?
