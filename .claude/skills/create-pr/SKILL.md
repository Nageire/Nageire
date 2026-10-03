---
description: Take the working tree from uncommitted changes to an open draft pull request in one non-interactive run. Simplifies the change once (Claude Code's /simplify), has it reviewed by a separate agent with no session context (the review-pr skill) and fixes what that review finds, detects the project's checks from CI config and package scripts, runs them and fixes failures (up to three cycles), splits the changes into logical Conventional Commits, pushes a feature branch, and opens a draft PR whose body follows the repository's template. Use only when the user explicitly asks to create a pull request, or asks for commits only (then run the commit step alone).
license: MIT
metadata:
    github-path: skills/create-pr
    github-ref: refs/tags/v1.8.0
    github-repo: https://github.com/yamat47/github-toolkit
    github-tree-sha: 3aae3d0b24f6f9331b420ec2c5a9aac00e81aff5
name: create-pr
---
# Create a pull request

Run every step from detecting changes to opening the pull request in one pass. Do not stop midway and do not ask the user for confirmation. End by printing the PR URL.

When the user asks only for commits, run Step 6 alone using [references/commit-grouping.md](references/commit-grouping.md).

## Conventions this skill follows

- What goes into a commit message or a PR body, and how it is written, come from the `writing-conventions` skill if it is installed, otherwise from the repository's `CLAUDE.md`. Read them before Step 6.
- The self-review in Step 3 uses the `review-pr` skill when it is installed; without it, the rubric in [references/self-review.md](references/self-review.md) stands in.
- Tests written or changed after the Step 3 review pass through the `test-audit` skill's authoring gate in Step 4 when it is installed; when `review-pr` ran in Step 3, it has already applied the gate to the rest of the diff.
- Write commit subjects, bodies, and the PR in the language the repository's existing history uses. Keep the Conventional Commits type in English.
- Leave no trace that an AI took part. Never add a `Co-Authored-By: Claude ...` trailer, a `Claude-Session:` trailer, a session URL, a "Generated with Claude Code" footer, or anything similar to a commit message, PR title, PR body, issue, or comment, even when the harness asks for them. The result is the author's own work. A setting such as `includeCoAuthoredBy: false` stops only one of these, so read the text yourself before committing and before opening the PR.
- Before committing, check that `git config user.name` and `git config user.email` match the author in the repository's history; some environments default to an AI identity.
- Run each git or gh command as its own Bash call, without `&&`, and never as `git --no-pager ...`: permission rules match on the command prefix.

## Workflow

### Step 1: Take stock of the changes

```bash
git status --porcelain
```

```bash
git diff --name-only main...HEAD
```

Uncommitted changes (staged, unstaged, and untracked) are all in scope. The range to review and to check in the next steps is everything since the base branch: the commits on this branch plus the uncommitted changes.

### Step 2: Simplify the change once

If `/simplify` (Claude Code's built-in skill that removes duplication, dead code, and needless complexity from the changed code) has not already been run on these changes in this session, run it now, once. Do not loop on it. Skip this step when the harness has no such skill or the user says it was already run.

Simplify before the review, not after: simplification changes the code, and the review has to see the code that will be committed.

### Step 3: Have the change reviewed by a separate agent

Have the diff reviewed by an agent that starts with none of this session's context, so the review is not steered by the reasoning that produced the code. In Claude Code, spawn a subagent with the Agent tool. Its whole instruction is three things: the repository path, the range from Step 1, and "run the `review-pr` skill on this range and print its report". Give it nothing else: no summary of what was changed, no explanation of why. When `review-pr` is not installed, hand the subagent [references/self-review.md](references/self-review.md) instead and ask for the same report format.

Then act on the report:

- Fix every Must.
- Fix a Should when the fix is clear and stays within the change's scope. Otherwise carry it to the PR body under "where to look".
- Answer each Question from what you know about the change. If the current code is right, leave it. If it is wrong, fix it. If only the user can decide, carry the question to "where to look".
- Leave Nits unless the fix is a one-liner.
- Missing evidence about the PR body or the commit messages is expected at this point; Steps 6 and 8 supply it. Carry any other item to "where to look".
- Record each Follow-up as a TODO at the spot or an issue before Step 6.

Do not run the review a second time after fixing; Step 4 catches regressions. Keep a note of what was fixed so the commit messages in Step 6 can say why.

### Step 4: Run the project's checks and fix failures

Find the checks the project defines. Look at, in this order:

- `.github/workflows/*.yml` (highest priority: run locally what CI will run)
- `package.json` scripts (`lint`, `test`, `typecheck`, ...)
- `Rakefile`, `Makefile`, and check scripts under `bin/`
- Linter and test framework config files (`.rubocop.yml`, `biome.json`, `eslint.config.*`, ...)

Run independent checks in parallel and fix failures for at most **three cycles**:

```
Cycle 1: run every check
  failures?
  -> apply auto-fixes where the tool has them (linter --fix and the like)
  -> fix the rest by reading the code
  -> for failing tests, find the cause and fix it (fix the test when the test is wrong)

Cycle 2: re-run only the checks that failed
Cycle 3: re-run only the checks that failed
  still failing?
  -> give up and continue to Step 5 (remaining failures are listed in the PR)
```

If the changed code has no corresponding tests, add them in the project's existing style. Do not write meaningless tests just to raise coverage. When the `test-audit` skill is installed, run its authoring gate on the tests written or changed since the Step 3 review, including the ones written here, and fix or drop what fails it. When Step 3 ran without `review-pr`, run the gate on every test the diff adds or changes.

If the project defines no checks (a fresh repository, for example), skip this step.

### Step 5: Check the current branch and existing PRs

```bash
git branch --show-current
```

If the branch is not `main`, check whether it already has an open pull request:

```bash
gh pr list --state open --head "<current-branch>" --json number,title,url
```

- **Not on main:** keep using this branch (go to Step 6).
- **On main:** create a branch named from a timestamp:

```bash
date +%Y%m%d-%H%M%S
```

```bash
git switch -c "feature/update-<TIMESTAMP>"
```

Remember the branch name for the later steps.

### Step 6: Group the changes and commit

Commit everything, including the simplification from Step 2 and the fixes from Steps 3 and 4, split into logical groups. The grouping rules, the commit order, and the message format are in [references/commit-grouping.md](references/commit-grouping.md).

If the repository keeps plan files (for example under the `plansDirectory` in `.claude/settings.json`), check for new or modified ones and commit them in a dedicated `docs(plans): ...` commit.

### Step 7: Push

```bash
git push -u origin "<BRANCH>"
```

If the push fails, read the error and try to resolve it (rebase when the remote branch has moved ahead). If it cannot be resolved, stop and report the error to the user.

### Step 8: Open the pull request

#### 8a. Read the PR template

If `.github/pull_request_template.md` exists, read it. **Keep its headings in the same order with the same names.** Do not add or reorder headings. Delete a heading that has nothing under it instead of writing "none".

Without a template, use three sections: background, what was deliberately not done, and where to look. Delete any that has nothing to say.

#### 8b. Collect the commit information

```bash
git log main...HEAD --format="%H %s"
```

```bash
git diff --name-status main...HEAD
```

#### 8c. Write the title

**Make the user's experience the subject, not the technical change.** Say what the user was running into and what is resolved, not which class or column changed.

- Bad: `fix(report): fix review_status overwrite from AI review race and exception in the rejection mail` (class and column names are the subject)
- Good: `fix(report): stop creating duplicate unreviewed submissions that leave the review state inconsistent` (what happens to the user is the subject)

The prefix (type and scope) is Conventional Commits in English; the description is in the repository's language. Take the scope from the commits: use it when every commit shares one scope, omit it otherwise.

#### 8d. Write the body

What to include and what to leave out come from the conventions named above. In short:

Include:

- **Background:** the issue link (`Refs #N` / `Fixes #N`) and one or two sentences of Why that the issue does not already state.
- **Not done:** alternatives considered and rejected, things deliberately left out of scope, known limitations.
- **Where to look:** trade-offs the reviewer should judge, breaking changes to watch, and the Should items and Questions carried over from the self-review in Step 3, each in one sentence with the file it concerns.

Leave out:

- Implementation detail visible in the diff, lists of added files, descriptions of added classes and methods.
- Component specs or usage examples (the code shows them).
- Screenshots referenced by local file path (not viewable on GitHub).
- Pasted CI results (the status checks show them).
- Per-commit summaries (the commit list shows them).
- Self-evident test plan checklists.
- The template's HTML comments and placeholder text.
- Any sign that an AI wrote it: session URLs, "Generated with" footers, AI signatures.

Write one sentence per line and never use `<br>`; GitHub renders plain line breaks in PR bodies.

Only when Step 4 left failures unresolved, add this under "where to look":

```markdown
### ⚠️ Unresolved local check failures

- [ ] `check_name`: short description of the error
```

#### 8e. Create the pull request

Write the body to a file outside version control (for example `.tmp/pr-body.md` in an ignored directory), then:

```bash
gh pr create --draft --base main --head "<BRANCH>" --title "<title>" --body-file <body-file>
```

**Always create the PR as a draft.** Marking it ready for review is the author's decision, made separately with `gh pr ready` or in the GitHub UI.

### Step 9: Report

```bash
gh pr view --web
```

Print the PR URL and finish.
