---
description: Background knowledge (not a command) on Swift concurrency for Swift 6.2 and later, loaded automatically while writing or reviewing Swift that uses async, await, actors, or tasks. Covers reading the build settings before judging code (language mode, default actor isolation, approachable concurrency, per-target SwiftPM settings), where code runs (MainActor by default, nonisolated, @concurrent), fixing Sendable and data-race errors in a fixed order (value types, sending, isolated conformances, Mutex, global state) and the silencing moves that need a written reason (@unchecked Sendable, nonisolated(unsafe), @preconcurrency, Task.detached, assumeIsolated), structured concurrency, task lifetime and cancellation, actor reentrancy, blocking calls, and bridging callbacks with continuations and AsyncStream. Use when implementing or reviewing .swift files that contain async code, a concurrency compiler error, Package.swift swiftSettings, or an Xcode project's concurrency build settings.
license: MIT
metadata:
    github-path: skills/swift-concurrency
    github-ref: refs/tags/v1.9.0
    github-repo: https://github.com/yamat47/github-toolkit
    github-tree-sha: a1fa613752d39713fcb68b8b0eac16b570c77bf9
name: swift-concurrency
---
# Swift concurrency

Background knowledge consulted while implementing or reviewing concurrent Swift. Each rule is written so a reviewer can check it against a diff. Rules marked as a preference are house style, not language rules. The rules target Swift 6.2 and later; the compiler behaviour described here was checked against Swift 6.4 (Xcode 27). Language rules outside concurrency belong to `swift-idioms`. View lifetime (`.task`, `@Observable` data flow) belongs to Apple's `swiftui-specialist`, and test migration to Apple's `modernize-tests`; both ship inside Xcode 27 and are exported with `xcrun agent skills export <dir>`.

## 1. Read the build settings first

The same source line is correct under one configuration and a data race error under another. Read the settings of the target that owns the file before writing or reviewing concurrent code, and never answer a concurrency question from the source alone.

| Xcode build setting | SwiftPM `swiftSettings` | Values |
|---|---|---|
| `SWIFT_VERSION` | `swiftLanguageModes: [.v6]` on the package, `.swiftLanguageMode(.v6)` on a target | `5` reports data races as warnings at most; `6` reports them as errors |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `.defaultIsolation(MainActor.self)` | `nonisolated` (the compiler default) or `MainActor` |
| `SWIFT_APPROACHABLE_CONCURRENCY` | one `.enableUpcomingFeature(...)` per feature | `YES` turns on `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `InferSendableFromCaptures`, `GlobalActorIsolatedTypesUsability`, `DisableOutwardActorInference` |
| `SWIFT_STRICT_CONCURRENCY` | `.enableUpcomingFeature("StrictConcurrency")` | Read only in language mode 5: `minimal`, `targeted`, `complete` |

- Read them with `xcodebuild -showBuildSettings -scheme <scheme> | grep -E 'SWIFT_(VERSION|DEFAULT_ACTOR_ISOLATION|APPROACHABLE_CONCURRENCY|STRICT_CONCURRENCY)'`, or in `Package.swift`.
- The app template in Xcode 26 and 27 sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. A project created earlier, and every Swift package, has neither unless someone added them.
- Settings are per target. A local package does not inherit the app target's isolation default, so the same unannotated class is `@MainActor` in the app and nonisolated in the package. When moving code between targets, re-read the destination's settings.
- Do not change these settings to make an error disappear. Lowering the language mode to 5, or `SWIFT_STRICT_CONCURRENCY` to `minimal`, turns the report off and leaves the race. Raising them is a migration with its own pull request.
- Preference: an app target uses language mode 6, `MainActor` default isolation, and approachable concurrency. A package of pure logic keeps the `nonisolated` default and turns on `NonisolatedNonsendingByDefault`.

What an unannotated declaration means under each configuration:

| Declaration | `nonisolated` default | `MainActor` default |
|---|---|---|
| `final class Store { var items: [Item] }` | nonisolated, not `Sendable` | `@MainActor`, therefore `Sendable` |
| `var cache: [String: Data] = [:]` at file scope | error in mode 6: global shared mutable state | `@MainActor` global, allowed |
| `func load() async` at file scope or in a nonisolated type | runs on the global concurrent executor, or on the caller's actor with `NonisolatedNonsendingByDefault` | `@MainActor` |

## 2. Where code runs

- `async` does not mean background. An `async` function isolated to the main actor runs on the main thread between its suspension points, and synchronous work inside it (decoding a large payload, resizing an image, hashing) blocks the interface exactly as it would in a synchronous function.
- Start on the main actor and move work off it when there is a measured reason. Most application code reads and writes interface state and gains nothing from running elsewhere.
- With `NonisolatedNonsendingByDefault`, a `nonisolated async` function runs on the actor of its caller. Without the feature it switches to the global concurrent executor on every call, and passing it a non-`Sendable` value from an actor is the error "sending 'self.x' risks causing data races". This one feature decides whether a plain helper is safe to call with actor state.
- `@concurrent` marks an `async` function that always runs on the global concurrent executor. It is the way to say "this work leaves the caller's actor". Use it on the function that does the expensive work, not on its callers. Its parameters and result cross an isolation boundary, so they are `Sendable` or `sending`.
- `nonisolated` on a type or member opts out of a `MainActor` default. Use it for value types and pure functions that must also be usable off the main actor: models decoded in `@concurrent` code, formatters, parsers.
- Do not hop with `await MainActor.run { }` or `DispatchQueue.main.async { }` to update state. Mark the function or type that owns the state `@MainActor` and call it; the compiler then inserts the hop and checks every caller.
- `Task { }` created in an isolated context inherits that isolation. A `Task { }` in a `@MainActor` method runs its body on the main actor, so wrapping synchronous work in it does not move the work anywhere.

```swift
// Target settings: MainActor default isolation, NonisolatedNonsendingByDefault.
final class ThumbnailStore {                     // implicitly @MainActor
    private(set) var thumbnails: [URL: CGImage] = [:]

    func load(_ url: URL) async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        thumbnails[url] = try await Self.decode(data)   // back on the main actor after the await
    }

    @concurrent
    nonisolated static func decode(_ data: Data) async throws -> CGImage {
        try makeThumbnail(from: data)            // a nonisolated helper: CPU work, off the main actor
    }
}
```

## 3. Fixing a data-race error

A concurrency error says that a value may be reached from two isolation domains. Work through the list in order and stop at the first entry that applies. The entries near the top remove the sharing; the ones near the bottom keep it and make it safe.

1. Ask whether the value has to cross at all. Often the caller and the callee can share one actor: mark the callee `@MainActor`, or remove a `Task.detached` or `@concurrent` that was not needed.
2. Make the type a value type. A `struct` or `enum` whose stored properties are all `Sendable` is `Sendable` implicitly when it is not `public`; a `public` one states `: Sendable`.
3. For a class with only immutable `Sendable` state, write `final class Token: Sendable` with `let` properties.
4. Transfer instead of share. A value created locally and not used after it is handed over can cross without being `Sendable`; state that in an API with a `sending` parameter or result.
5. Give shared mutable state an owner. Interface state belongs to a `@MainActor` type. State read and written from several domains belongs to an `actor`, or to a `Mutex` (the `Synchronization` module, iOS 18 and macOS 15) when access has to be synchronous.
6. For "conformance crosses into main actor-isolated code", isolate the conformance: `extension Model: @MainActor Named {}`. `InferIsolatedConformances` infers this for a type that is already `@MainActor`.
7. For "nonisolated global shared mutable state" on a global or `static var`, make it a `let`, or isolate it to an actor. A singleton is `static let shared`, and its type is an actor, `@MainActor`, or `Sendable`.
8. For a declaration imported from a module that has not adopted concurrency checking, `@preconcurrency import ThatModule` is the supported answer. It is not for the project's own modules.

The following make the error disappear without removing the race. Each needs a comment at the use site naming the mechanism that makes it safe (the lock that guards the state, the queue the framework promises), and a reviewer treats one without that comment as a defect.

- `@unchecked Sendable` on a type with mutable state.
- `nonisolated(unsafe)` on a variable.
- `MainActor.assumeIsolated { }` or `unsafe` casts of closure types. `assumeIsolated` traps at run time when the assumption is false; use it only where the framework documents the callback's thread.
- `Task.detached { }` used to drop the current isolation, or `@Sendable` added to a closure only to satisfy the checker.
- `@preconcurrency` on the project's own protocol or import.

```swift
import Synchronization

// BAD: a claim with nothing behind it
final class HitCounter: @unchecked Sendable {
    var count = 0
}

// GOOD: the compiler can verify this one
final class HitCounter: Sendable {
    private let count = Mutex(0)
    func record() { count.withLock { $0 += 1 } }
}
```

## 4. Tasks, lifetime, and cancellation

- Prefer structured concurrency. `async let` runs a fixed number of child operations in parallel; `withTaskGroup` and `withThrowingTaskGroup` run a dynamic number; `withDiscardingTaskGroup` runs children whose results are not collected. Children are cancelled with their parent and cannot outlive the scope, and their errors reach the caller.
- An unstructured `Task { }` belongs at the border between synchronous and asynchronous code: a button action, a delegate callback, an `init`. Inside an `async` function, `Task { }` is almost always a mistake; call the function with `await`, or use a group.
- Whoever creates an unstructured task owns it. Store the handle and cancel it when the owner goes away or the work is superseded (the next search keystroke, the next refresh). A task that loops forever, including every `for await` over a sequence that never finishes, keeps what it captures alive until it is cancelled; capture `self` weakly in such a loop and cancel in `isolated deinit`.
- A `Task { }` body that throws discards the error unless someone awaits `task.value`. Catch inside the task and put the failure where the user or a log can see it.
- Cancellation is cooperative. A long loop calls `try Task.checkCancellation()` on each iteration; a function that wraps a cancellable non-Swift API uses `withTaskCancellationHandler`. Treat `CancellationError` as the expected end of superseded work: do not present it to the user and do not log it as a failure.
- Cleanup that must finish after cancellation (closing a transaction, releasing a remote lock) runs inside `withTaskCancellationShield` (Swift 6.4, the 27 OS releases). `defer` may contain `await` from Swift 6.4.
- Use `Task.sleep(for: .seconds(1))`, never `Thread.sleep` or the nanosecond overload. A sleep is not a synchronisation tool: waiting "long enough" for another task to finish is a race with a delay.
- Do not use `Task.detached` to run work in the background. It drops priority and task-local values along with the isolation; a `@concurrent` function keeps both and says the same thing in the signature.
- Name long-lived tasks (`Task(name: "feed-refresh") { }`, Swift 6.2). The name appears in the debugger and in Instruments.

```swift
// BAD: two sequential requests, and an unowned task per call
func refresh() async {
    Task { self.profile = try await api.profile() }     // error is discarded
    let posts = try? await api.posts()
    let badges = try? await api.badges()
}

// GOOD
func refresh() async throws {
    async let profile = api.profile()
    async let posts = api.posts()
    async let badges = api.badges()
    (self.profile, self.posts, self.badges) = try await (profile, posts, badges)
}
```

```swift
final class SearchModel {                        // @MainActor by default
    private var search: Task<Void, Never>?

    func queryChanged(_ query: String) {
        search?.cancel()
        search = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                results = try await api.search(query)
            } catch is CancellationError {
                // superseded by the next keystroke
            } catch {
                failure = error
            }
        }
    }

    isolated deinit { search?.cancel() }
}
```

## 5. Actors

- An actor is reentrant. At every `await` inside an actor method, other calls to the same actor run, so state read before the `await` may be stale after it. Do the check and the mutation with no suspension between them, or re-check after the `await`.
- An actor is for state that several isolation domains mutate. State that only the interface touches belongs to a `@MainActor` class, which is simpler and synchronous for its callers. Do not turn a class into an actor because that silences a `Sendable` error; every caller becomes `async` and every read a suspension point.
- Design actor methods as whole operations. A caller that awaits `balance`, decides, and then awaits `withdraw` has put the race back outside the actor.
- Never block a thread of the cooperative pool: no `DispatchSemaphore.wait()`, no `DispatchGroup.wait()`, no `Thread.sleep`, no synchronous file or network call in a hot path, and no lock held across an `await`. `Mutex.withLock` takes a synchronous closure, so it cannot be held across one.
- A stored `let` of `Sendable` type and a function that touches no actor state can be `nonisolated`, which lets callers use them without `await`.

```swift
actor Wallet {
    private var balance = 100

    // BAD: balance can change while audit() is suspended
    func withdraw(_ amount: Int) async -> Bool {
        guard balance >= amount else { return false }
        await audit(amount)
        balance -= amount
        return true
    }

    // GOOD: check and mutation are one synchronous step
    func withdrawSafely(_ amount: Int) async -> Bool {
        guard balance >= amount else { return false }
        balance -= amount
        await audit(amount)
        return true
    }
}
```

## 6. Bridging older APIs

- Wrap a completion-handler API with `withCheckedThrowingContinuation` (or the non-throwing form). Resume exactly once on every path: zero resumes hang the caller forever, two crash. Check each early return and each error branch of the callback. Use the `Unsafe` variants only with a measurement that shows the checked one matters.
- Wrap a delegate or a repeating callback with `AsyncStream.makeStream(of:bufferingPolicy:)`. Set `onTermination` to stop the underlying source, call `finish()` when the source ends, and choose the buffering policy deliberately: the default is unbounded, and `.bufferingNewest(1)` fits "only the latest value matters".
- Observe an `@Observable` model from asynchronous code with `Observations { model.value }` (Swift 6.2, the 26 OS releases), which yields one value per transaction.
- Many SDK APIs already have an `async` form (`URLSession.data(from:)`, `NotificationCenter.notifications(named:)`). Use it before writing a wrapper.
- Preference: new code does not add Combine or a `DispatchQueue` for asynchronous work. Existing pipelines stay until the surrounding code is rewritten; bridge at the border with `publisher.values`.

```swift
func currentLocation() async throws -> Location {
    try await withCheckedThrowingContinuation { continuation in
        locator.requestLocation { location, error in
            if let location {
                continuation.resume(returning: location)
            } else {
                continuation.resume(throwing: error ?? LocationError.unavailable)
            }
        }
    }
}
```

## Checklist

- [ ] Were the target's language mode, default isolation, and upcoming features read before the code was written or judged, and were they left unchanged by a pull request that is not a migration?
- [ ] Does synchronous CPU work run on the main actor inside an `async` function, where a `@concurrent` function should hold it?
- [ ] Is state updated through `MainActor.run` or `DispatchQueue.main.async` where a `@MainActor` declaration would do?
- [ ] Does any `@unchecked Sendable`, `nonisolated(unsafe)`, `assumeIsolated`, `Task.detached`, or own-code `@preconcurrency` appear without a comment naming what makes it safe?
- [ ] Was a class turned into an actor, or a closure marked `@Sendable`, only to silence an error?
- [ ] Is a global or `static var` mutable and unisolated?
- [ ] Could an unstructured `Task { }` be `await`, `async let`, or a task group?
- [ ] Is every stored task cancelled when its owner goes away or the work is superseded, and does a never-ending loop capture `self` weakly?
- [ ] Does a `Task { }` body throw with nobody reading the error, or is `CancellationError` shown or logged as a failure?
- [ ] Does a long loop check for cancellation, and is anything waiting with a sleep for other work to finish?
- [ ] Does an actor method read state, `await`, and then act on what it read?
- [ ] Does anything block a pool thread (semaphore, group wait, `Thread.sleep`, a lock across `await`)?
- [ ] Does every continuation resume exactly once on every path, and does every `AsyncStream` stop its source in `onTermination`?
