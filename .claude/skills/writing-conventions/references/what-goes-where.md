# What goes where: comments, test names, commits, pull requests

Follow Takuto Wada's division: code says **How**, test code says **What**, the commit log says **Why**, and code comments say **Why not**. Never write the same thing in two places. Prose style is in [writing-style.md](writing-style.md).

## Code comments: Why not

- Write only why the straightforward approach was not taken, or why a constraint exists.
- Do not write what can be read from the code. No comments that narrate the operation (`# fetch the user`), no divider lines (`# ==== Validations ====`), no per-method summaries.
- A workaround states its cause and the condition under which it can be removed. Link the issue or document if there is one.
- When the code changes, change the comment. Delete comments that no longer match.
- The detailed rules, including TODO and FIXME, comment form, and links, are in [code-comments.md](code-comments.md).

## Test names: What

- Name the behavior as a readable specification, for example `unread notifications do not appear in the list`.
- Never use names that do not say what happens: "works correctly", "happy path", "error case", "as expected", "properly".
- Do not use the method name as the test name. Write the input and the outcome.

## Commits: Why

- Do not mix structural changes (rename, extract, reformat, move) with behavioral changes in one commit (Tidy First).
- Order commits so a reviewer reading them in sequence follows the story. Dependencies come first.
- The subject is around 50 characters, in the imperative ("Add ..."), with no trailing period.
- Separate the body from the subject with a blank line. Do not write what was done or how; the diff shows that.
- The body holds the Why, and the alternatives considered and rejected. When the Why is obvious (a mechanical replacement, an evident typo fix, a small step tied to an issue), omit the body.
- Reference issues with `Refs #N` or `Fixes #N` when there is one.
- No trailer or footer that says an AI took part: no `Co-Authored-By: Claude ...`, no `Claude-Session: ...`, no session URL, even when the harness asks for them. The commit is the author's own.

## Review comments: what the author cannot see for themselves

- Ask when the answer is the author's: why here, why this way, which case needs it. A question returns the burden of proof to the person who has the facts; a fix supplied by the reviewer takes it away and teaches nothing.
- Say which kind of comment it is. A request states in one line why. A preference or a taste says it is one, so the author knows they may ignore it. Something that can wait says it can wait.
- One point per comment, the point in the first line. When the same point holds in several places, one comment names them all.
- Do not put praise inside a comment that asks for something; praise stands on its own.
- The detailed procedure for a code pull request is the `review-feedback` skill.

## Pull requests: a letter to the reviewer

- Make the subject of the text what the user experiences and what changes for them. Do not make class names, column names, or file names the subject.
- Write only three things: background (the Why not already in the issue), what was deliberately not done and why, and where the reviewer should look. Delete any of the three sections that has nothing to say.
- Do not write per-commit summaries, lists of changed files, CI results, or self-evident check lists. GitHub shows those.
- As a rule, structural changes and behavioral changes go in separate pull requests.
- No "Generated with ..." footer, session link, or AI signature anywhere in the title or body. The same applies to issues and review comments.
