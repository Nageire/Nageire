# Structured output

Some callers run this skill non-interactively and ask for JSON (for example with Claude Code's `--json-schema`). The caller's schema wins; this file says how the report's sections map onto it so every caller gets the same content.

| Section | Field |
| --- | --- |
| Verdict, first word or phrase | `verdict`: `approve`, `approve_with_follow_ups`, or `request_changes` |
| Verdict, the rest | `overall`: the sentences after the verdict, including the not-installed-skill and other-owner notes |
| Must, Should, Nit, Question | `findings[]`, one per finding, in the order of the report, each with `severity` set to `must`, `should`, `nit`, or `question` |
| Follow-ups | `follow_ups[]`, one string per line |
| Missing evidence | `missing_evidence[]`, one string per line |

Each finding:

| Field | Value |
| --- | --- |
| `severity` | `must`, `should`, `nit`, or `question` |
| `path` | The first location's file, relative to the repository root. Always present |
| `start_line`, `end_line` | The first location's lines in the new version of the file, or `null` for a finding anchored to the file |
| `locations` | Every location as written on the line under the title, when the caller's schema has room for it |
| `title` | The finding's title |
| `body` | For Must and Should: ASIS, Problem, and TOBE as prose, in that order. For a Question: To confirm and Options. For a Nit: the sentence |
| `rationale` | Problem for Must and Should; Recommendation for a Question; `null` for a Nit |
| `suggestion` | The replacement code when TOBE is a code block for exactly the lines, else `null` |
