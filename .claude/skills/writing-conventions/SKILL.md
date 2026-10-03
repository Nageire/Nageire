---
description: House style for everything written around code, meaning code comments, test names, commit messages, pull request titles and bodies, issues, review comments, and documents under docs/. Load before writing or reviewing any of those, and whenever another skill (for example create-pr) asks for the commit, comment, or PR conventions. Applies in any language; carries extra rules for Japanese prose.
license: MIT
metadata:
    github-path: skills/writing-conventions
    github-ref: refs/tags/v1.8.0
    github-repo: https://github.com/yamat47/github-toolkit
    github-tree-sha: 079f10b568f81f75972912de9e67f25ff8c0b32c
name: writing-conventions
---
# Writing conventions

Three references, read the one you need:

- [references/what-goes-where.md](references/what-goes-where.md) decides **what belongs in a code comment, a test name, a commit message, or a pull request**, following Takuto Wada's rule: code says How, tests say What, the commit log says Why, and code comments say Why not. Never write the same thing in two places.
- [references/writing-style.md](references/writing-style.md) sets the **prose style**: sentence shape, expressions to avoid, and structure.
- [references/code-comments.md](references/code-comments.md) details **code comments**: what a comment must add and must not contain, TODO and FIXME, form, links, and what belongs in a runbook, lint config, or schema instead.

Formats such as Conventional Commits prefixes or a PR template are owned by the repository or by the skill that writes the text; this skill only governs what is said and how.

## Language

Write in the language the repository already uses for the artifact in question. A repository whose commit history is in Japanese gets Japanese commit messages, with the Conventional Commits type kept in English. The style rules apply to every language; the Japanese-specific ones are marked as such in the references.

## Quick checklist

Before committing, commenting, or opening a pull request:

- Does the comment explain why the obvious approach was not taken, rather than what the code does?
- Does the test name read as a specification of behavior, with input and outcome?
- Does the commit subject use the imperative and does the body contain only the Why (or nothing, when the Why is obvious)?
- Is the pull request written about what changes for the user, with only background, things deliberately not done, and places to look at?
- Is every section that has nothing to say deleted rather than filled with "none"?
- Is there no trailer, footer, link, or signature saying an AI took part? The work is the author's own.
