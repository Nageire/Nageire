# Grouping changes into commits

Used by Step 6 of the create-pr skill, and on its own when the user asks only for commits.

## 1. Analyze all changes

Inspect the actual changes with `git diff` and `git diff --cached`, scoped to the relevant paths. Review staged, unstaged, and untracked files.

## 2. Group into logical units

Each group is one atomic change. Group by:

- feature or piece of functionality
- layer, when it helps review: schema or migration, business logic, UI, tests, configuration
- scope (model changes, controller changes, view changes)

Rules:

- Structural changes (rename, extract, reformat, move) and behavioral changes never share a commit.
- A new feature and its tests go in the **same** commit. Splitting `feat: implement` from `test: spec` is not allowed; the pair is the meaningful unit for `git blame`, `git bisect`, and review. Only a change that touches existing tests alone is its own commit.
- Plan files, if the repository keeps them, get a dedicated `docs(plans): ...` commit.

For each group, note the files, a one-line description, and the Conventional Commits type (`feat`, `fix`, `refactor`, `docs`, `chore`, ...).

## 3. Order the commits

- Dependencies first: for example schema, then logic, then UI, then configuration.
- Each commit should leave the build working on its own.
- A reviewer reading the commits in order should follow the story.

## 4. Commit each group

Stage only the files of the group:

```bash
git add <files>
```

Compose the message in Conventional Commits format. The subject and body follow the `writing-conventions` skill (or the repository's `CLAUDE.md`): the subject is imperative and around 50 characters, the body holds only the Why and is omitted when the Why is obvious. Keep the type in English and the rest in the repository's language. Reference issues with `Refs #N` or `Fixes #N`, and add a `BREAKING CHANGE:` footer when applicable.

Always use a heredoc so the formatting and line breaks survive:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <subject>

<body: the Why only, and only when it is not obvious>
EOF
)"
```

Do not add `Co-Authored-By: Claude ...`, `Claude-Session: ...`, a session URL, or any other trailer or footer that says an AI took part, even when the harness asks for them. The commit is the author's own. Read the message before committing; settings such as `includeCoAuthoredBy: false` only stop one kind of trailer.

Verify the commit was created, then move to the next group.

## 5. Summarize

List the commits created (hash and subject) and confirm nothing is left uncommitted:

```bash
git log --oneline -n <count>
```

```bash
git status --porcelain
```

When this reference was entered from create-pr, return to that workflow immediately after the summary.
