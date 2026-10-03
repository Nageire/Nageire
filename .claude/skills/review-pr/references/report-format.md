# Report format

The report is Markdown printed to the terminal. The eight headings below always appear, in this order, spelled exactly like this, so other tools can split the report by heading. A section with nothing to report contains the single line `None.`

```markdown
# Review: <PR title or branch> (<target as given, and the range>)

## Verdict

<Approve | Approve with follow-ups | Request changes>. <One or two sentences saying why, naming the finding that decided it.>
<If a routed knowledge skill was not installed: "Reviewed <area> without <skill>; that part relies on general knowledge.">
<If someone else should look: "A <kind of owner> should review <what>, because <reason>.">

## Must

### <Short title of the problem>

`path/to/file.rb:12`, `path/to/other.rb:40`
ASIS: <what the code does now, in one or two sentences>
Problem: <what goes wrong and when>
TOBE: <what to change; a short code block when it is clearer than prose>

## Should

### <Short title>

`path/to/file.rb:88`
ASIS: ...
Problem: ...
TOBE: ...

## Nit

- `path/to/file.rb:5` <one sentence, ending with the fix>. Deferrable.

## Question

### <Short title>

`path/to/file.rb:23`
To confirm: <what is unclear and why it matters>
Options: <option A>; <option B>
Recommendation: <which option and why>

## Follow-ups

- <What to record before merge, and where: a TODO at path:line, or an issue.>

## Missing evidence

- <What the PR should show and does not, from the table in verification.md.>
```

Rules for the content:

- Findings are grouped by severity, then ordered by the order of the files in the diff.
- One finding covers every location of the same pattern; the locations are listed on the line under the title.
- ASIS describes the code, not the author. Problem names the consequence. TOBE is concrete enough to implement without a second question.
- A Question is used when the correct answer depends on intent or on a fact the reviewer cannot see; it is not a softened Should.
- A finding about a file as a whole, or a Question about the design of the change, is anchored to the file with no line number (`path/to/file.rb`). A design question goes on the file it concerns most, once, rather than on every file it touches.
- Write in the language the repository uses for pull requests. Keep the eight headings and the labels ASIS, Problem, TOBE, To confirm, Options, Recommendation in English so the structure is stable across repositories; the sentences after them follow the repository's language.
- No praise inside findings. When a strength changed the verdict (for example a regression test that proves the fix), say so in the Verdict sentence.
