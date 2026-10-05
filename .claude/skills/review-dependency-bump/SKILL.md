---
description: Review one automated dependency-update pull request (Dependabot, Renovate) or a manual version bump, locally, and print a fixed-heading Markdown report. Works out what actually changed (declared and effective versions, transitive updates, runtime and peer requirements), finds the authoritative changelog for the exact version range, maps the changes to where this codebase uses the package, reads the CI and advisory signals, and ends with a verdict (merge, merge after a named check, hold, insufficient signal). Posts nothing. Use when the user asks to review, check, or triage a Dependabot or Renovate PR, a gem or npm bump, a GitHub Actions version bump, a Docker base image or Terraform provider update.
license: MIT
metadata:
    github-path: skills/review-dependency-bump
    github-ref: refs/tags/v1.9.0
    github-repo: https://github.com/yamat47/github-toolkit
    github-tree-sha: 67990ff480e6cbb729dde273324c63cb441cda80
name: review-dependency-bump
---
# Review a dependency bump

This skill is the procedure for one dependency-update pull request: a bot PR from Dependabot or Renovate, or a bump a person made by hand. It is the sibling of `review-pr` for this one kind of change. The facts about each ecosystem (where changelogs live, which commands show the effective change, which traps recur) are in [references/ecosystems.md](references/ecosystems.md); read the row for the ecosystem at hand before Step 2. The skill prints a report to the terminal and posts nothing; the caller decides what to do with it. It never treats the bot's excerpt as the whole story: the release notes and changelog in a PR body are truncated, cover only the named package, and say nothing about the other packages the lockfile moved or about requirement changes.

## Target

- A PR number or URL: read it with `gh pr view <n> --json title,body,author,labels,files,baseRefName,headRefName` and `gh pr diff <n>`. The author `app/dependabot` or `app/renovate` marks a bot PR.
- Nothing: the current branch against its base, when the diff only changes dependency versions in a manifest or lockfile (`Gemfile`, `Gemfile.lock`, `package.json`, a JS lockfile, `.github/workflows/*.yml`, `action.yml`, a `Dockerfile`, `.terraform.lock.hcl`).

Run each `gh` and `git` command as its own Bash call so permission rules can match on the command prefix. Run the repository's package manager only for read-only queries (`bundle info`, `npm explain`, `pnpm why`); do not install, update, or push.

## Step 1: Identify the update

Record, for each package in the PR:

1. Name, ecosystem, declared version before and after, and the effective (locked) version before and after when they differ.
2. Kind: direct production, direct development, or indirect. Bot metadata says this (Dependabot `dependency-type`, the Renovate `Type` column); confirm it against the manifest.
3. Single or grouped. A grouped PR gets one report block per package.
4. The version class, computed by you with the rules in the "Version classes" section of the reference, not copied from the title.
5. The bot's own score, recorded as a signal and not as a conclusion: Dependabot's compatibility score (often `unknown`, absent on grouped PRs), Renovate's Age, Adoption, Passing, and Confidence columns. The reference explains what each measures.

Read the repository's own instructions (`CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, the Dependabot or Renovate configuration) before going on. Its rules on cooldowns, automerge, ignored versions, and who merges what outrank the default policy in Step 7.

## Step 2: Read the whole diff

The title names one package; the lockfile tells what moved.

- List every locked package whose version changed, with before and after. The reference names the lockfile sections to read for each ecosystem. Each of them gets a line in "What changed" and, when the move is more than a patch, a changelog check in Step 3.
- Compare the manifest change with the lockfile change. A manifest bump the lockfile does not reflect, or a lockfile move that the manifest's pin does not allow, is a finding.
- Compare the lockfile against the tip of the default branch, not only against the PR base commit: fetch the PR head, then `git diff origin/<default> <head> -- <lockfile>`. Any package that moved backwards means the bot branch was built on a stale lockfile; the verdict is Hold and the follow-up is to recreate the PR.
- Read requirement changes in the diff and in the package metadata: `engines`, `peerDependencies`, `required_ruby_version`, `PLATFORMS` and `RUBY VERSION` in `Gemfile.lock`, `runs.using` in `action.yml`, the base-image OS in a `FROM` line, the `constraints` line in `.terraform.lock.hcl`. Check each against what the repository runs (`.ruby-version`, `.node-version` or `engines`, the CI runner image, the Dockerfile).
- For an Action bump, confirm that the commit SHA in `uses:` is the commit the version comment names and that the tag is a published release (`gh api repos/O/R/git/ref/tags/vX`). A SHA that points at a branch head under a stale comment is a finding.

## Step 3: Find the changelog for the exact range

Bot excerpts are truncated and stop at ten commits. Get the full text for the whole range, in this order, and stop at the first source that covers it:

1. GitHub Releases for each version in the range (`gh api repos/O/R/releases/tags/vX`), rather than listing every release the repository ever published.
2. The `CHANGELOG` file at the new tag (`gh api repos/O/R/contents/CHANGELOG.md?ref=vX`), read from the new version down to the old one.
3. Registry metadata, which names the changelog and the source repository (`npm view <pkg>@<v> repository.url gitHead`; the RubyGems `changelog_uri` and `source_code_uri` fields; the reference has the paths).
4. The compare view between the two tags: `gh api repos/O/R/compare/vA...vB` (three dots; prefix `tags/` when a branch shares the name).

Read every version in the range, not only the top entry: a breaking change two minors down is still in the range. Keep five kinds of entry and drop the rest: breaking changes, deprecations, security fixes, behaviour changes (new defaults, changed output, rules a linter turns on), and requirement changes. Record the version each landed in.

When no changelog exists, say so in the report. For a git SHA bump, work from the commit list of the compare view. For a digest-only image bump, the change is a rebuild of the same tag; the signal is what the image's release channel says about the rebuild, and otherwise the build output. When the published artifact differs from its repository, diff the two published versions (`npm diff --diff=<pkg>@<a> --diff=<pkg>@<b>`; the reference names the equivalent for gems).

## Step 4: Map the changes to this repository

Classify the package first, because the same version class means different things for each kind:

- Framework (web framework, ORM, test framework): a minor changes defaults and deprecates APIs; a major has a migration guide that is part of the review.
- Runtime library (HTTP client, storage SDK, parser): the risk sits at the call sites; grep for them.
- Development tooling (linter, formatter, type checker, bundler): a minor adds rules or changes output; the check is running the tool, and the configuration's schema version and plugins have to follow.
- GitHub Action: a major renames or removes inputs and outputs and can change the runtime; read `action.yml` at both tags and compare against the inputs the workflows pass.
- Base image: a tag change is a language runtime or OS change; the check is the build and the packages the Dockerfile installs.
- Terraform provider: a minor can change how existing configuration is accepted; the check is the plan.

Then, for each entry kept in Step 3, decide whether this codebase reaches it:

- Grep for requires and imports, the configuration keys and DSL the entry names, initializers and `config/*` files, workflow inputs, Dockerfile instructions.
- A removed or renamed API that nothing calls is not reached; say so with the grep that shows it.
- A changed default is reached by every caller that did not set the option; list them.
- A requirement change is reached when the repository's runtime falls outside the new range.
- For a major, produce a table of every breaking change with its impact on this repository (`Reached` with the files, or `Not reached` with the reason). A major without this table has not been reviewed.

## Step 5: Read the signals

- `gh pr checks <n>`: which checks ran, passed, failed, or were skipped. Then ask what the passing checks exercise. A green run on a package no test imports proves that installation works and nothing else; say that in the report.
- Advisory and audit output the repository already runs (`bundle exec bundler-audit check --update`, `npm audit`, `pnpm audit`, a dependency review check). A failing audit on a grouped PR that names a package another PR bumps is a cross-link, not a reason to hand-edit; note both PRs.
- Every row of the "Supply-chain checks" table in the reference that applies to the ecosystem.
- The bot's scores from Step 1, as numbers with what they measure.

## Step 6: When CI is red because of the bump

- Read the failure. A missing method, a peer range error, or a plugin refusing the new major points at a companion package that has to move with this one.
- Find the companion: siblings from the same monorepo (same source repository), packages whose peer range excludes the new version (`npm explain <pkg>`, `pnpm why <pkg>`), plugins and adapters that pin the host's major, the shared sub-dependency Bundler moved.
- Name the companion and the version it needs in "Follow-ups". The fix belongs in the same PR, through the bot: a grouped update in the bot configuration followed by a recreate, or the bot's rebase or recreate command once the companion is on the default branch. Do not push hand edits to the bot's branch; the bot stops rebasing a branch someone else changed. When the repository has decided that people edit bot branches by hand, the edit comes with a comment naming cause, fix, and how it was checked.
- When the bump cannot be taken now, name the mechanism that stops the bot from reopening it: Dependabot's `@dependabot ignore this major version`, `ignore this minor version`, or `ignore this dependency` comment, or the `ignore` block in its configuration; Renovate's `ignoreDeps` or a closed PR (Renovate does not reopen a closed update). Say which one and until when.
- When several PRs overlap, say which one supersedes the others; the superseded ones are closed with a comment linking the one that landed, and the merged lockfile is checked for the version the other PR carried.

## Step 7: Verdict

Four verdicts, each meaning one thing:

- `Merge`: every relevant upstream change in the range was read, none is reached by this codebase or the reached ones are covered by a check that ran green, and no signal is red.
- `Merge after <named check>`: as `Merge`, except one thing has to happen first and the report names it (a lint run with the new version, a companion bump, a configuration change, a migration step).
- `Hold`: a breaking change is reached, a requirement is not met, a signal is red (a failure caused by the bump, a new publisher, a mismatched source, a stale lockfile), or the update belongs to a class the policy leaves to a person.
- `Insufficient signal`: the changelog for the range could not be found, or nothing that ran exercises the package, so the review cannot say; the report names what would supply the signal.

Default policy, which the repository's own instructions override:

1. Security updates go first. Review them before other bumps; when the fix is the only relevant change and CI is green, the verdict is `Merge`.
2. A patch or minor of a `>=1.0` library with green CI, no reached breaking change, and no red supply-chain check is `Merge`.
3. A minor of a linter or formatter is `Merge after` a run of the tool with the new version, because minors add rules.
4. A minor of a framework or runtime library with deprecations in the range is `Merge after` the grep that shows the deprecated APIs are not used, or `Hold` with the migration named.
5. A `0.x` minor and any major get the breaking-change table from Step 4. Majors of a framework, a language runtime, a base-image OS or database image, and Action majors that change inputs are `Hold` for a person, even with green CI.
6. A new publisher, a registry source that does not match the repository, a release younger than the repository's cooldown, or a newly added install script is `Hold`.
7. A git SHA or branch pin is not a released version. A hand-made bump that introduces one where a tag exists is `Hold` until the tag is used; a bot bump from one SHA to another is reviewed from its commit list and is `Insufficient signal` when the commits cannot be read.
8. A lockfile that moved backwards relative to the default branch is `Hold`; the follow-up is a recreate.
9. A digest-only image bump with the tag unchanged and a green build is `Merge`.
10. A manual bump pins with `~>` at patch level (`~> 3.0.7`) or a caret range so later patches flow through the bot; an exact pin without a comment saying why is a follow-up.

## Output

Print the report in this fixed format. The headings never change, so other tools can split the report by heading; a section with nothing to say contains the single line `None.` For a grouped PR, print `# Dependency review: <PR title>` once, then one block per package starting at its own `# Dependency review:` heading, in the order the PR lists them. Write the sentences in the language the repository uses for pull requests and keep the headings in English.

```markdown
# Dependency review: <package> <from> to <to>

## Verdict

<Merge | Merge after <named check> | Hold | Insufficient signal>. <One or two sentences naming the finding that decided it.>

## What changed

- Declared <manifest before> to <manifest after>; effective <locked before> to <locked after>.
- Other packages moved: <name, before, after>, one per line.
- Requirement changes: <engines, Ruby range, peer ranges, runtime, base OS>.

## Relevant upstream changes

- <version>: <change in one sentence>. <Reached | Not reached>: <files, or the reason>.

## Usage in this repository

- `path/to/file.rb:12` <API or configuration key used>.

## Signals

- CI: <checks that ran and their result; what they exercise>.
- Advisories: <audit output, or the advisory the update fixes>.
- Supply chain: <source match, publisher, release age, install scripts, SHA and tag>.
- Bot scores: <values as printed, with what they measure>.

## Follow-ups

- <Companion bump with version, configuration change, migration step, superseded PR to close with a link, ignore command to run.>
```

Rules for the content: every upstream change carries the version it landed in and a `Reached` or `Not reached` with evidence, never bare; the Verdict sentence names the item that decided it; no praise; the bot's excerpt is not repeated once the source was read.

## Checklist

- [ ] Did I compute the version class myself, with `0.x` minors as majors and SHA or tag bumps as their own class?
- [ ] Did I list every locked package that moved, not only the one in the title?
- [ ] Is the lockfile ahead of, not behind, the default branch for every package?
- [ ] Did I read the whole changelog range from the source, not the bot's excerpt?
- [ ] Does every kept upstream change carry its version and a `Reached` or `Not reached` with evidence?
- [ ] Did requirement changes (engines, Ruby range, peers, runtime, base OS) get checked against what this repository runs?
- [ ] For a major, does the report hold a table of every breaking change with its impact?
- [ ] Do I know what the green checks exercise, and did I say so when that is nothing?
- [ ] Does the registry source match the repository I read, and is the publisher unchanged?
- [ ] For an Action, does the SHA match the version comment and a tagged release?
- [ ] When CI is red, is the companion named with its version, and is the fix routed through the bot?
- [ ] Does the verdict follow the default policy or a repository rule I can cite?
