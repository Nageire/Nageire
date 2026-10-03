# Verification and severity

## Evidence a PR should show

Missing items go under "Missing evidence". The list is about what the author should have shown, not about what the reviewer could reproduce.

| Kind of change | Evidence expected in the PR |
|---|---|
| Any | The background and motivation, a statement that it was verified locally, links to the discussion where the approach was decided |
| Visible UI or user-facing text | Before and after screenshots, or a short recording, covering the edge cases the change introduces (several warnings at once, an empty list) |
| Bug fix | The test that fails before the fix and passes after, named in the description |
| Performance | Measurements before and after; for an N+1 fix, query counts or logs, with enough seeded data to show the difference |
| Migration that adds NOT NULL or a unique index to an existing table | Proof that the current data satisfies the constraint |
| Migration that changes a heavy object (materialized view, large table) | The release timing and a revert procedure |
| Terraform or CI workflow | Plan output or a real run; for a refactor, a plan with no diff |
| Dependency bump | Which feature that depends on the library was exercised, and the upstream release notes with the breaking changes assessed for this codebase |
| Release risk | The risk stated explicitly; "none" is almost never true, so "low, because ..." is the expected form |

## Drop or downgrade a candidate finding when

- The surrounding code, a database constraint, or a type already makes the failure impossible.
- The framework already handles the case (for example `belongs_to` already validates presence; bare `raise` inside `rescue` already re-raises).
- You are not sure how the API behaves. Read the gem source under the bundle path or the official documentation first; if still unsure, turn the finding into a Question that names what you checked.
- A linter the repository has configured would report it. Do not run the linter to find out; if the repository has no linter for the language, keep the finding as a Nit.
- The repository's `CLAUDE.md`, rules, or a linked decision explicitly chooses the pattern you would flag.
- The problem exists outside the diff and the change does not make it worse. At most a follow-up.
- The finding is a preference (a knowledge skill marks preferences as such) and the codebase consistently does otherwise. Preferences become Nits at most.
- The finding is a "might" or "could" without a concrete scenario. When you can name the scenario (the input, the order of events, the data that would have to exist), keep it as a Question that states the scenario and what you could not confirm; a concrete "does this break when X?" is what a reviewer would ask. Drop it only when no scenario can be named.

## Severity

| Severity | Use for |
|---|---|
| Must | Wrong results, data loss or corruption, exposure of personal data, a state no later action can correct, writes that bypass validations without a measured reason, a violation of a rule the repository states in its own instructions, and merge blockers such as unrelated diffs, a dependency pinned to a branch or SHA, a migration without its `schema.rb`, or a red CI |
| Should | A design or placement that diverges from the codebase without a reason, a schema that does not match the business, missing tests for new logic, a name that misleads, missing evidence for a claim the PR makes; fix or explain before merge |
| Nit | Style, wording, and taste; deferrable, and the report says it is deferrable |
| Question | The intent is unclear, or the correctness depends on a fact only the author knows; state the options and a recommendation |

Calibration rules: a Should does not become a Must because there are many of them; a Must is not softened because the PR is large; a preference is never a Must. When the same problem appears in several places, it is one finding at the severity of the worst instance, listing every location.

## Before printing

- Every finding has a file and line taken from the diff, not from memory.
- Every Must or Should states the fix, and every Question states the options and a recommendation.
- The verdict follows from the findings: any Must means Request changes.
- Follow-ups list what must be recorded before merge, not what the reviewer would like in general.
