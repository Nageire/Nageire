# Code comments

Expands the "Code comments: Why not" rule in [what-goes-where.md](what-goes-where.md). Prose style is in [writing-style.md](writing-style.md). The rules apply in any language; the ones marked **(Ruby)** or **(Japanese)** apply only there. Rules marked as a preference are house style, not something the language or framework requires.

## What a comment must add

A comment states what cannot be read from the code. Before writing one, be able to say what the reader learns from it.

- Write the reason behind a non-obvious condition or restriction: why a state is exempt, why a guard covers only one action, why a filter has an unusual clause. The condition itself does not carry the business reason.
- Write the reason for a piece of code that exists for a purpose the code does not show, such as an optimization or a short arithmetic block. A backoff formula gets a line saying what it computes and why.
- Record a non-obvious design decision next to the code it shaped, for example why a list sorts by one key before another. Good judgments are lost unless they survive where the next reader looks.
- When code special-cases a specific value, state the business reason. Without it a legitimate exception reads as favouritism or a hack.
- When code disables or overrides a default, name the default and the reason for changing it. "Build the generation config" restates the code; "thinking mode is off because ..." is the missing piece.
- When code works around a framework or engine quirk, explain the mechanism: what overrides what, where the extra parameter comes from. "An error occurs otherwise" is not an explanation.
- When a lookup returns a default instead of `nil` for unknown input, say so. Readers expect `nil` and are surprised by a silent fallback.
- Write a comment for a stub or placeholder saying what it is waiting for. "Always false for now" leaves the reader guessing at the intent.
- Never leave commented-out code without a line saying why it is there and what it waits for. A bare disabled line can be a todo, a switched-off feature, or a mistake.
- When several attributes constrain each other, describe the relationships in a class comment or link the design document. A first-time reader cannot infer them from four enums.
- A doc comment on a predicate removes the ambiguity in its name, with an example of when it applies if two readings are possible.
- Preference: when a directory or naming convention follows a library's idiom that collides with a project word, add a short pointer to the library.

## What a comment must not contain

- A translation of the method name into prose, or a restatement of what a framework feature does. If the comment adds no information, delete it.
- Pull request or review context. The pull request does not exist at runtime; a comment describes the behavior of the code.
- How callers use the result. "Used for the badge" inside the method inverts the dependency: the callee now knows its consumers, and the note goes stale when they change. The same holds for a custom error class: describe when the error is raised, not that it triggers a retry.
- Dates such as "changed on 2024/12/10". Version control records when a line changed. Preference.
- A pattern name the implementation does not match. Calling a class a Singleton when it is not misleads more than no comment. Preference: avoid pattern jargon in general and describe what the code or table holds in plain words.
- Vague metaphors or nuance without meaning. A comment that has to be asked about, or that only makes sense after reading the implementation, has failed.
- A cause and effect that do not connect. "Limit to 150 because we want high-priority items first" explains nothing; the reader must be able to follow the reasoning without asking.
- An approximation of what the code does. If the code fetches contacts and keeps one row per company, the comment says that, not "fetches companies".
- **(Ruby)** Words that collide with the surrounding namespace, for example "received from admin" inside an `Admins` controller. Name the actual actor.
- Typos and inconsistent casing (`iD` for `ID`). Comments are read as documentation and misspellings cost trust.

## Keeping comments true

- When the code changes, change the comment in the same change. A comment that says "skip validation" while the code skips callbacks, or a config header that contradicts the rules below it, misleads the next reader.
- When a comment and its code disagree ("converts to date" over code that converts to a string), fix one of them before merge. Either side may be the wrong one.
- **(Ruby)** Doc comments and `@example` blocks name the right method and carry no notes pasted from another method.
- A temporary or dummy class keeps the comment saying why it exists and when it will be removed for as long as the class exists. Deleting the note leaves the next reader asking in person.

## TODO and FIXME

- The first line is a one-line summary of the action ("migrate X to Y and delete X"). Background follows after it. A TODO whose action is buried in history is not actionable.
- A TODO or FIXME that enters the main branch is tracked: an issue, or an owner named in the review, so that it is resolved rather than forgotten.
- Delete a TODO once the work is done or once review has shown it is not needed. A stale TODO sends the next reader down a path that was already rejected.
- Delete a TODO nobody can explain any more instead of moving it along in a refactor. A dated TODO with no owner is noise.
- Preference: leave a TODO at the spot where a known planned feature will change the behavior, so the placeholder logic is revisited when the feature lands.

## Form

- Complete sentences. **(Japanese)** End every sentence with 「。」, including a one-line comment.
- Preference: a multi-line comment starts with a one-line summary, and the body follows. Preference: separate the summary from the body with a blank comment line.

  ```ruby
  # Retry a transient connection error up to three times with exponential backoff.
  #
  # The provider drops connections during its nightly maintenance window, and the
  # third attempt lands after the window in every case observed so far.
  ```
- Preference: a comment that explains a condition sits directly above the `if`, not inside the branch it guards. The reader meets the decision first.
- **(Ruby)** Document methods and attributes in YARD or RDoc rather than free-form `# NOTE:` or `# method_name description` comments. Tooling and every Ruby developer recognize the standard format.
- Document the failure behavior next to the return value ("returns an empty array on error"), not only the happy path. Callers look there first when something goes wrong.
- Preference: when a style or component computation is not obvious, such as a tooltip position relative to its target, say in a sentence what is being calculated.

## Links

- When code is adapted from a framework or library, put a permanent URL pinned to a commit in the comment, at every place the adaptation is relevant. A branch URL drifts and the maintainer needs to diff against the exact original.
- In a monkey patch, mark exactly which lines differ from upstream so the reader sees at a glance what was changed and what was copied.
- Every workaround (a dependency patch, a polyfill stub, an upper bound on a version) records why it exists, links the upstream issue, and states the condition under which it can be removed. If not in the file, then in the commit message or pull request.
- When a comment points to information elsewhere ("see the commit message"), include the direct link. A reference without a path makes the reader hunt.
- Preference: next to a type definition or key list that mirrors a third-party API, link the provider's documentation. Field names copied from an API can only be checked against it.

## Things that are not code comments

Some information looks like a comment but belongs somewhere else.

- Troubleshooting knowledge for a failing test or alert goes in a runbook linked from the failure notification, not in an application file nobody will open years later. Preference.
- The reason for a disabled lint rule sits next to the directive, both inline (`# rubocop:disable Cop/Name -- reason`) and in the configuration file. Without it nobody can judge whether the exception still holds.
- The reason for a permission that deviates from the default policy sits next to the grant in source, not in pull request history.
- `.env.example` lists every variable the application needs. Adding one variable is the moment to fill in the ones that were missing.
- A generated file distributed to other repositories starts with a header saying which tool manages it and that it must not be edited by hand.
- An OpenAPI description states what the endpoint returns: the exact string format of a date, a path rather than a file name, the error responses an auth guard adds. Release-plan notes ("in v1 only the name is editable") are not part of the contract; only an explicit TODO belongs there.
- A released library gets a CHANGELOG entry for every user-facing change, in the format the file already uses.
