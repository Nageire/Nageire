---
description: Value bar for tests in any repository, in three modes. The authoring gate checks every new or changed test for the behavior it protects, the regression that fails it, why existing coverage does not catch it, and whether it needs a test-only production seam. The audit sweeps existing tests for junk patterns (assertion-free probes, source greps, duplicated contracts, mocks that implement the asserted behavior, dead production code only tests call) and deletes with recorded evidence. The campaign prunes one subsystem's whole test surface. Use when writing or changing tests, when reviewing a diff that adds or changes tests, or when asked to audit, sweep, prune, clean up, or consolidate tests, remove low-value or duplicate tests, or drop test-only exports.
license: MIT
metadata:
    github-path: skills/test-audit
    github-ref: refs/tags/v1.9.0
    github-repo: https://github.com/yamat47/github-toolkit
    github-tree-sha: 60ffdab60edf0a8841e25702796594f58c1db4bf
name: test-audit
---
# Test audit

The rules are upstream's: [references/upstream/SKILL.md](references/upstream/SKILL.md) for every mode, [references/upstream/CAMPAIGN.md](references/upstream/CAMPAIGN.md) for a campaign. They are written for the openclaw repository and name its `AGENTS.md` files, its Vitest scripts, and skills such as `$openclaw-testing` that exist only there; the table below says what each means in the repository you are in.

Read the upstream `SKILL.md` in full before judging a test.

## Pick the mode

- Authoring when a test is written or changed, or when another skill passes a diff. Apply the gate to each added or changed test; when `review-pr` or `create-pr` is the caller, return the findings and edit nothing.
- Audit when the user asks to sweep, prune, clean up, or consolidate tests, or asks whether a test is worth keeping.
- Campaign only when the user names one subsystem and asks for its whole test surface pruned in one PR.

## Translate the upstream text to this repository

The first three rows apply in every mode. The rest matter only in audit and campaign modes.

| Upstream says | Here it means |
|---|---|
| Root and scoped `AGENTS.md` | The repository's own rules: `CLAUDE.md`, `AGENTS.md`, files under `.claude/rules/` whose paths match, and any testing guide they point to. They outrank this skill and upstream. |
| `$openclaw-testing`, `$crabbox`, "while Vitest is running" | The repository's test runner, its rules about where tests may run, and its watch mode. Find them the way `create-pr` Step 4 finds the project's checks. |
| `node scripts/run-vitest.mjs <path-or-filter>` | The repository's command for one test file or filter: `bundle exec rspec <path>`, `pnpm vitest run <path>`, or whatever CI runs. |
| `node scripts/check-changed.mjs --dry-run`, "the changed gate" | The repository's formatter, linter, and type checker on the changed paths, then `git diff --check`. When CI has a single entry point (`make lint`, `pnpm check`, `bin/ci`), run that. |
| `$autoreview` | `review-pr` when it is installed, run as `create-pr` Step 3 runs it. Without it, re-read the diff against the retention bar once more and say that no independent review ran. |
| `$openclaw-pr-maintainer`, `scripts/pr` | `create-pr` when it is installed and the user asked for commits or a PR. Otherwise stop at the handoff report; committing is the user's call. |
| Discovery lanes `src/`, `packages/`, `extensions/` | The test roots the repository's runner config names (`spec/`, `test/`, `*.test.*`, and the like), split into lanes along production owners. |
| CI routing, test inventories, shrink-only line-cap baselines | Only where the repository has them. A moved or deleted test file must still be picked up by whatever selects tests in CI. |

When installed, load `rails-idioms` for RSpec; `typescript-idioms`, `vue-patterns`, and `react-patterns` for their testing sections; `writing-conventions` for test names and for the commit messages an audit produces. When `review-pr` or `create-pr` is the caller, it has already loaded them; do not load them again.

## Output

Authoring mode returns, per test, either "passes the gate" or the junk pattern it matches with the evidence: what it asserts, what breaks it, and the stronger proof that already exists. A test-only production seam is reported with its location. Audit and campaign modes end with upstream's handoff report.

## Called from other skills

`review-pr` loads this skill through its routing table for changed test files, and `create-pr` runs the gate in its Step 4; what each does with the result is in its own file. A caller passes a range, a list of paths, or a subsystem name and nothing else: the gate is applied to what the tests assert, not to what the author meant.

The upstream text is from [openclaw/openclaw](https://github.com/openclaw/openclaw/tree/main/.agents/skills/test-audit), MIT (see [LICENSE.txt](LICENSE.txt)).
