---
description: Background knowledge (not a command) on writing and reviewing GitHub Actions workflows, composite actions, and reusable workflows. Covers permissions and GITHUB_TOKEN, pull_request_target and workflow_run, script injection through github.event context, SHA pinning of every uses reference with a version comment, OIDC instead of stored cloud credentials, secrets inherit versus named secrets, environments, concurrency and cancel-in-progress, timeout-minutes, fail-fast, actions/cache keys and cache poisoning, upload-artifact and download-artifact, paths filters on required checks, workflow_dispatch inputs, cron, reusable workflow vs composite action and workflow_call, action.yml rules, thin SHA-pinned wrapper actions, Dependabot github-actions configuration and cooldown, GITHUB_OUTPUT, actionlint and zizmor findings, and how to verify a workflow change. Use when adding or changing a file under .github/workflows, an action.yml, or Dependabot configuration for actions.
license: MIT
metadata:
    github-path: skills/github-actions-workflows
    github-ref: refs/tags/v1.9.0
    github-repo: https://github.com/yamat47/github-toolkit
    github-tree-sha: 25d387fc07cc62aec410d1c145b3e6656d285e24
name: github-actions-workflows
---
# GitHub Actions workflows

Background knowledge consulted while writing or reviewing files under `.github/workflows/`, an `action.yml`, or a Dependabot configuration for the `github-actions` ecosystem. Each rule is something a reviewer checks against a diff. Rules marked as a preference are house style rather than platform behaviour.

## 1. Security

Never interpolate untrusted context with `${{ }}` inside `run:` or an inline script step. The expression is expanded before the shell starts, so a pull request title, body, branch name, commit message, author name, or comment body written by a contributor becomes shell code. Assign the value to `env:` and read the variable.

```yaml
# BAD
- run: echo "${{ github.event.pull_request.title }}"

# GOOD
- env:
    TITLE: ${{ github.event.pull_request.title }}
  run: echo "$TITLE"
```

`pull_request_target` and `workflow_run` are privileged: they run with the base repository's token, secrets, and default-branch cache. Under these triggers the workflow file and the default checkout come from the default branch, and `actions/checkout` refuses to check out a fork's pull request ref unless `allow-unsafe-pr-checkout: true` is set; the input is named to stand out in review. Never execute code checked out from the pull request under a privileged trigger: no dependency install, no test run, no build script. Prefer `pull_request` together with the repository setting that requires approval for fork workflows. When a privileged half is unavoidable, split the work into two workflows and treat what the unprivileged half produces as untrusted data. Disagreement: the official hardening guide documents safe patterns for `pull_request_target`, while several security guides hold that the trigger cannot be used safely and recommend avoiding it altogether.

Pin every third-party action and container image to a full commit SHA followed by a `# vX.Y.Z` comment. A tag can be moved: in several incidents every tag of a widely used action was repointed at a commit that dumped runner memory into the logs, and consumers pinned to a SHA were unaffected unless they bumped inside the window. Pin transitively: an action used inside a composite action or a reusable workflow needs the same pin, because a pinned top-level reference protects nothing when the action calls a floating tag internally. The allowed-actions policy of a repository or organisation can require SHA pins (an unpinned `uses:` then fails rather than warns) and can block an action by name with a `!owner/action` entry during an incident. Prefer actions whose repositories publish immutable releases; their tags cannot be moved or deleted.

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  with:
    persist-credentials: false
```

Set `persist-credentials: false` on checkout unless a later step pushes. The token is written to `.git/config` and leaks with any artifact that contains the workspace, and an artifact can be downloaded before the job that uploaded it has finished.

Never upload the whole workspace or hidden files. `actions/upload-artifact` excludes hidden files by default; do not set `include-hidden-files: true` without a reason in the diff.

Keep `actions/cache` out of release and publish jobs. A cache written on the default branch is readable from every branch, `restore-keys` restores the newest entry with a matching prefix, and the hit decision is made client side, so a poisoned cache feeds the release. Elsewhere, use exact keys and a `restore-keys` prefix scoped to OS and tool.

Treat artifacts from other runs as untrusted input. Download them by `run-id` with a token that holds only `actions: read`; a fork can produce an artifact with the same name as the one the privileged job expects.

Never write untrusted input to `GITHUB_ENV` or `GITHUB_PATH`. A crafted value defines variables or prepends binaries for every later step. Pass values between steps through `GITHUB_OUTPUT`.

Do not register self-hosted runners on a public repository. A non-ephemeral runner keeps state between jobs, and any pull request author can run code on it. When self-hosting is required, use ephemeral or just-in-time runners, runner groups, and an egress allowlist.

Run actionlint and zizmor on every change to a workflow. List `.github/workflows/**`, `actions/**`, and security gate configuration such as secret-scanning rules in CODEOWNERS so the team that owns CI reviews each change, and state the scope of the change in the pull request (for example, build settings only) so that team can approve quickly.

## 2. Permissions and secrets

Declare `permissions:` in every workflow. Start from `permissions: {}` or `contents: read` at workflow level and grant per job. Setting any scope sets every unlisted scope to `none`, so a job that only reads code gets no write scope even when the repository default is still read-write. Put a comment on each grant naming the step that uses it.

```yaml
permissions: {}

jobs:
  release:
    permissions:
      contents: write # gh release upload
      id-token: write # fetches the OIDC token for the cloud role
```

Use OIDC instead of stored cloud credentials. Grant `id-token: write` on the deploying job only and use the provider's official credentials action; the token is issued for one job and expires with it. In the cloud trust policy, restrict the subject to the repository and environment, and for a reusable workflow to the `job_workflow_ref` claim. `id-token: write` only permits fetching the token; it grants nothing on GitHub.

Pass secrets to a reusable workflow by name under `secrets:`. Disagreement: the official docs permit `secrets: inherit` inside an organisation, while zizmor and security guides flag it because it hides which secrets the callee reads and hands every secret to a workflow that needs one. Never build `toJson(secrets)`.

Scope deployment secrets to environments with required reviewers, a wait timer, and a branch or tag policy; the secrets are released only after the rules pass. A caller job that `uses:` a reusable workflow cannot set `environment:`, so the environment goes on the job inside the reusable workflow.

Do not store structured data (a JSON document, a whole `.env`) as one secret. Redaction is an exact match on the whole value, so parts of a structured secret print in clear. Mask derived values with `::add-mask::`. After an exposure, rotate the secret and delete the run logs.

A push, tag, or pull request created with `GITHUB_TOKEN` does not start another workflow run (`workflow_dispatch` and `repository_dispatch` excepted). Use a GitHub App installation token when the chain is intended. The reverse swap also needs care: `GITHUB_TOKEN` has narrower scopes than an App token, so check the `permissions:` block when replacing one with the other. When a ruleset or branch protection is tightened, list the workflows that pushed under a bypass and plan how they keep working.

## 3. Triggers

Do not put `paths:` or `paths-ignore:` on a workflow that is a required status check. A workflow that does not run leaves the check pending forever, while a job skipped by `if:` reports success. Add a change-detection job that outputs which areas changed and gate the downstream jobs with `if:`.

```yaml
  test:
    needs: changes
    if: needs.changes.outputs.app == 'true'
```

`paths` and `paths-ignore` are mutually exclusive for one event, and the filter is bypassed for a push above 1,000 commits or 3,000 changed files. When a deploy workflow does filter on paths, include `.github/**` in the list; a change to the pipeline itself can affect every service.

Type every `workflow_dispatch` input and give it a default. The dispatch entry appears in the UI only once the file is on the default branch.

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [staging, production]
        default: staging
      dry-run:
        type: boolean
        default: true
```

Require approval for workflows from forks (first-time contributors, or all outside collaborators) in the repository settings. Set `name:` on every workflow, and `run-name:` when the run list needs to show an input or a ref.

Before choosing a comment keyword such as a mention to trigger automation, check that the handle is not an existing user. A mention in a comment is a real mention, and the account behind it gets a notification from every pull request.

Remove temporary triggers before merge. A feature branch added to `on.push.branches` to test a workflow runs staging builds from that branch if it stays; mark such lines with a TODO during review. Check a `cron` expression against the schedule the pull request describes, including day-of-week numbering (0 is Sunday) and the conversion from local time to UTC.

## 4. Structure and reuse

| Criterion | Reusable workflow | Composite action |
|---|---|---|
| Unit | One or more jobs, called from `jobs.<id>.uses` | Steps, called from `steps[].uses` |
| Location | File directly in `.github/workflows/`, no subdirectory | Any directory with an `action.yml`, or its own repository |
| Runner, matrix, `environment` | Chosen inside the workflow | Runs on the caller's runner and job |
| Secrets | `on.workflow_call.secrets` or `secrets: inherit` | None; pass them as inputs |
| Nesting | Ten levels of calls | Ten composite actions deep |
| Logging | Each step shown live | Collapsed into one step |
| `timeout-minutes` | On each job | Not supported on composite steps |
| Marketplace | No | Yes |
| OIDC claim | `job_workflow_ref` identifies the workflow | None |
| SHA-pin policy | Reference by tag allowed | Must be SHA-pinned |

Choose a composite action when callers need to place steps around it, or when one platform team serves many teams that own their own pipelines. Choose a reusable workflow when one team owns a whole pipeline that many repositories run identically. Abstract per-repository YAML into reusable workflows or shared actions so that a fix rolls out horizontally; when a sibling workflow already fixed the same problem, copy that implementation exactly so a later fix does not land in one of them only. Preference: when workflows differ only by target environment, extract a reusable workflow that takes the environment as an input rather than keeping one file per environment.

Every `run` step in a composite action declares `shell:`; the file is rejected otherwise. Read inputs through `${{ inputs.x }}` (composite actions receive no `INPUT_*` variables). Declare each output under `outputs.<id>.value` and reference a step output there. Reach bundled files through `${{ github.action_path }}`. Composite steps accept `if`, `env`, `working-directory`, `uses`, `with`, and `continue-on-error`, but not `timeout-minutes`. Composite inputs are strings, so quote defaults such as `"true"`. A JavaScript action declares `using: node24`; the `node20` runtime is scheduled for removal, so a bump to a major version of an action often carries the runtime change together with behaviour changes.

```yaml
runs:
  using: composite
  steps:
    - id: upstream
      uses: actions/cache@0000000000000000000000000000000000000000 # v4.2.2
      with:
        path: ${{ inputs.path }}
        key: ${{ inputs.key }}
    - shell: bash
      run: "${{ github.action_path }}/scripts/report.sh"
```

Inside a composite action, `./path` resolves against the caller's workspace, not the action's repository. `uses:` accepts no expressions, so there is no form relative to the action itself: reference a sibling action by its full `owner/repo/actions/<name>@<sha>`, and reach scripts shipped with the action from `run` steps through `github.action_path`. A recipe that chains upstream actions otherwise pins them directly, since an exact-tag self-reference cannot exist before the tag does.

Keep shared workflows and actions in one dedicated repository with its own CI, tagged together with exact semver tags and shared through the repository's Access setting. Consumers pin an exact tag or SHA; never `@main` in production. A thin wrapper around an upstream action pins the upstream SHA in one place, so Dependabot bumps one file and every consumer receives the update at the next release. That repository's own CI runs every local action through a relative reference (`./actions/<name>`); actionlint then checks the inputs each job passes against the action's declared inputs and the outputs the job reads against its declared outputs.

Preference: keep the scripts and prompts a workflow depends on in a directory named after the workflow, such as `.github/workflows/<workflow>/scripts/`, rather than in a shared `.github/scripts/`. Each workflow then reads as one unit and does not grow accidental dependencies on another workflow's helpers. Move any `run:` body longer than a few lines into such a script file, where shellcheck and a local shell can run it.

Split a reusable workflow that has grown many optional inputs; twenty optional inputs mark a workflow doing unrelated things. The organisation `.github` repository's `workflow-templates/` are starters that consumers copy; they are not shared logic and do not update after copying.

In automation that calls a language model, keep every deterministic step (API calls, JSON filtering, dependency updates, git and `gh` operations, pull request templating) in scripts and hand the model only the judgement task. Restrict its tools to what that judgement needs (read, search, fetch), never `git push`, `git commit`, or `gh pr create`. Fix branch names, titles, and metadata formats in templates, pin the structure of the model's output in the prompt, and validate that structure in the script before using it. Decide up front how a failing item is handled: skipped, labelled for manual handling, or reported in the job summary.

## 5. Reliability

Key `concurrency` on the workflow and the ref. For push-triggered workflows use `github.ref`; `github.head_ref` is empty outside pull request events, so every push run lands in one group and cancels the others. Set `cancel-in-progress: true` for CI and `false` for a deploy, so a rollout completes before the next one starts. Group names are case-insensitive.

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Set `timeout-minutes` on every job. The default is 360, so a hung job is billed for six hours and holds its concurrency group. Decide `fail-fast` deliberately: the default `true` cancels the sibling matrix jobs on the first failure, which hides whether the others would have passed. For a matrix that calls a rate-limited API, set `max-parallel` or loop sequentially.

```yaml
jobs:
  test:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    strategy:
      fail-fast: false
      matrix:
        ruby: ["3.3", "3.4"]
    steps:
      - if: ${{ !cancelled() }}
        run: ./scripts/cleanup.sh
```

Gate cleanup with `if: ${{ !cancelled() }}`. `always()` also runs after a cancellation, and a cleanup that then waits on a cancelled service runs until the timeout.

Declare `shell: bash` on `run` steps that use pipes. The implicit default is `bash -e`; the explicit form adds `-o pipefail`, without which `cmd | tee log` succeeds when `cmd` fails. Do not swallow a lookup with `2>/dev/null || true` when its result changes what the step does; a sticky comment that fails to find its predecessor and posts a new one is worse than a red step. Verify which fields a CLI returns before scripting against them; a `jq` path that resolves to nothing makes a branch silently disappear (for example, `gh pr view --json comments` exposes GraphQL node ids, not the numeric ids the REST API takes).

```yaml
# BAD: an empty id turns "update the comment" into "post a new one" without a trace
- run: id=$(gh api "repos/$REPO/issues/$PR/comments" --jq "$QUERY" 2>/dev/null || true)

# GOOD
- shell: bash
  run: id=$(gh api "repos/$REPO/issues/$PR/comments" --jq "$QUERY")
```

Build cache keys from `runner.os` and `hashFiles` of the lockfile. Prefer the caching built into `setup-*` actions (`cache: npm` with `cache-dependency-path`), which caches the package manager's store rather than `node_modules`. Caches are immutable, a repository holds 10 GB, and an entry unused for seven days is evicted.

```yaml
- uses: actions/cache@0000000000000000000000000000000000000000 # v4.2.2
  with:
    path: vendor/bundle
    key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
    restore-keys: ${{ runner.os }}-gems-
```

Give every artifact a name unique per matrix cell. Uploads with the same name fail unless `overwrite: true`, file permissions flatten to 755 and 644, and matrix output is reassembled on download with `pattern:` and `merge-multiple: true`.

```yaml
- uses: actions/upload-artifact@0000000000000000000000000000000000000000 # v4.6.2
  with:
    name: test-results-${{ matrix.os }}-${{ matrix.ruby }}
    path: tmp/results
```

There is no step-level retry; a re-run restarts the job. Wrap a step known to be flaky in a retry action, or retry inside the tool, and put the reason next to it. Pin `runs-on` to an explicit image such as `ubuntu-24.04` for release and deploy jobs; the `ubuntu-latest` label moves to a new image with different default tool versions.

Write results a human needs to `$GITHUB_STEP_SUMMARY`, and emit `::error file=..,line=..::` annotations or a problem matcher for findings tied to a file. Annotations are capped at 10 per severity per step and 50 per job.

## 6. Maintainability

Keep `# vX.Y.Z` as the last token after a SHA pin. Dependabot updates the comment only when the version ends the line, and zizmor reports a comment that disagrees with the SHA.

For the `github-actions` ecosystem, `directory: "/"` covers `.github/workflows/` and a root `action.yml` only. List every `actions/<name>` directory through `directories` (globs are accepted) and group the updates so one pull request bumps them together.

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directories: ["/", "/actions/*"]
    schedule:
      interval: weekly
    groups:
      actions:
        patterns: ["*"]
    cooldown:
      default-days: 7
```

Wait seven to fourteen days before adopting a new version of an action, so a poisoned release is caught by others first. Disagreement: the Dependabot changelog says `cooldown` covers every supported ecosystem except one and issue reports show it applied to Actions using tag commit dates, while the options reference does not list `github-actions` under cooldown, and some teams enforce the delay with a different updater or a pin tool's minimum-age flag instead.

When reviewing a bump of an action, enumerate the inputs the workflow passes and the outputs it reads, confirm each is unchanged in the new version's release notes, and state the rollback (reverting one line). When a deprecation is fixed in one repository, check the sibling repositories that share the pattern.

Write step outputs and state to `$GITHUB_OUTPUT` and `$GITHUB_STATE`, with a heredoc delimiter for multiline values. `::set-output` and `::save-state` are disabled.

```yaml
- id: build
  shell: bash
  run: |
    echo "version=1.2.3" >> "$GITHUB_OUTPUT"
    {
      echo "notes<<NOTES"
      cat CHANGELOG.md
      echo "NOTES"
    } >> "$GITHUB_OUTPUT"
```

Document inputs, outputs, secrets, and a deprecation policy for every shared workflow and action. Next to any setting introduced as temporary, state when or under which condition it is removed.

Question every setup step. Do not install a toolchain the job does not use, and do not reinstall a tool the runner image already has; zizmor flags both. Do not introduce a YAML anchor that nothing references.

For container images a workflow builds: keep one Dockerfile for every environment and select behaviour with environment variables at run time (preference); keep the Dockerfile and its entrypoint script together in one directory; precompile assets at image build time with dummy secrets rather than at container start, where the compile repeats on every task launch. Keep the CI database version equal to the one production runs; bumping CI first hides incompatibilities.

## 7. Verification

actionlint checks syntax and unknown keys, expression syntax and types, which contexts are available where, untrusted input interpolated into `run:`, the shell scripts themselves through shellcheck, runner labels, `uses:` inputs and outputs against the referenced `action.yml` (including local `./actions/<name>` references), `workflow_call` inputs, outputs, and secrets, permission scopes, `cron` syntax, `needs` cycles, deprecated workflow commands, and constant conditions (`if: ${{ false }} || x` is always true).

zizmor audits, among others, `template-injection`, `dangerous-triggers`, `excessive-permissions`, `unpinned-uses`, `ref-version-mismatch`, `artipacked`, `cache-poisoning`, `github-env`, `secrets-inherit`, `self-repository`, `superfluous-actions`, and `known-vulnerable-actions`; its pedantic level adds `undocumented-permissions`, `anonymous-definition`, `concurrency-limits`, and `self-hosted-runner`, and `dependabot-cooldown` is configurable.

Test a workflow on a branch with a `push` or `pull_request` trigger. A `workflow_dispatch` trigger needs a stub of the workflow on the default branch first; then run it against the branch with `gh workflow run --ref <branch>`. Remove the temporary triggers before merge. Test a shared workflow or action from a consumer with `@<branch>` (or a relative path inside the same repository), then switch to the tag or SHA. Use `act` for fast local iteration only; its images and event support differ from the hosted runners, so confirm on GitHub.

A pull request that changes a build or deploy pipeline states how the change was exercised (a branch run, a dispatch, a consumer run, a staging deploy), because the diff alone does not show whether it works. Do not merge on a run whose jobs were cancelled or skipped; re-run and confirm the job that exercises the change completed. Preference: a coverage-only or known-flaky failure does not block a merge or release once it is confirmed to be the only failure.

Attest release artifacts with the build-provenance action (`id-token: write`, `attestations: write`, `contents: read`) and verify them with `gh attestation verify`.

## Checklist

- [ ] Does any `run:` or inline script interpolate `github.event.*`, `github.head_ref`, or an input directly instead of through `env:`?
- [ ] Is the trigger `pull_request_target` or `workflow_run`, and if so is checked-out code only read, never executed, with `allow-unsafe-pr-checkout` absent?
- [ ] Is `permissions:` declared at workflow level as `{}` or `contents: read`, with a comment on each per-job grant?
- [ ] Is every `uses:` a full 40-character SHA with a trailing `# vX.Y.Z`, including inside `actions/*/action.yml`, and is the action maintained and not a typosquat?
- [ ] Are secrets passed by name, environment-scoped for deploys, never structured, and could OIDC replace a stored credential?
- [ ] Does checkout set `persist-credentials: false`, and do uploads exclude `.git`, dotfiles, and whole workspaces?
- [ ] Is `actions/cache` used in a release job or with a broad `restore-keys` prefix, and are cross-run artifacts fetched by `run-id` and treated as untrusted?
- [ ] Are `timeout-minutes` and a workflow-plus-ref `concurrency` group set, with `cancel-in-progress` right for CI versus deploy and `github.ref` for push triggers?
- [ ] Is `fail-fast` intentional, do artifact names include the matrix values, and does cleanup use `!cancelled()` rather than `always()`?
- [ ] Is `shell: bash` explicit where pipes are used, and does no `2>/dev/null || true` hide a lookup that changes behaviour?
- [ ] Is this a required check carrying `paths:` filters, and does a comment-keyword trigger avoid an existing user's handle?
- [ ] Reusable workflow: is the file directly in `.github/workflows/` with typed inputs, defaults, and outputs declared? Composite action: does every `run` have `shell:`, are sibling actions referenced by full `owner/repo/path@sha`, and bundled scripts through `github.action_path`?
- [ ] Does Dependabot's `directories` cover this directory, and does CODEOWNERS route the change to the team that owns CI?
- [ ] Was the change exercised (branch run, dispatch, consumer `@branch`), do actionlint and zizmor pass, and does the pull request say so?
- [ ] Are temporary triggers, unused anchors, unneeded setup steps, and undocumented temporary settings gone before merge?
