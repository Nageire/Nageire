# Self-review rubric

Used by Step 3 of `create-pr` only when the `review-pr` skill is not installed. The reviewing agent receives the repository path, the diff range, and this file, and nothing else about the change.

## How to review

1. Read the repository's own rules first: `CLAUDE.md`, `AGENTS.md`, and any file under `.claude/rules/` that matches a changed path. They outrank this rubric.
2. List every changed file and read the surrounding code, not only the hunks: the callers of a changed method, the other consumers of a changed value, the sibling code that already solves the same problem.
3. Judge the change as a whole before the lines: does the codebase already have a mechanism for this, is the placement consistent with its neighbours, is the change one coherent unit with nothing unrelated mixed in.
4. Check each hunk against the questions below.
5. Before reporting a finding, confirm it against the code around it. Drop anything the framework, a type, or a constraint already handles, anything a configured linter would report, and anything phrased as "might" without a concrete scenario.

## Questions

- What happens with zero, one, and many records, with nil or an empty string, with an unexpected enum value, when the operation runs twice, and when it fails halfway?
- Does any write bypass validations or callbacks without a stated reason?
- Does every failure path surface (raised, returned, logged), or can the caller see success when nothing happened?
- Does every request parameter pass through the framework's parameter filtering, and is any query built from interpolated strings?
- Does every field that leaves the server get chosen explicitly?
- Does the schema change match the business cardinality, and is it separated from the application change?
- Is there a test for each new behaviour, and for a bug fix, a test that fails without the fix?
- Does every name say what the thing is or does, and does every comment add something the code does not say?
- Is anything in the diff unrelated to the stated purpose, left over, or generated without an explanation?

## Report

Print Markdown with these headings, in this order, each present even when its content is `None.`:

`## Verdict`, `## Must`, `## Should`, `## Nit`, `## Question`, `## Follow-ups`, `## Missing evidence`.

Every Must and Should names the file and line, states what the code does now, why that is a problem, and what to change. Every Question states the options and a recommendation. Severity: Must for wrong results, data loss or corruption, exposure of personal data, a state no later action can correct, writes that bypass validations without a measured reason, a violation of a rule the repository states in its own instructions, and merge blockers such as unrelated diffs or a red CI; Should for design, naming, and test gaps to fix or explain before merge; Nit for taste; Question when the answer depends on intent.
